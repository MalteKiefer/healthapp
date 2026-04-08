# HealthVault — Vollständiges Code Review, Design Review & Security Audit

**Datum:** 2026-04-08
**Scope:** Gesamtes Repository (`mobile/`, `api/`, `web/`, `deploy/`, `backup/`, CI/CD)
**Methode:** 42 parallele Analyse-Agenten, 48.000+ Zeilen Code
**Bewertungsskala:** Critical > High/Important > Medium > Low

---

## Executive Summary

HealthVault ist eine funktionale, gut strukturierte Health-Data-Plattform mit modernem Stack (Go, React/Vite, Flutter/Riverpod). Die Ende-zu-Ende-Verschlüsselung ist architektonisch angelegt aber **auf dem Client noch nicht vollständig implementiert**. Es gibt **kritische Sicherheitslücken** in der Authentifizierung, der Kryptographie und der Deployment-Konfiguration, die vor einem Produktiveinsatz behoben werden müssen.

### Statistik (final, alle 42 Agenten)

| Severity | Anzahl |
|----------|--------|
| **CRITICAL** | 62 |
| **IMPORTANT** | 94 |
| **MEDIUM/LOW** | ~50 |
| **Gesamt** | **~206 Findings** |

---

## Teil 1: Security Audit — Kritische Findings

### 1.1 Authentifizierung & Session Management

| # | Finding | Severity | Datei |
|---|---------|----------|-------|
| S1 | **Recovery Codes umgehen 2FA komplett** — `HandleRecovery` ruft `completeLogin` ohne TOTP-Check auf | CRITICAL | `api/handlers/auth.go:671-738` |
| S2 | **Refresh Token überlebt Logout** — nur Access Token wird denied, Refresh bleibt gültig | CRITICAL | `api/handlers/auth.go:639-661` |
| S3 | **Logout-Route liegt außerhalb JWTAuth-Middleware** — Cookies werden nie gelöscht | CRITICAL | `api/router.go:216` |
| S4 | **Session-Timeout auf User-ID statt Session-ID** — eine Session hält alle anderen am Leben | CRITICAL | `api/middleware/timeout.go:32` |
| S5 | **Rate Limiter per X-Forwarded-For spoofbar** — unbegrenzte Login-Versuche möglich | CRITICAL | `api/middleware/ratelimit.go:105` |
| S6 | **TOTP-Disable ohne Passwort-Bestätigung** — nur TOTP-Code nötig | CRITICAL | `api/handlers/totp.go:150-201` |
| S7 | **TOTP-Codes nicht replay-geschützt** — 90s Fenster ohne Used-Code-Store | IMPORTANT | `api/handlers/totp.go:132` |
| S8 | **Passwort-Änderung denied nicht den aktuellen Access Token** — 15min Weiterbenutzung | IMPORTANT | `api/handlers/users.go:430` |
| S9 | **Email-Enumeration über Register-Init** — `409` vs `200` unterscheidbar | IMPORTANT | `api/handlers/auth.go:233-237` |
| S10 | **Recovery: Lineare Argon2id-Scan über 10 Hashes** — CPU-DoS-Vektor | HIGH | `api/handlers/auth.go:714-724` |

### 1.2 Kryptographie

| # | Finding | Severity | Datei |
|---|---------|----------|-------|
| K1 | **Deterministic Salt (SHA-256 der Email)** für PBKDF2 — Rainbow-Table-Angriff möglich | CRITICAL | `web/crypto/keys.ts:182`, `mobile/crypto/auth_crypto.dart:11` |
| K2 | **Auth-Hash persistent gespeichert** — statisches Passwort-Äquivalent im Keychain | CRITICAL | `mobile/auth/auth_service.dart:16` |
| K3 | **TOTP-2FA wird auf Mobile komplett übersprungen** — `requires_totp` wird nie geprüft | CRITICAL | `mobile/main.dart:57-60` |
| K4 | **Encryption Key aus JWT Private Key abgeleitet** — Kompromittierung kaskadiert | CRITICAL | `api/crypto/jwt.go:226-244` |
| K5 | **AES-GCM Nonce-Kollisionsrisiko** bei hohem Volumen mit statischem Key | CRITICAL | `api/crypto/aesgcm.go:28-33` |
| K6 | **Signing-Keypair ist ECDH statt ECDSA** — kann keine Signaturen erstellen | CRITICAL | `web/Register.tsx:108` |
| K7 | **Unwrapped Profile Key ist `extractable: true`** — XSS kann Key exfiltrieren | HIGH | `web/crypto/encrypt.ts:120` |
| K8 | **Keine AES-GCM Tests vorhanden** | HIGH | `api/crypto/` (kein test file) |
| K9 | **Korrupte Key-Datei triggert leise Legacy-Derivation** | HIGH | `api/crypto/jwt.go:219-222` |
| K10 | **`pekSalt` auf Mobile nie benutzt** — Zero-Knowledge-Architektur nicht implementiert | MEDIUM | `mobile/models/auth.dart:16` |

### 1.3 SQL Injection & Injection

| # | Finding | Severity | Datei |
|---|---------|----------|-------|
| I1 | **SQL Injection in `GetChartData`** — `metric` per `fmt.Sprintf` in Query interpoliert | CRITICAL | `api/repository/postgres/vital.go:178-181` |
| I2 | **Webhook SSRF-Filter fehlt Cloud-Metadata-Range** — `169.254.0.0/16` nicht blockiert | CRITICAL | `api/handlers/webhooks.go:88-98` |
| I3 | **Content-Disposition Header Injection** via Filename mit Newlines | CRITICAL | `api/handlers/documents.go:464` |
| I4 | **MIME Type vom Client akzeptiert** — kein Server-Side-Validation | CRITICAL | `api/handlers/documents.go:152` |
| I5 | **Kein File-Size-Limit nach Upload** — Disk Exhaustion möglich | CRITICAL | `api/handlers/documents.go:110-146` |

### 1.4 Deployment & Infrastructure

| # | Finding | Severity | Datei |
|---|---------|----------|-------|
| D1 | **DB_SSLMODE=disable** — Datenbank-Traffic unverschlüsselt | CRITICAL | `docker-compose.yml:27` |
| D2 | **PgBouncer-Config nie gemountet** — alle Hardening-Settings inaktiv | CRITICAL | `docker-compose.yml:59-73` |
| D3 | **Cleartext HTTP in Production-Manifest erlaubt** | CRITICAL | `mobile/android/network_security_config.xml:3` |
| D4 | **HTTPS-Downgrade in URL-Discovery** — HTTP-Fallback für alle Hosts | CRITICAL | `mobile/api/api_client.dart:44` |
| D5 | **Release-APK mit Debug-Keystore signiert** | CRITICAL | `mobile/android/build.gradle.kts:37` |
| D6 | **Trivy-Action auf `@master` gepinnt** — Supply-Chain-Risiko | CRITICAL | `release.yml:118` |
| D7 | **Image wird vor Security-Scan gepusht** | CRITICAL | `release.yml:111` |
| D8 | **Backend-Tests in CI deaktiviert** — PRs mergen ungetestet | CRITICAL | `ci.yml:29` |
| D9 | **Backup-Encryption-Key in `/proc/cmdline` sichtbar** | CRITICAL | `backup/backup.sh:22` |
| D10 | **`emergency_cards.data` nicht verschlüsselt** — Plaintext-PHI in DB | CRITICAL | `migrations/000001:532` |
| D11 | **Redis an 0.0.0.0 gebunden** ohne Cloud-Metadata-Schutz | CRITICAL | `deploy/redis/redis.conf:4` |
| D12 | **`go 1.26.1` in go.mod** — diese Go-Version existiert nicht | IMPORTANT | `api/go.mod:3` |

### 1.5 Consent & GDPR

| # | Finding | Severity | Datei |
|---|---------|----------|-------|
| G1 | **Consent-Middleware fails open** bei DB-Fehler — GDPR-Bypass | CRITICAL | `api/middleware/consent.go:56-59` |
| G2 | **Rate Limiter fails closed** obwohl Doku "fail open" sagt | CRITICAL | `api/middleware/ratelimit.go:51` |
| G3 | **Audit-Log in detachiertem Goroutine** — Verlust bei Shutdown möglich | CRITICAL | `api/middleware/audit.go:68-73` |

---

## Teil 2: Code Review — Go API Backend

### 2.1 Architektur (Score: 6/10)

**Positiv:**
- Standard Go Project Layout korrekt umgesetzt
- Domain-Packages gut strukturiert mit Interface/Model-Trennung
- Parameterisierte SQL-Queries durchgehend (außer `GetChartData`)
- Soft-Delete konsistent implementiert

**Probleme:**
- **~17 Handler nehmen raw `*pgxpool.Pool`** statt Repository-Interface — nicht testbar
- **Middleware importiert Handlers** — zirkuläre Abhängigkeitsrichtung
- **Kein Service-Layer** zwischen Handlers und Repositories
- **`AuditWriter` definiert aber nie registriert** — Audit-Logik in Handlers dupliziert
- **`registrationMode()` ignoriert Config-Struct** — liest direkt aus DB/Env

### 2.2 API Design Probleme

| Finding | Datei |
|---------|-------|
| `GET /recovery-codes` führt destruktive Mutation aus | `router.go:236` |
| `HandleGetSettings` ist eigentlich ein PATCH-Handler | `admin.go:467` |
| URL-Param-Mismatch: `medID` vs `medicationID` — **Intake-CRUD komplett kaputt** | `medications.go:433,515` |
| URL-Param-Mismatch: `vaccID` vs `vaccinationID` — **Vaccination-CRUD kaputt** | `vaccinations.go:144,189,245` |
| URL-Param-Mismatch: `diagID` vs `diagnosisID` — **Diagnosen-CRUD kaputt** | `diagnoses.go:155,200,261` |
| `notifications/model.go` leer — Package kompiliert nicht | `notifications/model.go:1` |
| Keine OpenAPI-Spec für ~120 Routes | — |

### 2.3 Migration & Config

| Finding | Severity | Datei |
|---------|----------|-------|
| Migrations laufen ohne Transaktion — Crash = korrupter Schema-State | CRITICAL | `main.go:562-595` |
| `getEnvInt`/`getEnvDuration` schlucken Parse-Fehler leise | IMPORTANT | `config.go:142-164` |
| DSN enthält Passwort als URL-String — leakt in Error-Logs | IMPORTANT | `config.go:118-123` |
| Redis ohne TLS-Option | IMPORTANT | `cache/redis.go:14-24` |
| `migrateDown` aktualisiert `schema_migrations` nicht nach Rollback | IMPORTANT | `main.go:310-371` |

---

## Teil 3: Code Review — Web Frontend

### 3.1 Architektur (Score: 7/10)

**Positiv:**
- TypeScript `strict` mode aktiviert
- Alle Routes lazy-loaded mit Suspense
- Token-Refresh-Deduplication korrekt implementiert
- Crypto-Module sauber separiert
- Idle-Timeout mit passiven Event-Listenern

**Probleme:**
- **`xlsx` v0.18.5** — abandoned, CVE-2023-30533 (Prototype Pollution)
- **`escapeValue: true` in i18n** — Double-Encoding in React
- **Vitals/Profiles duplizieren Crypto-Logik** statt `encryptedEntity.ts` zu nutzen
- **React Query Cache wird bei Logout nicht gelöscht** — PHI bleibt im Speicher
- **`useMemo` als Side-Effect** in `Vitals.tsx:200` (sollte `useEffect` sein)
- **Migration Queue Race Condition** — concurrent drain möglich
- **Document-Upload umgeht Auth-Refresh** — nutzt raw `fetch` statt API-Client
- **Silent Data Loss**: Write ohne Profile Key schickt leere `content_enc`

### 3.2 Crypto (Web)

| Finding | Severity |
|---------|----------|
| Auth-Hash nutzt deterministischen Email-Salt statt Server-Salt | CRITICAL |
| Signing-Keypair ist ECDH (kann nicht signieren) | CRITICAL |
| Profile Key als `extractable: true` importiert | HIGH |
| HKDF-Salt ist `Uint8Array(0)` — schwächt formales Sicherheitsmodell | HIGH |
| Recovery Codes: 80 Bit Entropie, Kommentar sagt 128 Bit | HIGH |
| `_pek_salt_tmp` in localStorage statt sessionStorage, kein Cleanup bei Fehler | HIGH |
| Keine Tests für encrypt/decrypt/wrapKey/unwrapKey/ECDH | LOW |

### 3.3 Components & Pages

| Finding | Datei |
|---------|-------|
| OCR: Kein File-Size-Limit, MIME nur per Extension geprüft, Object-URL-Leak | `OCRUpload.tsx` |
| OCR: Reference-Range-Split bricht bei negativen Werten / En-Dash | `OCRUpload.tsx:89` |
| LabTrendsView crash bei leerem `data_points`-Array | `LabTrendsView.tsx:168` |
| ConfirmDelete: Kein `role="dialog"`, kein Focus-Trap, kein Escape-Key | `ConfirmDelete.tsx` |
| Dashboard blockiert komplett wenn ein Query lädt | `Dashboard.tsx:155` |
| Mutations ohne `onError` in 4+ Seiten — leise Fehler | Diagnoses, Vaccinations, etc. |
| `fixDates` 3x copy-pasted statt extrahiert | Diagnoses, Vaccinations, Tasks |

---

## Teil 4: Flutter / Mobile Review

### 4.1 Architektur (Score: 5/10)

| Bereich | Score |
|---------|-------|
| Architecture Pattern | 5/10 |
| Folder Structure | 6/10 |
| Separation of Concerns | 4/10 |
| Dependency Injection | 5/10 |
| Code Quality | 6/10 |
| Widget Composition | 6/10 |

### 4.2 Kritische Mobile Findings

| # | Finding | Severity | Datei |
|---|---------|----------|-------|
| M1 | **Auth-Hash persistent gespeichert & replayed** — Passwort-Äquivalent | CRITICAL | `auth_service.dart:16` |
| M2 | **CookieJar nur in-memory** — erzwingt Credential-Replay bei jedem Neustart | CRITICAL | `api_client.dart:17` |
| M3 | **HTTPS zu HTTP Downgrade** bei URL-Discovery | CRITICAL | `api_client.dart:44` |
| M4 | **TOTP komplett übersprungen** — `requires_totp` wird nie geprüft | CRITICAL | `login_screen.dart:75-79` |
| M5 | **Kein Auth-Route-Guard** — alle Routes ohne Schutz erreichbar | CRITICAL | `app_router.dart:22` |
| M6 | **Splash-Route navigiert nie weiter** — ewiger Spinner möglich | CRITICAL | `app_router.dart:25-30` |
| M7 | **`_downloadPdf` verwirft heruntergeladene Bytes** — Feature kaputt | CRITICAL | `documents_screen.dart:345-364` |
| M8 | **Duplicate Provider-Deklarationen** — Home vs Detail-Screen zeigen inkonsistente Daten | CRITICAL | `home_screen.dart:14-45` |
| M9 | **Alle `fromJson`-Factories crashen bei null** — bare `json['id']` ohne Null-Check | CRITICAL | Alle Model-Dateien |
| M10 | **Shared Widgets existieren aber werden nie benutzt** — alles inline dupliziert | IMPORTANT | `widgets/` + alle Screens |

### 4.3 UI/UX Probleme

| Finding | Betroffen |
|---------|-----------|
| Long-Press als einziger Delete-Mechanismus — nicht entdeckbar | Alle Screens |
| 10+ hardcoded deutsche Strings in `documents_screen.dart` | `documents_screen.dart` |
| 6 hardcoded englische Labels im Home-Screen | `home_screen.dart:357-408` |
| Zero Accessibility/Semantics Labels im gesamten Codebase | Alle Screens |
| `Navigator.pop()` vor API-Call — Fehler nicht korrigierbar | 9 Screens |
| Delete-Dialog 11x copy-pasted, Error-Widget 13x, Form-Sheet 11x | Alle Screens |
| Kein Pull-to-Refresh außer Home-Screen | 9 von 10 Screens |
| `intl: any` — unbounded Dependency | `pubspec.yaml:52` |
| `CFBundleDisplayName` = "Healthapp" statt "HealthVault" | `Info.plist` |

---

## Teil 5: CI/CD & Testing

| Finding | Severity |
|---------|----------|
| **Backend-Tests in CI deaktiviert** — alle PRs mergen ohne Tests | CRITICAL |
| **Go-Version-Mismatch**: CI=1.26, Release=1.22, Security=1.22 | CRITICAL |
| **Trivy auf `@master` gepinnt** — Supply-Chain-Risiko mit Write-Permissions | CRITICAL |
| **Image vor Scan gepusht** — verwundbare Images öffentlich verfügbar | CRITICAL |
| **E2E-Tests nicht in CI integriert** — Playwright läuft nie automatisch | CRITICAL |
| Kein Frontend-Lint/Test/Build-Job in CI | IMPORTANT |
| `web` und `backup` Docker-Images nie in CI gebaut | IMPORTANT |
| Weekly Trivy-Scan mit `exit-code: 0` — Fehler leise | IMPORTANT |
| `govulncheck@latest` unpinned | IMPORTANT |
| `make deploy` = raw `git push main` — umgeht gesamte Pipeline | IMPORTANT |
| 2FA-Login-Flow hat keinerlei Tests (E2E, Unit, Integration) | IMPORTANT |
| Nur 8 E2E-Testfälle für 22 Routes | IMPORTANT |

---

## Teil 6: Backup & Disaster Recovery

| Finding | Severity |
|---------|----------|
| Encryption Key in Prozessliste sichtbar (`/proc/cmdline`) | CRITICAL |
| HMAC nutzt denselben Key wie Encryption | CRITICAL |
| `record_result` Funktion aufgerufen aber nie definiert | CRITICAL |
| Entschlüsselter Dump in vorhersagbarem `/tmp`-Pfad | CRITICAL |
| Kein Off-Site-Backup — alles auf derselben Maschine | IMPORTANT |
| `verify.sh` prüft HMAC nicht vor Restore | IMPORTANT |
| Backup-Container läuft als Root | IMPORTANT |
| Redis-State wird nicht gesichert | IMPORTANT |

---

## Teil 7: Dokumentation

| Finding | Severity |
|---------|----------|
| CHANGELOG hat keine versionierten Releases | CRITICAL |
| README und SETUP.md referenzieren unterschiedliche Setup-Flows | CRITICAL |
| API-Doku ohne Request/Response-Schemas oder Error Codes | CRITICAL |
| `docs/superpowers/` enthält absolute Entwickler-Pfade | IMPORTANT |
| Go-Version "1.26" in README — existiert nicht | IMPORTANT |
| Kein CONTRIBUTING.md | IMPORTANT |
| `web/README.md` und `mobile/README.md` sind unmodifizierte Templates | LOW |

---

## Teil 8: Zusätzliche Findings (finale Agenten-Runde)

### 8.1 Onboarding sendet Plaintext-Passphrase (NEUES CRITICAL Finding)

| Finding | Severity | Datei |
|---------|----------|-------|
| **`Onboarding.tsx` sendet `data.passphrase` direkt als `auth_hash`** — bricht Zero-Knowledge-Modell, Login schlägt fehl für alle Onboarding-User | CRITICAL | `web/pages/Onboarding.tsx:145` |
| `Register.tsx` macht es korrekt mit `deriveAuthHash()` — Inkonsistenz | — | `web/pages/Register.tsx` |

### 8.2 E2E-Encryption: Architektonische Lücken

| Finding | Severity |
|---------|----------|
| **Recovery Codes können PEK nicht wiederherstellen** — User verlieren ALLE Daten nach Recovery | CRITICAL |
| **Mobile hat KEINE Crypto-Implementierung** — kann `content_enc` nicht entschlüsseln | CRITICAL |
| **Profile-Metadaten (DOB, Blutgruppe, Geschlecht) unverschlüsselt** in DB | CRITICAL |
| **Grant-Signaturen nicht verifiziert** — Server kann Fake-Grants erstellen | CRITICAL |
| **PEK nutzt PBKDF2 statt Argon2id** — GPU-parallelisierbar, TODO im Code | CRITICAL |
| **Key-Rotation Endpoint gibt 501** — keine Forward Secrecy | IMPORTANT |
| **`measured_at` Timestamps leaken Timing** von Gesundheitsereignissen | IMPORTANT |

### 8.3 GDPR/Datenschutz: Compliance-Lücken

| Finding | Severity | GDPR-Artikel |
|---------|----------|--------------|
| **Consent-Accept-Endpoint existiert nicht** — User permanent gesperrt nach Policy-Publish | CRITICAL | Art. 7 |
| **Datenexport komplett unimplementiert** — alle Export-Endpoints geben 410/501 zurück | CRITICAL | Art. 20 |
| **Keine Datenretention-Policy** — Audit-Logs wachsen unbegrenzt | CRITICAL | Art. 5(1)(e) |
| **Emergency Card speichert Plaintext-PHI** ohne Zugriffs-Logging | CRITICAL | Art. 25, 32 |
| **Audit-Log erfasst nur Writes** — Health-Data-Reads komplett ungeloggt | HIGH | Art. 32 |
| **Account-Deletion löscht Dateien auf Disk nicht** — Dokumente verwaisen | IMPORTANT | Art. 17 |
| **Consent unterscheidet nicht zwischen Privacy Policy und ToS** | IMPORTANT | Art. 7 |
| **Webhook-Secrets im Klartext in DB** | IMPORTANT | Art. 32 |

### 8.4 Security Misconfiguration (OWASP A05)

| Finding | Severity |
|---------|----------|
| 3 unauthentifizierte Endpoints ohne Rate-Limiting (ICS, Emergency, Share) | CRITICAL |
| `Vary: Origin` Header fehlt bei CORS — Cache-Poisoning-Risiko | IMPORTANT |
| Backup: AES-CBC ohne Authenticated Encryption (AEAD) | CRITICAL |

### 8.5 Observability & Logging

| Finding | Severity |
|---------|----------|
| **`AuditWrites` Middleware ist Dead Code** — nie im Router registriert | HIGH |
| **Email in Audit-Log-Metadata** — PII in `audit_log` Tabelle | HIGH |
| **Keine Metriken/Tracing** — kein Prometheus, kein OpenTelemetry | IMPORTANT |
| **Health-Check exponiert Infrastruktur-Details** öffentlich | IMPORTANT |

### 8.6 Test Coverage

| Bereich | Status |
|---------|--------|
| AES-GCM (Server) | **Zero Tests** |
| Web Crypto (encrypt, decrypt, wrapKey, unwrapKey) | **Zero Tests** |
| Web Key Sharing (createKeyGrant, receiveKeyGrant) | **Zero Tests** |
| 2FA Login Flow | **Zero Tests** |
| Recovery Code Flow | **Zero Tests** |
| Alle Middleware (JWTAuth, RateLimit, Consent, SessionTimeout) | **Zero Tests** |
| SSRF Guard (`isPrivateOrLocalhost`) | **Zero Tests** |
| Cross-User-Isolation | **Zero Tests** |

### 8.7 Performance

| Finding | Severity | Datei |
|---------|----------|-------|
| **N+1 Query in Lab List** — separate DB-Query pro Ergebnis-Row | CRITICAL | `postgres/lab.go:137` |
| Unbounded Goroutine-Spawning in Audit-Middleware | CRITICAL | `middleware/audit.go:68` |
| `io.Copy` Error bei Document-Download verworfen | CRITICAL | `documents.go:466` |
| Vitals Page fetcht immer 200 Items, filtert Client-seitig | IMPORTANT | `pages/Vitals.tsx:88` |
| Mobile `_trendsProvider` ruft deprecated 410-Endpoint auf | IMPORTANT | `labs_screen.dart:22` |

### 8.8 Input Validation

| Finding | Severity | Datei |
|---------|----------|-------|
| Content-Disposition Header Injection via Filename-Newlines | CRITICAL | `documents.go:464` |
| MIME-Type akzeptiert ohne Magic-Byte-Prüfung | IMPORTANT | `documents.go:152` |
| Emergency `wait_hours` ohne Obergrenze — Integer-Overflow → sofortige Auto-Approve | CRITICAL | `emergency.go:186` |
| Invite-Token ohne Längen-Validierung — Slice-Panic bei kurzem Token | IMPORTANT | `invites.go:187` |

---

## Top 15 Prioritäten (aktualisiert)

1. **Onboarding-Fix**: `Onboarding.tsx` muss `deriveAuthHash()` verwenden statt Plaintext-Passphrase
2. **Recovery-Key-Recovery**: Recovery Codes müssen PEK-Wrapper enthalten, sonst = permanenter Datenverlust
3. **Auth-Fixes**: Recovery-2FA-Bypass, Refresh-Token-bei-Logout, Logout-Route, Session-Key-Scoping
4. **Consent-Accept-Endpoint**: `POST /api/v1/legal/accept` implementieren — User sind sonst permanent gesperrt
5. **Krypto-Salt**: Deterministischen Email-Salt durch Server-generierten Random-Salt ersetzen
6. **Mobile Crypto**: Komplette PEK/ECDH/AES-GCM-Implementierung in Dart fehlt
7. **SQL Injection**: `GetChartData` entfernen oder mit Allowlist absichern
8. **URL-Param-Fixes**: `medID`/`medicationID`, `vaccID`/`vaccinationID`, `diagID`/`diagnosisID`
9. **Deployment**: DB_SSLMODE=require, PgBouncer-Config mounten, Debug-Keystore ersetzen
10. **GDPR-Export**: Mindestens JSON-Export aller Gesundheitsdaten implementieren
11. **CI/CD**: Backend-Tests reaktivieren, Go-Version vereinheitlichen, Trivy pinnen
12. **File Upload**: Size-Limit, MIME-Validation, Content-Disposition-Sanitization
13. **AuditWrites-Middleware**: Im Router registrieren + Reads loggen
14. **Test Coverage**: AES-GCM, Web Crypto, 2FA-Flow, Middleware-Tests
15. **Backup**: AES-CBC durch AES-GCM ersetzen, Key-Separation für HMAC

---

## Positive Highlights

- **Parameterisierte SQL-Queries** durchgehend (eine Ausnahme)
- **Structured Logging** mit Zap — kein User-Input in Log-Messages
- **Security Headers** in Caddy gut konfiguriert
- **Docker-Netzwerk-Isolation** mit `internal: true`
- **Argon2id-Parameter** entsprechen OWASP-Minimum
- **JWT mit RSA-Signierung** und Redis-basierter Denylist
- **TypeScript Strict Mode** im Web-Frontend
- **Route-Code-Splitting** mit Lazy Loading
- **Backup-Verschlüsselung** mit AES-256-CBC + PBKDF2
- **Consent-Tracking** als Middleware implementiert

---

*Report generiert durch 42 parallele Analyse-Agenten am 2026-04-08*
