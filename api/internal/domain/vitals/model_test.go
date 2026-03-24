package vitals

import (
	"math"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestCalculateBMI(t *testing.T) {
	weight := 80.0
	height := 180.0
	v := Vital{
		Weight: &weight,
		Height: &height,
	}

	v.CalculateBMI()

	require.NotNil(t, v.BMI, "BMI should be calculated when weight and height are set")
	// Expected: 80 / (1.8 * 1.8) = 24.691... truncated to 1 decimal = 24.6
	assert.InDelta(t, 24.6, *v.BMI, 0.1, "BMI for 80kg/180cm should be ~24.6")
	// Verify it is rounded to one decimal
	rounded := math.Round(*v.BMI*10) / 10
	assert.Equal(t, *v.BMI, rounded, "BMI should be rounded to 1 decimal place")
}

func TestCalculateBMI_NoWeight(t *testing.T) {
	height := 180.0
	v := Vital{
		Weight: nil,
		Height: &height,
	}

	v.CalculateBMI()
	assert.Nil(t, v.BMI, "BMI should remain nil when weight is not set")
}

func TestCalculateBMI_NoHeight(t *testing.T) {
	weight := 80.0
	v := Vital{
		Weight: &weight,
		Height: nil,
	}

	v.CalculateBMI()
	assert.Nil(t, v.BMI, "BMI should remain nil when height is not set")
}

func TestCalculateBMI_ZeroHeight(t *testing.T) {
	weight := 80.0
	height := 0.0
	v := Vital{
		Weight: &weight,
		Height: &height,
	}

	v.CalculateBMI()
	assert.Nil(t, v.BMI, "BMI should remain nil when height is zero (avoid division by zero)")
}
