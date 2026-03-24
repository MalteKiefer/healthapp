package calendar

import (
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestGenerateICS_Empty(t *testing.T) {
	ics := GenerateICS("Test Calendar", "Europe/Berlin", nil)

	assert.Contains(t, ics, "BEGIN:VCALENDAR", "should contain VCALENDAR begin")
	assert.Contains(t, ics, "END:VCALENDAR", "should contain VCALENDAR end")
	assert.Contains(t, ics, "VERSION:2.0", "should contain version 2.0")
	assert.Contains(t, ics, "X-WR-CALNAME:Test Calendar", "should contain calendar name")
	assert.NotContains(t, ics, "BEGIN:VEVENT", "should not contain any VEVENT")
	assert.NotContains(t, ics, "BEGIN:VTODO", "should not contain any VTODO")
}

func TestGenerateICS_SingleEvent(t *testing.T) {
	start := time.Date(2026, 3, 24, 14, 0, 0, 0, time.UTC)
	end := time.Date(2026, 3, 24, 15, 0, 0, 0, time.UTC)
	events := []CalendarEvent{
		{
			UID:         "evt-001",
			Summary:     "Doctor Appointment",
			Description: "Annual checkup",
			Location:    "Clinic",
			Start:       start,
			End:         &end,
		},
	}

	ics := GenerateICS("Health", "UTC", events)

	assert.Contains(t, ics, "BEGIN:VEVENT", "should contain VEVENT begin")
	assert.Contains(t, ics, "END:VEVENT", "should contain VEVENT end")
	assert.Contains(t, ics, "SUMMARY:Doctor Appointment", "should contain event summary")
	assert.Contains(t, ics, "DTSTART:20260324T140000Z", "should contain correct DTSTART")
	assert.Contains(t, ics, "DTEND:20260324T150000Z", "should contain correct DTEND")
	assert.Contains(t, ics, "UID:evt-001@healthvault", "should contain UID")
	assert.Contains(t, ics, "DESCRIPTION:Annual checkup", "should contain description")
	assert.Contains(t, ics, "LOCATION:Clinic", "should contain location")

	// Verify there is exactly one VEVENT
	assert.Equal(t, 1, strings.Count(ics, "BEGIN:VEVENT"), "should have exactly one VEVENT")
}

func TestGenerateICS_Todo(t *testing.T) {
	start := time.Date(2026, 4, 1, 0, 0, 0, 0, time.UTC)
	events := []CalendarEvent{
		{
			UID:     "todo-001",
			Summary: "Take medication",
			Start:   start,
			IsTodo:  true,
		},
	}

	ics := GenerateICS("Tasks", "UTC", events)

	assert.Contains(t, ics, "BEGIN:VTODO", "should contain VTODO begin")
	assert.Contains(t, ics, "END:VTODO", "should contain VTODO end")
	assert.Contains(t, ics, "SUMMARY:Take medication", "should contain todo summary")
	assert.Contains(t, ics, "STATUS:NEEDS-ACTION", "should default to NEEDS-ACTION status")
	assert.NotContains(t, ics, "BEGIN:VEVENT", "should not contain VEVENT for a todo")
}

func TestGenerateICS_Alarm(t *testing.T) {
	start := time.Date(2026, 3, 24, 14, 0, 0, 0, time.UTC)
	events := []CalendarEvent{
		{
			UID:     "evt-alarm",
			Summary: "Lab Results",
			Start:   start,
			Alarms: []Alarm{
				{
					TriggerBefore: 15 * time.Minute,
					Description:   "Upcoming lab appointment",
				},
			},
		},
	}

	ics := GenerateICS("Health", "UTC", events)

	assert.Contains(t, ics, "BEGIN:VALARM", "should contain VALARM begin")
	assert.Contains(t, ics, "END:VALARM", "should contain VALARM end")
	assert.Contains(t, ics, "TRIGGER:", "should contain TRIGGER")
	assert.Contains(t, ics, "ACTION:DISPLAY", "should contain ACTION:DISPLAY")
	assert.Contains(t, ics, "DESCRIPTION:Upcoming lab appointment", "should contain alarm description")

	// The alarm should be nested inside the event
	veventStart := strings.Index(ics, "BEGIN:VEVENT")
	veventEnd := strings.Index(ics, "END:VEVENT")
	valarmStart := strings.Index(ics, "BEGIN:VALARM")
	assert.Greater(t, valarmStart, veventStart, "VALARM should be after VEVENT start")
	assert.Less(t, valarmStart, veventEnd, "VALARM should be before VEVENT end")
}
