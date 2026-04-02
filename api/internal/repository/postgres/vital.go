package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/vitals"
)

type VitalRepo struct {
	db *pgxpool.Pool
}

func NewVitalRepo(db *pgxpool.Pool) *VitalRepo {
	return &VitalRepo{db: db}
}

func (r *VitalRepo) Create(ctx context.Context, v *vitals.Vital) error {
	if v.ID == uuid.Nil {
		v.ID = uuid.New()
	}
	now := time.Now().UTC()
	v.CreatedAt = now
	v.UpdatedAt = now
	v.CalculateBMI()

	query := `
		INSERT INTO vitals (
			id, profile_id, blood_pressure_systolic, blood_pressure_diastolic,
			pulse, oxygen_saturation, weight, height, body_temperature,
			blood_glucose, respiratory_rate, waist_circumference, hip_circumference,
			body_fat_percentage, bmi, sleep_duration_minutes, sleep_quality,
			measured_at, device, notes, created_at, updated_at
		) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21,$22)`

	_, err := r.db.Exec(ctx, query,
		v.ID, v.ProfileID, v.BloodPressureSystolic, v.BloodPressureDiastolic,
		v.Pulse, v.OxygenSaturation, v.Weight, v.Height, v.BodyTemperature,
		v.BloodGlucose, v.RespiratoryRate, v.WaistCircumference, v.HipCircumference,
		v.BodyFatPercentage, v.BMI, v.SleepDurationMinutes, v.SleepQuality,
		v.MeasuredAt, v.Device, v.Notes, v.CreatedAt, v.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("insert vital: %w", err)
	}
	return nil
}

func (r *VitalRepo) GetByID(ctx context.Context, id uuid.UUID) (*vitals.Vital, error) {
	query := `
		SELECT id, profile_id, blood_pressure_systolic, blood_pressure_diastolic,
			pulse, oxygen_saturation, weight, height, body_temperature,
			blood_glucose, respiratory_rate, waist_circumference, hip_circumference,
			body_fat_percentage, bmi, sleep_duration_minutes, sleep_quality,
			measured_at, device, notes, created_at, updated_at, deleted_at
		FROM vitals WHERE id = $1 AND deleted_at IS NULL`

	return r.scanVital(r.db.QueryRow(ctx, query, id))
}

func (r *VitalRepo) List(ctx context.Context, filter vitals.ListFilter) ([]vitals.Vital, int, error) {
	countQuery := "SELECT COUNT(*) FROM vitals WHERE profile_id = $1 AND deleted_at IS NULL"
	args := []interface{}{filter.ProfileID}
	argIdx := 2

	if filter.From != nil {
		countQuery += fmt.Sprintf(" AND measured_at >= $%d", argIdx)
		args = append(args, *filter.From)
		argIdx++
	}
	if filter.To != nil {
		countQuery += fmt.Sprintf(" AND measured_at <= $%d", argIdx)
		args = append(args, *filter.To)
		argIdx++
	}

	var total int
	if err := r.db.QueryRow(ctx, countQuery, args...).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count vitals: %w", err)
	}

	query := `
		SELECT id, profile_id, blood_pressure_systolic, blood_pressure_diastolic,
			pulse, oxygen_saturation, weight, height, body_temperature,
			blood_glucose, respiratory_rate, waist_circumference, hip_circumference,
			body_fat_percentage, bmi, sleep_duration_minutes, sleep_quality,
			measured_at, device, notes, created_at, updated_at, deleted_at
		FROM vitals WHERE profile_id = $1 AND deleted_at IS NULL`

	listArgs := []interface{}{filter.ProfileID}
	listIdx := 2

	if filter.From != nil {
		query += fmt.Sprintf(" AND measured_at >= $%d", listIdx)
		listArgs = append(listArgs, *filter.From)
		listIdx++
	}
	if filter.To != nil {
		query += fmt.Sprintf(" AND measured_at <= $%d", listIdx)
		listArgs = append(listArgs, *filter.To)
		listIdx++
	}

	query += " ORDER BY measured_at DESC"

	if filter.Limit > 0 {
		query += fmt.Sprintf(" LIMIT $%d", listIdx)
		listArgs = append(listArgs, filter.Limit)
		listIdx++
	}
	if filter.Offset > 0 {
		query += fmt.Sprintf(" OFFSET $%d", listIdx)
		listArgs = append(listArgs, filter.Offset)
	}

	rows, err := r.db.Query(ctx, query, listArgs...)
	if err != nil {
		return nil, 0, fmt.Errorf("query vitals: %w", err)
	}
	defer rows.Close()

	var result []vitals.Vital
	for rows.Next() {
		v, err := r.scanVitalRow(rows)
		if err != nil {
			return nil, 0, err
		}
		result = append(result, *v)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate rows: %w", err)
	}

	return result, total, nil
}

func (r *VitalRepo) Update(ctx context.Context, v *vitals.Vital) error {
	v.UpdatedAt = time.Now().UTC()
	v.CalculateBMI()

	query := `
		UPDATE vitals SET
			blood_pressure_systolic = $2, blood_pressure_diastolic = $3,
			pulse = $4, oxygen_saturation = $5, weight = $6, height = $7,
			body_temperature = $8, blood_glucose = $9, respiratory_rate = $10,
			waist_circumference = $11, hip_circumference = $12,
			body_fat_percentage = $13, bmi = $14, sleep_duration_minutes = $15,
			sleep_quality = $16, measured_at = $17, device = $18, notes = $19,
			updated_at = $20
		WHERE id = $1 AND deleted_at IS NULL`

	_, err := r.db.Exec(ctx, query,
		v.ID, v.BloodPressureSystolic, v.BloodPressureDiastolic,
		v.Pulse, v.OxygenSaturation, v.Weight, v.Height,
		v.BodyTemperature, v.BloodGlucose, v.RespiratoryRate,
		v.WaistCircumference, v.HipCircumference,
		v.BodyFatPercentage, v.BMI, v.SleepDurationMinutes,
		v.SleepQuality, v.MeasuredAt, v.Device, v.Notes,
		v.UpdatedAt,
	)
	if err != nil {
		return fmt.Errorf("update vital: %w", err)
	}
	return nil
}

func (r *VitalRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx,
		"UPDATE vitals SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL",
		id, time.Now().UTC(),
	)
	if err != nil {
		return fmt.Errorf("soft delete vital: %w", err)
	}
	return nil
}

// CheckDuplicate looks for an entry with similar values within ±2 minutes.
func (r *VitalRepo) CheckDuplicate(ctx context.Context, v *vitals.Vital) (*uuid.UUID, error) {
	query := `
		SELECT id FROM vitals
		WHERE profile_id = $1
		  AND deleted_at IS NULL
		  AND measured_at BETWEEN $2 - INTERVAL '2 minutes' AND $2 + INTERVAL '2 minutes'
		  AND created_at > NOW() - INTERVAL '5 minutes'
		LIMIT 1`

	var existingID uuid.UUID
	err := r.db.QueryRow(ctx, query, v.ProfileID, v.MeasuredAt).Scan(&existingID)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, fmt.Errorf("check duplicate: %w", err)
	}
	return &existingID, nil
}

func (r *VitalRepo) GetChartData(ctx context.Context, profileID uuid.UUID, metric string, from, to *string) ([]vitals.ChartPoint, error) {
	query := fmt.Sprintf(`
		SELECT measured_at, %s
		FROM vitals
		WHERE profile_id = $1 AND deleted_at IS NULL AND %s IS NOT NULL`, metric, metric)

	args := []interface{}{profileID}
	argIdx := 2

	if from != nil {
		query += fmt.Sprintf(" AND measured_at >= $%d", argIdx)
		args = append(args, *from)
		argIdx++
	}
	if to != nil {
		query += fmt.Sprintf(" AND measured_at <= $%d", argIdx)
		args = append(args, *to)
	}

	query += " ORDER BY measured_at ASC"

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("chart query: %w", err)
	}
	defer rows.Close()

	var points []vitals.ChartPoint
	for rows.Next() {
		var p vitals.ChartPoint
		var value interface{}
		if err := rows.Scan(&p.MeasuredAt, &value); err != nil {
			return nil, fmt.Errorf("scan chart point: %w", err)
		}
		p.Values = map[string]interface{}{metric: value}
		points = append(points, p)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("iterate rows: %w", err)
	}

	return points, nil
}

func (r *VitalRepo) scanVital(row pgx.Row) (*vitals.Vital, error) {
	var v vitals.Vital
	err := row.Scan(
		&v.ID, &v.ProfileID, &v.BloodPressureSystolic, &v.BloodPressureDiastolic,
		&v.Pulse, &v.OxygenSaturation, &v.Weight, &v.Height, &v.BodyTemperature,
		&v.BloodGlucose, &v.RespiratoryRate, &v.WaistCircumference, &v.HipCircumference,
		&v.BodyFatPercentage, &v.BMI, &v.SleepDurationMinutes, &v.SleepQuality,
		&v.MeasuredAt, &v.Device, &v.Notes, &v.CreatedAt, &v.UpdatedAt, &v.DeletedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, fmt.Errorf("scan vital: %w", err)
	}
	return &v, nil
}

func (r *VitalRepo) scanVitalRow(rows pgx.Rows) (*vitals.Vital, error) {
	var v vitals.Vital
	err := rows.Scan(
		&v.ID, &v.ProfileID, &v.BloodPressureSystolic, &v.BloodPressureDiastolic,
		&v.Pulse, &v.OxygenSaturation, &v.Weight, &v.Height, &v.BodyTemperature,
		&v.BloodGlucose, &v.RespiratoryRate, &v.WaistCircumference, &v.HipCircumference,
		&v.BodyFatPercentage, &v.BMI, &v.SleepDurationMinutes, &v.SleepQuality,
		&v.MeasuredAt, &v.Device, &v.Notes, &v.CreatedAt, &v.UpdatedAt, &v.DeletedAt,
	)
	if err != nil {
		return nil, fmt.Errorf("scan vital row: %w", err)
	}
	return &v, nil
}
