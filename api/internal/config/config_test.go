package config

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// clearConfigEnv unsets all config-related env vars so tests start from a clean
// state. Returns a cleanup function that restores the original values.
func clearConfigEnv(t *testing.T) {
	t.Helper()

	keys := []string{
		"SERVER_HOST", "SERVER_PORT",
		"DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD", "DB_NAME", "DB_SSLMODE",
		"REDIS_HOST", "REDIS_PORT", "REDIS_PASSWORD", "REDIS_DB",
		"JWT_PRIVATE_KEY_PATH", "JWT_PUBLIC_KEY_PATH",
		"INSTANCE_HOSTNAME", "REGISTRATION_MODE",
	}

	saved := make(map[string]string)
	for _, k := range keys {
		saved[k] = os.Getenv(k)
		os.Unsetenv(k)
	}

	t.Cleanup(func() {
		for k, v := range saved {
			if v != "" {
				os.Setenv(k, v)
			} else {
				os.Unsetenv(k)
			}
		}
	})
}

func TestLoad_MissingDBPassword(t *testing.T) {
	clearConfigEnv(t)
	// Set REDIS_PASSWORD but leave DB_PASSWORD empty.
	os.Setenv("REDIS_PASSWORD", "redispass")

	_, err := Load()
	require.Error(t, err)
	assert.Contains(t, err.Error(), "DB_PASSWORD", "error should mention DB_PASSWORD")
}

func TestLoad_MissingRedisPassword(t *testing.T) {
	clearConfigEnv(t)
	// Set DB_PASSWORD but leave REDIS_PASSWORD empty.
	os.Setenv("DB_PASSWORD", "dbpass")

	_, err := Load()
	require.Error(t, err)
	assert.Contains(t, err.Error(), "REDIS_PASSWORD", "error should mention REDIS_PASSWORD")
}

func TestLoad_ValidConfig(t *testing.T) {
	clearConfigEnv(t)
	os.Setenv("DB_PASSWORD", "dbpass")
	os.Setenv("REDIS_PASSWORD", "redispass")
	os.Setenv("SERVER_PORT", "9090")
	os.Setenv("DB_HOST", "mydbhost")

	cfg, err := Load()
	require.NoError(t, err)
	require.NotNil(t, cfg)

	assert.Equal(t, "dbpass", cfg.Database.Password)
	assert.Equal(t, "redispass", cfg.Redis.Password)
	assert.Equal(t, 9090, cfg.Server.Port)
	assert.Equal(t, "mydbhost", cfg.Database.Host)
	// Verify defaults for fields we did not override.
	assert.Equal(t, "0.0.0.0", cfg.Server.Host)
	assert.Equal(t, "healthvault", cfg.Database.User)
	assert.Equal(t, "healthvault", cfg.Database.Name)
}

func TestDSN(t *testing.T) {
	db := DatabaseConfig{
		Host:     "localhost",
		Port:     5432,
		User:     "testuser",
		Password: "testpass",
		Name:     "testdb",
		SSLMode:  "disable",
	}

	dsn := db.DSN()
	assert.Equal(t, "postgres://testuser:testpass@localhost:5432/testdb?sslmode=disable", dsn)
}

func TestListenAddr(t *testing.T) {
	srv := ServerConfig{
		Host: "127.0.0.1",
		Port: 3000,
	}

	addr := srv.ListenAddr()
	assert.Equal(t, "127.0.0.1:3000", addr)
}
