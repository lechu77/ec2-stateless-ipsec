# ec2-stateless-ipsec

Automated bootstrap for an Amazon Linux 2023 EC2 instance managed by an **Auto Scaling Group (ASG)** with a **Launch Template**, acting as an IPsec VPN gateway with an Apache web service backend behind a **Network Load Balancer (NLB)**.

The instance is fully **stateless**: terminating and relaunching it
(via Terraform or ASG Auto-Healing) is the standard replacement procedure.
No state is stored on disk — all configuration is pulled from
AWS SSM Parameter Store at boot.

> [!IMPORTANT]
> **Remote State Management (`tfstate`)**:
> For team collaboration and production deployments, storing `terraform.tfstate` locally or in Git is strongly discouraged. It is recommended to configure an AWS S3 Bucket with versioning enabled and a DynamoDB Table for state locking:
> ```hcl
> terraform {
>   backend "s3" {
>     bucket         = "my-company-terraform-states"
>     key            = "vpn-gateway/terraform.tfstate"
>     region         = "us-east-1"
>     dynamodb_table = "terraform-state-locks"
>     encrypt        = true
>   }
> }
> ```

---

## Architecture

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

### High Availability & Auto-Healing

- **Launch Template**: Manages instance specifications, AMI ID, IAM Instance Profile, and base64-encoded `user-data.sh`.
- **Auto Scaling Group**: Maintains instance availability (`min_size=1`, `max_size=1`, `desired_capacity=1`). If an instance or Availability Zone fails, the ASG automatically terminates the unhealthy instance and launches a replacement.
- **Stateless Re-attachment**: When a new instance launches, `user-data.sh` executes automatically, re-claims the designated Elastic IPs from SSM, re-establishes IPsec host routes, clones the CodeCommit repositories, and registers with the NLB Target Group.
- **Load Balancer Choice**: Set `create_load_balancer = true` to create a dedicated Network Load Balancer (NLB) and Target Group, or set `create_load_balancer = false` and supply `existing_target_group_arn` to attach the ASG to an existing load balancer.

---

## Repository Structure

```
ec2-stateless-ipsec/
├── user-data.sh                      # EC2 user-data bootstrap script
├── modules/                          # Decoupled reusable Terraform modules
│   ├── iam/                          # IAM Role, Policy, and Instance Profile
│   ├── ssm/                          # SSM Parameter Store resources
│   ├── lb/                           # Network Load Balancer (NLB), Target Group & Listener
│   ├── launch_template/              # Launch Template resource
│   └── asg/                          # Auto Scaling Group resource
├── ssm/
│   ├── bootstrap-helpers.sh          # Shell functions → /vpn-gateway/bootstrap/helpers
│   ├── bootstrap-vars.sh             # Variable extraction → /vpn-gateway/bootstrap/vars
│   ├── bootstrap-config.json.example # Template JSON config
│   ├── ipsec.conf.example            # Template Libreswan config
│   ├── psk.example                   # Template IPsec PSK secret
│   ├── remote-gateway.example        # Template remote gateway IP
│   ├── remote-hosts.example          # Template remote peer host IPs
│   └── vhost.conf.example            # Template Apache VirtualHost
├── scripts/
│   ├── setup.sh                      # Interactive wizard: generates ssm/* and terraform.tfvars
│   └── ssm-put-parameters.sh         # Helper to upload ssm/* files via AWS CLI
├── terraform/
│   ├── main.tf                       # Root module composing all modules
│   ├── variables.tf                  # Root input variables
│   ├── outputs.tf                    # Infrastructure outputs
│   └── terraform.tfvars.example      # Sample Terraform variables
└── README.md
```

---

## SSM Parameter Store

All parameters are stored as **SecureString** (KMS-encrypted).
The bootstrap script reads them at launch — nothing sensitive is baked
into the AMI or the user-data.

### Parameters managed in Terraform (`modules/ssm`)

| Parameter | Source file | Description |
|-----------|-------------|-------------|
| `/vpn-gateway/bootstrap/helpers` | `ssm/bootstrap-helpers.sh` | Shell helper functions |
| `/vpn-gateway/bootstrap/vars` | `ssm/bootstrap-vars.sh` | Variable extraction & validation |
| `/vpn-gateway/bootstrap/config` | `ssm/bootstrap-config.json` | Hostname, EIP allocation IDs, CodeCommit repo URLs |
| `/vpn-gateway/ipsec/ipsec.conf` | `ssm/ipsec.conf` | Libreswan connection template |
| `/vpn-gateway/ipsec/psk` | `ssm/psk` | IPsec pre-shared key |
| `/vpn-gateway/ipsec/remote-gateway` | `ssm/remote-gateway` | Remote IPsec gateway IP |
| `/vpn-gateway/ipsec/remote-hosts` | `ssm/remote-hosts` | Comma-separated list of remote IPsec hosts |
| `/vpn-gateway/httpd/vhost.conf` | `ssm/vhost.conf` | Apache VirtualHost template |

---

## Prerequisites

- AWS CLI v2 configured with appropriate credentials
- Terraform >= 1.5.0
- Existing VPC, public subnets, security group, and two Elastic IP Allocation IDs

---

## Deployment

### 1. Interactive Setup Wizard

Run the interactive setup wizard script. It prompts for your environment details, validates input, auto-generates a secure PSK if needed, and writes all required configuration files to `ssm/` and `terraform/terraform.tfvars`:

```bash
./scripts/setup.sh
```

Edit the generated files in `ssm/` with your actual environment details, IPs, and secrets. Real configuration files are gitignored to prevent leaking sensitive data.

### 2. Configure Terraform

Edit `terraform/terraform.tfvars` (created from `terraform.tfvars.example` by `setup.sh`):

* Set `vpc_id` and `subnet_ids` (or `subnet_id`).
* Choose Load Balancer configuration:
  * `create_load_balancer = true` (creates a new NLB & Target Group).
  * `create_load_balancer = false` and set `existing_target_group_arn = "arn:aws:elasticloadbalancing:..."` (attaches to an existing Target Group).

### 3. Deploy everything with Terraform

Terraform automatically provisions the SSM parameters, IAM Role/Policies, Launch Template, Target Group, NLB, and Auto Scaling Group in a single step:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 4. Instance Replacement / Refresh

Because the instance is stateless, trigger an ASG Instance Refresh or force replacement via Terraform:

```bash
cd terraform
terraform apply -replace=aws_launch_template.vpn
```

---

## Troubleshooting

### Check bootstrap log

```bash
cat /var/log/user-data.log
```

### IPsec tunnels not passing traffic

```bash
sudo ipsec status
sudo ipsec trafficstatus
ip -4 route show | grep 192.0.2
```

### Apache not running after bootstrap

Check that the VirtualHost config in SSM includes `env=!nlb_healthcheck`
on the `CustomLog` directive in a single line (not split with `\`).
