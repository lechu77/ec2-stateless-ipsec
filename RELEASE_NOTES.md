# RELEASE_NOTES.md — Release Notes v1.0.0

## Release 1.0.0 — Production-Ready Stateless IPsec VPN Gateway & Web Service

We are pleased to announce the official **v1.0.0** release of `ec2-stateless-ipsec`, an automated, stateless IPsec VPN gateway and web service backend deployed on AWS using Terraform, Auto Scaling Groups, and SSM Parameter Store.

---

## Key Highlights

### 1. High Availability & Auto-Healing (ASG + Launch Template)
- Migrated from a single EC2 instance model to an **Auto Scaling Group (ASG)** backed by an **EC2 Launch Template**.
- Integrated support for **Network Load Balancers (NLB)** with health checks configured on `/healthCheck.php`.
- Zero-touch recovery: If an instance fails, the ASG launches a fresh replacement that automatically re-claims Elastic IPs and re-establishes VPN tunnels.

### 2. Interactive AWS Discovery Setup Wizard (`scripts/setup.sh`)
- Interactive setup script that authenticates with AWS and dynamically discovers VPCs, Subnets, Security Groups, Key Pairs, Elastic IPs, and Target Groups.
- Provides fallback options for authentication failures (CloudShell, `aws configure`, or temporary key entry).
- Generates all local configuration files (`ssm/*` and `terraform/terraform.tfvars`) with validated parameters.

### 3. Decoupled Modular Terraform Architecture
- Modularized into 5 dedicated components under `modules/`:
  - `modules/iam` — Role, Policies, and Instance Profile.
  - `modules/ssm` — Parameter Store resources managed in Terraform.
  - `modules/lb` — Network Load Balancer and Target Group.
  - `modules/launch_template` — EC2 Launch Template specification.
  - `modules/asg` — Auto Scaling Group management.

### 4. Complete Anonymization & Security
- Fully anonymized codebase using RFC 5737 documentation IP addresses (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`).
- Git-ignored local configuration files ensuring no secrets or private IPs are committed.

---

## Quick Start

```bash
# 1. Run interactive setup wizard
./scripts/setup.sh

# 2. Deploy with Terraform
cd terraform
terraform init
terraform apply
```
