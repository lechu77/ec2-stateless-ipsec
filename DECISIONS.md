# DECISIONS.md — Architectural Decision Records (ADR)

This document records key architectural, design, and technical decisions made during the evolution of `ec2-stateless-ipsec`.

---

## ADR-001: Fully Stateless EC2 Bootstrap via SSM Parameter Store

- **Status**: Accepted
- **Context**: Storing application state, IPsec configuration, or pre-shared keys directly on EC2 instance EBS volumes makes instance replacement difficult and introduces state drift.
- **Decision**: All configuration files, templates, scripts, and secrets are stored in AWS SSM Parameter Store as KMS-encrypted `SecureString`. The EC2 instance pulls these parameters dynamically at launch via `user-data.sh`.
- **Consequences**: Instances can be terminated and recreated at any time without data loss or configuration drift.

---

## ADR-002: Dynamic Elastic IP (EIP) Re-association at Boot

- **Status**: Accepted
- **Context**: IPsec VPN tunnels require static public IP addresses for IKE identity and encryption domain routing, but instances launched by an Auto Scaling Group receive dynamic private/public IPs.
- **Decision**: The bootstrap script uses EC2 API calls (`assign-private-ip-addresses` and `associate-address`) to claim predetermined Elastic IPs (`PRIMARY_EIP_ALLOCATION_ID` and `SECONDARY_EIP_ALLOCATION_ID`) at boot time.
- **Consequences**: Tunnels automatically recover even when instances are replaced across different Availability Zones.

---

## ADR-003: Transition from Standalone EC2 to Launch Template + Auto Scaling Group (ASG)

- **Status**: Accepted
- **Context**: A single standalone `aws_instance` resource does not provide auto-healing if the instance or Availability Zone fails.
- **Decision**: Replaced `aws_instance` with `aws_launch_template` and `aws_autoscaling_group` with `desired_capacity=1` and `min_size=1`.
- **Consequences**: Enables zero-touch auto-healing. If health checks fail, the ASG automatically launches a fresh replacement instance that boots statelessly.

---

## ADR-004: Decoupled Modular Terraform Architecture under `modules/`

- **Status**: Accepted
- **Context**: Monolithic `main.tf` files make it difficult to inspect, test, or re-use individual infrastructure components independently.
- **Decision**: Modularized Terraform into 5 decoupled sub-modules: `modules/iam`, `modules/ssm`, `modules/lb`, `modules/launch_template`, and `modules/asg`.
- **Consequences**: Allows independent lifecycle management (ABM) for each component and improves maintainability.

---

## ADR-005: Interactive AWS Discovery Setup Wizard (`scripts/setup.sh`)

- **Status**: Accepted
- **Context**: Manual editing of JSON and HCL configuration files leads to human syntax errors (missing commas, invalid IP formats, bad ARN strings).
- **Decision**: Built an interactive setup wizard that authenticates with AWS, queries AWS APIs for available VPCs, Subnets, SGs, Key Pairs, EIPs, and Target Groups, and automatically generates valid config files.
- **Consequences**: Reduces human interaction to a 2-step workflow (`./scripts/setup.sh` -> `terraform apply`).

---

## ADR-006: S3 + DynamoDB Remote State Backend Recommendation

- **Status**: Accepted
- **Context**: Storing `terraform.tfstate` locally or in Git is unsafe and prevents multi-developer collaboration.
- **Decision**: Documented an explicit `> [!IMPORTANT]` guideline in `README.md` recommending an S3 Bucket (versioned, SSE-KMS encrypted) with a DynamoDB Table for state locking.
- **Consequences**: Ensures state integrity and safety for team deployment.
