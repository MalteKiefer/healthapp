#!/bin/bash
set -e
ERRORS=0

# ── Check 1: Zero occurrences of "nginx" anywhere in the codebase ─────────
echo "Checking for nginx references..."
NGINX_HITS=$(grep -r -i "nginx" \
  --include="*.go" --include="*.ts" --include="*.tsx" \
  --include="*.yml" --include="*.yaml" \
  --include="Dockerfile*" --include="Caddyfile*" \
  --include="*.conf" --include="*.md" \
  --exclude-dir=".git" . 2>/dev/null | wc -l)
if [ "$NGINX_HITS" -gt 0 ]; then
  echo "FAIL: nginx references found — must be removed:"
  grep -r -i "nginx" \
    --include="*.go" --include="*.ts" --include="*.tsx" \
    --include="*.yml" --include="*.yaml" \
    --include="Dockerfile*" --include="Caddyfile*" \
    --include="*.conf" --include="*.md" \
    --exclude-dir=".git" . 2>/dev/null
  ERRORS=$((ERRORS+1))
else
  echo "  OK  zero nginx references"
fi

# ── Check 2: No certbot / cert-init in any compose file ───────────────────
echo "Checking for certbot/cert-init in compose files..."
CERTBOT_HITS=$(grep -i "certbot\|cert-init\|certbot-webroot" \
  docker-compose*.yml 2>/dev/null | wc -l)
if [ "$CERTBOT_HITS" -gt 0 ]; then
  echo "FAIL: certbot or cert-init found in docker-compose files"
  grep -i "certbot\|cert-init\|certbot-webroot" docker-compose*.yml
  ERRORS=$((ERRORS+1))
else
  echo "  OK  no certbot/cert-init in compose files"
fi

# ── Check 3: Caddyfile exists for both proxy and web ──────────────────────
echo "Checking Caddyfile presence..."
if [ ! -f "proxy/Caddyfile" ]; then
  echo "FAIL: proxy/Caddyfile missing"
  ERRORS=$((ERRORS+1))
fi
if [ ! -f "web/Caddyfile" ]; then
  echo "FAIL: web/Caddyfile missing"
  ERRORS=$((ERRORS+1))
fi
if [ -f "proxy/Caddyfile" ] && [ -f "web/Caddyfile" ]; then
  echo "  OK  Caddyfile present in proxy/ and web/"
fi

# ── Check 4: No .env files tracked (except .env.example) ──────────────────
echo "Checking .env files are not tracked..."
ENV_TRACKED=$(git ls-files | grep -E "^\.env" | grep -v "\.example$" | wc -l)
if [ "$ENV_TRACKED" -gt 0 ]; then
  echo "FAIL: .env files are tracked by git:"
  git ls-files | grep -E "^\.env" | grep -v "\.example$"
  ERRORS=$((ERRORS+1))
else
  echo "  OK  no .env files tracked"
fi

# ── Check 5: No plaintext secrets in tracked Go/TS files ──────────────────
echo "Checking for hardcoded secrets..."
SECRET_HITS=$(grep -r -E "(password|secret|api_key|private_key)\s*=\s*['\"][^'\"]{8,}" \
  --include="*.go" --include="*.ts" --include="*.tsx" \
  --exclude-dir=".git" . 2>/dev/null \
  | grep -v "_test\.\|\.example\|placeholder\|changeme\|your_" | wc -l)
if [ "$SECRET_HITS" -gt 0 ]; then
  echo "WARN: Possible hardcoded secrets — review:"
  grep -r -E "(password|secret|api_key|private_key)\s*=\s*['\"][^'\"]{8,}" \
    --include="*.go" --include="*.ts" --include="*.tsx" \
    --exclude-dir=".git" . 2>/dev/null \
    | grep -v "_test\.\|\.example\|placeholder\|changeme\|your_"
fi

# ── Result ──────────────────────────────────────────────────────────────────
if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "INTEGRITY CHECK FAILED ($ERRORS error(s)) — fix before committing"
  exit 1
fi
echo ""
echo "All integrity checks passed"
