# TASKS.md — Task Backlog & Roadmap

This document records completed milestones, active tasks, and future roadmap items for `ec2-stateless-ipsec`.

---

## Completed Milestones (v1.0.0)

- [x] Initial stateless EC2 user-data bootstrap script development.
- [x] Decouple variable extraction into SSM parameter `/vpn-gateway/bootstrap/vars`.
- [x] Extract remote gateway and remote hosts to separate SSM parameters.
- [x] Anonymize repository codebase (RFC 5737 IPs, generic domains).
- [x] Build interactive AWS discovery setup wizard (`scripts/setup.sh`).
- [x] Add authentication error handling with CloudShell / credentials entry guidance.
- [x] Evolve architecture from standalone EC2 to Launch Template + Auto Scaling Group (ASG).
- [x] Integrate optional Network Load Balancer (NLB) & Target Group (`modules/lb`).
- [x] Modularize Terraform into `modules/iam`, `modules/ssm`, `modules/lb`, `modules/launch_template`, `modules/asg`.
- [x] Document Remote State Management (`tfstate` in S3 + DynamoDB) in `README.md`.
- [x] Add comprehensive documentation suite (`AGENTS.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `CONTEXT.md`, `DECISIONS.md`, `MEMORY.md`, `RELEASE_NOTES.md`, `STATE.md`, `TASKS.md`).

---

## Future Roadmap & Backlog

### Phase 2: Observability & Security Enhancements
- [ ] Add CloudWatch Alarms for ASG health and IPsec tunnel status.
- [ ] Support AWS Secrets Manager as an alternative backend to SSM Parameter Store for PSK management.
- [ ] Implement automated GitHub Actions workflow for linting (`tflint`, `shellcheck`).

### Phase 3: CI/CD & Testing
- [ ] Add Terratest / integration test suite for automated plan validation.
- [ ] Provide Terraform S3 + DynamoDB remote backend bootstrap script (`scripts/init-backend.sh`).
