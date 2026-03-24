#!/bin/bash
# setup.sh — convenience wrapper for first-run setup
set -e

echo "HealthVault — First-Run Setup"
echo "────────────────────────────────────────"

echo "Checking Docker Compose..."
docker compose version > /dev/null || { echo "Docker Compose not found."; exit 1; }

echo "Checking .env file..."
if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created .env from .env.example — please review it before continuing."
  echo "Run this script again after editing .env"
  exit 0
fi

echo "Starting database and cache..."
docker compose up -d db redis

echo "Waiting for PostgreSQL to be ready..."
until docker compose exec db pg_isready -U "${POSTGRES_USER:-postgres}" > /dev/null 2>&1; do
  sleep 1
done

echo "Running HealthVault setup..."
docker compose run --rm api healthvault setup

echo ""
echo "Starting full stack..."
docker compose up -d

echo ""
echo "Setup complete. Check the output above for your admin registration link."
