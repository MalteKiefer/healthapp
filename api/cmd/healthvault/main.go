package main

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"

	"github.com/healthvault/healthvault/internal/api"
	"github.com/healthvault/healthvault/internal/cache"
	"github.com/healthvault/healthvault/internal/config"
	"github.com/healthvault/healthvault/internal/crypto"
	"github.com/healthvault/healthvault/internal/migrations"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// Set via ldflags at build time.
var (
	Version   = "dev"
	BuildTime = "unknown"
	GitCommit = "unknown"
)

// migrationFile represents a single numbered migration file.
type migrationFile struct {
	Version  int
	Name     string
	Filename string
}

// migrationRegex matches files like "000001_initial_schema.up.sql".
var migrationRegex = regexp.MustCompile(`^(\d+)_.*\.(up|down)\.sql$`)

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

	// Schema version check and auto-migration
	if err := checkAndMigrateSchema(ctx, db, logger); err != nil {
		return fmt.Errorf("schema migration: %w", err)
	}

	// JWT Token Service — auto-generate keys if missing
	if !fileExists(cfg.JWT.PrivateKeyPath) || !fileExists(cfg.JWT.PublicKeyPath) {
		logger.Info("JWT keys not found, generating new RS256 keypair...")
		if err := generateJWTKeypair(cfg.JWT.PrivateKeyPath, cfg.JWT.PublicKeyPath); err != nil {
			return fmt.Errorf("generate JWT keys: %w", err)
		}
		logger.Info("JWT keypair generated",
			zap.String("private", cfg.JWT.PrivateKeyPath),
			zap.String("public", cfg.JWT.PublicKeyPath),
		)
	}

	ts, err := crypto.NewTokenService(
		cfg.JWT.PrivateKeyPath, cfg.JWT.PublicKeyPath, cfg.JWT.TOTPKeyPath,
		rdb, cfg.JWT.AccessTTL, cfg.JWT.RefreshTTL,
	)
	if err != nil {
		return fmt.Errorf("init token service: %w", err)
	}
	logger.Info("JWT token service initialized")

	// HTTP server
	srv := api.NewServer(db, rdb, logger, cfg, ts, Version)

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

// ---------------------------------------------------------------------------
// Schema check on startup
// ---------------------------------------------------------------------------

func checkAndMigrateSchema(ctx context.Context, db *pgxpool.Pool, logger *zap.Logger) error {
	upMigrations, err := listMigrations("up")
	if err != nil {
		return fmt.Errorf("list migrations: %w", err)
	}
	expectedVersion := 0
	if len(upMigrations) > 0 {
		expectedVersion = upMigrations[len(upMigrations)-1].Version
	}

	currentVersion, err := getSchemaVersion(ctx, db)
	if err != nil {
		// Table might not exist yet — treat as version 0
		currentVersion = 0
	}

	switch {
	case currentVersion > expectedVersion:
		logger.Fatal("Database schema is newer than this binary -- update HealthVault",
			zap.Int("schema_version", currentVersion),
			zap.Int("binary_version", expectedVersion),
		)
		return fmt.Errorf("database schema (v%d) is newer than this binary (v%d)", currentVersion, expectedVersion)

	case currentVersion < expectedVersion:
		pending := countPending(upMigrations, currentVersion)
		logger.Info(fmt.Sprintf("Running %d pending migrations...", pending),
			zap.Int("from", currentVersion),
			zap.Int("to", expectedVersion),
		)
		if err := applyMigrationsUp(ctx, db, upMigrations, currentVersion); err != nil {
			return err
		}
		logger.Info("Schema up to date",
			zap.Int("version", expectedVersion),
		)

	default:
		logger.Info("Schema up to date",
			zap.Int("version", currentVersion),
		)
	}

	return nil
}

// ---------------------------------------------------------------------------
// Migration CLI: healthvault migrate [up|down N|status|version]
// ---------------------------------------------------------------------------

func runMigrate(args []string) {
	if len(args) == 0 {
		fmt.Fprintln(os.Stderr, "Usage: healthvault migrate [up|down N|status|version]")
		os.Exit(1)
	}

	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "load config: %v\n", err)
		os.Exit(1)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	db, err := postgres.NewPool(ctx, &cfg.Database)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect database: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()

	switch args[0] {
	case "up":
		migrateUp(ctx, db)
	case "down":
		if len(args) < 2 {
			fmt.Fprintln(os.Stderr, "Usage: healthvault migrate down N")
			os.Exit(1)
		}
		n, err := strconv.Atoi(args[1])
		if err != nil || n < 1 {
			fmt.Fprintln(os.Stderr, "N must be a positive integer")
			os.Exit(1)
		}
		migrateDown(ctx, db, n)
	case "status":
		migrateStatus(ctx, db)
	case "version":
		migrateVersion(ctx, db)
	default:
		fmt.Fprintf(os.Stderr, "Unknown migrate subcommand: %s\nUsage: healthvault migrate [up|down N|status|version]\n", args[0])
		os.Exit(1)
	}
}

func migrateUp(ctx context.Context, db *pgxpool.Pool) {
	upMigrations, err := listMigrations("up")
	if err != nil {
		fmt.Fprintf(os.Stderr, "list migrations: %v\n", err)
		os.Exit(1)
	}

	currentVersion, err := getSchemaVersion(ctx, db)
	if err != nil {
		currentVersion = 0
	}

	pending := countPending(upMigrations, currentVersion)
	if pending == 0 {
		fmt.Printf("No pending migrations. Schema at version %d.\n", currentVersion)
		return
	}

	fmt.Printf("Applying %d pending migrations (current: v%d)...\n", pending, currentVersion)
	if err := applyMigrationsUp(ctx, db, upMigrations, currentVersion); err != nil {
		fmt.Fprintf(os.Stderr, "migration failed: %v\n", err)
		os.Exit(1)
	}

	newVersion, _ := getSchemaVersion(ctx, db)
	fmt.Printf("Migrations complete. Schema at version %d.\n", newVersion)
}

func migrateDown(ctx context.Context, db *pgxpool.Pool, n int) {
	downMigrations, err := listMigrations("down")
	if err != nil {
		fmt.Fprintf(os.Stderr, "list migrations: %v\n", err)
		os.Exit(1)
	}

	// Sort descending for rollback order
	sort.Slice(downMigrations, func(i, j int) bool {
		return downMigrations[i].Version > downMigrations[j].Version
	})

	currentVersion, err := getSchemaVersion(ctx, db)
	if err != nil || currentVersion == 0 {
		fmt.Fprintln(os.Stderr, "No migrations to roll back (schema at version 0).")
		os.Exit(1)
	}

	for step := 0; step < n; step++ {
		if currentVersion <= 0 {
			fmt.Println("Already at version 0, stopping.")
			break
		}

		// Find the down migration for currentVersion
		var mig *migrationFile
		for i := range downMigrations {
			if downMigrations[i].Version == currentVersion {
				mig = &downMigrations[i]
				break
			}
		}
		if mig == nil {
			fmt.Fprintf(os.Stderr, "No down migration found for version %d\n", currentVersion)
			os.Exit(1)
		}

		sql, err := fs.ReadFile(migrations.FS, mig.Filename)
		if err != nil {
			fmt.Fprintf(os.Stderr, "read %s: %v\n", mig.Filename, err)
			os.Exit(1)
		}

		fmt.Printf("Rolling back migration %d (%s)...\n", mig.Version, mig.Name)

		tx, err := db.Begin(ctx)
		if err != nil {
			fmt.Fprintf(os.Stderr, "begin tx for rollback %d: %v\n", currentVersion, err)
			os.Exit(1)
		}

		// Mark dirty before attempting
		if _, err := tx.Exec(ctx,
			"UPDATE schema_migrations SET dirty = TRUE WHERE version = $1",
			currentVersion,
		); err != nil {
			_ = tx.Rollback(ctx)
			fmt.Fprintf(os.Stderr, "mark dirty version %d: %v\n", currentVersion, err)
			os.Exit(1)
		}

		if _, err := tx.Exec(ctx, string(sql)); err != nil {
			_ = tx.Rollback(ctx)
			fmt.Fprintf(os.Stderr, "rollback version %d failed (dirty=true): %v\n", currentVersion, err)
			os.Exit(1)
		}

		// Remove the rolled-back version from schema_migrations
		if _, err := tx.Exec(ctx,
			"DELETE FROM schema_migrations WHERE version = $1",
			currentVersion,
		); err != nil {
			_ = tx.Rollback(ctx)
			fmt.Fprintf(os.Stderr, "delete schema_migrations row for version %d: %v\n", currentVersion, err)
			os.Exit(1)
		}

		if err := tx.Commit(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "commit rollback for version %d: %v\n", currentVersion, err)
			os.Exit(1)
		}

		currentVersion--
	}

	v, _ := getSchemaVersion(ctx, db)
	fmt.Printf("Rollback complete. Schema at version %d.\n", v)
}

func migrateStatus(ctx context.Context, db *pgxpool.Pool) {
	upMigrations, err := listMigrations("up")
	if err != nil {
		fmt.Fprintf(os.Stderr, "list migrations: %v\n", err)
		os.Exit(1)
	}

	currentVersion, err := getSchemaVersion(ctx, db)
	if err != nil {
		currentVersion = 0
	}

	fmt.Printf("Current schema version: %d\n", currentVersion)
	fmt.Println()

	for _, m := range upMigrations {
		status := "applied"
		if m.Version > currentVersion {
			status = "pending"
		}
		fmt.Printf("  %06d  %-40s  %s\n", m.Version, m.Name, status)
	}

	pending := countPending(upMigrations, currentVersion)
	if pending > 0 {
		fmt.Printf("\n%d pending migration(s).\n", pending)
	} else {
		fmt.Println("\nAll migrations applied.")
	}
}

func migrateVersion(ctx context.Context, db *pgxpool.Pool) {
	v, err := getSchemaVersion(ctx, db)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Schema version: 0 (schema_migrations table not found)")
		return
	}
	fmt.Printf("Schema version: %d\n", v)
}

// ---------------------------------------------------------------------------
// Setup command: healthvault setup
// ---------------------------------------------------------------------------

func runSetup(_ []string) {
	fmt.Println("HealthVault setup")
	fmt.Println("=================")

	// Load config
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintf(os.Stderr, "load config: %v\n", err)
		os.Exit(1)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()

	// Connect to database
	fmt.Println("[1/3] Connecting to database...")
	db, err := postgres.NewPool(ctx, &cfg.Database)
	if err != nil {
		fmt.Fprintf(os.Stderr, "connect database: %v\n", err)
		os.Exit(1)
	}
	defer db.Close()
	fmt.Println("      Connected to PostgreSQL.")

	// Run migrations
	fmt.Println("[2/3] Running database migrations...")
	upMigrations, err := listMigrations("up")
	if err != nil {
		fmt.Fprintf(os.Stderr, "list migrations: %v\n", err)
		os.Exit(1)
	}

	currentVersion, err := getSchemaVersion(ctx, db)
	if err != nil {
		currentVersion = 0
	}

	pending := countPending(upMigrations, currentVersion)
	if pending > 0 {
		fmt.Printf("      Applying %d migration(s)...\n", pending)
		if err := applyMigrationsUp(ctx, db, upMigrations, currentVersion); err != nil {
			fmt.Fprintf(os.Stderr, "migration failed: %v\n", err)
			os.Exit(1)
		}
	}
	newVersion, _ := getSchemaVersion(ctx, db)
	fmt.Printf("      Schema at version %d.\n", newVersion)

	// Generate JWT keys if they don't exist
	fmt.Println("[3/3] Checking JWT RS256 keypair...")
	privPath := cfg.JWT.PrivateKeyPath
	pubPath := cfg.JWT.PublicKeyPath

	privExists := fileExists(privPath)
	pubExists := fileExists(pubPath)

	if privExists && pubExists {
		fmt.Printf("      Keys already exist at:\n        %s\n        %s\n", privPath, pubPath)
	} else {
		fmt.Println("      Generating new RS256 keypair...")
		if err := generateJWTKeypair(privPath, pubPath); err != nil {
			fmt.Fprintf(os.Stderr, "generate JWT keys: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("      Private key: %s\n", privPath)
		fmt.Printf("      Public key:  %s\n", pubPath)
	}

	fmt.Println()
	fmt.Println("Setup complete.")
}

// ---------------------------------------------------------------------------
// Migration helpers
// ---------------------------------------------------------------------------

// listMigrations returns sorted migration files of the given direction ("up" or "down").
func listMigrations(direction string) ([]migrationFile, error) {
	entries, err := fs.ReadDir(migrations.FS, ".")
	if err != nil {
		return nil, fmt.Errorf("read embedded migrations dir: %w", err)
	}

	result := make([]migrationFile, 0, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		matches := migrationRegex.FindStringSubmatch(e.Name())
		if matches == nil {
			continue
		}
		if matches[2] != direction {
			continue
		}
		version, err := strconv.Atoi(matches[1])
		if err != nil {
			continue
		}
		// Derive a human-readable name from the filename.
		name := e.Name()
		name = strings.TrimSuffix(name, "."+direction+".sql")
		// Remove the leading version number and underscore.
		if idx := strings.Index(name, "_"); idx >= 0 {
			name = name[idx+1:]
		}

		result = append(result, migrationFile{
			Version:  version,
			Name:     name,
			Filename: e.Name(),
		})
	}

	sort.Slice(result, func(i, j int) bool {
		return result[i].Version < result[j].Version
	})

	return result, nil
}

// getSchemaVersion queries the current schema version from the database.
// It fatally exits if any migration is marked dirty, indicating a previous
// migration failed mid-way and requires manual intervention.
func getSchemaVersion(ctx context.Context, db *pgxpool.Pool) (int, error) {
	// Check for dirty migrations first.
	var dirtyVersion int
	err := db.QueryRow(ctx,
		"SELECT version FROM schema_migrations WHERE dirty = TRUE ORDER BY version DESC LIMIT 1",
	).Scan(&dirtyVersion)
	if err == nil {
		fmt.Fprintf(os.Stderr, "FATAL: migration version %d is marked dirty. A previous migration failed and requires manual intervention.\n", dirtyVersion)
		os.Exit(1)
	}

	var version int
	err = db.QueryRow(ctx,
		"SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1",
	).Scan(&version)
	if err != nil {
		return 0, err
	}
	return version, nil
}

// countPending returns the number of migration files with version > currentVersion.
func countPending(migs []migrationFile, currentVersion int) int {
	count := 0
	for _, m := range migs {
		if m.Version > currentVersion {
			count++
		}
	}
	return count
}

// applyMigrationsUp applies all pending up-migrations after currentVersion.
// Each migration runs inside a single transaction so that a failure leaves
// the schema_migrations table in a consistent state.
func applyMigrationsUp(ctx context.Context, db *pgxpool.Pool, migs []migrationFile, currentVersion int) error {
	// Ensure the tracking table exists (outside the per-migration tx).
	_, _ = db.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version     BIGINT PRIMARY KEY,
			dirty       BOOLEAN NOT NULL DEFAULT FALSE,
			applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)`)

	for _, m := range migs {
		if m.Version <= currentVersion {
			continue
		}

		sqlBytes, err := fs.ReadFile(migrations.FS, m.Filename)
		if err != nil {
			return fmt.Errorf("read migration %s: %w", m.Filename, err)
		}

		tx, err := db.Begin(ctx)
		if err != nil {
			return fmt.Errorf("begin tx for migration %d: %w", m.Version, err)
		}

		// Mark dirty before attempting
		if _, err := tx.Exec(ctx,
			"INSERT INTO schema_migrations (version, dirty) VALUES ($1, TRUE) ON CONFLICT (version) DO UPDATE SET dirty = TRUE",
			m.Version,
		); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("mark dirty migration %d: %w", m.Version, err)
		}

		// Execute the migration SQL
		if _, err := tx.Exec(ctx, string(sqlBytes)); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("apply migration %06d (%s): %w [dirty=true]", m.Version, m.Name, err)
		}

		// Mark clean after success
		if _, err := tx.Exec(ctx,
			"INSERT INTO schema_migrations (version, dirty) VALUES ($1, FALSE) ON CONFLICT (version) DO UPDATE SET dirty = FALSE, applied_at = NOW()",
			m.Version,
		); err != nil {
			_ = tx.Rollback(ctx)
			return fmt.Errorf("record migration %d: %w", m.Version, err)
		}

		if err := tx.Commit(ctx); err != nil {
			return fmt.Errorf("commit migration %d: %w", m.Version, err)
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// JWT key generation
// ---------------------------------------------------------------------------

func generateJWTKeypair(privPath, pubPath string) error {
	// Ensure parent directories exist
	if err := os.MkdirAll(filepath.Dir(privPath), 0o700); err != nil {
		return fmt.Errorf("create directory for private key: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(pubPath), 0o700); err != nil {
		return fmt.Errorf("create directory for public key: %w", err)
	}

	// Generate 4096-bit RSA key
	privKey, err := rsa.GenerateKey(rand.Reader, 4096)
	if err != nil {
		return fmt.Errorf("generate RSA key: %w", err)
	}

	// Encode private key as PKCS#1 PEM
	privPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: x509.MarshalPKCS1PrivateKey(privKey),
	})
	if err := os.WriteFile(privPath, privPEM, 0o600); err != nil {
		return fmt.Errorf("write private key: %w", err)
	}

	// Encode public key as PKIX PEM
	pubBytes, err := x509.MarshalPKIXPublicKey(&privKey.PublicKey)
	if err != nil {
		return fmt.Errorf("marshal public key: %w", err)
	}
	pubPEM := pem.EncodeToMemory(&pem.Block{
		Type:  "PUBLIC KEY",
		Bytes: pubBytes,
	})
	if err := os.WriteFile(pubPath, pubPEM, 0o600); err != nil {
		return fmt.Errorf("write public key: %w", err)
	}

	return nil
}

func fileExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}
