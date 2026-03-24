package calendar

import (
	"fmt"
	"strings"
	"time"
)

// GenerateICS produces a valid iCalendar document from a list of events.
func GenerateICS(calName, timezone string, events []CalendarEvent) string {
	var b strings.Builder

	b.WriteString("BEGIN:VCALENDAR\r\n")
	b.WriteString("VERSION:2.0\r\n")
	b.WriteString("PRODID:-//HealthVault//HealthVault v1.0//EN\r\n")
	b.WriteString("CALSCALE:GREGORIAN\r\n")
	b.WriteString("METHOD:PUBLISH\r\n")
	b.WriteString(fmt.Sprintf("X-WR-CALNAME:%s\r\n", escapeICS(calName)))
	b.WriteString(fmt.Sprintf("X-WR-TIMEZONE:%s\r\n", timezone))
	b.WriteString("REFRESH-INTERVAL;VALUE=DURATION:PT1H\r\n")
	b.WriteString("X-PUBLISHED-TTL:PT1H\r\n")

	for _, ev := range events {
		if ev.IsTodo {
			writeTodo(&b, ev)
		} else {
			writeEvent(&b, ev)
		}
	}

	b.WriteString("END:VCALENDAR\r\n")
	return b.String()
}

func writeEvent(b *strings.Builder, ev CalendarEvent) {
	b.WriteString("BEGIN:VEVENT\r\n")
	b.WriteString(fmt.Sprintf("UID:%s@healthvault\r\n", ev.UID))
	b.WriteString(fmt.Sprintf("DTSTAMP:%s\r\n", formatDateTime(time.Now().UTC())))

	if ev.AllDay {
		b.WriteString(fmt.Sprintf("DTSTART;VALUE=DATE:%s\r\n", formatDate(ev.Start)))
	} else {
		b.WriteString(fmt.Sprintf("DTSTART:%s\r\n", formatDateTime(ev.Start)))
		if ev.End != nil {
			b.WriteString(fmt.Sprintf("DTEND:%s\r\n", formatDateTime(*ev.End)))
		}
	}

	b.WriteString(fmt.Sprintf("SUMMARY:%s\r\n", escapeICS(ev.Summary)))

	if ev.Description != "" {
		b.WriteString(fmt.Sprintf("DESCRIPTION:%s\r\n", escapeICS(ev.Description)))
	}
	if ev.Location != "" {
		b.WriteString(fmt.Sprintf("LOCATION:%s\r\n", escapeICS(ev.Location)))
	}

	for _, alarm := range ev.Alarms {
		writeAlarm(b, alarm)
	}

	b.WriteString("END:VEVENT\r\n")
}

func writeTodo(b *strings.Builder, ev CalendarEvent) {
	b.WriteString("BEGIN:VTODO\r\n")
	b.WriteString(fmt.Sprintf("UID:%s@healthvault\r\n", ev.UID))
	b.WriteString(fmt.Sprintf("DTSTAMP:%s\r\n", formatDateTime(time.Now().UTC())))
	b.WriteString(fmt.Sprintf("DUE;VALUE=DATE:%s\r\n", formatDate(ev.Start)))
	b.WriteString(fmt.Sprintf("SUMMARY:%s\r\n", escapeICS(ev.Summary)))

	if ev.Status != "" {
		b.WriteString(fmt.Sprintf("STATUS:%s\r\n", ev.Status))
	} else {
		b.WriteString("STATUS:NEEDS-ACTION\r\n")
	}
	if ev.Priority > 0 {
		b.WriteString(fmt.Sprintf("PRIORITY:%d\r\n", ev.Priority))
	}
	if ev.Description != "" {
		b.WriteString(fmt.Sprintf("DESCRIPTION:%s\r\n", escapeICS(ev.Description)))
	}

	b.WriteString("END:VTODO\r\n")
}

func writeAlarm(b *strings.Builder, a Alarm) {
	b.WriteString("BEGIN:VALARM\r\n")
	b.WriteString(fmt.Sprintf("TRIGGER:%s\r\n", formatDuration(a.TriggerBefore)))
	b.WriteString("ACTION:DISPLAY\r\n")
	b.WriteString(fmt.Sprintf("DESCRIPTION:%s\r\n", escapeICS(a.Description)))
	b.WriteString("END:VALARM\r\n")
}

func formatDateTime(t time.Time) string {
	return t.UTC().Format("20060102T150405Z")
}

func formatDate(t time.Time) string {
	return t.Format("20060102")
}

func formatDuration(d time.Duration) string {
	if d <= 0 {
		return "-PT0S"
	}
	neg := "-"
	days := int(d.Hours() / 24)
	hours := int(d.Hours()) % 24
	minutes := int(d.Minutes()) % 60

	if days > 0 && hours == 0 && minutes == 0 {
		return fmt.Sprintf("%sP%dD", neg, days)
	}
	if days > 0 {
		return fmt.Sprintf("%sP%dDT%dH%dM", neg, days, hours, minutes)
	}
	if hours > 0 {
		return fmt.Sprintf("%sPT%dH", neg, hours)
	}
	return fmt.Sprintf("%sPT%dM", neg, minutes)
}

func escapeICS(s string) string {
	s = strings.ReplaceAll(s, "\\", "\\\\")
	s = strings.ReplaceAll(s, ";", "\\;")
	s = strings.ReplaceAll(s, ",", "\\,")
	s = strings.ReplaceAll(s, "\n", "\\n")
	return s
}
