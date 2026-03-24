package handlers_test

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/healthvault/healthvault/internal/api/handlers"
	"github.com/healthvault/healthvault/internal/api/middleware"
	"github.com/healthvault/healthvault/internal/crypto"
	"github.com/healthvault/healthvault/internal/repository/postgres"
)

// setupVitalsEnv reuses the shared DB/Redis setup and adds profile + vital
// routes to the router.
func setupVitalsEnv(t *testing.T) *testEnv {
	t.Helper()

	env := setupTestEnv(t)

	profileRepo := postgres.NewProfileRepo(env.DB)
	vitalRepo := postgres.NewVitalRepo(env.DB)

	profileHandler := handlers.NewProfileHandler(profileRepo, env.Logger)
	vitalHandler := handlers.NewVitalHandler(vitalRepo, profileRepo, env.Logger)

	// Add profile and vital routes behind JWT auth
	env.Router.Group(func(r chi.Router) {
		r.Use(middleware.JWTAuth(env.TokenService))

		r.Post("/api/v1/profiles", profileHandler.HandleCreate)
		r.Get("/api/v1/profiles/{profileID}/vitals", vitalHandler.HandleList)
		r.Post("/api/v1/profiles/{profileID}/vitals", vitalHandler.HandleCreate)
	})

	return env
}

// createTestProfile creates a profile for the given user and returns the profile ID.
func createTestProfile(t *testing.T, env *testEnv, accessToken string) string {
	t.Helper()

	body := mustJSON(t, map[string]string{
		"display_name": "Test Profile",
	})
	req := httptest.NewRequest(http.MethodPost, "/api/v1/profiles", body)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+accessToken)
	w := httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)
	require.Equal(t, http.StatusCreated, w.Code, "create profile should return 201: %s", w.Body.String())

	var resp map[string]interface{}
	require.NoError(t, json.NewDecoder(w.Body).Decode(&resp))
	id, ok := resp["id"].(string)
	require.True(t, ok, "profile response should have string id")
	return id
}

// createTestVital creates a vital under the given profile and returns the
// decoded response and the status code.
func createTestVital(t *testing.T, env *testEnv, accessToken, profileID string, vital map[string]interface{}) (map[string]interface{}, int) {
	t.Helper()

	body := &bytes.Buffer{}
	require.NoError(t, json.NewEncoder(body).Encode(vital))

	url := fmt.Sprintf("/api/v1/profiles/%s/vitals", profileID)
	req := httptest.NewRequest(http.MethodPost, url, body)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+accessToken)
	w := httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)

	var resp map[string]interface{}
	_ = json.NewDecoder(w.Body).Decode(&resp)
	return resp, w.Code
}

func TestCreateAndListVitals(t *testing.T) {
	env := setupVitalsEnv(t)

	email := fmt.Sprintf("vitals-%d@example.com", time.Now().UnixNano())
	_ = registerTestUser(t, env, email)

	authHash, err := crypto.HashArgon2id("test-password-123")
	require.NoError(t, err)

	loginResp := loginTestUser(t, env, email, authHash)
	accessToken := loginResp["access_token"].(string)

	// Create a profile
	profileID := createTestProfile(t, env, accessToken)

	// Create a vital
	pulse := 72
	systolic := 120
	diastolic := 80
	measuredAt := time.Now().UTC().Add(-10 * time.Minute).Format(time.RFC3339)

	vitalData := map[string]interface{}{
		"pulse":                    pulse,
		"blood_pressure_systolic":  systolic,
		"blood_pressure_diastolic": diastolic,
		"measured_at":              measuredAt,
	}

	resp, code := createTestVital(t, env, accessToken, profileID, vitalData)
	require.Equal(t, http.StatusCreated, code, "create vital should return 201")
	assert.NotEmpty(t, resp["id"], "vital should have an id")
	assert.Equal(t, float64(pulse), resp["pulse"])

	// List vitals
	url := fmt.Sprintf("/api/v1/profiles/%s/vitals", profileID)
	req := httptest.NewRequest(http.MethodGet, url, nil)
	req.Header.Set("Authorization", "Bearer "+accessToken)
	w := httptest.NewRecorder()
	env.Router.ServeHTTP(w, req)
	require.Equal(t, http.StatusOK, w.Code, "list vitals should return 200: %s", w.Body.String())

	var listResp map[string]interface{}
	require.NoError(t, json.NewDecoder(w.Body).Decode(&listResp))

	total, ok := listResp["total"].(float64)
	require.True(t, ok, "total should be a number")
	assert.Equal(t, float64(1), total, "should have exactly 1 vital")

	items, ok := listResp["items"].([]interface{})
	require.True(t, ok, "items should be an array")
	require.Len(t, items, 1, "items array should have 1 element")

	item := items[0].(map[string]interface{})
	assert.Equal(t, resp["id"], item["id"], "listed vital id should match created vital id")
	assert.Equal(t, float64(pulse), item["pulse"])
	assert.Equal(t, float64(systolic), item["blood_pressure_systolic"])
	assert.Equal(t, float64(diastolic), item["blood_pressure_diastolic"])
}

func TestVitalDuplicateDetection(t *testing.T) {
	env := setupVitalsEnv(t)

	email := fmt.Sprintf("vitals-dup-%d@example.com", time.Now().UnixNano())
	_ = registerTestUser(t, env, email)

	authHash, err := crypto.HashArgon2id("test-password-123")
	require.NoError(t, err)

	loginResp := loginTestUser(t, env, email, authHash)
	accessToken := loginResp["access_token"].(string)

	profileID := createTestProfile(t, env, accessToken)

	// Use current time so the duplicate-detection 5-minute window applies.
	measuredAt := time.Now().UTC().Format(time.RFC3339)

	vitalData := map[string]interface{}{
		"pulse":       65,
		"measured_at": measuredAt,
	}

	// First create should succeed
	_, code := createTestVital(t, env, accessToken, profileID, vitalData)
	require.Equal(t, http.StatusCreated, code, "first vital should be created")

	// Second create with same data should be flagged as duplicate (409)
	resp, code := createTestVital(t, env, accessToken, profileID, vitalData)
	assert.Equal(t, http.StatusConflict, code, "duplicate vital should return 409")
	assert.Equal(t, "possible_duplicate", resp["error"], "error should indicate possible_duplicate")
	assert.NotEmpty(t, resp["existing_id"], "should return existing_id")
}
