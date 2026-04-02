package config

import (
	"fmt"
	"os"
	"strconv"
	"time"
)

// Config holds all application configuration loaded from environment variables.
type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	Redis    RedisConfig
	JWT      JWTConfig
	Instance InstanceConfig
}

type ServerConfig struct {
	Host         string
	Port         int
	ReadTimeout  time.Duration
	WriteTimeout time.Duration
	IdleTimeout  time.Duration
}

type DatabaseConfig struct {
	Host     string
	Port     int
	User     string
	Password string
	Name     string
	SSLMode  string
	MaxConns int32
	MinConns int32
}

type RedisConfig struct {
	Host     string
	Port     int
	Password string
	DB       int
}

type JWTConfig struct {
	PrivateKeyPath string
	PublicKeyPath  string
	TOTPKeyPath    string
	AccessTTL      time.Duration
	RefreshTTL     time.Duration
}

type InstanceConfig struct {
	Hostname         string
	RegistrationMode string // open, invite_only, closed
	DefaultQuotaMB   int
	MaxFileSizeMB    int
	MaxProfiles      int
	MaxFamilySize    int
	SessionTimeout   time.Duration
}

// Load reads configuration from environment variables with sensible defaults.
func Load() (*Config, error) {
	cfg := &Config{
		Server: ServerConfig{
			Host:         getEnv("SERVER_HOST", "0.0.0.0"),
			Port:         getEnvInt("SERVER_PORT", 8080),
			ReadTimeout:  getEnvDuration("SERVER_READ_TIMEOUT", 30*time.Second),
			WriteTimeout: getEnvDuration("SERVER_WRITE_TIMEOUT", 30*time.Second),
			IdleTimeout:  getEnvDuration("SERVER_IDLE_TIMEOUT", 120*time.Second),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "pgbouncer"),
			Port:     getEnvInt("DB_PORT", 6432),
			User:     getEnv("DB_USER", "healthvault"),
			Password: getEnv("DB_PASSWORD", ""),
			Name:     getEnv("DB_NAME", "healthvault"),
			SSLMode:  getEnv("DB_SSLMODE", "disable"),
			MaxConns: int32(getEnvInt("DB_MAX_CONNS", 20)),
			MinConns: int32(getEnvInt("DB_MIN_CONNS", 5)),
		},
		Redis: RedisConfig{
			Host:     getEnv("REDIS_HOST", "redis"),
			Port:     getEnvInt("REDIS_PORT", 6379),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getEnvInt("REDIS_DB", 0),
		},
		JWT: JWTConfig{
			PrivateKeyPath: getEnv("JWT_PRIVATE_KEY_PATH", "/data/keys/jwt_private.pem"),
			PublicKeyPath:  getEnv("JWT_PUBLIC_KEY_PATH", "/data/keys/jwt_public.pem"),
			TOTPKeyPath:    getEnv("TOTP_KEY_PATH", "/data/keys/totp.key"),
			AccessTTL:      getEnvDuration("JWT_ACCESS_TTL", 15*time.Minute),
			RefreshTTL:     getEnvDuration("JWT_REFRESH_TTL", 7*24*time.Hour),
		},
		Instance: InstanceConfig{
			Hostname:         getEnv("INSTANCE_HOSTNAME", "localhost"),
			RegistrationMode: getEnv("REGISTRATION_MODE", "invite_only"),
			DefaultQuotaMB:   getEnvInt("DEFAULT_QUOTA_MB", 5120),
			MaxFileSizeMB:    getEnvInt("MAX_FILE_SIZE_MB", 50),
			MaxProfiles:      getEnvInt("MAX_PROFILES_PER_USER", 10),
			MaxFamilySize:    getEnvInt("MAX_FAMILY_SIZE", 10),
			SessionTimeout:   getEnvDuration("SESSION_TIMEOUT", 60*time.Minute),
		},
	}

	if cfg.Database.Password == "" {
		return nil, fmt.Errorf("DB_PASSWORD is required")
	}
	if cfg.Redis.Password == "" {
		return nil, fmt.Errorf("REDIS_PASSWORD is required")
	}

	return cfg, nil
}

// DSN returns a PostgreSQL connection string.
func (d *DatabaseConfig) DSN() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%d/%s?sslmode=%s",
		d.User, d.Password, d.Host, d.Port, d.Name, d.SSLMode,
	)
}

// Addr returns the Redis address as host:port.
func (r *RedisConfig) Addr() string {
	return fmt.Sprintf("%s:%d", r.Host, r.Port)
}

// ListenAddr returns the server listen address.
func (s *ServerConfig) ListenAddr() string {
	return fmt.Sprintf("%s:%d", s.Host, s.Port)
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func getEnvInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	i, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return i
}

func getEnvDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}
