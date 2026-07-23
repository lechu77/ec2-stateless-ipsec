# STATE.md — System State & Component Health

This document tracks the current status, component matrix, and deployment readiness of the `ec2-stateless-ipsec` solution.

---

## 1. System Readiness Matrix

| Component | Status | Location | Notes |
|-----------|--------|----------|-------|
| Setup Wizard | `READY` | `scripts/setup.sh` | Interactive discovery & non-interactive modes verified |
| IAM Module | `READY` | `modules/iam/` | Role, Policy, Instance Profile & SSM Core attached |
| SSM Module | `READY` | `modules/ssm/` | Parameter resources managed directly in Terraform |
| LB Module | `READY` | `modules/lb/` | NLB, Target Group (health check `/healthCheck.php`) |
| Launch Template | `READY` | `modules/launch_template/` | Configured for AL2023 ARM64 & base64 user-data |
| Auto Scaling Group | `READY` | `modules/asg/` | Auto-healing ASG with rolling refresh enabled |
| Root Module | `READY` | `terraform/main.tf` | Composes all modules cleanly |
| User Data Script | `READY` | `user-data.sh` | IMDSv2, EIP re-association, Libreswan & Apache setup |
| Documentation | `READY` | Root Directory | Complete Markdown documentation suite |

---

## 2. Parameter Namespace Status

All SSM parameters are mapped under `/vpn-gateway/*`:
- `/vpn-gateway/bootstrap/helpers`
- `/vpn-gateway/bootstrap/vars`
- `/vpn-gateway/bootstrap/config`
- `/vpn-gateway/ipsec/ipsec.conf`
- `/vpn-gateway/ipsec/psk`
- `/vpn-gateway/ipsec/remote-gateway`
- `/vpn-gateway/ipsec/remote-hosts`
- `/vpn-gateway/httpd/vhost.conf`

---

## 3. Git Status

- **Tracking**: All source code, modules, setup scripts, example templates, and markdown files are tracked.
- **Gitignored**: Local generated files (`ssm/bootstrap-config.json`, `ssm/ipsec.conf`, `ssm/vhost.conf`, `ssm/psk`, `ssm/remote-gateway`, `ssm/remote-hosts`, `terraform/terraform.tfvars`, `*.local.md`).
