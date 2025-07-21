# EKS Container Platform - Analytics to Cloud Engineering Journey

**Business Context:** Learning production-ready container orchestration to support scalable data processing workloads.

A complete end-to-end deployment of a containerized application on Amazon EKS using Fargate, demonstrating modern cloud-native DevOps practices with focus on cost optimization and security.

```
Internet → ALB → EKS Fargate Pods → 2048 Game Application
```

## 🎯 Project Goals
- **Primary:** Master EKS networking, security, and serverless compute patterns
- **Secondary:** Build foundation for deploying data analytics applications at scale
- **Learning Focus:** Cost-optimized infrastructure for variable workloads (common in analytics)

## 🧠 Key Learning Outcomes
- **Fargate vs EC2 Trade-offs:** When to choose serverless containers vs managed nodes
- **AWS Integration Patterns:** How Load Balancer Controller integrates with Kubernetes ingress
- **Security Best Practices:** OIDC provider setup and IAM service account binding
- **Cost Optimization:** Pay-per-use model evaluation for analytics workloads

## 🏗️ Architecture Overview

### Key Components:
- **Container Orchestration:** Amazon EKS (Kubernetes 1.32)
- **Compute:** AWS Fargate (Serverless containers)
- **Load Balancing:** AWS Application Load Balancer
- **Infrastructure Management:** eksctl, kubectl
- **Package Management:** Helm
- **Networking:** VPC with public/private subnets
- **Security:** IAM roles, OIDC provider, Service Accounts

### Infrastructure Design:
- **Networking:** VPC with public and private subnets across 2 AZs
- **Security:** IAM roles with least privilege access, OIDC authentication
- **Compute:** Fargate profiles for serverless container execution
- **Cost Optimization:** No EC2 instances to manage, pay-per-use model

## 📋 Prerequisites
- AWS CLI configured with appropriate permissions
- kubectl installed
- eksctl installed
- Helm installed
- Docker understanding (for containerization concepts)

## 🚀 Deployment Steps

### 1. Create EKS Cluster with Fargate
```bash
# Create cluster with Fargate profile
eksctl create cluster --name demo-cluster --region us-east-1 --fargate

# Verify cluster creation
kubectl get nodes
eksctl get cluster
```

### 2. Configure Fargate Profile
```bash
# Create namespace-specific Fargate profile
eksctl create fargateprofile \
  --cluster demo-cluster \
  --region us-east-1 \
  --name alb-sample-app \
  --namespace game-2048
```

### 3. Setup AWS Load Balancer Controller
```bash
# Associate IAM OIDC provider for service accounts
eksctl utils associate-iam-oidc-provider --cluster demo-cluster --approve

# Download and create IAM policy
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.11.0/docs/install/iam_policy.json
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json

# Create service account with IAM role
eksctl create iamserviceaccount \
  --cluster=demo-cluster \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name=AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT-ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve
```

### 4. Install Load Balancer Controller via Helm
```bash
# Install controller via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=demo-cluster \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

### 5. Deploy Application
```bash
# Deploy using the official AWS Load Balancer Controller example
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/examples/2048/2048_full.yaml

# Monitor deployment
kubectl get pods -n game-2048 -w
kubectl get ingress -n game-2048
```

### 6. Access Application
```bash
# Get the application URL (may take 2-3 minutes for ALB provisioning)
kubectl get ingress ingress-2048 -n game-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## 🔍 Monitoring & Verification
```bash
# Check all components
kubectl get all -n game-2048
kubectl get ingress -n game-2048
kubectl describe ingress ingress-2048 -n game-2048

# Get application URL
kubectl get ingress ingress-2048 -n game-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## 📊 Analytics Background Context
This project bridges my data analytics experience with cloud engineering:

**Why This Matters for Data Teams:**
- **Scalable Processing:** Container orchestration handles variable analytics workloads
- **Cost Control:** Fargate eliminates idle compute costs common in data projects
- **Security:** IAM integration supports data governance requirements
- **Monitoring Ready:** Foundation for observability in data pipelines

## 🔧 Troubleshooting Guide
Common issues I encountered and solutions:

1. **Pods Stuck Pending:** Check Fargate profile namespace matching
2. **ALB Not Created:** Verify Load Balancer Controller installation
3. **Access Denied:** Confirm OIDC provider and IAM policy attachment
4. **Long Provisioning Time:** ALB creation takes 2-3 minutes - be patient

## 💰 Cost Considerations
- **Fargate:** Pay only for vCPU and memory resources used
- **No Idle EC2 Instances:** Fargate eliminates unused capacity costs
- **ALB:** Pay per hour and per processed requests
- **Auto-scaling:** Resources scale to zero when not in use

See [COST_ANALYSIS.md](./COST_ANALYSIS.md) for detailed cost comparison with EC2 alternatives.

## 🧹 Cleanup
```bash
# Delete the application
kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/examples/2048/2048_full.yaml

# Delete the cluster (this removes all resources)
eksctl delete cluster --name demo-cluster
```

## 📚 Skills Demonstrated
- **Container Orchestration:** Hands-on experience with Kubernetes on AWS
- **Serverless Compute:** Understanding Fargate vs traditional EC2 node groups
- **Cloud Networking:** VPC, subnets, load balancers, and ingress concepts
- **Security Best Practices:** IAM roles, service accounts, and RBAC
- **Infrastructure as Code:** Using eksctl for reproducible deployments
- **Monitoring & Troubleshooting:** kubectl commands and AWS console navigation

## 🎯 Next Steps
- [ ] Replace demo app with Flask data processing API
- [ ] Add CloudWatch monitoring dashboard
- [ ] Implement Terraform for infrastructure as code
- [ ] Create CI/CD pipeline with GitHub Actions
- [ ] Add resource limits and requests for production readiness

## 🙏 Acknowledgments
This project builds upon the Day 22 - AWS EKS tutorial from [iam-veeramalla's aws-devops-zero-to-hero](https://github.com/iam-veeramalla/aws-devops-zero-to-hero/tree/main/day-22) repository, with additional analysis and improvements focused on real-world application.

## 📝 Additional Resources
- [Lessons_Learned.md](./Lessons_Learned.md) - Detailed troubleshooting and insights
- [COST_ANALYSIS.md](./COST_ANALYSIS.md) - Fargate vs EC2 cost comparison
- [architecture/DESIGN_DECISIONS.md](./architecture/DESIGN_DECISIONS.md) - Architecture rationale
