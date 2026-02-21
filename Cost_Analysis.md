# Cost Analysis — EKS Fargate vs EC2 Node Groups

## The Number That Surprises People

Before comparing Fargate vs EC2, the most important cost to understand is the one
both share equally:

**EKS Control Plane Fee: $0.10/hr = $72/month**

This fee covers the managed Kubernetes control plane (API server, etcd, scheduler)
that AWS runs for you. It accrues whether your cluster has zero pods or a thousand,
and whether you're using Fargate or EC2. It is often the single largest line item
for small or learning clusters.

For a weekend deployment (~60 hours): **~$6.00 just for the control plane.**

---

## Weekend Deployment Cost (~60 hours, us-east-1)

| Component | Rate | ~60-hour cost |
|-----------|------|---------------|
| EKS control plane | $0.10/hr | **~$6.00** |
| Fargate compute (3 pods × 0.25 vCPU / 0.5 GB) | ~$0.037/hr | ~$2.22 |
| NAT Gateway (Single, base only) | $0.045/hr | ~$2.70 |
| Application Load Balancer (base) | $0.0225/hr | ~$1.35 |
| Data transfer | variable | ~$0.50 |
| **Total** | | **~$12-16** |

**NAT Gateway note:** This project uses a Single NAT Gateway (configured in
`cluster/cluster-config.yaml`). The eksctl default (`HighlyAvailable`) creates one
NAT Gateway per AZ — two in us-east-1a/b — doubling the base NAT cost from
~$2.70 to ~$5.40 for the same weekend. Single NAT is appropriate for a learning
project; HighlyAvailable is appropriate for production.

---

## Monthly Projection (24/7 running)

This is what a forgotten cluster would cost:

| Component | Monthly Cost |
|-----------|--------------|
| EKS control plane (24/7) | **~$72.00** |
| Fargate compute (3 pods, 24/7) | ~$27.00 |
| NAT Gateway (Single, 24/7) | ~$32.40 |
| Application Load Balancer (base) | ~$16.20 |
| LCU + data transfer | ~$5.00 |
| **Total** | **~$150+/month** |

The control plane dominates. At $72/month, it is larger than Fargate compute,
NAT Gateway, and the ALB combined for a lightly-used cluster.

---

## Fargate vs EC2: Detailed Comparison

### Scenario: Analytics Workload Pattern
- Peak usage: 8 hours/day (business hours)
- Idle time: 16 hours/day (nights/weekends)
- Pattern: Batch ETL, ML training, report generation

### Fargate (this project)

| Resource | Rate | Daily cost (8hr active) |
|----------|------|------------------------|
| 0.25 vCPU | $0.04048/hr | $0.081 |
| 0.5 GB memory | $0.004445/GB/hr | $0.018 |
| **Compute total/day** | | **$0.099** |
| Monthly compute | | **~$2.97** |

Full monthly cost with shared infrastructure:

| Component | Monthly |
|-----------|---------|
| EKS control plane | ~$72.00 |
| Fargate compute (8hr/day) | ~$2.97 |
| NAT Gateway (Single) | ~$32.40 |
| ALB (base) | ~$16.20 |
| Data transfer | ~$0.50 |
| **Total** | **~$124/month** |

### EC2 Node Group — t3.small

| Component | Monthly |
|-----------|---------|
| EKS control plane | ~$72.00 |
| t3.small EC2 (24/7, $0.0208/hr) | ~$15.37 |
| EBS storage (30GB gp3) | ~$3.00 |
| NAT Gateway (Single) | ~$32.40 |
| ALB (base) | ~$16.20 |
| Data transfer | ~$0.50 |
| **Total** | **~$139/month** |

### EC2 Node Group — t3.medium

| Component | Monthly |
|-----------|---------|
| EKS control plane | ~$72.00 |
| t3.medium EC2 (24/7, $0.0416/hr) | ~$30.74 |
| EBS storage (30GB gp3) | ~$3.00 |
| NAT Gateway (Single) | ~$32.40 |
| ALB (base) | ~$16.20 |
| Data transfer | ~$0.50 |
| **Total** | **~$155/month** |

### Summary Table

| Option | Monthly Total | Notes |
|--------|--------------|-------|
| Fargate (8hr/day) | ~$124 | Compute scales to zero, control plane does not |
| Fargate (24/7) | ~$150+ | No advantage over EC2 at full utilization |
| EC2 t3.small (24/7) | ~$139 | Cheaper compute than Fargate at high utilization |
| EC2 t3.medium (24/7) | ~$155 | More headroom for multiple workloads |

---

## The Real Decision: Usage Pattern

The comparison is not "Fargate is cheaper than EC2." It is:

**"What is your usage pattern, and how much of the fixed cost can you justify?"**

The EKS control plane is $72/month regardless. Given that:

- **Fargate wins** for intermittent workloads (scale to zero, pay zero for compute
  during idle hours). The compute savings compound over time.
- **EC2 wins** for workloads running 16+ hours/day. At continuous utilization,
  EC2 compute per hour is lower than Fargate, and you're paying the same fixed
  costs either way.
- **Neither is cheap for learning projects** if left running. Delete the cluster
  when not in use.

---

## When Fargate Is the Wrong Choice

- **Workloads running 16+ hours/day.** EC2 compute is less expensive per hour.
- **GPU or custom instance types.** Fargate only supports specific vCPU/memory
  combinations. ML training needs EC2.
- **Cold start latency requirements.** Fargate pod startup: ~45-60 seconds.
  For real-time applications with aggressive scaling, this may be too slow.
- **Stateful workloads needing EBS.** Fargate supports EFS (Elastic File System)
  persistent volumes but not EBS. Databases and stateful services typically need
  EC2 node groups for EBS support.

**If you choose EC2 node groups:** Look into Karpenter instead of Cluster Autoscaler.
Karpenter provisions right-sized nodes faster and is now the recommended approach
for EC2-based EKS clusters.

---

## Cost Monitoring

**Recommended tools:**
- **AWS Cost Explorer** — track spending trends by service
- **CloudWatch** — monitor resource utilization and set billing alarms
- **Kubecost** — Kubernetes-native cost breakdown per namespace and pod
- **Cast AI** — optimization recommendations for EKS clusters

**Billing alarm (set this before deploying):**
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name eks-cost-alarm \
  --metric-name EstimatedCharges \
  --namespace AWS/Billing \
  --statistic Maximum \
  --period 86400 \
  --threshold 20 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:<region>:<account-id>:<topic>
```
