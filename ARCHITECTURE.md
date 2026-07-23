# ARCHITECTURE.md — System Architecture & Design Specification

This document details the architectural design, networking topology, bootstrap sequence, and component interactions of the `ec2-stateless-ipsec` solution.

---

## 1. High-Level Architecture Diagram

```
                       ┌─────────────────────────────────────────┐
                       │       Network Load Balancer (NLB)       │
                       │              Port 80 / TCP              │
                       └────────────────────┬────────────────────┘
                                            │
                                            ▼
                       ┌─────────────────────────────────────────┐
                       │        Auto Scaling Group (ASG)         │
                       │               Capacity: 1               │
                       └────────────────────┬────────────────────┘
                                            │
                                            ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                              EC2 Instance (Launch Template)                            │
│                              t4g.micro | Amazon Linux 2023                             │
│                                                                                        │
│   ┌───────────────────────────┐   ┌───────────────────────────┐   ┌────────────────┐   │
│   │     Primary Elastic IP    │   │   Encryption Domain EIP   │   │ Apache Backend │   │
│   │        203.0.113.10       │   │       198.51.100.20       │   │  + PHP-FPM     │   │
│   └─────────────┬─────────────┘   └─────────────┬─────────────┘   └───────▲────────┘   │
│                 │                               │                         │            │
└─────────────────┼───────────────────────────────┼─────────────────────────┼────────────┘
                  │                               │                         │
                  ▼                               ▼                         │
          ┌───────────────┐             ┌──────────────────┐        ┌───────┴────────┐
          │  SSH / Admin  │             │   Remote IPsec   │        │  Target Group  │
          │    Access     │             │  192.0.2.0/24    │        │  Health Check  │
          └───────────────┘             └──────────────────┘        └────────────────┘
                                                  ▲
                                                  │
                               ┌──────────────────┴──────────────┐
                               │       SSM Parameter Store       │
                               │    /vpn-gateway/bootstrap/*     │
                               │    /vpn-gateway/ipsec/*         │
                               │    /vpn-gateway/httpd/*         │
                               └─────────────────────────────────┘
```

---

## 2. Core Architectural Components

### 2.1 Auto Scaling Group & Launch Template
- **Launch Template (`modules/launch_template`)**: Defines the ARM64 AMI (`al2023`), `t4g.micro` instance type, root volume (`gp3`, 8GB), IAM instance profile, and base64-encoded `user-data.sh`.
- **Auto Scaling Group (`modules/asg`)**: Manages lifecycle (`desired_capacity=1`, `min_size=1`, `max_size=1`). Provides **Auto-Healing**: if the instance fails a health check or its Availability Zone experiences an outage, the ASG terminates the instance and launches a replacement across configured subnets.

### 2.2 Network Load Balancer (NLB) & Health Check
- **Load Balancer (`modules/lb`)**: Optional Network Load Balancer (NLB) operating at Layer 4 (TCP). Forwarding port 80 to an EC2 Target Group.
- **Health Check**: Configured on `/healthCheck.php`. `user-data.sh` sets up Apache `SetEnvIf Request_URI "^/healthCheck\.php$" nlb_healthcheck` to exclude NLB health checks from access logs.

### 2.3 Dual Elastic IP (EIP) Stateless Networking
The EC2 instance attaches two public Elastic IPs to a single Elastic Network Interface (ENI):
1. **Primary EIP (`203.0.113.10`)**: Used for SSH access, NLB Target Group registration, and IKE identity.
2. **Secondary EIP (`198.51.100.20`)**: Serves as the **IPsec Encryption Domain** source and destination address.

During boot, `user-data.sh`:
- Assigns a secondary private IP to the ENI via `aws ec2 assign-private-ip-addresses`.
- Associates both Elastic IPs (`PRIMARY_EIP_ALLOCATION_ID` and `SECONDARY_EIP_ALLOCATION_ID`) to the ENI.
- Sets host routes toward remote IPsec peers with explicit source binding (`ip route replace 192.0.2.X/32 via <default_gw> dev ens5 src 198.51.100.20`).

---

## 3. Bootstrap Execution Sequence

1. **IMDSv2 Token & Metadata Discovery**: Fetches instance ID, MAC address, ENI ID, and local IPv4.
2. **Inline SSM Function Loading**: Defines `get_secure_parameter` before loading external scripts.
3. **SSM Helper Sourcing**: Fetches and sources `/vpn-gateway/bootstrap/helpers` (retry loops, IPv4 validation, template rendering).
4. **Package Installation**: Installs `git`, `httpd`, `php-fpm`, `libreswan`, `jq`, `python3`, `nmap-ncat`.
5. **JSON Configuration Sourcing**: Fetches and validates `/vpn-gateway/bootstrap/config` (JSON).
6. **SSM Vars Sourcing**: Sources `/vpn-gateway/bootstrap/vars` which fetches `/vpn-gateway/ipsec/remote-gateway` and `/vpn-gateway/ipsec/remote-hosts`.
7. **EIP Resolution & Networking**: Resolves EIP allocation IDs, assigns secondary private IP, associates EIPs, waits for `systemd-networkd` stabilization, and configures host routes.
8. **IPsec Service Configuration**: Fetches `/vpn-gateway/ipsec/ipsec.conf` and `/vpn-gateway/ipsec/psk`, renders template placeholders, and restarts `ipsec` (Libreswan).
9. **CodeCommit Repository Cloning**: Configures `aws codecommit credential-helper` for user `apache` and clones `webservice` and `plataforma` repositories.
10. **Apache VirtualHost Configuration**: Fetches `/vpn-gateway/httpd/vhost.conf`, renders placeholders, patches global `httpd.conf` for NLB log exclusion, and restarts `php-fpm` and `httpd`.
11. **Endpoint Validation**: Performs local health check via `curl -H "Host: ${HTTPD_SERVER_NAME}" http://127.0.0.1/healthCheck.php`.

---

## 4. Terraform Module Topology

```
terraform/ (Root Module)
  ├── module "iam"               --> modules/iam
  ├── module "ssm"               --> modules/ssm
  ├── module "lb"                --> modules/lb (conditional: create_load_balancer)
  ├── module "launch_template"   --> modules/launch_template (depends_on: module.ssm)
  └── module "asg"               --> modules/asg
```
