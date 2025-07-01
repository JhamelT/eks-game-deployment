# EKS 2048 Game Deployment with AWS Load Balancer Controller

A complete end-to-end deployment of a containerized 2048 game on Amazon EKS using Fargate, demonstrating modern cloud-native DevOps practices.

## 🏗️ Architecture Overview

```
Internet → ALB → EKS Fargate Pods → 2048 Game Application
```

**Key Components:**
- **Amazon EKS Cluster** with Fargate compute
- **AWS Load Balancer Controller** for ingress management
- **Application Load Balancer (ALB)** for external access
- **Kubernetes Ingress** for traffic routing
- **Multiple Fargate Profiles** for namespace isolation

## 🛠️ Technologies Used

- **Container Orchestration:** Amazon EKS (Kubernetes 1.32)
- **Compute:** AWS Fargate (Serverless containers)
- **Load Balancing:** AWS Application Load Balancer
- **Infrastructure Management:** eksctl, kubectl
- **Package Management:** Helm
- **Networking:** VPC with public/private subnets
- **Security:** IAM roles, OIDC provider, Service Accounts

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

### 2. Set up Additional Fargate Profile

```bash
# Create namespace-specific Fargate profile
eksctl create fargateprofile \
    --cluster demo-cluster \
    --region us-east-1 \
    --name alb-sample-app \
    --namespace game-2048
```

### 3. Configure OIDC Provider

```bash
# Associate IAM OIDC provider for service accounts
eksctl utils associate-iam-oidc-provider --cluster demo-cluster --approve
```

### 4. Install AWS Load Balancer Controller

```bash
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

# Install controller via Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
    -n kube-system \
    --set clusterName=demo-cluster \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller
```

### 5. Deploy the 2048 Game Application

```bash
# Deploy using the official AWS Load Balancer Controller example
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/examples/2048/2048_full.yaml

# Monitor deployment
kubectl get pods -n game-2048 -w
kubectl get ingress -n game-2048

# Get the application URL (may take 2-3 minutes for ALB provisioning)
kubectl get ingress ingress-2048 -n game-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## 🔍 Verification & Testing

```bash
# Check all components
kubectl get all -n game-2048
kubectl get ingress -n game-2048
kubectl describe ingress ingress-2048 -n game-2048

# Get application URL
kubectl get ingress ingress-2048 -n game-2048 -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## 🏛️ Infrastructure Details

**Networking:**
- VPC with public and private subnets across 2 AZs
- Internet Gateway for public subnet access
- NAT Gateway for private subnet egress

**Security:**
- IAM roles with least privilege access
- Security groups for pod-to-pod communication
- OIDC provider for Kubernetes service account authentication

**Compute:**
- Fargate profiles for serverless container execution
- No EC2 instances to manage or patch
- Automatic scaling based on resource requirements

## 💰 Cost Optimization

- **Fargate**: Pay only for vCPU and memory resources used
- **No idle EC2 instances**: Fargate eliminates unused capacity costs
- **ALB**: Pay per hour and per processed requests
- **Auto-scaling**: Resources scale to zero when not in use

## 🧹 Cleanup

```bash
# Delete the application
kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/examples/2048/2048_full.yaml

# Delete the cluster (this removes all resources)
eksctl delete cluster --name demo-cluster
```

## 🎯 Key Learning Outcomes

- **Container Orchestration**: Hands-on experience with Kubernetes on AWS
- **Serverless Compute**: Understanding Fargate vs traditional EC2 node groups
- **Cloud Networking**: VPC, subnets, load balancers, and ingress concepts
- **Security Best Practices**: IAM roles, service accounts, and RBAC
- **Infrastructure as Code**: Using eksctl for reproducible deployments
- **Monitoring & Troubleshooting**: kubectl commands and AWS console navigation

## 🔗 Tutorial Reference

This project follows the **Day 22 - AWS EKS** tutorial from [iam-veeramalla's aws-devops-zero-to-hero](https://github.com/iam-veeramalla/aws-devops-zero-to-hero/tree/main/day-22) repository.

**Key Learning Path:**
- EKS cluster creation with Fargate
- AWS Load Balancer Controller setup
- OIDC provider configuration
- Ingress controller deployment
- Real-world application deployment

## 📚 Additional Resources

- [Amazon EKS Documentation](https://docs.aws.amazon.com/eks/)
- [AWS Load Balancer Controller Guide](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Kubernetes Ingress Documentation](https://kubernetes.io/docs/concepts/services-networking/ingress/)
