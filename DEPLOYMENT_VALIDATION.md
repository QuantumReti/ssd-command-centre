# Deployment Validation Test Suite
## Sun State Digital Platform

**Run after every deployment to confirm all systems operational.**

---

## Quick Validation

```bash
# Run the built-in validation script
./verify-deployment.sh

# For full test suite (slower, more thorough)
./verify-deployment.sh --full
```

---

## 1. Functional Tests

### Health Check Endpoints

```bash
#!/bin/bash
echo "=== HEALTH CHECK TESTS ==="

PASS=0; FAIL=0

check() {
  local name="$1" url="$2" expected="$3"
  local response=$(curl -sf "$url" 2>/dev/null)
  local http_code=$(curl -so /dev/null -w "%{http_code}" "$url" 2>/dev/null)

  if [[ "$http_code" == "$expected" ]]; then
    echo "  ✓ $name (HTTP $http_code)"
    PASS=$((PASS+1))
  else
    echo "  ✗ $name (expected $expected, got $http_code)"
    FAIL=$((FAIL+1))
  fi
}

check "OpenClaw Gateway health" "https://api.ssd.cloud/health" "200"
check "Quantum API health" "https://quantum.ssd.cloud/health" "200"
check "Blog Frontend" "https://blog.ssd.cloud" "200"
check "Main Dashboard" "https://ssd.cloud" "200"
check "Monitoring" "https://monitor.ssd.cloud" "200"
check "HTTP→HTTPS redirect" "http://ssd.cloud" "301"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "✅ ALL HEALTH CHECKS PASSED" || echo "❌ SOME CHECKS FAILED"
```

### API Endpoint Tests

```bash
#!/bin/bash
echo "=== API ENDPOINT TESTS ==="

BASE="https://api.ssd.cloud"
API_KEY="${OPENCLAW_API_KEY}"

# Test auth (should return 401 without credentials)
HTTP=$(curl -so /dev/null -w "%{http_code}" "${BASE}/api/v1/clients" 2>/dev/null)
[[ "$HTTP" == "401" ]] && echo "✓ Auth required on /api/v1/clients" \
  || echo "✗ Expected 401, got $HTTP"

# Test login
LOGIN_RESP=$(curl -sf -X POST "${BASE}/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@ssd.cloud","password":"test"}' 2>/dev/null)
[[ -n "$LOGIN_RESP" ]] && echo "✓ Login endpoint responds" \
  || echo "✗ Login endpoint not responding"

# Test lead qualification with API key
LEAD_RESP=$(curl -sf -X POST "${BASE}/api/v1/leads/qualify" \
  -H "X-API-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test Lead","email":"test@test.com","phone":"+61412345678","source":"test"}' \
  2>/dev/null)
[[ -n "$LEAD_RESP" ]] && echo "✓ Lead qualification endpoint responds" \
  || echo "✗ Lead qualification not responding"

# Test webhook endpoint (should accept POST)
WEBHOOK_HTTP=$(curl -so /dev/null -w "%{http_code}" \
  -X POST "${BASE}/webhooks/meta" \
  -d "hub.mode=subscribe&hub.verify_token=test&hub.challenge=testchallenge" \
  2>/dev/null)
echo "  Webhook endpoint: HTTP $WEBHOOK_HTTP (200=ok, 403=expected if verify token wrong)"

echo "✅ API endpoint tests complete"
```

### Quantum API Tests

```bash
#!/bin/bash
echo "=== QUANTUM API TESTS ==="

QUANTUM="https://quantum.ssd.cloud"
API_KEY="${QUANTUM_API_KEY}"

# Health with DB check
HEALTH=$(curl -sf "${QUANTUM}/health" 2>/dev/null)
DB_STATUS=$(echo "$HEALTH" | jq -r '.database // "unknown"')
REDIS_STATUS=$(echo "$HEALTH" | jq -r '.redis // "unknown"')

echo "  Database: $DB_STATUS"
echo "  Redis: $REDIS_STATUS"
[[ "$DB_STATUS" == "connected" ]] && echo "✓ Database connected" || echo "✗ Database NOT connected"
[[ "$REDIS_STATUS" == "connected" ]] && echo "✓ Redis connected" || echo "✗ Redis NOT connected"

# Test lead scoring
SCORE_RESP=$(curl -sf -X POST "${QUANTUM}/api/v1/leads/score" \
  -H "X-API-Key: ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","email":"test@company.com","phone":"+61412345678"}' \
  2>/dev/null)
SCORE=$(echo "$SCORE_RESP" | jq -r '.score // -1')
[[ "$SCORE" -ge 0 ]] && echo "✓ Lead scoring returns score: $SCORE" || echo "✗ Lead scoring failed"

echo "✅ Quantum API tests complete"
```

---

## 2. Load Test Expectations

### Baseline Performance Targets

| Metric | Target | Test |
|---|---|---|
| API response time (P50) | < 100ms | `ab -n 100 -c 10` |
| API response time (P95) | < 500ms | `ab -n 1000 -c 50` |
| API response time (P99) | < 2000ms | `ab -n 1000 -c 100` |
| Throughput | > 100 req/s | `ab -n 1000 -c 100` |
| Error rate under load | < 0.1% | `ab -n 1000 -c 100` |

### Run Load Tests

```bash
# Install Apache Bench
apt-get install -y apache2-utils  # or brew install httpd on Mac

# Basic load test — health endpoint
ab -n 1000 -c 50 -H "X-API-Key: $OPENCLAW_API_KEY" \
  https://api.ssd.cloud/health

# Lead qualification load test
ab -n 100 -c 10 \
  -H "X-API-Key: $OPENCLAW_API_KEY" \
  -H "Content-Type: application/json" \
  -p /tmp/lead-payload.json \
  -T application/json \
  https://api.ssd.cloud/api/v1/leads/qualify

# Expected output should show:
# Requests per second: > 50
# Time per request: < 100ms mean
# Failed requests: 0
```

### Stress Test (to find breaking point)

```bash
# Gradually increase concurrency until failure
for concurrency in 10 25 50 100 200; do
  echo "=== Concurrency: $concurrency ==="
  ab -n 500 -c $concurrency \
    -H "X-API-Key: $OPENCLAW_API_KEY" \
    https://api.ssd.cloud/health 2>&1 | \
    grep -E "Requests per second|Failed requests|Time per request"
  sleep 5
done
```

---

## 3. Security Scan Requirements

### SSL/TLS Configuration Test

```bash
# Check SSL grade (should be A or A+)
# Online: https://www.ssllabs.com/ssltest/analyze.html?d=ssd.cloud

# Manual checks
echo "=== SSL CONFIGURATION ==="

# Check TLS version
openssl s_client -connect api.ssd.cloud:443 -tls1 2>&1 | grep -q "handshake failure" \
  && echo "✓ TLS 1.0 disabled" || echo "✗ TLS 1.0 enabled (INSECURE)"

openssl s_client -connect api.ssd.cloud:443 -tls1_1 2>&1 | grep -q "handshake failure" \
  && echo "✓ TLS 1.1 disabled" || echo "✗ TLS 1.1 enabled (INSECURE)"

openssl s_client -connect api.ssd.cloud:443 -tls1_2 2>&1 | grep -q "Cipher" \
  && echo "✓ TLS 1.2 supported" || echo "✗ TLS 1.2 not working"

openssl s_client -connect api.ssd.cloud:443 -tls1_3 2>&1 | grep -q "Cipher" \
  && echo "✓ TLS 1.3 supported" || echo "✗ TLS 1.3 not supported"

# Check cipher suites
openssl s_client -connect api.ssd.cloud:443 2>/dev/null | grep "Cipher    :"
```

### Security Headers Check

```bash
echo "=== SECURITY HEADERS ==="
HEADERS=$(curl -sI https://api.ssd.cloud 2>/dev/null)

check_header() {
  local name="$1" expected="$2"
  echo "$HEADERS" | grep -qi "$expected" \
    && echo "✓ $name present" \
    || echo "✗ $name MISSING"
}

check_header "Strict-Transport-Security" "strict-transport-security"
check_header "X-Frame-Options" "x-frame-options"
check_header "X-Content-Type-Options" "x-content-type-options"
check_header "X-XSS-Protection" "x-xss-protection"
check_header "Referrer-Policy" "referrer-policy"

# Check server header is hidden
SERVER=$(echo "$HEADERS" | grep -i "^server:" | head -1)
[[ -z "$SERVER" ]] || echo "  Server header: $SERVER (consider hiding)"
```

### Basic Vulnerability Checks

```bash
# Check for common exposed paths
echo "=== COMMON EXPOSURE CHECKS ==="

for path in "/.env" "/config" "/admin" "/.git" "/phpinfo.php" "/wp-admin"; do
  HTTP=$(curl -so /dev/null -w "%{http_code}" "https://ssd.cloud${path}" 2>/dev/null)
  [[ "$HTTP" != "200" ]] && echo "✓ ${path} not exposed (HTTP $HTTP)" \
    || echo "✗ ${path} returns 200 — CHECK THIS!"
done
```

---

## 4. SSL/TLS Verification

```bash
echo "=== SSL CERTIFICATE VERIFICATION ==="

for domain in ssd.cloud api.ssd.cloud quantum.ssd.cloud blog.ssd.cloud; do
  # Get cert info
  CERT_INFO=$(echo | openssl s_client -connect "${domain}:443" 2>/dev/null | \
    openssl x509 -noout -subject -dates -issuer 2>/dev/null)

  SUBJECT=$(echo "$CERT_INFO" | grep "subject" | sed 's/subject=//')
  NOT_AFTER=$(echo "$CERT_INFO" | grep "notAfter" | sed 's/notAfter=//')
  ISSUER=$(echo "$CERT_INFO" | grep "issuer" | sed 's/issuer=//')

  # Calculate days until expiry
  EXPIRY_DATE=$(date -d "$NOT_AFTER" +%s 2>/dev/null || \
                date -j -f "%b %e %T %Y %Z" "$NOT_AFTER" +%s 2>/dev/null)
  NOW=$(date +%s)
  DAYS=$(( (EXPIRY_DATE - NOW) / 86400 ))

  if [[ $DAYS -gt 30 ]]; then
    echo "✓ ${domain}: expires in ${DAYS} days"
  elif [[ $DAYS -gt 7 ]]; then
    echo "⚠ ${domain}: expires in ${DAYS} days — RENEW SOON"
  else
    echo "✗ ${domain}: expires in ${DAYS} days — CRITICAL!"
  fi
done
```

---

## 5. Database Migration Verification

```bash
echo "=== DATABASE MIGRATION VERIFICATION ==="

# Check current migration state (Alembic)
CURRENT=$(docker-compose run --rm quantum-api python -m alembic current 2>/dev/null)
echo "Current migration: $CURRENT"

# Check for pending migrations
PENDING=$(docker-compose run --rm quantum-api python -m alembic heads 2>/dev/null)
echo "Latest migration: $PENDING"

if [[ "$CURRENT" == *"(head)"* ]]; then
  echo "✓ Database is at latest migration"
else
  echo "⚠ Database may have pending migrations"
  echo "Run: docker-compose run --rm quantum-api python -m alembic upgrade head"
fi

# Verify key tables exist
docker exec postgres psql -U ssd_user -d ssd_production -c "\dt" 2>/dev/null | \
  grep -E "clients|leads|api_keys|workflows|events" | \
  while read -r table; do
    echo "✓ Table exists: $table"
  done
```

---

## 6. Rollback Test

```bash
#!/bin/bash
echo "=== ROLLBACK TEST (dry run) ==="

# Identify current deployment
CURRENT_IMAGE=$(docker inspect openclaw-gateway \
  --format '{{.Config.Image}}' 2>/dev/null || echo "unknown")
echo "Current image: $CURRENT_IMAGE"

# Get previous task definition (ECS)
PREV_TASK=$(aws ecs list-task-definitions \
  --family-prefix ssd-openclaw-gateway \
  --sort DESC \
  --region ap-southeast-2 \
  --query 'taskDefinitionArns[1]' \
  --output text 2>/dev/null || echo "not-on-ecs")

echo "Previous task definition: $PREV_TASK"

if [[ "$PREV_TASK" == "not-on-ecs" ]]; then
  # Docker compose rollback
  GIT_PREV=$(cd /opt/ssd && git log --oneline -2 | tail -1 | awk '{print $1}')
  echo "Previous git commit: $GIT_PREV"
  echo "To rollback: cd /opt/ssd && git checkout ${GIT_PREV} docker-compose.yml && docker-compose up -d"
else
  echo "To rollback ECS: aws ecs update-service --cluster ssd-prod-cluster --service ssd-openclaw-gateway --task-definition $PREV_TASK"
fi

echo "✓ Rollback path identified"
```

---

## Validation Checklist

```
BEFORE MARKING DEPLOYMENT COMPLETE:

Functional Tests:
[ ] All health endpoints return 200
[ ] Auth endpoints respond correctly (401 without token)
[ ] Lead qualification endpoint processes test lead
[ ] Webhook endpoints accept POST requests

Security Tests:
[ ] TLS 1.0 and 1.1 disabled
[ ] TLS 1.2 and 1.3 working
[ ] Security headers present (HSTS, X-Frame-Options, etc.)
[ ] .env and sensitive paths return 404/403

Database Tests:
[ ] Database connectivity confirmed
[ ] All tables exist
[ ] Migrations at latest version
[ ] Read/write operations working

SSL Tests:
[ ] All domains have valid certificates
[ ] Certificates expire > 30 days from now
[ ] Auto-renewal cron job active

Performance Tests:
[ ] Health endpoint < 50ms
[ ] API endpoints < 500ms at P95
[ ] No errors under 50 concurrent users

Rollback Tests:
[ ] Previous deployment identified
[ ] Rollback path documented
[ ] Team knows rollback procedure
```

---

*Run `./verify-deployment.sh --full` to automate most of these checks.*
