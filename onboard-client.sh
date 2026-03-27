#!/bin/bash

# Sun State Digital - Client Onboarding
# Automated client setup in 5 minutes
# Usage: bash onboard-client.sh

set -e

source .env

echo "👤 Sun State Digital - Client Onboarding"
echo "=========================================="
echo ""

# Prompt for client details
read -p "Client Name: " CLIENT_NAME
read -p "Client Email: " CLIENT_EMAIL
read -p "Client Phone: " CLIENT_PHONE
read -p "Subscription Tier (starter/professional/enterprise): " TIER
read -p "Monthly Budget (USD): " BUDGET

# Validate inputs
if [ -z "$CLIENT_NAME" ] || [ -z "$CLIENT_EMAIL" ]; then
    echo "❌ Client name and email required"
    exit 1
fi

echo ""
echo "Creating client account..."
echo ""

# Generate client credentials
CLIENT_ID=$(uuidgen)
CLIENT_SECRET=$(openssl rand -hex 32)
API_KEY=$(openssl rand -base64 32)

echo "Client ID: $CLIENT_ID"
echo "Client Secret: $CLIENT_SECRET"
echo "API Key: $API_KEY"
echo ""

# Create database entry
echo "Creating database records..."
kubectl exec -n ssd postgres-0 -- psql -U "$POSTGRES_USER" -d ssd_production << SQL
INSERT INTO clients (id, name, email, phone, tier, budget, status, created_at)
VALUES ('$CLIENT_ID', '$CLIENT_NAME', '$CLIENT_EMAIL', '$CLIENT_PHONE', '$TIER', $BUDGET, 'active', NOW());

INSERT INTO client_credentials (client_id, api_key, secret, created_at)
VALUES ('$CLIENT_ID', '$API_KEY', '$CLIENT_SECRET', NOW());
SQL
echo "✅ Database records created"
echo ""

# Create client namespace
echo "Creating Kubernetes namespace..."
kubectl create namespace "client-$CLIENT_ID" || true
echo "✅ Namespace created"
echo ""

# Create client secrets
echo "Creating client secrets..."
kubectl create secret generic client-credentials \
    --from-literal=client-id="$CLIENT_ID" \
    --from-literal=client-secret="$CLIENT_SECRET" \
    --from-literal=api-key="$API_KEY" \
    -n "client-$CLIENT_ID" || true
echo "✅ Secrets created"
echo ""

# Deploy client gateway instance
echo "Deploying client gateway..."
cat << YAML | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway-client-$CLIENT_ID
  namespace: client-$CLIENT_ID
spec:
  replicas: 2
  selector:
    matchLabels:
      app: gateway
      client: $CLIENT_ID
  template:
    metadata:
      labels:
        app: gateway
        client: $CLIENT_ID
    spec:
      containers:
      - name: gateway
        image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ssd-gateway:latest
        ports:
        - containerPort: 18789
        env:
        - name: CLIENT_ID
          value: $CLIENT_ID
        - name: NAMESPACE
          value: client-$CLIENT_ID
        - name: POSTGRES_HOST
          value: postgres.default.svc.cluster.local
        - name: REDIS_HOST
          value: redis.default.svc.cluster.local
        volumeMounts:
        - name: credentials
          mountPath: /etc/credentials
      volumes:
      - name: credentials
        secret:
          secretName: client-credentials
---
apiVersion: v1
kind: Service
metadata:
  name: gateway-client-$CLIENT_ID
  namespace: client-$CLIENT_ID
spec:
  selector:
    app: gateway
    client: $CLIENT_ID
  ports:
  - protocol: TCP
    port: 80
    targetPort: 18789
  type: LoadBalancer
YAML
echo "✅ Client gateway deployed"
echo ""

# Create client dashboard
echo "Creating client dashboard..."
cat << YAML | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dashboard-client-$CLIENT_ID
  namespace: client-$CLIENT_ID
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dashboard
      client: $CLIENT_ID
  template:
    metadata:
      labels:
        app: dashboard
        client: $CLIENT_ID
    spec:
      containers:
      - name: dashboard
        image: $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ssd-blog:latest
        ports:
        - containerPort: 80
        env:
        - name: CLIENT_ID
          value: $CLIENT_ID
        - name: API_ENDPOINT
          value: https://api.ssd.cloud/client/$CLIENT_ID
YAML
echo "✅ Client dashboard deployed"
echo ""

# Wait for services to be ready
echo "Waiting for services to be ready..."
kubectl rollout status deployment/gateway-client-$CLIENT_ID -n "client-$CLIENT_ID" --timeout=5m || true
echo "✅ Services ready"
echo ""

# Get client gateway IP
CLIENT_LB_IP=$(kubectl get svc gateway-client-$CLIENT_ID -n "client-$CLIENT_ID" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
echo ""

echo "✅ CLIENT ONBOARDED!"
echo ""
echo "Client Details:"
echo "  Name: $CLIENT_NAME"
echo "  Email: $CLIENT_EMAIL"
echo "  Tier: $TIER"
echo "  Budget: \$${BUDGET}/month"
echo ""
echo "Access Credentials:"
echo "  Client ID: $CLIENT_ID"
echo "  API Key: $API_KEY"
echo "  Client Secret: $CLIENT_SECRET"
echo ""
echo "Gateway URL:"
if [ "$CLIENT_LB_IP" != "pending" ]; then
    echo "  http://$CLIENT_LB_IP"
else
    echo "  (Pending IP allocation - check in 2-3 minutes)"
    echo "  kubectl get svc -n client-$CLIENT_ID"
fi
echo ""
echo "Next Steps:"
echo "  1. Send credentials to client"
echo "  2. Setup client integrations (Gmail, Stripe, etc.)"
echo "  3. Configure client workflows"
echo "  4. Enable monitoring and alerts"
echo "  5. Start billing"
echo ""
echo "Support: support@sunstatedigital.com.au"
