# MEMORY.md — Persistent Operational Memory & Context

This file maintains persistent operational context and key system constraints for developers and AI assistants working on `ec2-stateless-ipsec`.

---

## 1. Key System Constraints

- **User-Data Size**: `user-data.sh` must remain under 16,384 bytes (16 KB). Current size: ~16.28 KB.
- **Portability**: All shell scripts must work in Bash 3.2 (macOS default), Bash 4/5 (Linux), and AWS CloudShell.
- **Secrets & Anonymization**: Never hardcode real AWS Account IDs, private customer IPs, pre-shared keys, or private domain names in committed files.
- **SSM Parameter Namespace**: Fixed to `/vpn-gateway/*`.

---

## 2. Active Components & File Locations

- **Root Modules**: `terraform/main.tf`, `terraform/variables.tf`, `terraform/outputs.tf`, `terraform/terraform.tfvars.example`
- **Infrastructure Modules**:
  - `modules/iam/` (IAM Role, Policy, Instance Profile)
  - `modules/ssm/` (SSM Parameter Store resources)
  - `modules/lb/` (Network Load Balancer & Target Group)
  - `modules/launch_template/` (EC2 Launch Template)
  - `modules/asg/` (Auto Scaling Group)
- **Bootstrap Scripts**:
  - `user-data.sh` (EC2 User-Data entry point)
  - `ssm/bootstrap-helpers.sh` (Shared shell helper functions)
  - `ssm/bootstrap-vars.sh` (Variable extraction script)
- **Automation Scripts**:
  - `scripts/setup.sh` (AWS Discovery Setup Wizard)
  - `scripts/ssm-put-parameters.sh` (AWS CLI SSM Uploader fallback)

---

## 3. Operational Workflow

1. Run `./scripts/setup.sh` (interactive or `--non-interactive`).
2. Run `cd terraform && terraform init && terraform apply`.
3. To replace instance: `cd terraform && terraform apply -replace=module.launch_template.aws_launch_template.vpn`.
