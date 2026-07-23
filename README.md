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
                               ┌───────────────────────────────────┐
                               │     Network Load Balancer (NLB)   │
                               │           Port 80 / TCP           │
                               └─────────────────┬─────────────────┘
                                                 │
                               ┌─────────────────▼─────────────────┐
                               │    Auto Scaling Group (ASG)       │
                               │       (Desired Capacity: 1)       │
                               └─────────────────┬─────────────────┘
                                                 │
                        ┌────────────────────────▼────────┐
                        │      Launch Template Instance    │
                        │  t4g.micro / Amazon Linux 2023  │
                        │                                  │
Internet ───────────────│  EIP 203.0.113.10  (primary)     │
                        │  EIP 198.51.100.20 (enc-domain)  │
                        │                                  │
Remote IPsec peers ─────│  Libreswan (IKEv2/PSK)          │
192.0.2.0/24            │  src: 198.51.100.20              │
                        │                                  │
Target Group ───────────│  Apache + PHP-FPM               │
/healthCheck.php        │  CodeCommit repos cloned at boot │
                        └─────────────────────────────────┘
                                      │
                               SSM Parameter Store
                               /vpn-gateway/bootstrap/*
                               /vpn-gateway/ipsec/*
                               /vpn-gateway/httpd/*
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
│   ├── setup.sh                      # Copies .example templates to gitignored config files
│   └── ssm-put-parameters.sh         # Helper to upload ssm/* files via AWS CLI
├── terraform/
│   ├── main.tf                       # Launch Template & Auto Scaling Group
│   ├── lb.tf                         # Network Load Balancer, Target Group & Listener
│   ├── ssm.tf                        # SSM Parameter Store resources
│   ├── iam.tf                        # IAM Role, Policy, and Instance Profile
│   ├── variables.tf                  # Input variables (VPC, subnets, ASG, ELB options)
│   ├── outputs.tf                    # Infrastructure outputs (NLB DNS, ASG ID, etc.)
│   └── terraform.tfvars.example      # Sample Terraform variables
└── README.md
```

---

## SSM Parameter Store

All parameters are stored as **SecureString** (KMS-encrypted).
The bootstrap script reads them at launch — nothing sensitive is baked
into the AMI or the user-data.

### Parameters managed in Terraform (`terraform/ssm.tf`)

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

### 1. Initialize local configuration files

Run the setup script to generate local configuration files from anonymized `.example` templates:

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
