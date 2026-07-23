# CHANGELOG.md — Version History

All notable changes to the `ec2-stateless-ipsec` project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-07-23

### Added
- **Interactive AWS Discovery Setup Wizard (`scripts/setup.sh`)**:
  - Validates AWS credentials via `sts:GetCallerIdentity`.
  - Provides options for CloudShell, `aws configure`, or temporary Access Key entry upon authentication failure.
  - Dynamically queries AWS APIs to list and select VPCs, Subnets, Security Groups, Key Pairs, EIP Allocations, and Target Groups.
  - Auto-generates a 32-character secure IPsec Pre-Shared Key (PSK) if none is provided.
  - Supports non-interactive / CI-CD execution via `--non-interactive`.
- **Modularized Terraform Architecture (`modules/`)**:
  - Decoupled into `modules/iam`, `modules/ssm`, `modules/lb`, `modules/launch_template`, and `modules/asg`.
  - Managed SSM Parameter Store resources directly within Terraform (`modules/ssm`).
- **High Availability & Auto-Healing**:
  - Replaced standalone `aws_instance` with `aws_launch_template` and `aws_autoscaling_group` (ASG).
  - Integrated Network Load Balancer (NLB), Target Group, and Listener configuration (`modules/lb`).
- **Anonymization & Security**:
  - Replaced all customer-specific paths, domain names, IPs, and keys with generic `.example` templates and RFC 5737 documentation addresses.
  - Updated `.gitignore` to prevent committing sensitive local SSM configuration files and `terraform.tfvars`.
- **Comprehensive Documentation Suite**:
  - Added `AGENTS.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `CONTEXT.md`, `DECISIONS.md`, `MEMORY.md`, `RELEASE_NOTES.md`, `STATE.md`, and `TASKS.md`.

### Changed
- Refactored `ssm/bootstrap-vars.sh` to retrieve `/vpn-gateway/ipsec/remote-gateway` and `/vpn-gateway/ipsec/remote-hosts` directly from SSM.
- Updated `user-data.sh` to use generic `/vpn-gateway/*` SSM parameter namespace.
- Improved ASCII architecture diagram in `README.md` using clean Unicode box drawing.

### Removed
- Removed hardcoded customer specific files (`claro-uy.conf`, `ws-claro-uy-plat-ilfis.com.conf`).
- Removed requirement for manual parameter uploads via shell scripts prior to Terraform deployment.
