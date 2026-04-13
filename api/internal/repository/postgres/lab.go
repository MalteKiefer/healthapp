package postgres

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/healthvault/healthvault/internal/domain/labs"
)

type LabRepo struct {
	db *pgxpool.Pool
}

func NewLabRepo(db *pgxpool.Pool) *LabRepo {
	return &LabRepo{db: db}
}

const labResultColumns = `id, profile_id, lab_name, ordered_by, sample_date, result_date, notes,
	version, previous_id, is_current, created_at, updated_at, deleted_at`

const labValueColumns = `id, lab_result_id, marker, value, value_text, unit, reference_low, reference_high, flag`

func (r *LabRepo) Create(ctx context.Context, lr *labs.LabResult) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	if lr.ID == uuid.Nil {
		lr.ID = uuid.New()
	}
	now := time.Now().UTC()
	lr.CreatedAt = now
	lr.UpdatedAt = now
	lr.Version = 1
	lr.IsCurrent = true

	_, err = tx.Exec(ctx, `
		INSERT INTO lab_results (id, profile_id, lab_name, ordered_by, sample_date, result_date, notes,
			version, previous_id, is_current, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
		lr.ID, lr.ProfileID, lr.LabName, lr.OrderedBy, lr.SampleDate, lr.ResultDate, lr.Notes,
		lr.Version, lr.PreviousID, lr.IsCurrent, lr.CreatedAt, lr.UpdatedAt)
	if err != nil {
		return fmt.Errorf("insert lab_result: %w", err)
	}

	for i := range lr.Values {
		v := &lr.Values[i]
		if v.ID == uuid.Nil {
			v.ID = uuid.New()
		}
		v.LabResultID = lr.ID
		_, err = tx.Exec(ctx, `
			INSERT INTO lab_values (id, lab_result_id, marker, value, value_text, unit, reference_low, reference_high, flag)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
			v.ID, v.LabResultID, v.Marker, v.Value, v.ValueText, v.Unit, v.ReferenceLow, v.ReferenceHigh, v.Flag)
		if err != nil {
			return fmt.Errorf("insert lab_value: %w", err)
		}
	}

	return tx.Commit(ctx)
}

func (r *LabRepo) GetByID(ctx context.Context, id uuid.UUID) (*labs.LabResult, error) {
	var lr labs.LabResult
	err := r.db.QueryRow(ctx, `SELECT `+labResultColumns+` FROM lab_results WHERE id = $1 AND deleted_at IS NULL`, id).Scan(
		&lr.ID, &lr.ProfileID, &lr.LabName, &lr.OrderedBy, &lr.SampleDate, &lr.ResultDate, &lr.Notes,
		&lr.Version, &lr.PreviousID, &lr.IsCurrent, &lr.CreatedAt, &lr.UpdatedAt, &lr.DeletedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("scan lab_result: %w", err)
	}

	values, err := r.getValues(ctx, lr.ID)
	if err != nil {
		return nil, err
	}
	lr.Values = values
	return &lr, nil
}

func (r *LabRepo) List(ctx context.Context, profileID uuid.UUID, limit, offset int) ([]labs.LabResult, int, error) {
	var total int
	if err := r.db.QueryRow(ctx,
		"SELECT COUNT(*) FROM lab_results WHERE profile_id = $1 AND is_current = TRUE AND deleted_at IS NULL",
		profileID).Scan(&total); err != nil {
		return nil, 0, fmt.Errorf("count lab_results: %w", err)
	}

	rows, err := r.db.Query(ctx, `SELECT `+labResultColumns+`
		FROM lab_results WHERE profile_id = $1 AND is_current = TRUE AND deleted_at IS NULL
		ORDER BY created_at DESC LIMIT $2 OFFSET $3`, profileID, limit, offset)
	if err != nil {
		return nil, 0, fmt.Errorf("query lab_results: %w", err)
	}
	defer rows.Close()

	var results []labs.LabResult
	for rows.Next() {
		var lr labs.LabResult
		if err := rows.Scan(&lr.ID, &lr.ProfileID, &lr.LabName, &lr.OrderedBy, &lr.SampleDate, &lr.ResultDate, &lr.Notes,
			&lr.Version, &lr.PreviousID, &lr.IsCurrent, &lr.CreatedAt, &lr.UpdatedAt, &lr.DeletedAt); err != nil {
			return nil, 0, fmt.Errorf("scan lab_result row: %w", err)
		}
		results = append(results, lr)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, fmt.Errorf("iterate rows: %w", err)
	}

	// Batch-load all lab values
	if len(results) > 0 {
		ids := make([]uuid.UUID, len(results))
		for i, lr := range results {
			ids[i] = lr.ID
		}

		valRows, err := r.db.Query(ctx, `SELECT `+labValueColumns+`
			FROM lab_values WHERE lab_result_id = ANY($1) ORDER BY lab_result_id`, ids)
		if err != nil {
			return nil, 0, fmt.Errorf("batch query lab_values: %w", err)
		}
		defer valRows.Close()

		valMap := make(map[uuid.UUID][]labs.LabValue)
		for valRows.Next() {
			var v labs.LabValue
			if err := valRows.Scan(&v.ID, &v.LabResultID, &v.Marker, &v.Value, &v.ValueText, &v.Unit,
				&v.ReferenceLow, &v.ReferenceHigh, &v.Flag); err != nil {
				return nil, 0, fmt.Errorf("scan lab_value: %w", err)
			}
			valMap[v.LabResultID] = append(valMap[v.LabResultID], v)
		}
		for i := range results {
			results[i].Values = valMap[results[i].ID]
		}
	}

	return results, total, nil
}

func (r *LabRepo) Update(ctx context.Context, lr *labs.LabResult) error {
	tx, err := r.db.Begin(ctx)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback(ctx)

	_, err = tx.Exec(ctx, "UPDATE lab_results SET is_current = FALSE, updated_at = $2 WHERE id = $1",
		lr.ID, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("mark old version: %w", err)
	}

	previousID := lr.ID
	lr.PreviousID = &previousID
	lr.ID = uuid.New()
	lr.Version++
	lr.IsCurrent = true
	now := time.Now().UTC()
	lr.CreatedAt = now
	lr.UpdatedAt = now

	_, err = tx.Exec(ctx, `
		INSERT INTO lab_results (id, profile_id, lab_name, ordered_by, sample_date, result_date, notes,
			version, previous_id, is_current, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`,
		lr.ID, lr.ProfileID, lr.LabName, lr.OrderedBy, lr.SampleDate, lr.ResultDate, lr.Notes,
		lr.Version, lr.PreviousID, lr.IsCurrent, lr.CreatedAt, lr.UpdatedAt)
	if err != nil {
		return fmt.Errorf("insert new version: %w", err)
	}

	for i := range lr.Values {
		v := &lr.Values[i]
		v.ID = uuid.New()
		v.LabResultID = lr.ID
		_, err = tx.Exec(ctx, `
			INSERT INTO lab_values (id, lab_result_id, marker, value, value_text, unit, reference_low, reference_high, flag)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
			v.ID, v.LabResultID, v.Marker, v.Value, v.ValueText, v.Unit, v.ReferenceLow, v.ReferenceHigh, v.Flag)
		if err != nil {
			return fmt.Errorf("insert lab_value: %w", err)
		}
	}

	return tx.Commit(ctx)
}

func (r *LabRepo) SoftDelete(ctx context.Context, id uuid.UUID) error {
	_, err := r.db.Exec(ctx, "UPDATE lab_results SET deleted_at = $2 WHERE id = $1 AND deleted_at IS NULL", id, time.Now().UTC())
	if err != nil {
		return fmt.Errorf("soft delete lab result: %w", err)
	}
	return nil
}

func (r *LabRepo) CheckDuplicate(ctx context.Context, lr *labs.LabResult) (*uuid.UUID, error) {
	var existingID uuid.UUID
	err := r.db.QueryRow(ctx, `
		SELECT id FROM lab_results
		WHERE profile_id = $1 AND deleted_at IS NULL AND is_current = TRUE
		AND created_at BETWEEN $2 - INTERVAL '2 minutes' AND $2 + INTERVAL '2 minutes'
		LIMIT 1`, lr.ProfileID, lr.CreatedAt).Scan(&existingID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("check duplicate: %w", err)
	}
	return &existingID, nil
}

func (r *LabRepo) getValues(ctx context.Context, labResultID uuid.UUID) ([]labs.LabValue, error) {
	rows, err := r.db.Query(ctx, `SELECT `+labValueColumns+` FROM lab_values WHERE lab_result_id = $1`, labResultID)
	if err != nil {
		return nil, fmt.Errorf("query lab_values: %w", err)
	}
	defer rows.Close()

	var values []labs.LabValue
	for rows.Next() {
		var v labs.LabValue
		if err := rows.Scan(&v.ID, &v.LabResultID, &v.Marker, &v.Value, &v.ValueText, &v.Unit,
			&v.ReferenceLow, &v.ReferenceHigh, &v.Flag); err != nil {
			return nil, fmt.Errorf("scan lab_value: %w", err)
		}
		values = append(values, v)
	}
	return values, rows.Err()
}

func (r *LabRepo) ListTrends(ctx context.Context, profileID uuid.UUID, from, to *time.Time) ([]labs.MarkerTrend, error) {
	query := `
		SELECT lv.marker, lv.value, lv.unit, lv.reference_low, lv.reference_high, lv.flag, lr.sample_date
		FROM lab_values lv
		JOIN lab_results lr ON lr.id = lv.lab_result_id
		WHERE lr.profile_id = $1 AND lr.is_current = TRUE AND lr.deleted_at IS NULL
		AND lv.value IS NOT NULL`

	args := []interface{}{profileID}
	argIdx := 2
	if from != nil {
		query += fmt.Sprintf(" AND lr.sample_date >= $%d", argIdx)
		args = append(args, *from)
		argIdx++
	}
	if to != nil {
		query += fmt.Sprintf(" AND lr.sample_date <= $%d", argIdx)
		args = append(args, *to)
	}
	query += " ORDER BY lv.marker, lr.sample_date"

	rows, err := r.db.Query(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("query trends: %w", err)
	}
	defer rows.Close()

	trendMap := make(map[string]*labs.MarkerTrend)
	for rows.Next() {
		var marker string
		var value float64
		var unit *string
		var refLow, refHigh *float64
		var flag *string
		var sampleDate time.Time
		if err := rows.Scan(&marker, &value, &unit, &refLow, &refHigh, &flag, &sampleDate); err != nil {
			return nil, fmt.Errorf("scan trend row: %w", err)
		}
		t, ok := trendMap[marker]
		if !ok {
			t = &labs.MarkerTrend{Marker: marker, Unit: unit, ReferenceLow: refLow, ReferenceHigh: refHigh}
			trendMap[marker] = t
		}
		t.DataPoints = append(t.DataPoints, labs.TrendDataPoint{Date: sampleDate, Value: value, Flag: flag})
	}

	var trends []labs.MarkerTrend
	for _, t := range trendMap {
		trends = append(trends, *t)
	}
	return trends, nil
}
