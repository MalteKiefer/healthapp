package crypto

import (
	"encoding/base64"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestHashArgon2id(t *testing.T) {
	hash, err := HashArgon2id("mysecretpassword")
	require.NoError(t, err)
	assert.True(t, strings.HasPrefix(hash, "$argon2id$"), "hash should start with $argon2id$, got: %s", hash)

	// Verify the format: $argon2id$v=<version>$m=<mem>,t=<time>,p=<threads>$<salt>$<hash>
	parts := strings.Split(hash, "$")
	assert.Equal(t, 6, len(parts), "hash should have 6 parts separated by $")
	assert.Equal(t, "", parts[0])
	assert.Equal(t, "argon2id", parts[1])
	assert.True(t, strings.HasPrefix(parts[2], "v="), "third part should start with v=")
}

func TestVerifyArgon2id_Valid(t *testing.T) {
	password := "correcthorsebatterystaple"
	hash, err := HashArgon2id(password)
	require.NoError(t, err)

	ok, err := VerifyArgon2id(password, hash)
	require.NoError(t, err)
	assert.True(t, ok, "verification should succeed for the same password")
}

func TestVerifyArgon2id_Invalid(t *testing.T) {
	hash, err := HashArgon2id("password1")
	require.NoError(t, err)

	ok, err := VerifyArgon2id("password2", hash)
	require.NoError(t, err)
	assert.False(t, ok, "verification should fail for a different password")
}

func TestVerifyArgon2id_BadFormat(t *testing.T) {
	_, err := VerifyArgon2id("anything", "totalgarbage")
	assert.Error(t, err, "should return an error for badly formatted hash")

	_, err = VerifyArgon2id("anything", "$notargon$v=1$m=1,t=1,p=1$salt$hash")
	assert.Error(t, err, "should return an error for wrong algorithm identifier")

	_, err = VerifyArgon2id("anything", "")
	assert.Error(t, err, "should return an error for empty hash")
}

func TestGenerateSalt(t *testing.T) {
	length := 16
	salt, err := GenerateSalt(length)
	require.NoError(t, err)
	assert.NotEmpty(t, salt, "salt should not be empty")

	// Decode to verify the raw byte length matches
	decoded, err := base64.RawStdEncoding.DecodeString(salt)
	require.NoError(t, err)
	assert.Equal(t, length, len(decoded), "decoded salt should have the requested byte length")

	// Generate a second salt and ensure they differ (non-deterministic)
	salt2, err := GenerateSalt(length)
	require.NoError(t, err)
	assert.NotEqual(t, salt, salt2, "two salts should (almost certainly) be different")
}
