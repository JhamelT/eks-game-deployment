# Architecture Design Decisions

## Project Context

This project was originally deployed in February 2026 as a short-lived Amazon EKS
learning environment for hosting the 2048 web application.

The design prioritized:

- Hands-on Kubernetes and AWS integration
- Private application workloads
- Pod-level IAM permissions
- Cost awareness
- Repeatable teardown
- Clear documentation of tradeoffs

The implementation is best described as a **production-aligned learning
architecture**, not a complete production platform.

---

## 1. AWS Fargate vs EC2 Managed Node Groups

**Decision:** Run the application and supporting Kubernetes workloads on AWS
Fargate.

### Rationale

- **No worker-node management:** No EC2 worker operating systems to patch,
  replace, or scale.
- **Pod-level isolation:** Each Fargate pod receives dedicated provisioned
  compute instead of sharing an EC2 worker node.
- **Learning focus:** Keeps attention on Kubernetes scheduling, networking,
  ingress, and IAM rather than node administration.
- **Short-lived environment fit:** Appropriate for a temporary lab that is
  deployed, validated, and then removed.

### Tradeoffs

- Fargate generally has a higher sustained compute-unit cost than efficiently
  utilized EC2 worker nodes.
- A Kubernetes Deployment with fixed replicas continues generating compute
  charges until it is explicitly scaled down or deleted.
- Fargate removes idle worker-node capacity, but it does not automatically scale
  the workload to zero.
- Fargate provides less control over the worker operating system and instance
  type.
- The project should not claim a fixed percentage savings over EC2 because the
  options are not operationally equivalent.

### When to Reconsider

EC2 managed node groups may be a better fit when:

- Workloads run continuously at predictable utilization
- Many pods can efficiently share node capacity
- Specialized instance types are required
- The team needs deeper control over the worker environment
- Node scaling, patching, and lifecycle management are already mature

---

## 2. Application Load Balancer vs Network Load Balancer

**Decision:** Use an Application Load Balancer provisioned by the AWS Load
Balancer Controller.

### Rationale

- The application serves HTTP traffic.
- ALB supports Layer 7 routing.
- Host- and path-based routing can support future services.
- Kubernetes Ingress provides a declarative interface for the routing
  configuration.
- ALB integrates naturally with AWS Certificate Manager for a future HTTPS
  implementation.

### Tradeoffs

- The ALB introduces an hourly base charge and usage-based capacity charges.
- The current project does not implement HTTPS termination, AWS WAF, or custom
  domain routing.
- The AWS Load Balancer Controller requires AWS permissions and additional
  Kubernetes configuration.

---

## 3. IRSA and the Cluster OIDC Provider

**Decision:** Use IAM Roles for Service Accounts (IRSA) for the AWS Load
Balancer Controller.

### Rationale

- The controller receives only the AWS permissions required to manage load
  balancer resources.
- The IAM role is associated with a Kubernetes service account rather than
  granting broad permissions through a worker-node role.
- The cluster OIDC provider creates the trust relationship between Kubernetes
  service-account identity and AWS IAM.
- EKS Pod Identity depends on a node agent and is not supported for Fargate
  pods, so IRSA is the appropriate pod-level identity mechanism for this
  Fargate-only design.

### Security Principle

Grant AWS permissions to the workload that needs them rather than to every
workload running in the cluster.

---

## 4. Single NAT Gateway vs High Availability and VPC Endpoints

**Decision:** Use one NAT Gateway for the temporary development environment.

### Rationale

- Reduces the fixed hourly cost compared with deploying one NAT Gateway per
  Availability Zone.
- Provides general outbound connectivity for private workloads.
- Keeps the temporary lab simpler to deploy and troubleshoot.

### Tradeoffs

- Private workloads in both Availability Zones depend on one NAT Gateway.
- A failure in the NAT Gateway's Availability Zone can interrupt outbound
  connectivity for workloads in the other Availability Zone.
- Cross-AZ traffic may introduce additional processing charges.
- This is a cost-optimized development decision, not the preferred
  high-availability production pattern.

### VPC Endpoint Alternative

VPC endpoints can keep supported AWS-service traffic on private AWS networking
and allow tighter endpoint policies. They can reduce dependence on general
internet egress.

However, interface endpoints are billed per endpoint and per Availability Zone.
For a small, short-lived cluster, the required endpoint set may cost more than
one NAT Gateway.

VPC endpoints should therefore be evaluated primarily as a security and egress
control decision, with cost modeled separately for the required services and
traffic volume.

---

## 5. Helm vs Direct Manifest Installation

**Decision:** Install the AWS Load Balancer Controller with Helm.

### Rationale

- Provides structured release and values management.
- Simplifies controlled upgrades.
- Makes configuration differences easier to review.
- Reflects common Kubernetes platform practices.

### Improvement

A future deployment should pin both the Helm chart version and controller image
version rather than installing whichever release is current at deployment time.

---

## 6. Application Resource Sizing

**Decision:** Request 0.25 vCPU and 512 MiB for each of three application
containers.

```yaml
resources:
  requests:
    cpu: "250m"
    memory: "512Mi"
  limits:
    cpu: "250m"
    memory: "512Mi"
```

### Important Billing Detail

EKS Fargate adds platform overhead to the pod's declared memory request before
selecting a supported Fargate configuration.

Because of that overhead, this workload is expected to provision at 0.25 vCPU
and 1 GB rather than the 0.5 GB tier.

The `CapacityProvisioned` annotation on a running pod is the final source of
truth for the provisioned and billable Fargate size.

---

## 7. NodePort Service and ALB IP Targets

**Decision:** Use a Kubernetes `NodePort` Service with ALB target type `ip`.

```yaml
alb.ingress.kubernetes.io/target-type: ip
```

### Rationale

- The Service provides the backend referenced by the Kubernetes Ingress.
- IP target mode registers the Fargate pod IP addresses directly.
- Fargate pods do not have backing EC2 worker nodes available for ALB instance
  target registration.
- The Service selector must match the Deployment labels exactly or the Service
  will have no endpoints and the ALB will return 503 responses.

The important Fargate-specific requirement is IP target registration. This
implementation uses `NodePort`; it should not claim that NodePort is the only
possible Service type supported for the ALB integration.

---

## 8. Kubernetes Version Lifecycle

**Historical configuration:** Amazon EKS 1.32.

The cluster was deployed in February 2026 while version 1.32 was still in
standard EKS support. It has since entered extended support.

The repository preserves version 1.32 to document the historical deployment
accurately. A new deployment should use a Kubernetes version currently in
standard support after validating:

- AWS Load Balancer Controller compatibility
- CoreDNS and other add-ons
- Workload manifests
- IAM integration
- Teardown automation

Version lifecycle management is both an operational and cost-control
responsibility because EKS extended-support cluster pricing is higher than
standard-support pricing.

---

## 9. Networking Model

The application architecture uses:

- Public subnets for the internet-facing ALB and NAT Gateway
- Private subnets for Fargate workloads
- An Internet Gateway for public ingress and NAT egress
- One logical ALB spanning public subnets in two Availability Zones
- Direct ALB target registration to Fargate pod IP addresses

Inbound and outbound traffic are separate paths:

```text
Inbound:
User -> Internet Gateway -> ALB -> Fargate pod IP

Outbound:
Fargate pod -> NAT Gateway -> Internet Gateway
```

The NAT Gateway is not part of the inbound ALB request path.

---

## 10. Current Limitations

The project intentionally does not claim complete production readiness.

Current limitations include:

- No HTTPS or ACM certificate
- No AWS WAF
- No readiness or liveness probes
- No Horizontal Pod Autoscaler
- No scheduled or event-driven scale-to-zero mechanism
- No centralized metrics dashboard
- No CI/CD deployment pipeline
- No infrastructure implementation in Terraform or CloudFormation
- Container image uses the mutable `latest` tag
- Kubernetes and controller versions are historical rather than current

---

## Modernization Roadmap

### Deployment Hardening

1. Deploy on a Kubernetes version currently in standard EKS support.
2. Pin the AWS Load Balancer Controller chart and image versions.
3. Pin the 2048 image by digest.
4. Add readiness and liveness probes.
5. Add deployment health validation before reporting success.
6. Capture the observed `CapacityProvisioned` annotation for cost verification.

### Infrastructure and Delivery

1. Rebuild the environment with Terraform.
2. Add automated validation in CI.
3. Add controlled deployment and teardown workflows.
4. Add policy checks for Kubernetes and IAM configuration.

### Security

1. Add HTTPS with AWS Certificate Manager.
2. Evaluate AWS WAF for internet-facing traffic.
3. Add Kubernetes NetworkPolicies where supported by the networking design.
4. Evaluate VPC endpoints for private AWS-service access.
5. Review IAM permissions against the current controller policy.

### Observability and Cost

1. Enable centralized application and controller logs.
2. Add CloudWatch dashboards and alarms.
3. Track pod-level resource usage before changing requests.
4. Compare NAT Gateway and VPC endpoint costs using measured traffic.
5. Alert on clusters running extended-support Kubernetes versions.

---

## Decision Framework for Future Projects

Each architecture decision should document:

1. **Context:** What problem and constraints exist?
2. **Options:** What reasonable alternatives were considered?
3. **Decision:** What was selected?
4. **Rationale:** Why does the choice fit this workload?
5. **Tradeoffs:** What cost, reliability, security, or operational compromises
   were accepted?
6. **Validation:** What evidence proves the design works?
7. **Revisit trigger:** What change would cause the decision to be reconsidered?
