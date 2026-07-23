# AGENTS.md — AI Agent Operating Instructions & Guidelines

This document provides instructions for AI Coding Assistants and Autonomous Agents interacting with the `ec2-stateless-ipsec` codebase.

---

## 1. System Overview

`ec2-stateless-ipsec` is a fully stateless Infrastructure-as-Code (IaC) repository for deploying an Amazon Linux 2023 EC2 instance managed by an Auto Scaling Group (ASG) behind a Network Load Balancer (NLB). The instance acts as an IPsec VPN gateway (Libreswan) and an Apache web service backend (`httpd` + `php-fpm`).

### Core Principles
- **100% Stateless EC2 Instances**: No state is stored on instance local disks. Terminating and relaunching instances via ASG or Terraform is the standard procedure.
- **SSM Parameter Store Configuration**: All runtime configuration, helper functions, IPsec secrets, host lists, and Apache templates are stored in AWS SSM Parameter Store (`/vpn-gateway/*`) as KMS-encrypted `SecureString`.
- **Dynamic EIP Re-association**: At boot time, `user-data.sh` queries IMDSv2 and AWS EC2 APIs to discover ENI IDs, assign secondary private IPs, and associate designated Elastic IPs (`PRIMARY_EIP_ALLOCATION_ID` and `SECONDARY_EIP_ALLOCATION_ID`).
- **Decoupled Modular Terraform**: All infrastructure resources are modularized under `modules/` (`iam`, `ssm`, `lb`, `launch_template`, `asg`).

---

## 2. Repository Conventions & Rules

1. **Zero Hardcoded Secrets or IPs**:
   - Never commit AWS credentials, private IPs, pre-shared keys (PSK), customer names, or specific domain names to Git.
   - All example files in `ssm/` must use `.example` extension with RFC 5737 documentation IPs (`192.0.2.x`, `198.51.100.x`, `203.0.113.x`) and generic domains (`ws.example.com`).

2. **EC2 User-Data Size Limit**:
   - AWS EC2 `user-data` has a strict **16 KB (16,384 bytes)** limit.
   - Do NOT bloat `user-data.sh`. Complex variable extraction and helper functions must remain in `ssm/bootstrap-vars.sh` and `ssm/bootstrap-helpers.sh` which are fetched dynamically from SSM at boot.

3. **Shell Script Portability**:
   - Bash scripts (`scripts/setup.sh`, `scripts/ssm-put-parameters.sh`) must be compatible with macOS default Bash 3.2, Linux Bash 4/5, and AWS CloudShell.
   - Avoid Bash 4+ features like `mapfile`/`readarray` unless guarded; prefer portable `while IFS= read -r line; do ... done`.

4. **Terraform Module Hierarchy**:
   - Root module in `terraform/main.tf` composes modules from `modules/`.
   - Do not mix raw resource blocks into `terraform/main.tf` if a corresponding module exists in `modules/`.

---

## 3. Workflow for Agent Operations

- **Setup Execution**: Run `./scripts/setup.sh` (or `./scripts/setup.sh --non-interactive`) to generate local config files from `.example` templates.
- **Terraform Plan / Apply**: Execute from `terraform/` directory (`cd terraform && terraform init && terraform plan`).
- **Secret & Config Verification**: Ensure real generated files in `ssm/` and `terraform/terraform.tfvars` remain in `.gitignore`.
