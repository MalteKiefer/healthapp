package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/api"
	"github.com/healthvault/healthvault/internal/cache"
	"github.com/healthvault/healthvault/internal/config"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// Set via ldflags at build time.
var (
	Version   = "dev"
	BuildTime = "unknown"
	GitCommit = "unknown"
)

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "version":
			fmt.Printf("HealthVault %s (commit: %s, built: %s)\n", Version, GitCommit, BuildTime)
			return
		case "migrate":
			runMigrate(os.Args[2:])
			return
		case "setup":
			runSetup(os.Args[2:])
			return
		case "serve":
			// fall through to default behavior
		default:
			fmt.Fprintf(os.Stderr, "Unknown command: %s\nUsage: healthvault [serve|version|migrate|setup]\n", os.Args[1])
			os.Exit(1)
		}
	}

	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "fatal: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	// Logger
	logger, err := zap.NewProduction()
	if err != nil {
		return fmt.Errorf("init logger: %w", err)
	}
	defer logger.Sync()

	logger.Info("starting HealthVault",
		zap.String("version", Version),
		zap.String("commit", GitCommit),
		zap.String("built", BuildTime),
	)

	// Config
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("load config: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Database
	db, err := postgres.NewPool(ctx, &cfg.Database)
	if err != nil {
		return fmt.Errorf("connect database: %w", err)
	}
	defer db.Close()
	logger.Info("connected to PostgreSQL")

	// Redis
	rdb, err := cache.NewRedisClient(&cfg.Redis)
	if err != nil {
		return fmt.Errorf("connect redis: %w", err)
	}
	defer rdb.Close()
	logger.Info("connected to Redis")

	// TODO: run migrations on startup

	// HTTP server
	srv := api.NewServer(db, rdb, logger, cfg)

	httpServer := &http.Server{
		Addr:         cfg.Server.ListenAddr(),
		Handler:      srv.Router,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
		IdleTimeout:  cfg.Server.IdleTimeout,
	}

	// Graceful shutdown
	errCh := make(chan error, 1)
	go func() {
		logger.Info("listening", zap.String("addr", httpServer.Addr))
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errCh <- err
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	select {
	case sig := <-quit:
		logger.Info("shutting down", zap.String("signal", sig.String()))
	case err := <-errCh:
		return fmt.Errorf("server error: %w", err)
	}

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer shutdownCancel()

	if err := httpServer.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}

	logger.Info("server stopped")
	return nil
}

func runMigrate(args []string) {
	// TODO: implement migration CLI
	fmt.Println("Migration commands not yet implemented.")
	fmt.Println("Usage: healthvault migrate [up|down|status|version]")
}

func runSetup(args []string) {
	// TODO: implement setup wizard
	fmt.Println("Setup wizard not yet implemented.")
	fmt.Println("Usage: healthvault setup [--repair|--reset-admin|--regen-keys]")
}
