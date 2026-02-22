# Lessons Learned & Troubleshooting

## 🚧 Challenges Encountered & Solutions

### 0. Teardown Order (The Mistake That Costs Money)
**Issue:** Running `eksctl delete cluster` immediately after finishing, only for it to hang or fail.
**Root Cause:** The Application Load Balancer is a Kubernetes-managed resource. When the
AWS Load Balancer Controller processes the Ingress, it creates a real ALB in AWS. That ALB
is attached to VPC subnets. When you try to delete the cluster, AWS cannot delete the VPC
while a load balancer is still attached to it — so the `eksctl` CloudFormation stack either
hangs or fails with a dependency error.

**Correct teardown order:**
```bash
# 1. Delete the Ingress — this triggers the controller to remove the ALB from AWS
kubectl delete ingress ingress-2048 -n game-2048

# 2. Wait for the ALB to be fully removed before proceeding
kubectl wait --for=delete ingress/ingress-2048 -n game-2048 --timeout=300s

# 3. Buffer for AWS to finish deregistering
sleep 30

# 4. NOW it is safe to delete the cluster
eksctl delete cluster --name demo-cluster --region us-east-1
```

Or just run:
```bash
bash scripts/teardown.sh
```

**Lesson:** The cluster teardown is as important as the deployment. An EKS cluster left
running costs ~$150+/month in background charges. Teardown is part of the project.

---

### 1. Load Balancer Provisioning Delays
**Issue:** ALB took 3+ minutes to become available after ingress creation
**Root Cause:** AWS resource propagation time and DNS configuration
**Solution:** 
```bash
# Added monitoring commands to track provisioning status
kubectl get ingress -n game-2048 -w
kubectl describe ingress ingress-2048 -n game-2048
```
**Analytics Parallel:** Similar to waiting for large dataset processing - need progress monitoring and patience with cloud resource provisioning

### 2. Fargate Profile Namespace Isolation
**Issue:** Pods stuck in `Pending` state initially
**Root Cause:** Fargate profile not correctly matching the target namespace
**Learning:** Fargate requires explicit namespace targeting unlike EC2 node groups
**Solution:** Verified Fargate profile configuration:
```bash
eksctl get fargateprofile --cluster demo-cluster
kubectl describe pod -n game-2048
```
**Business Impact:** Critical understanding for multi-tenant analytics environments where namespace isolation is required

### 3. OIDC Provider Setup Complexity
**Issue:** Service account permissions initially failed with authentication errors
**Root Cause:** IAM policy attachment timing - policy wasn't fully propagated before service account creation
**Solution:** Added verification step and wait time:
```bash
# Verify OIDC provider exists
aws eks describe-cluster --name demo-cluster --query "cluster.identity.oidc.issuer"
# Wait for policy propagation before proceeding
sleep 30
```
**Key Insight:** Security setup is sequential - document the exact order and include verification steps

### 4. Load Balancer Controller Pod Failures
**Issue:** AWS Load Balancer Controller pods failing to start
**Root Cause:** Insufficient permissions or incorrect cluster name in Helm values
**Debug Process:**
```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller
kubectl describe deployment -n kube-system aws-load-balancer-controller
```
**Learning:** Always verify Helm chart values match your actual cluster configuration

### 5. Network Connectivity Issues
**Issue:** Application accessible from ALB but ingress showed no endpoints
**Root Cause:** Service selector labels didn't match pod labels
**Investigation Steps:**
```bash
kubectl get endpoints -n game-2048
kubectl describe service -n game-2048
kubectl get pods -n game-2048 --show-labels
```
**Analytics Connection:** Similar to data pipeline debugging - trace the flow from source to destination

## 🧠 Key Technical Insights

### Container Networking in AWS
- **Discovery:** Fargate networking is different from EC2 — each pod gets its own ENI
- **Implication:** Different security group and network ACL considerations
- **Future Application:** Important for high-throughput data processing applications

### Fargate Persistent Volumes (EFS, not EBS)
- **Clarification:** Fargate does support persistent volumes, but only via EFS (Elastic
  File System), not EBS (Elastic Block Store).
- **Why:** EBS volumes are attached to EC2 instance block devices. Fargate has no
  underlying EC2 instance to attach to.
- **EFS on Fargate:** You can mount EFS volumes using the Amazon EFS CSI driver.
  EFS is network-attached, so it works with Fargate's pod-per-ENI model.
- **Implication:** If you need local-disk-speed storage (databases, write-heavy
  workloads), those workloads should run on EC2 node groups with EBS, not Fargate.

### IAM and Kubernetes Integration
- **Learning:** OIDC provider creates a bridge between AWS IAM and Kubernetes RBAC
- **Best Practice:** Use service accounts for fine-grained permissions rather than node-level IAM roles
- **Security Benefit:** Each workload can have minimal required permissions

### Cost Optimization Patterns
- **Observation:** Fargate billing starts when pod is scheduled, ends when terminated
- **Strategy:** For analytics workloads, design for quick startup/shutdown cycles
- **Metric to Track:** Time-to-ready for containers (impacts cost efficiency)

## 🔄 What I Would Do Differently

### 1. Infrastructure as Code First
**What I Did:** Used imperative eksctl commands
**Better Approach:** Start with Terraform or CloudFormation templates
**Why:** Reproducible across environments, version controlled infrastructure

### 2. Monitoring from Day One
**What I Did:** Basic kubectl commands for monitoring
**Better Approach:** Set up CloudWatch Container Insights immediately
**Why:** Understanding resource utilization patterns early informs optimization decisions

### 3. Security Scanning Integration
**What I Did:** Deployed without image security scanning
**Better Approach:** Integrate container image scanning in deployment pipeline
**Why:** Security should be built-in, not bolt-on

## 🎯 Advanced Scenarios Encountered

### Resource Quotas and Limits
**Challenge:** Understanding default Fargate resource allocation
**Investigation:**
```bash
kubectl describe node # Shows Fargate node capacity
kubectl top pods -n game-2048 # Resource usage
```
**Learning:** Fargate allocates specific CPU/memory combinations - important for cost planning

### DNS Resolution Patterns
**Discovery:** Internal service discovery works differently in Fargate
**Testing:**
```bash
kubectl exec -it pod-name -n game-2048 -- nslookup kubernetes.default.svc.cluster.local
```
**Application:** Critical for microservices communication patterns

## 📈 Performance Observations

### Cold Start Times
- **Fargate Pod Startup:** ~45-60 seconds from schedule to ready
- **ALB Target Registration:** ~30 seconds after pod ready
- **Total Time to Serve Traffic:** ~90-120 seconds

**Analytics Workload Implications:** 
- Not suitable for real-time processing with frequent scaling
- Excellent for batch processing with predictable schedules
- Consider warm pool strategies for interactive analytics

### Resource Utilization
- **2048 Game App:** ~50m CPU, ~64Mi memory under light load
- **Fargate Minimum:** 0.25 vCPU, 0.5 GB memory (smallest unit)
- **Efficiency:** 20% CPU utilization, 12% memory utilization

**Cost Optimization Learning:** Right-size applications to Fargate resource boundaries

## 🚀 Next Phase Improvements

### Immediate (Next 2 weeks)
1. **Replace demo app** with Flask-based data processing API
2. **Add resource requests/limits** to deployment manifests
3. **Implement health checks** with proper liveness/readiness probes
4. **Create monitoring dashboard** with CloudWatch or Grafana

### Medium Term (Next month)
1. **Terraform conversion** for infrastructure as code
2. **CI/CD pipeline** with GitHub Actions
3. **Security scanning** integration
4. **Multi-environment setup** (dev/staging/prod)

### New Skills Applied
- **Systematic Troubleshooting:** Applied data debugging methodologies to container issues
- **Documentation Practices:** Used analytical thinking to document decision rationale
- **Monitoring Mindset:** Approached infrastructure with same observability focus as data pipelines

This experience reinforced that many analytical thinking patterns translate directly to infrastructure problem-solving.
