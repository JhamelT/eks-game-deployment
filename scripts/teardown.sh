#!/usr/bin/env bash
# Safe ordered teardown for the EKS 2048 deployment.
# Run from the repo root: bash scripts/teardown.sh
#
# ORDER MATTERS. The ALB is a Kubernetes-managed resource created by the
# AWS Load Balancer Controller. If you run 'eksctl delete cluster' while
# the ALB still exists, AWS will fail to delete the VPC (ALB is attached
# to subnets). You must delete the Ingress first to trigger ALB removal.
set -euo pipefail

CLUSTER_NAME="demo-cluster"
REGION="us-east-1"

echo "=== Step 1: Delete Ingress (this triggers ALB deletion in AWS) ==="
kubectl delete ingress ingress-2048 -n game-2048 --ignore-not-found

echo ""
echo "=== Step 2: Wait for ALB to be fully removed from AWS ==="
echo "The Load Balancer Controller watches for Ingress deletion and removes"
echo "the ALB. This typically takes 30-60 seconds."
kubectl wait --for=delete ingress/ingress-2048 \
  -n game-2048 --timeout=300s 2>/dev/null || true

# Extra buffer: AWS ALB deletion is async even after the Ingress object is gone
echo "Waiting additional 30s for AWS to fully deregister the ALB..."
sleep 30

echo ""
echo "=== Step 3: Uninstall Helm chart ==="
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null \
  || echo "Helm release not found, continuing..."

echo ""
echo "=== Step 4: Delete remaining application manifests ==="
kubectl delete -f k8s/ --ignore-not-found 2>/dev/null || true

echo ""
echo "=== Step 5: Delete IAM service account ==="
eksctl delete iamserviceaccount \
  --cluster="$CLUSTER_NAME" \
  --region="$REGION" \
  --name=aws-load-balancer-controller \
  --namespace=kube-system 2>/dev/null || echo "Service account not found, continuing..."

echo ""
echo "=== Step 6: Delete cluster ==="
echo "This removes the VPC, Fargate profiles, OIDC provider, and CloudFormation stacks."
eksctl delete cluster --name "$CLUSTER_NAME" --region "$REGION"

echo ""
echo "=== Step 7: (Optional) Delete IAM policy ==="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws iam delete-policy \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy" \
  2>/dev/null || echo "Policy already deleted or not found."

echo ""
echo "=== Teardown complete. All resources deleted. No ongoing charges. ==="
