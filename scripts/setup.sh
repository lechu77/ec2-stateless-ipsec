#!/bin/bash
# setup.sh — Smart Interactive Setup Wizard for AWS Discovery & Configuration
# Discovers AWS resources (VPCs, Subnets, SGs, Key Pairs, EIPs, Target Groups)
# and generates ssm/* and terraform/terraform.tfvars with zero syntax errors.
# Fully compatible with macOS (Bash 3.2+), Linux, and AWS CloudShell.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SSM_DIR="${REPO_ROOT}/ssm"
TERRAFORM_DIR="${REPO_ROOT}/terraform"

# ANSI Colors
BOLD="\033[1m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

NON_INTERACTIVE=false
if [[ "${1:-}" == "--non-interactive" || "${NON_INTERACTIVE:-false}" == "true" ]]; then
    NON_INTERACTIVE=true
fi

echo -e "${BOLD}${BLUE}==========================================================${RESET}"
echo -e "${BOLD}${BLUE}    AWS EC2 Stateless IPsec VPN Gateway Setup Wizard      ${RESET}"
echo -e "${BOLD}${BLUE}==========================================================${RESET}"
echo ""

# ---------------------------------------------------------------------------
# 1. AWS Authentication & Credentials Check
# ---------------------------------------------------------------------------

check_aws_auth() {
    echo -e "${BOLD}Checking AWS credentials...${RESET}"
    if CALLER_IDENTITY="$(aws sts get-caller-identity --output json 2>/dev/null)"; then
        ACCOUNT_ID="$(jq -r '.Account' <<< "$CALLER_IDENTITY")"
        ARN="$(jq -r '.Arn' <<< "$CALLER_IDENTITY")"
        echo -e "${GREEN}✔ Authenticated as:${RESET} ${ARN} (Account: ${ACCOUNT_ID})"
        return 0
    else
        echo -e "${RED}[ERROR] Unable to authenticate with AWS.${RESET}"
        echo -e "${YELLOW}Reason:${RESET} No valid AWS credentials found or missing permissions for sts:GetCallerIdentity."
        echo ""
        echo "Options to resolve authentication:"
        echo "  1) Enter temporary AWS Access Key & Secret Key for this setup session"
        echo "  2) Run 'aws configure' in a separate terminal and restart setup"
        echo "  3) Run this setup script inside AWS CloudShell (recommended)"
        echo ""

        if [[ "$NON_INTERACTIVE" == "true" ]]; then
            echo -e "${RED}Exiting: Cannot proceed in --non-interactive mode without active AWS credentials.${RESET}"
            exit 1
        fi

        read -rp "Would you like to enter AWS Access Key & Secret Key now? (y/N): " auth_choice
        if [[ "$auth_choice" =~ ^[Yy]$ ]]; then
            read -rp "AWS Access Key ID: " input_ak
            read -rsp "AWS Secret Access Key: " input_sk
            echo ""
            read -rp "AWS Session Token (optional, press Enter to skip): " input_st

            export AWS_ACCESS_KEY_ID="$input_ak"
            export AWS_SECRET_ACCESS_KEY="$input_sk"
            if [[ -n "$input_st" ]]; then
                export AWS_SESSION_TOKEN="$input_st"
            fi

            if CALLER_IDENTITY="$(aws sts get-caller-identity --output json 2>/dev/null)"; then
                ACCOUNT_ID="$(jq -r '.Account' <<< "$CALLER_IDENTITY")"
                ARN="$(jq -r '.Arn' <<< "$CALLER_IDENTITY")"
                echo -e "${GREEN}✔ Authenticated as:${RESET} ${ARN} (Account: ${ACCOUNT_ID})"
            else
                echo -e "${RED}Authentication failed with provided credentials. Please check permissions.${RESET}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Please configure credentials or launch AWS CloudShell, then rerun ./scripts/setup.sh${RESET}"
            exit 1
        fi
    fi
}

check_aws_auth

# ---------------------------------------------------------------------------
# 2. Region & Dynamic Resource Discovery
# ---------------------------------------------------------------------------

# Resolve Region
DEFAULT_REGION="$(aws configure get region 2>/dev/null || echo "${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}")"
if [[ "$NON_INTERACTIVE" == "true" ]]; then
    AWS_REGION="${AWS_REGION:-$DEFAULT_REGION}"
else
    read -rp "AWS Region [default: ${DEFAULT_REGION}]: " input_region
    AWS_REGION="${input_region:-$DEFAULT_REGION}"
fi
export AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
echo -e "${GREEN}✔ AWS Region set to:${RESET} ${AWS_REGION}"
echo ""

# Generic prompt function
prompt_text() {
    local var_name="$1"
    local prompt_label="$2"
    local default_val="$3"
    local val=""

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        val="${!var_name:-$default_val}"
    else
        read -rp "${prompt_label} [default: ${default_val}]: " input_val
        val="${input_val:-$default_val}"
    fi

    printf -v "$var_name" "%s" "$val"
}

# Select item from array options
select_menu() {
    local prompt_label="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}

    if (( num_options == 0 )); then
        return 1
    fi

    echo -e "${BOLD}${prompt_label}:${RESET}"
    local i
    for i in "${!options[@]}"; do
        printf "  %2d) %s\n" "$((i+1))" "${options[$i]}"
    done

    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        SELECTED_CHOICE="${options[0]}"
        return 0
    fi

    while true; do
        read -rp "Select an option (1-${num_options}) or press Enter for option 1: " choice
        choice="${choice:-1}"
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= num_options )); then
            SELECTED_CHOICE="${options[$((choice-1))]}"
            return 0
        else
            echo -e "${RED}Invalid selection. Try again.${RESET}"
        fi
    done
}

# ---------------------------------------------------------------------------
# 3. Dynamic VPC Discovery
# ---------------------------------------------------------------------------

echo -e "${BOLD}Discovering VPCs in ${AWS_REGION}...${RESET}"
VPC_LIST=()
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    vpc_id="$(awk '{print $1}' <<< "$line")"
    cidr="$(awk '{print $2}' <<< "$line")"
    name="$(awk '{print $3}' <<< "$line")"
    if [[ -n "$name" && "$name" != "None" ]]; then
        VPC_LIST+=("${vpc_id} (${cidr} - ${name})")
    else
        VPC_LIST+=("${vpc_id} (${cidr})")
    fi
done < <(aws ec2 describe-vpcs --region "$AWS_REGION" --query "Vpcs[*].[VpcId,CidrBlock,Tags[?Key=='Name'].Value | [0]]" --output text 2>/dev/null || true)

if (( ${#VPC_LIST[@]} > 0 )); then
    select_menu "Select VPC" "${VPC_LIST[@]}"
    VPC_ID="$(awk '{print $1}' <<< "$SELECTED_CHOICE")"
else
    echo -e "${YELLOW}No VPCs auto-discovered or permission denied.${RESET}"
    prompt_text VPC_ID "Enter VPC ID (e.g. vpc-0123456789abcdef0)" "vpc-0123456789abcdef0"
fi
echo -e "${GREEN}✔ Selected VPC:${RESET} ${VPC_ID}"
echo ""

# ---------------------------------------------------------------------------
# 4. Dynamic Subnet Discovery
# ---------------------------------------------------------------------------

echo -e "${BOLD}Discovering Subnets in VPC ${VPC_ID}...${RESET}"
SUBNET_LIST=()
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    sub_id="$(awk '{print $1}' <<< "$line")"
    az="$(awk '{print $2}' <<< "$line")"
    cidr="$(awk '{print $3}' <<< "$line")"
    name="$(awk '{print $4}' <<< "$line")"
    if [[ -n "$name" && "$name" != "None" ]]; then
        SUBNET_LIST+=("${sub_id} (${az} | ${cidr} | ${name})")
    else
        SUBNET_LIST+=("${sub_id} (${az} | ${cidr})")
    fi
done < <(aws ec2 describe-subnets --region "$AWS_REGION" --filters "Name=vpc-id,Values=${VPC_ID}" --query "Subnets[*].[SubnetId,AvailabilityZone,CidrBlock,Tags[?Key=='Name'].Value | [0]]" --output text 2>/dev/null || true)

if (( ${#SUBNET_LIST[@]} > 0 )); then
    select_menu "Select Primary Subnet" "${SUBNET_LIST[@]}"
    PRIMARY_SUBNET_ID="$(awk '{print $1}' <<< "$SELECTED_CHOICE")"

    if (( ${#SUBNET_LIST[@]} > 1 )); then
        select_menu "Select Secondary Subnet for Multi-AZ" "${SUBNET_LIST[@]}"
        SECONDARY_SUBNET_ID="$(awk '{print $1}' <<< "$SELECTED_CHOICE")"
    else
        SECONDARY_SUBNET_ID="$PRIMARY_SUBNET_ID"
    fi
else
    echo -e "${YELLOW}No subnets auto-discovered for VPC ${VPC_ID}.${RESET}"
    prompt_text PRIMARY_SUBNET_ID "Enter Primary Subnet ID" "subnet-0123456789abcdef0"
    prompt_text SECONDARY_SUBNET_ID "Enter Secondary Subnet ID" "subnet-0fedcba9876543210"
fi

echo -e "${GREEN}✔ Primary Subnet:${RESET} ${PRIMARY_SUBNET_ID}"
echo -e "${GREEN}✔ Secondary Subnet:${RESET} ${SECONDARY_SUBNET_ID}"
echo ""

# ---------------------------------------------------------------------------
# 5. Dynamic Security Group & Key Pair Discovery
# ---------------------------------------------------------------------------

echo -e "${BOLD}Discovering Security Groups & Key Pairs...${RESET}"
SG_LIST=()
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    sg_id="$(awk '{print $1}' <<< "$line")"
    sg_name="$(awk '{print $2}' <<< "$line")"
    SG_LIST+=("${sg_id} (${sg_name})")
done < <(aws ec2 describe-security-groups --region "$AWS_REGION" --filters "Name=vpc-id,Values=${VPC_ID}" --query "SecurityGroups[*].[GroupId,GroupName]" --output text 2>/dev/null || true)

if (( ${#SG_LIST[@]} > 0 )); then
    select_menu "Select Security Group" "${SG_LIST[@]}"
    SECURITY_GROUP_ID="$(awk '{print $1}' <<< "$SELECTED_CHOICE")"
else
    prompt_text SECURITY_GROUP_ID "Enter Security Group ID" "sg-0123456789abcdef0"
fi

KEY_LIST=()
while IFS= read -r key_item; do
    [[ -n "$key_item" ]] && KEY_LIST+=("$key_item")
done < <(aws ec2 describe-key-pairs --region "$AWS_REGION" --query "KeyPairs[*].KeyName" --output text 2>/dev/null || true)

if (( ${#KEY_LIST[@]} > 0 )); then
    select_menu "Select Key Pair" "${KEY_LIST[@]}"
    KEY_NAME="$SELECTED_CHOICE"
else
    prompt_text KEY_NAME "Enter Key Pair Name" "my-key-pair"
fi

prompt_text AMI_ID "Amazon Linux 2023 ARM64 AMI ID" "ami-0123456789abcdef0"

# ---------------------------------------------------------------------------
# 6. Instance & Web Service Configuration
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}--- Web Service & Instance Names ---${RESET}"
prompt_text SYSTEM_HOSTNAME "System Hostname" "VPN-Gateway-Instance"
prompt_text HTTPD_SERVER_NAME "Apache ServerName (Domain)" "ws.example.com"
prompt_text REPO_WEBSERVICE_URL "CodeCommit Repository URL for webservice" "https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/webservice"
prompt_text REPO_PLATAFORMA_URL "CodeCommit Repository URL for plataforma" "https://git-codecommit.${AWS_REGION}.amazonaws.com/v1/repos/plataforma"

# ---------------------------------------------------------------------------
# 7. Elastic IPs & Remote IPsec Peers
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}Discovering Elastic IPs (EIPs)...${RESET}"
EIP_LIST=()
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    alloc_id="$(awk '{print $1}' <<< "$line")"
    pub_ip="$(awk '{print $2}' <<< "$line")"
    tag_name="$(awk '{print $3}' <<< "$line")"
    if [[ -n "$tag_name" && "$tag_name" != "None" ]]; then
        EIP_LIST+=("${alloc_id} (${pub_ip} - ${tag_name})")
    else
        EIP_LIST+=("${alloc_id} (${pub_ip})")
    fi
done < <(aws ec2 describe-addresses --region "$AWS_REGION" --query "Addresses[*].[AllocationId,PublicIp,Tags[?Key=='Name'].Value | [0]]" --output text 2>/dev/null || true)

if (( ${#EIP_LIST[@]} >= 2 )); then
    select_menu "Select Primary Elastic IP (SSH/NLB)" "${EIP_LIST[@]}"
    PRIMARY_EIP_ALLOC="$(awk '{print $1}' <<< "$SELECTED_CHOICE")"

    select_menu "Select Secondary Elastic IP (Encryption Domain)" "${EIP_LIST[@]}"
    SECONDARY_EIP_ALLOC="$(awk '{print $1}' <<< "$SELECTED_CHOICE")"
else
    prompt_text PRIMARY_EIP_ALLOC "Primary EIP Allocation ID" "eipalloc-0123456789abcdef0"
    prompt_text SECONDARY_EIP_ALLOC "Secondary EIP Allocation ID" "eipalloc-0fedcba9876543210"
fi

prompt_text REMOTE_GATEWAY_IP "Remote IPsec Gateway IP" "192.0.2.253"
prompt_text REMOTE_HOSTS_IPS "Remote IPsec Host IPs (comma-separated)" "192.0.2.10,192.0.2.11,192.0.2.12"

DEFAULT_PSK="$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom | head -c 32 || echo "SecureIPsecPSK123!@#AutoGenerated")"
prompt_text IPSEC_PSK "IPsec Pre-Shared Key (PSK)" "$DEFAULT_PSK"

# ---------------------------------------------------------------------------
# 8. Load Balancer / Target Group Choice & Discovery
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}--- Load Balancer Integration ---${RESET}"
prompt_text CREATE_NLB "Create new Network Load Balancer (true/false)" "true"

EXISTING_TG_ARN=""
if [[ "$CREATE_NLB" == "false" ]]; then
    echo -e "${BOLD}Discovering Existing Target Groups in ${AWS_REGION}...${RESET}"
    TG_LIST=()
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        tg_arn="$(awk '{print $1}' <<< "$line")"
        tg_name="$(awk '{print $2}' <<< "$line")"
        tg_proto="$(awk '{print $3}' <<< "$line")"
        tg_port="$(awk '{print $4}' <<< "$line")"
        TG_LIST+=("${tg_arn} (${tg_name} - ${tg_proto}:${tg_port})")
    done < <(aws elbv2 describe-target-groups --region "$AWS_REGION" --query "TargetGroups[*].[TargetGroupArn,TargetGroupName,Protocol,Port]" --output text 2>/dev/null || true)

    if (( ${#TG_LIST[@]} > 0 )); then
        select_menu "Select Existing Target Group" "${TG_LIST[@]}"
        EXISTING_TG_ARN="$(awk '{print $1}' <<< "$SELECTED_CHOICE")"
    else
        prompt_text EXISTING_TG_ARN "Enter Existing Target Group ARN" ""
    fi
fi

# ---------------------------------------------------------------------------
# 9. Generating All Configuration Files
# ---------------------------------------------------------------------------

echo ""
echo -e "${BOLD}${BLUE}==========================================================${RESET}"
echo -e "${BOLD}${BLUE} Generating Configuration Files...                         ${RESET}"
echo -e "${BOLD}${BLUE}==========================================================${RESET}"

mkdir -p "$SSM_DIR" "$TERRAFORM_DIR"

# ssm/bootstrap-config.json
cat > "${SSM_DIR}/bootstrap-config.json" <<EOF
{
  "hostname": "${SYSTEM_HOSTNAME}",
  "httpd_server_name": "${HTTPD_SERVER_NAME}",
  "primary_eip_allocation_id": "${PRIMARY_EIP_ALLOC}",
  "secondary_eip_allocation_id": "${SECONDARY_EIP_ALLOC}",
  "repositories": [
    {
      "url": "${REPO_WEBSERVICE_URL}",
      "directory": "/var/www/webservice"
    },
    {
      "url": "${REPO_PLATAFORMA_URL}",
      "directory": "/var/www/plataforma"
    }
  ]
}
EOF
echo -e "${GREEN}✔ Generated ssm/bootstrap-config.json${RESET}"

# ssm/ipsec.conf
cat > "${SSM_DIR}/ipsec.conf" <<'EOF'
conn vpn-connection
    type=tunnel
    ikev2=insist
    authby=secret

    left=%defaultroute
    leftid=${PRIMARY_PUBLIC_IP}
    leftsubnet=${LOCAL_ENCRYPTION_DOMAIN}/32
    leftsourceip=${LOCAL_ENCRYPTION_DOMAIN}

    right=${REMOTE_GATEWAY}
    rightid=${REMOTE_GATEWAY}
    rightsubnets=${REMOTE_SUBNETS}

    ike=aes256-sha2_256;modp2048
    esp=aes256-sha2_256
    pfs=no

    ikelifetime=28800s
    salifetime=3600s
    rekeymargin=300s
    rekeyfuzz=0%
    keyingtries=%forever

    dpddelay=30s
    dpdaction=restart

    auto=start
EOF
echo -e "${GREEN}✔ Generated ssm/ipsec.conf${RESET}"

# ssm/vhost.conf
cat > "${SSM_DIR}/vhost.conf" <<'EOF'
<VirtualHost *:80>
    ServerName ${HTTPD_SERVER_NAME}

    ServerAlias ${PRIMARY_PUBLIC_IP} ${SECONDARY_PUBLIC_IP} ${PRIMARY_PRIVATE_IP} ${SECONDARY_PRIVATE_IP}

    DocumentRoot /var/www/webservice/ws
    ServerAdmin admin@${HTTPD_SERVER_NAME}

    ErrorLog /var/log/httpd/${HTTPD_SERVER_NAME}_error_log

    SetEnvIf Request_URI "^/healthCheck\.php$" nlb_healthcheck

    CustomLog /var/log/httpd/${HTTPD_SERVER_NAME}_access_log combined env=!nlb_healthcheck

    <Directory "/var/www/webservice/ws">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
echo -e "${GREEN}✔ Generated ssm/vhost.conf${RESET}"

# ssm/psk
printf '%s' "$IPSEC_PSK" > "${SSM_DIR}/psk"
echo -e "${GREEN}✔ Generated ssm/psk${RESET}"

# ssm/remote-gateway
printf '%s' "$REMOTE_GATEWAY_IP" > "${SSM_DIR}/remote-gateway"
echo -e "${GREEN}✔ Generated ssm/remote-gateway${RESET}"

# ssm/remote-hosts
printf '%s' "$REMOTE_HOSTS_IPS" > "${SSM_DIR}/remote-hosts"
echo -e "${GREEN}✔ Generated ssm/remote-hosts${RESET}"

# terraform/terraform.tfvars
cat > "${TERRAFORM_DIR}/terraform.tfvars" <<EOF
# Generated automatically by setup.sh wizard
region = "${AWS_REGION}"
ami_id = "${AMI_ID}"

instance_type     = "t4g.micro"
vpc_id            = "${VPC_ID}"
subnet_id         = "${PRIMARY_SUBNET_ID}"
subnet_ids        = ["${PRIMARY_SUBNET_ID}", "${SECONDARY_SUBNET_ID}"]
security_group_id = "${SECURITY_GROUP_ID}"
key_name          = "${KEY_NAME}"

iam_instance_profile = "EC2-VPN-Gateway-Role"
instance_name        = "${SYSTEM_HOSTNAME}"

asg_min_size         = 1
asg_max_size         = 1
asg_desired_capacity = 1

create_load_balancer      = ${CREATE_NLB}
existing_target_group_arn = "${EXISTING_TG_ARN}"

tags = {
  Project     = "vpn-gateway"
  Environment = "production"
}
EOF
echo -e "${GREEN}✔ Generated terraform/terraform.tfvars${RESET}"

echo ""
echo -e "${BOLD}${BLUE}==========================================================${RESET}"
echo -e "${BOLD}${GREEN} Setup completed successfully!                            ${RESET}"
echo -e "${BOLD} Next step: Deploy everything with Terraform               ${RESET}"
echo -e "   ${BOLD}cd terraform && terraform init && terraform apply${RESET}"
echo -e "${BOLD}${BLUE}==========================================================${RESET}"
