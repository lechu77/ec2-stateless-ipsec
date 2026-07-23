# CONTEXT.md — Technical Context & Dependencies

This document describes the environment context, system prerequisites, package dependencies, and operational constraints for `ec2-stateless-ipsec`.

---

## 1. Operating System & Base AMI

- **Operating System**: Amazon Linux 2023 (AL2023)
- **Architecture**: ARM64 (`aarch64`)
- **Default Instance Type**: `t4g.micro` (AWS Graviton2)
- **Package Manager**: `dnf`

---

## 2. Operating System Package Dependencies

Installed during `user-data.sh` execution:

| Package | Purpose |
|---------|---------|
| `git` | CodeCommit repository cloning (`webservice` and `plataforma`) |
| `httpd` | Apache 2.4 Web Server |
| `php` | PHP runtime for application endpoints |
| `php-fpm` | PHP FastCGI Process Manager |
| `libreswan` | IPsec IKEv2 daemon for VPN tunnels |
| `jq` | JSON parsing in shell scripts |
| `python3` | String escaping, IP validation, and template rendering helpers |
| `nmap-ncat` | Network port and connectivity testing |

---

## 3. AWS Prerequisites & IAM Permissions

### 3.1 Network Requirements
- An existing AWS VPC with at least one public subnet (multi-AZ subnets recommended).
- Internet Gateway (IGW) attached to the VPC.
- Two allocated public Elastic IP (EIP) Allocation IDs:
  - `PRIMARY_EIP_ALLOCATION_ID`: Associated to primary ENI private IP.
  - `SECONDARY_EIP_ALLOCATION_ID`: Associated to secondary ENI private IP (IPsec Encryption Domain).

### 3.2 IAM Instance Profile (`EC2-VPN-Gateway-Role`)
The IAM role attached to the EC2 instance must contain policies granting:
1. `ssm:GetParameter`, `ssm:GetParameters`, `ssm:GetParameterHistory`, `ssm:GetParametersByPath` on `arn:aws:ssm:*:*:parameter/vpn-gateway/*`.
2. `kms:Decrypt` for SecureString decryption.
3. `ec2:DescribeAddresses`, `ec2:DescribeNetworkInterfaces`, `ec2:AssignPrivateIpAddresses`, `ec2:AssociateAddress`.
4. `codecommit:GitPull`, `codecommit:BatchGet*`, `codecommit:Get*` on target CodeCommit repositories.
5. AWS Managed Policy: `AmazonSSMManagedInstanceCore` for AWS Session Manager console access.

---

## 4. Parameter Namespace Mapping

| Parameter Name | Type | Description |
|----------------|------|-------------|
| `/vpn-gateway/bootstrap/helpers` | SecureString | Shell helper functions sourced at boot |
| `/vpn-gateway/bootstrap/vars` | SecureString | Variable extraction script sourced at boot |
| `/vpn-gateway/bootstrap/config` | SecureString | JSON containing hostname, server name, EIP IDs, CodeCommit URLs |
| `/vpn-gateway/ipsec/ipsec.conf` | SecureString | Libreswan connection configuration template |
| `/vpn-gateway/ipsec/psk` | SecureString | IPsec Pre-Shared Key |
| `/vpn-gateway/ipsec/remote-gateway` | SecureString | IPsec Remote Peer Gateway IP |
| `/vpn-gateway/ipsec/remote-hosts` | SecureString | Comma-separated list of remote IPsec peer IPs |
| `/vpn-gateway/httpd/vhost.conf` | SecureString | Apache VirtualHost configuration template |
