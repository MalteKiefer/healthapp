# Changelog

## [Unreleased]

### Added

#### Infrastructure
- Initial project skeleton with full infrastructure (Docker Compose, Caddy, PostgreSQL, Redis, backup container) (`9c25aa7`)

#### Backend
- Authentication, user profiles, and vitals modules (`8417dde`)
- All health data modules (medications, allergies, immunizations, conditions, procedures, labs, symptoms, diary, emergency) (`bd2c831`)
- ICS calendar feeds, notifications, families, and CI/CD pipeline (`fbb3ae9`)
- Family sharing handlers wired into the router (`4cd1f66`)
- User management, labs, emergency access, and search endpoints (`5fb23eb`)
- Admin panel handlers wired into the router (`57fe2d7`)
- Contacts, tasks, appointments, and symptoms handlers wired into the router (`39d6c61`)
- 2FA TOTP, FHIR R4 export, webhooks, legal endpoints, and diary/settings UI (`fc47e98`)
- 100% API coverage -- all endpoint stubs eliminated (`d695e0e`)

#### Frontend
- React PWA initialized with full routing and auth (`bcd8860`)
- Vitals UI with interactive charts (`5fb23eb`)
- All 13 frontend pages completed -- zero placeholders remain (`d0490ac`)
