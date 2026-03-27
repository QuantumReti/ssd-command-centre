#!/bin/bash

# Sun State Digital - Deployment Verification
# Checks all services are healthy and operational
# Usage: bash verify-deployment.sh

set -e

echo "🔍 Verifying SSD Deployment"
echo "=============================="
echo ""

source .env

HEALTHY=0
TOTAL=0

# Function to test endpoint
test_endpoint() {
    local name=$1
    local url=$2
    local expected_code=$3
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "Testing $name... "
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    
    if [ "$response" = "$expected_code" ]; then
        echo "✅ PASS (HTTP $response)"
        HEALTHY=$((HEALTHY + 1))
    else
        echo "❌ FAIL (Expected $expected_code, got $response)"
    fi
}

# Function to test Kubernetes pod
test_pod() {
    local name=$1
    local deployment=$2
    
    TOTAL=$((TOTAL + 1))
    
    echo -n "Checking pod $name... "
    running=$(kubectl get pods -n ssd -l app=$deployment -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -c "Running" || echo "0")
    
    if [ "$running" -gt 0 ]; then
        echo "✅ PASS (Running)"
        HEALTHY=$((HEALTHY + 1))
    else
        echo "❌ FAIL (Not running)"
    fi
}

echo "=== HTTP Endpoints ==="
test_endpoint "Gateway Health" "https://$DOMAIN/gateway/health" "200"
test_endpoint "API Health" "https://$DOMAIN/api/health" "200"
test_endpoint "Blog Home" "https://$DOMAIN" "200"
test_endpoint "N8n" "https://$DOMAIN/n8n" "200"
test_endpoint "Prometheus" "https://$DOMAIN/prometheus" "200"
echo ""

echo "=== Kubernetes Pods ==="
test_pod "Gateway" "gateway"
test_pod "API" "api"
test_pod "N8n" "n8n"
test_pod "Blog" "blog"
test_pod "PostgreSQL" "postgres"
test_pod "Redis" "redis"
echo ""

echo "=== Database Connectivity ==="
TOTAL=$((TOTAL + 1))
echo -n "Testing PostgreSQL... "
if kubectl exec -n ssd postgres-0 -- pg_isready -U "$POSTGRES_USER" -d ssd_production > /dev/null 2>&1; then
    echo "✅ PASS"
    HEALTHY=$((HEALTHY + 1))
else
    echo "❌ FAIL"
fi

TOTAL=$((TOTAL + 1))
echo -n "Testing Redis... "
if kubectl exec -n ssd redis-0 -- redis-cli PING > /dev/null 2>&1; then
    echo "✅ PASS"
    HEALTHY=$((HEALTHY + 1))
else
    echo "❌ FAIL"
fi
echo ""

echo "=== SSL Certificates ==="
TOTAL=$((TOTAL + 1))
echo -n "Checking certificate validity... "
cert_valid=$(kubectl get certificate -n ssd ssd-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")
if [ "$cert_valid" = "True" ]; then
    echo "✅ PASS"
    HEALTHY=$((HEALTHY + 1))
else
    echo "❌ FAIL"
fi
echo ""

echo "=== Infrastructure ==="
TOTAL=$((TOTAL + 1))
echo -n "Checking load balancer... "
lb_status=$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query 'LoadBalancers[?contains(Tags[?Key==`Name`].Value, `ssd-alb`)].State.Code' --output text 2>/dev/null || echo "unknown")
if [ "$lb_status" = "active" ]; then
    echo "✅ PASS"
    HEALTHY=$((HEALTHY + 1))
else
    echo "❌ FAIL (Status: $lb_status)"
fi

TOTAL=$((TOTAL + 1))
echo -n "Checking RDS database... "
db_status=$(aws rds describe-db-instances --db-instance-identifier ssd-postgres --region "$AWS_REGION" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "unknown")
if [ "$db_status" = "available" ]; then
    echo "✅ PASS"
    HEALTHY=$((HEALTHY + 1))
else
    echo "❌ FAIL (Status: $db_status)"
fi

TOTAL=$((TOTAL + 1))
echo -n "Checking S3 buckets... "
buckets_ok=true
for bucket in "$S3_BLOG_BUCKET" "$S3_BACKUPS_BUCKET" "$S3_ASSETS_BUCKET"; do
    if ! aws s3 ls "s3://$bucket" --region "$AWS_REGION" > /dev/null 2>&1; then
        buckets_ok=false
        break
    fi
done
if [ "$buckets_ok" = true ]; then
    echo "✅ PASS"
    HEALTHY=$((HEALTHY + 1))
else
    echo "❌ FAIL"
fi
echo ""

echo "=== Monitoring ==="
TOTAL=$((TOTAL + 1))
echo -n "Checking Prometheus... "
if test_endpoint "dummy" "https://$DOMAIN/prometheus" "200" 2>/dev/null | grep -q "✅"; then
    echo "✅ PASS"
    HEALTHY=$((HEALTHY + 1))
else
    echo "❌ FAIL"
fi

TOTAL=$((TOTAL + 1))
echo -n "Checking Grafana... "
if test_endpoint "dummy" "https://$DOMAIN/grafana" "200" 2>/dev/null | grep -q "✅"; then
    echo "✅ PASS"
    HEALTHY=$((HEALTHY + 1))
else
    echo "❌ FAIL"
fi
echo ""

echo "=== Summary ==="
echo "Tests Passed: $HEALTHY/$TOTAL"
echo ""

if [ $HEALTHY -eq $TOTAL ]; then
    echo "✅ ALL CHECKS PASSED - DEPLOYMENT HEALTHY"
    echo ""
    echo "System is ready for production use!"
    exit 0
else
    FAILED=$((TOTAL - HEALTHY))
    echo "⚠️  $FAILED CHECK(S) FAILED"
    echo ""
    echo "Troubleshooting:"
    echo "  - Check pod logs: kubectl logs -n ssd <pod-name>"
    echo "  - Check events: kubectl get events -n ssd"
    echo "  - Check services: kubectl get svc -n ssd"
    echo ""
    exit 1
fi
