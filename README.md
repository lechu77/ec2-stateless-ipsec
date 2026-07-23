# ec2-stateless-ipsec

Automated bootstrap for an Amazon Linux 2023 EC2 instance acting as an
IPsec VPN gateway with an Apache web service backend.

The instance is fully **stateless**: terminating and relaunching it
(via Terraform or the console) is the standard replacement procedure.
No state is stored on disk — all configuration is pulled from
AWS SSM Parameter Store at boot.

---

## Architecture

```
                        ┌─────────────────────────────────┐
                        │         EC2 Instance             │
                        │  t4g.micro / Amazon Linux 2023  │
                        │                                  │
Internet ───────────────│  EIP 203.0.113.10  (primary)     │
                        │  EIP 198.51.100.20 (enc-domain)  │
                        │                                  │
Remote IPsec peers ─────│  Libreswan (IKEv2/PSK)          │
192.0.2.0/24            │  src: 198.51.100.20              │
                        │                                  │
NLB ────────────────────│  Apache + PHP-FPM               │
                        │  CodeCommit repos cloned at boot │
                        └─────────────────────────────────┘
                                      │
                               SSM Parameter Store
                               /vpn-gateway/bootstrap/*
                               /vpn-gateway/ipsec/*
                               /vpn-gateway/httpd/*
```

### Networking

The instance uses two Elastic IPs on a single ENI:

| EIP | Role |
|-----|------|
| `203.0.113.10` | Primary — SSH, NLB health checks, IKE identity |
| `198.51.100.20` | IPsec encryption domain — tunnel source/dest |

A secondary private IP is assigned to the ENI at boot and the secondary
EIP is associated to it. Host routes toward each remote IPsec peer are
set with `src 198.51.100.20` so that tunnel traffic always originates
from the encryption domain address.

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
│   └── ssm-put-parameters.sh         # Uploads local ssm/* files to AWS SSM Parameter Store
├── terraform/
│   ├── main.tf                       # EC2 Instance resource
│   ├── iam.tf                        # IAM Role, Policy, and Instance Profile
│   ├── variables.tf                  # Input variables
│   ├── outputs.tf                    # Infrastructure outputs
│   └── terraform.tfvars.example      # Sample Terraform variables
└── README.md
```

---

## SSM Parameter Store

All parameters are stored as **SecureString** (KMS-encrypted).
The bootstrap script reads them at launch — nothing sensitive is baked
into the AMI or the user-data.

### Parameters managed in this repo

Uploaded via `scripts/ssm-put-parameters.sh`:

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

### `/vpn-gateway/bootstrap/config` schema

```json
{
  "hostname": "VPN-Gateway-Instance",
  "httpd_server_name": "ws.example.com",
  "primary_eip_allocation_id": "eipalloc-xxxxxxxxxxxxxxxxx",
  "secondary_eip_allocation_id": "eipalloc-xxxxxxxxxxxxxxxxx",
  "repositories": [
    {
      "url": "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/webservice",
      "directory": "/var/www/webservice"
    },
    {
      "url": "https://git-codecommit.us-east-1.amazonaws.com/v1/repos/plataforma",
      "directory": "/var/www/plataforma"
    }
  ]
}
```

---

## Prerequisites

- AWS CLI v2 configured with appropriate credentials
- Terraform >= 1.5.0
- Existing VPC, subnet, security group, and two Elastic IP Allocation IDs
- SSM parameters populated (see below)

---

## Deployment

### 1. Initialize local configuration files

Run the setup script to generate local configuration files from anonymized `.example` templates:

```bash
./scripts/setup.sh
```

Then edit the generated files in `ssm/` with your actual environment details, IPs, and secrets. Real configuration files are gitignored to prevent leaking sensitive data.

### 2. Upload SSM parameters

```bash
./scripts/ssm-put-parameters.sh --region us-east-1 [--profile myprofile]
```

### 3. Configure Terraform

Edit `terraform/terraform.tfvars` (created from `terraform.tfvars.example` by `setup.sh`) with your AWS subnet ID, AMI ID, security group, and key pair.

### 4. Deploy

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### 5. Replace the instance

Because the instance is stateless, the standard way to apply changes
(new user-data, new AMI, config update) is to destroy and recreate:

```bash
cd terraform
terraform apply   # user_data_replace_on_change = true handles this automatically
```

Or force a replacement:

```bash
terraform apply -replace=aws_instance.vpn
```

---

## Bootstrap flow

When the instance starts, `user-data.sh` executes the following steps:

1. Set up logging to `/var/log/user-data.log` and `/dev/console`
2. Retrieve IMDS token and collect instance metadata (instance ID, ENI, IPs)
3. Pull `get_secure_parameter` inline functions (required before SSM access)
4. **Source** `/vpn-gateway/bootstrap/helpers` from SSM → loads shell helper functions
5. Install packages: `git`, `httpd`, `php-fpm`, `libreswan`, `jq`, `python3`, `nmap-ncat`
6. Validate IAM role availability
7. Retrieve and validate `/vpn-gateway/bootstrap/config` (JSON)
8. **Source** `/vpn-gateway/bootstrap/vars` from SSM → extracts and validates variables
9. Resolve EIP public IPs, assign secondary private IP to ENI
10. Associate both EIPs to the ENI
11. **Wait** for `systemd-networkd` to finish reconfiguring after EIP association
12. Configure host routes: each remote IPsec peer routed via `src 198.51.100.20`
13. Validate networking
14. Set system hostname
15. Retrieve Libreswan config template from SSM, render with runtime values, start `ipsec`
16. Configure Apache user, clone CodeCommit repositories
17. Retrieve Apache VirtualHost template from SSM, render with runtime values
18. Patch global `httpd.conf` to exclude NLB health checks from access logs
19. Start `php-fpm` and `httpd`
20. Validate NLB health-check endpoint (`/healthCheck.php`)
21. Log final state summary

---

## Troubleshooting

### Check bootstrap log

```bash
cat /var/log/user-data.log
```

### user-data did not execute at all

- **Do not paste** user-data in the AWS console — the browser may silently
  truncate or corrupt content near the 16 KB limit.
- Always use **File upload** in the console, or pass `--user-data file://user-data.sh`
  with the AWS CLI / Terraform.

### IPsec tunnels not passing traffic

```bash
sudo ipsec status
sudo ipsec trafficstatus
ip -4 route show | grep 192.0.2
```

If routes toward remote peers are missing, `systemd-networkd` reconfigured
the interface after the bootstrap set them. This is prevented by waiting for networkd to stabilize after EIP association, but if you observe it on a running instance:

```bash
sudo ip route replace 192.0.2.X/32 via <gateway> dev ens5 src 198.51.100.20
```

### Apache not running after bootstrap

Check that the VirtualHost config in SSM includes `env=!nlb_healthcheck`
on the `CustomLog` directive in a single line (not split with `\`).
