#!/usr/bin/env bash
# Full deployment script for EKS 2048 game on Fargate.
# Run from the repo root: bash scripts/deploy.sh
set -euo pipefail

CLUSTER_NAME="demo-cluster"
REGION="us-east-1"
POLICY_NAME="AWSLoadBalancerControllerIAMPolicy"
SERVICE_ACCOUNT_NAME="aws-load-balancer-controller"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "=== Step 1: Create EKS cluster ==="
echo "Using cluster config: cluster/cluster-config.yaml"
echo "This creates the VPC, Fargate profiles, and OIDC provider (~15-20 minutes)."
eksctl create cluster -f cluster/cluster-config.yaml

echo ""
echo "=== Step 2: Verify OIDC provider ==="
aws eks describe-cluster \
  --name "$CLUSTER_NAME" \
  --region "$REGION" \
  --query "cluster.identity.oidc.issuer" \
  --output text

echo "Waiting 30s for IAM/OIDC propagation before creating service accounts..."
sleep 30

echo ""
echo "=== Step 3: Create IAM policy for Load Balancer Controller ==="
aws iam create-policy \
  --policy-name "$POLICY_NAME" \
  --policy-document file://iam/iam_policy.json \
  --no-cli-pager 2>/dev/null || echo "Policy $POLICY_NAME already exists, continuing..."

echo ""
echo "=== Step 4: Create IAM service account (IRSA) ==="
# IRSA binds a Kubernetes service account to an IAM role via the OIDC provider.
# The Load Balancer Controller uses this to create/manage ALBs without
# node-level IAM permissions.
eksctl create iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --region="$REGION" \
  --namespace=kube-system \
  --name="$SERVICE_ACCOUNT_NAME" \
  --role-name="AmazonEKSLoadBalancerControllerRole" \
  --attach-policy-arn="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" \
  --approve

echo ""
echo "=== Step 5: Install AWS Load Balancer Controller via Helm ==="
helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name="$SERVICE_ACCOUNT_NAME"

echo "Waiting for controller pods to be ready..."
kubectl rollout status deployment/aws-load-balancer-controller \
  -n kube-system --timeout=120s

echo ""
echo "=== Step 6: Deploy application ==="
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
kubectl apply -f k8s/ingress.yaml

echo ""
echo "=== Waiting for ALB to provision (typically 2-5 minutes) ==="
echo "Tip: ALB provisioning is async. Watch the ADDRESS field below:"
echo ""

for i in $(seq 1 36); do
  ADDRESS=$(kubectl get ingress ingress-2048 -n game-2048 \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$ADDRESS" ]; then
    echo ""
    echo "=== Deployment complete ==="
    echo "Application URL: http://${ADDRESS}"
    echo ""
    echo "Note: Wait ~60 additional seconds for DNS propagation before accessing."
    echo "Note: The EKS control plane (\$0.10/hr) and ALB (\$0.0225/hr) accrue charges"
    echo "      whether or not the app is receiving traffic. Run teardown.sh when done."
    exit 0
  fi
  printf "  [%02d/36] ALB not ready yet, waiting 10s...\r" "$i"
  sleep 10
done

echo ""
echo "ALB is still provisioning after 6 minutes. Check status with:"
echo "  kubectl get ingress -n game-2048"
echo "  kubectl describe ingress ingress-2048 -n game-2048"
