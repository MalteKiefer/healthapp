.PHONY: build test lint dev up down clean migrate deploy mobile-test mobile-build-release

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
BUILD_TIME ?= $(shell date -u '+%Y-%m-%dT%H:%M:%SZ')
GIT_COMMIT ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")

LDFLAGS = -s -w \
	-X main.Version=$(VERSION) \
	-X main.BuildTime=$(BUILD_TIME) \
	-X main.GitCommit=$(GIT_COMMIT)

# ── Build ──────────────────────────────────────────────────────────

build:
	cd api && CGO_ENABLED=0 go build -ldflags="$(LDFLAGS)" -o ../healthvault ./cmd/healthvault

# ── Test ───────────────────────────────────────────────────────────

test:
	cd api && go test -race -count=1 ./...

test-coverage:
	cd api && go test -race -coverprofile=coverage.out ./... && go tool cover -html=coverage.out -o coverage/index.html

# ── Lint ───────────────────────────────────────────────────────────

lint:
	cd api && golangci-lint run ./...

# ── Docker ─────────────────────────────────────────────────────────

up:
	docker compose up -d

down:
	docker compose down

dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up --build

dev-down:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml down

# ── Database ───────────────────────────────────────────────────────

migrate-up:
	docker compose exec api healthvault migrate up

migrate-down:
	docker compose exec api healthvault migrate down 1

migrate-status:
	docker compose exec api healthvault migrate status

# ── Mobile ─────────────────────────────────────────────────────────

mobile-test:
	cd mobile && flutter test --coverage

mobile-build-release:
	cd mobile && flutter build apk --release --obfuscate --split-debug-info=build/symbols
	cd mobile && flutter build appbundle --release --obfuscate --split-debug-info=build/symbols

# ── Utilities ──────────────────────────────────────────────────────

clean:
	rm -f healthvault
	rm -rf api/tmp
	rm -rf coverage/

setup:
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example — edit it before starting")
	docker compose up -d db redis
	@echo "Waiting for PostgreSQL..."
	@until docker compose exec db pg_isready -U postgres > /dev/null 2>&1; do sleep 1; done
	docker compose run --rm api healthvault setup
	docker compose up -d

deploy:
	@echo "ERROR: Direct deploy via Makefile is disabled. Use the CI/CD pipeline instead." && exit 1

version:
	@echo "$(VERSION)"
