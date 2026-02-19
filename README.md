# EKS 2048 Game Deployment

![AWS](https://img.shields.io/badge/AWS-EKS-orange)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.32-blue)
![Fargate](https://img.shields.io/badge/Compute-Fargate-green)

Kubernetes deployment of the 2048 game on Amazon EKS with Fargate, demonstrating production-grade manifest practices and AWS ALB integration.

## Architecture

```
Internet → ALB (HTTPS) → EKS Fargate Pods (3 replicas, multi-AZ) → 2048 Game
```

| Component | Technology |
|-----------|------------|
| Cluster | Amazon EKS 1.32, Fargate-only compute |
| Load balancer | AWS ALB via Load Balancer Controller v2.11.0 |
| Networking | VPC with public/private subnets across 2 AZs |
| Security | OIDC/IRSA, pod security context, network policies |
| Config management | Kustomize (base + dev/prod overlays) |
| CI/CD | GitHub Actions (validate on PR, deploy on merge) |

## Repository Structure

```
k8s/
├── base/                  # Shared manifests
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── deployment.yaml    # Resources, probes, securityContext, topology spread
│   ├── service.yaml
│   ├── ingress.yaml       # HTTP base; HTTPS added in prod overlay
│   ├── hpa.yaml           # CPU/memory autoscaling, min 2 / max 10
│   ├── pdb.yaml           # minAvailable: 2
│   └── networkpolicy.yaml # Ingress on :80, egress DNS only
└── overlays/
    ├── dev/               # 2 replicas, relaxed HPA/PDB, no TLS
    └── prod/              # HTTPS with ACM cert, HTTP→HTTPS redirect
.github/workflows/
├── validate.yaml          # PR: kustomize build, kubeconform, trivy, checkov
└── deploy.yaml            # main push: diff → apply → rollout verify
Architecture/
└── Design_Decisions.md
```

## Prerequisites

| Tool | Version |
|------|---------|
| AWS CLI | >= 2.x |
| kubectl | >= 1.32 |
| eksctl | >= 0.191 |
| kustomize | >= 5.x |
| Helm | >= 3.x |

Required IAM permissions: EKS full access, IAM role creation, VPC management, EC2/ALB management.

## Initial Cluster Setup

Run once to provision the EKS cluster and supporting infrastructure.

```bash
# 1. Create cluster with Fargate
eksctl create cluster --name demo-cluster --region us-east-1 --fargate

# 2. Create Fargate profile scoped to the app namespace
eksctl create fargateprofile \
  --cluster demo-cluster \
  --region us-east-1 \
  --name alb-sample-app \
  --namespace game-2048

# 3. Associate OIDC provider (required for IRSA)
eksctl utils associate-iam-oidc-provider --cluster demo-cluster --approve

# 4. Create ALB controller IAM policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# 5. Bind IAM role to the controller service account
eksctl create iamserviceaccount \
  --cluster=demo-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name=AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# 6. Install ALB controller via Helm
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=demo-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

## Deploying the Application

**Before deploying to prod**, update the ACM certificate ARN in `k8s/overlays/prod/ingress-patch.yaml`:
```yaml
alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:REGION:ACCOUNT_ID:certificate/CERT_ID
```

**Dev (manual):**
```bash
kustomize build k8s/overlays/dev | kubectl apply -f -
kubectl rollout status deployment/deployment-2048 -n game-2048
```

**Prod (automated):** Push to `main` — the `deploy.yaml` workflow runs `kubectl diff`, applies, and verifies rollout.

**Get the application URL:**
```bash
kubectl get ingress ingress-2048 -n game-2048 \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```
ALB provisioning takes 2-3 minutes after first apply.

## CI/CD

| Workflow | Trigger | Steps |
|----------|---------|-------|
| `validate.yaml` | PR to `main` | kustomize build (dev+prod), kubeconform schema check, trivy image scan, checkov policy |
| `deploy.yaml` | Push to `main` | AWS OIDC auth, kubeconfig update, kubectl diff, kubectl apply, rollout verify |

**Required GitHub secrets:**

| Secret | Description |
|--------|-------------|
| `AWS_DEPLOY_ROLE_ARN` | IAM role ARN with EKS deploy permissions. Trust policy must allow `token.actions.githubusercontent.com` as the OIDC provider. |

## Rollback

```bash
kubectl rollout undo deployment/deployment-2048 -n game-2048
kubectl rollout status deployment/deployment-2048 -n game-2048
```

## Verification

```bash
kubectl get all -n game-2048
kubectl get ingress ingress-2048 -n game-2048
kubectl describe ingress ingress-2048 -n game-2048
kubectl top pods -n game-2048
```

## Cleanup

```bash
kubectl delete namespace game-2048
eksctl delete cluster --name demo-cluster
```

> Note: deleting the namespace removes all app resources. Deleting the cluster removes the ALB, Fargate profiles, and node IAM roles. The ACM certificate and IAM policies created during setup must be removed separately.

## Known Limitations

- Image tag is `latest` — pin to a digest once a versioning pipeline is in place.
- `runAsNonRoot` is commented out in `deployment.yaml` — the upstream image runs nginx as root. Enable after rebuilding on `nginxinc/nginx-unprivileged` or equivalent.
- Fargate cold start: 45-60 seconds. Total time from pod scheduled to LB ready: 90-120 seconds.
- Topology spread requires at least 2 AZs with available Fargate capacity. If only one AZ is available, pods will not schedule (`whenUnsatisfiable: DoNotSchedule`).

## Additional Documentation

- [Architecture/Design_Decisions.md](./Architecture/Design_Decisions.md) — rationale for Fargate, ALB, and OIDC choices
- [Lessons_Learned.md](./Lessons_Learned.md) — post-mortem notes on provisioning delays and debugging
