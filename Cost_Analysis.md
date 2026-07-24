# Cost Analysis — Amazon EKS on AWS Fargate

## Scope and Assumptions

This document models the architecture as it was originally deployed in February
2026 in `us-east-1`.

The estimates use:

- One Amazon EKS cluster
- Three application replicas on AWS Fargate
- One NAT Gateway
- One internet-facing Application Load Balancer
- A 30-day month with 720 hours
- Linux/x86 Fargate pricing
- Base infrastructure pricing before variable data-processing charges

The deployment requests the following resources for each application container:

```yaml
cpu: "250m"
memory: "512Mi"
```

Amazon EKS adds Fargate platform overhead to the pod's declared memory request
before selecting a supported Fargate configuration. With that overhead, this
workload is expected to provision at:

- 0.25 vCPU
- 1 GB memory

The `CapacityProvisioned` annotation on a running pod is the final source of
truth for its actual billable Fargate size.

---

## Pricing Assumptions

Approximate `us-east-1` rates used in this model:

| Resource | Rate |
|----------|------|
| EKS cluster during standard version support | $0.10 per cluster-hour |
| EKS cluster during extended version support | $0.60 per cluster-hour |
| Fargate Linux/x86 vCPU | $0.04048 per vCPU-hour |
| Fargate Linux/x86 memory | $0.004445 per GB-hour |
| NAT Gateway base charge | $0.045 per hour |
| Application Load Balancer base charge | $0.0225 per hour |

These estimates exclude taxes, promotional credits, free-tier credits, and
usage-based charges that vary with traffic.

Official pricing references:

- Amazon EKS: https://aws.amazon.com/eks/pricing/
- AWS Fargate: https://aws.amazon.com/fargate/pricing/
- Amazon VPC and NAT Gateway: https://aws.amazon.com/vpc/pricing/
- Elastic Load Balancing: https://aws.amazon.com/elasticloadbalancing/pricing/

---

## Fargate Compute Calculation

### Per pod

CPU:

```text
0.25 vCPU × $0.04048 = $0.01012 per hour
```

Memory:

```text
1 GB × $0.004445 = $0.004445 per hour
```

Total per pod:

```text
$0.01012 + $0.004445 = $0.014565 per hour
```

### Three application replicas

```text
3 × $0.014565 = $0.043695 per hour
```

This calculation covers only the three application pods. Additional Fargate
workloads, including CoreDNS or the AWS Load Balancer Controller, may generate
additional compute charges depending on their observed placement and
provisioned capacity.

---

## Historical Weekend Deployment

The original deployment ran for approximately 60 hours while EKS 1.32 was still
in standard support.

| Component | Calculation | Approximate Cost |
|-----------|-------------|------------------|
| EKS control plane | 60 × $0.10 | $6.00 |
| Three Fargate application pods | 60 × $0.043695 | $2.62 |
| Single NAT Gateway base charge | 60 × $0.045 | $2.70 |
| Application Load Balancer base charge | 60 × $0.0225 | $1.35 |
| **Base subtotal** | | **$12.67** |

The subtotal excludes:

- NAT Gateway data-processing charges
- ALB capacity-unit charges
- Internet data transfer
- CloudWatch log ingestion and storage
- Other short-lived supporting resources

This model is consistent with an observed total of less than $20 for the
weekend deployment.

---

## Monthly Projection: Three Pods Running 24/7

This scenario assumes a Kubernetes version in standard support.

### Fargate compute

```text
$0.043695 per hour × 720 hours = $31.46 per month
```

### Full base-cost projection

| Component | Approximate Monthly Cost |
|-----------|--------------------------|
| EKS control plane | $72.00 |
| Three Fargate application pods | $31.46 |
| Single NAT Gateway | $32.40 |
| Application Load Balancer base charge | $16.20 |
| **Base subtotal** | **$152.06** |

Variable NAT data processing, ALB capacity units, data transfer, logging, and
other supporting workloads would increase the final bill.

The EKS control plane is the largest individual line item. However, the
combined networking and application-compute costs are greater than the
control-plane fee.

The EKS control plane, NAT Gateway, and ALB contribute approximately:

```text
$72.00 + $32.40 + $16.20 = $120.60 per month
```

Those platform and networking costs exist before accounting for application
traffic.

---

## Kubernetes Version Lifecycle Cost

The project was originally deployed using EKS 1.32 in February 2026, when that
version was still in standard support.

EKS 1.32 entered extended support on March 23, 2026.

A cluster still running version 1.32 during extended support would incur:

```text
$0.60 per hour × 720 hours = $432.00 per month
```

Using the same three-pod architecture:

| Component | Approximate Monthly Cost |
|-----------|--------------------------|
| EKS 1.32 extended-support control plane | $432.00 |
| Three Fargate application pods | $31.46 |
| Single NAT Gateway | $32.40 |
| Application Load Balancer base charge | $16.20 |
| **Base subtotal** | **$512.06** |

This does not mean the historical weekend estimate was incorrect. It shows that
Kubernetes version lifecycle management is also a cost-control responsibility.

A new deployment should use a Kubernetes version currently in EKS standard
support after validating add-on and workload compatibility.

---

## Eight-Hour-Per-Day Scenario

AWS Fargate does not automatically change a Kubernetes Deployment from three
replicas to zero.

The current manifest declares:

```yaml
replicas: 3
```

Unless the Deployment is manually scaled down or controlled by scheduled
automation or an event-driven autoscaler, all three pods continue running and
continue generating Fargate charges.

If an external mechanism explicitly ran all three pods for eight hours per day
and scaled the Deployment to zero for the remaining 16 hours:

```text
3 pods × $0.014565 × 8 hours × 30 days
= approximately $10.49 per month
```

The standard-support base-cost projection would then be:

| Component | Approximate Monthly Cost |
|-----------|--------------------------|
| EKS control plane | $72.00 |
| Fargate application compute | $10.49 |
| Single NAT Gateway | $32.40 |
| Application Load Balancer base charge | $16.20 |
| **Base subtotal** | **$131.09** |

This is a hypothetical operating model. The project does not currently
implement scheduled scaling, KEDA, or another scale-to-zero mechanism.

Fargate removes the need to pay for idle worker nodes. It does not remove the
cost of pods that are still declared and running.

---

## Fargate Versus EC2 Node Groups

This project should not claim a fixed percentage savings over EC2.

A single `t3.small` node is not an equivalent high-availability comparison to
three Fargate pods running in a multi-AZ VPC. A production-oriented EC2 node
group would normally require multiple nodes across Availability Zones, EBS
storage, scaling configuration, patching, and node lifecycle management.

### Fargate is a strong fit when

- Workloads are short-lived or intermittent
- The team does not want to operate worker nodes
- Pod-level resource isolation is useful
- Demand is unpredictable
- Operational simplicity is more valuable than the lowest sustained
  compute-unit price

### EC2 node groups are a strong fit when

- Workloads run continuously at predictable utilization
- Many pods can efficiently share node capacity
- The workload requires broader instance-type selection
- The team needs deeper control over the worker operating system
- The organization already operates mature node scaling and patching processes

The correct decision is based on workload shape, reliability requirements,
security constraints, and operational ownership rather than one universal
percentage comparison.

---

## NAT Gateway Versus VPC Endpoints

The project uses one NAT Gateway as a deliberate development-cost tradeoff.

A single NAT Gateway:

- Provides general outbound access for private workloads
- Is simpler to configure for a temporary lab
- Introduces a dependency on one Availability Zone
- Adds hourly and per-GB processing charges

VPC endpoints can provide more restrictive private connectivity to supported
AWS services and reduce reliance on internet egress. However, interface
endpoints also incur hourly charges per endpoint and per Availability Zone.

For this small project, VPC endpoints are not automatically cheaper than one
NAT Gateway. Their strongest benefit would be tighter egress control rather
than guaranteed cost reduction.

A production decision should compare:

- Required AWS services
- Number of interface endpoints
- Number of Availability Zones
- Expected data volume
- Need for general internet access
- Security and compliance requirements

---

## Cost-Control Practices Demonstrated

This project applies several practical controls:

1. One NAT Gateway instead of one per Availability Zone for the temporary lab
2. Explicit CPU and memory requests
3. Immediate teardown after validation
4. Dependency-aware deletion of the Ingress and ALB before cluster teardown
5. Cost analysis that separates fixed platform costs from workload compute
6. Documentation of the Kubernetes version lifecycle
7. Clear distinction between historical cost and current pricing

For temporary EKS learning environments, teardown discipline is usually the
largest cost optimization.
