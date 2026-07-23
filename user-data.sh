#!/bin/bash
set -Eeuo pipefail

# Logging
exec > >(
    tee -a /var/log/user-data.log |
    logger -t user-data -s 2>/dev/console
) 2>&1

trap '
    rc=$?
    echo "ERROR: user-data failed at line ${LINENO}, exit code ${rc}"
    exit "${rc}"
' ERR

# Static bootstrap configuration
REGION="us-east-1"

SSM_BOOTSTRAP_CONFIG="/vpn-gateway/bootstrap/config"
SSM_BOOTSTRAP_HELPERS="/vpn-gateway/bootstrap/helpers"
SSM_BOOTSTRAP_VARS="/vpn-gateway/bootstrap/vars"
SSM_IPSEC_CONFIG="/vpn-gateway/ipsec/ipsec.conf"
SSM_IPSEC_PSK="/vpn-gateway/ipsec/psk"
SSM_HTTPD_CONFIG="/vpn-gateway/httpd/vhost.conf"

IPSEC_CONFIG_FILE="/etc/ipsec.d/ipsec.conf"
IPSEC_SECRETS_FILE="/etc/ipsec.d/ipsec.secrets"

HTTPD_CONFIG_FILE="/etc/httpd/conf.d/vhost.conf"
HTTPD_HEALTHCHECK_LOG_CONFIG="/etc/httpd/conf.d/00-nlb-healthcheck-logging.conf"

HEALTHCHECK_PATH="/healthCheck.php"
HEALTHCHECK_DOCUMENT="/var/www/webservice/ws/healthCheck.php"

GIT_USER="apache"

# SSM bootstrap functions (inline - required before loading helpers from SSM)
get_secure_parameter() {
    local parameter_name="$1"

    aws ssm get-parameter \
        --region "$REGION" \
        --name "$parameter_name" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text
}

get_secure_parameter_with_retry() {
    local parameter_name="$1"
    local output=""
    local attempt

    for attempt in $(seq 1 20); do
        if output="$(get_secure_parameter "$parameter_name" 2>/dev/null)" &&
           [[ -n "$output" ]] &&
           [[ "$output" != "None" ]]; then

            printf '%s' "$output"
            return 0
        fi

        echo \
            "Unable to retrieve ${parameter_name}. " \
            "Attempt ${attempt}/20." >&2

        sleep 3
    done

    echo \
        "Unable to retrieve Parameter Store value: ${parameter_name}" >&2

    return 1
}

# Load helper functions from SSM
BOOTSTRAP_HELPERS_FILE="$(mktemp)"
get_secure_parameter_with_retry "$SSM_BOOTSTRAP_HELPERS" > "$BOOTSTRAP_HELPERS_FILE"
# shellcheck source=/dev/null
source "$BOOTSTRAP_HELPERS_FILE"
rm -f "$BOOTSTRAP_HELPERS_FILE"

# Retrieve EC2 metadata through IMDSv2
IMDS_TOKEN="$(
    curl \
        --fail \
        --silent \
        --show-error \
        --connect-timeout 2 \
        --max-time 10 \
        --request PUT \
        --header "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
        "http://169.254.169.254/latest/api/token"
)"

INSTANCE_ID="$(imds_get "meta-data/instance-id")"
PRIMARY_PRIVATE_IP="$(imds_get "meta-data/local-ipv4")"

MAC_ADDRESS="$(
    imds_get "meta-data/network/interfaces/macs/" |
    head -n 1 |
    tr -d '/'
)"

ENI_ID="$(
    imds_get \
        "meta-data/network/interfaces/macs/${MAC_ADDRESS}/interface-id"
)"

NETWORK_INTERFACE="$(
    ip -o -4 address show |
    awk -v address="$PRIMARY_PRIVATE_IP" '
        {
            split($4, value, "/")

            if (value[1] == address) {
                print $2
                exit
            }
        }
    '
)"

if [[ -z "$INSTANCE_ID" ]]; then
    echo "Unable to determine the EC2 instance ID."
    exit 1
fi

if [[ -z "$PRIMARY_PRIVATE_IP" ]]; then
    echo "Unable to determine the primary private IP."
    exit 1
fi

if [[ -z "$ENI_ID" ]]; then
    echo "Unable to determine the primary ENI ID."
    exit 1
fi

if [[ -z "$NETWORK_INTERFACE" ]]; then
    echo "Unable to determine the Linux network interface."
    exit 1
fi

validate_ipv4_addresses "$PRIMARY_PRIVATE_IP"

# Install dependencies
dnf install -y \
    git \
    httpd \
    php \
    php-fpm \
    libreswan \
    jq \
    python3 \
    nmap-ncat

command -v aws >/dev/null
command -v curl >/dev/null
command -v git >/dev/null
command -v httpd >/dev/null
command -v ip >/dev/null
command -v ipsec >/dev/null
command -v jq >/dev/null
command -v python3 >/dev/null

# Validate IAM role availability
retry 20 3 \
    aws sts get-caller-identity \
        --region "$REGION" \
        --output json \
        >/dev/null

# Retrieve bootstrap configuration
BOOTSTRAP_CONFIG="$(
    get_secure_parameter_with_retry "$SSM_BOOTSTRAP_CONFIG"
)"

if ! jq -e . >/dev/null 2>&1 <<< "$BOOTSTRAP_CONFIG"; then
    echo "The bootstrap configuration is not valid JSON."
    exit 1
fi

# Load vars from SSM and source them into the current shell
BOOTSTRAP_VARS_FILE="$(mktemp)"
get_secure_parameter_with_retry "$SSM_BOOTSTRAP_VARS" > "$BOOTSTRAP_VARS_FILE"
# shellcheck source=/dev/null
source "$BOOTSTRAP_VARS_FILE"
rm -f "$BOOTSTRAP_VARS_FILE"

# Resolve Elastic IP addresses
PRIMARY_PUBLIC_IP="$(
    aws ec2 describe-addresses \
        --region "$REGION" \
        --allocation-ids "$PRIMARY_EIP_ALLOCATION_ID" \
        --query 'Addresses[0].PublicIp' \
        --output text
)"

SECONDARY_PUBLIC_IP="$(
    aws ec2 describe-addresses \
        --region "$REGION" \
        --allocation-ids "$SECONDARY_EIP_ALLOCATION_ID" \
        --query 'Addresses[0].PublicIp' \
        --output text
)"

if [[ -z "$PRIMARY_PUBLIC_IP" || "$PRIMARY_PUBLIC_IP" == "None" ]]; then
    echo "Unable to resolve the primary Elastic IP address."
    exit 1
fi

if [[ -z "$SECONDARY_PUBLIC_IP" ||
      "$SECONDARY_PUBLIC_IP" == "None" ]]; then

    echo "Unable to resolve the secondary Elastic IP address."
    exit 1
fi

validate_ipv4_addresses \
    "$PRIMARY_PUBLIC_IP" \
    "$SECONDARY_PUBLIC_IP"

LOCAL_ENCRYPTION_DOMAIN="$SECONDARY_PUBLIC_IP"

# Assign or discover the secondary ENI IP
SECONDARY_PRIVATE_IP="$(
    aws ec2 describe-network-interfaces \
        --region "$REGION" \
        --network-interface-ids "$ENI_ID" \
        --query \
        'NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].PrivateIpAddress | [0]' \
        --output text
)"

if [[ -z "$SECONDARY_PRIVATE_IP" ||
      "$SECONDARY_PRIVATE_IP" == "None" ]]; then

    aws ec2 assign-private-ip-addresses \
        --region "$REGION" \
        --network-interface-id "$ENI_ID" \
        --secondary-private-ip-address-count 1

    for attempt in $(seq 1 20); do
        SECONDARY_PRIVATE_IP="$(
            aws ec2 describe-network-interfaces \
                --region "$REGION" \
                --network-interface-ids "$ENI_ID" \
                --query \
                'NetworkInterfaces[0].PrivateIpAddresses[?Primary==`false`].PrivateIpAddress | [0]' \
                --output text
        )"

        if [[ -n "$SECONDARY_PRIVATE_IP" &&
              "$SECONDARY_PRIVATE_IP" != "None" ]]; then
            break
        fi

        echo \
            "Waiting for the secondary private IP. " \
            "Attempt ${attempt}/20."

        sleep 3
    done
fi

if [[ -z "$SECONDARY_PRIVATE_IP" ||
      "$SECONDARY_PRIVATE_IP" == "None" ]]; then

    echo "Unable to assign or retrieve the secondary private IP."
    exit 1
fi

validate_ipv4_addresses "$SECONDARY_PRIVATE_IP"

# Associate Elastic IP addresses
aws ec2 associate-address \
    --region "$REGION" \
    --network-interface-id "$ENI_ID" \
    --allocation-id "$PRIMARY_EIP_ALLOCATION_ID" \
    --private-ip-address "$PRIMARY_PRIVATE_IP" \
    --allow-reassociation

aws ec2 associate-address \
    --region "$REGION" \
    --network-interface-id "$ENI_ID" \
    --allocation-id "$SECONDARY_EIP_ALLOCATION_ID" \
    --private-ip-address "$SECONDARY_PRIVATE_IP" \
    --allow-reassociation

# Wait for networkd to finish reconfiguring after EIP association
for attempt in $(seq 1 30); do
    sleep 2
    journalctl -u systemd-networkd --since "-3s" --no-pager -q |
        grep -q "Reconfiguring\|lease lost" || break
done

# Discover default gateway
DEFAULT_GATEWAY="$(
    ip -4 route show default dev "$NETWORK_INTERFACE" |
    awk 'NR == 1 { print $3 }'
)"

if [[ -z "$DEFAULT_GATEWAY" ]]; then
    echo "Unable to determine the default gateway."
    exit 1
fi

validate_ipv4_addresses "$DEFAULT_GATEWAY"

# Configure stateless runtime networking
ip address replace \
    "${SECONDARY_PRIVATE_IP}/32" \
    dev "$NETWORK_INTERFACE"

ip address replace \
    "${LOCAL_ENCRYPTION_DOMAIN}/32" \
    dev lo

for remote_host in "${REMOTE_HOSTS[@]}"; do
    ip route replace \
        "${remote_host}/32" \
        via "$DEFAULT_GATEWAY" \
        dev "$NETWORK_INTERFACE" \
        src "$LOCAL_ENCRYPTION_DOMAIN"
done

# Validate runtime networking
ip -4 address show dev "$NETWORK_INTERFACE" |
    grep -F "${SECONDARY_PRIVATE_IP}/32" >/dev/null

ip -4 address show dev lo |
    grep -F "${LOCAL_ENCRYPTION_DOMAIN}/32" >/dev/null

for remote_host in "${REMOTE_HOSTS[@]}"; do
    ROUTE_OUTPUT="$(
        ip -4 route get "$remote_host"
    )"

    if ! grep -q "src ${LOCAL_ENCRYPTION_DOMAIN}" <<< "$ROUTE_OUTPUT"; then
        echo "Incorrect source address for route to ${remote_host}:"
        echo "$ROUTE_OUTPUT"
        exit 1
    fi
done

# Set hostname after networking to avoid networkd wiping routes
hostnamectl set-hostname "$SYSTEM_HOSTNAME"

# Create temporary template files
IPSEC_TEMPLATE_FILE="$(mktemp)"
HTTPD_TEMPLATE_FILE="$(mktemp)"

cleanup() {
    rm -f \
        "$IPSEC_TEMPLATE_FILE" \
        "$HTTPD_TEMPLATE_FILE"
}

trap cleanup EXIT

# Retrieve and render Libreswan configuration
install -d \
    -o root \
    -g root \
    -m 0700 \
    /etc/ipsec.d

get_secure_parameter_with_retry "$SSM_IPSEC_CONFIG" \
    > "$IPSEC_TEMPLATE_FILE"

IPSEC_PSK="$(
    get_secure_parameter_with_retry "$SSM_IPSEC_PSK"
)"

if [[ -z "$IPSEC_PSK" ]]; then
    echo "The IPsec PSK is empty."
    exit 1
fi

REMOTE_SUBNETS="$(
    printf '%s/32\n' "${REMOTE_HOSTS[@]}" |
    paste -sd, -
)"

export \
    PRIMARY_PUBLIC_IP \
    SECONDARY_PUBLIC_IP \
    PRIMARY_PRIVATE_IP \
    SECONDARY_PRIVATE_IP \
    LOCAL_ENCRYPTION_DOMAIN \
    REMOTE_GATEWAY \
    REMOTE_SUBNETS

render_template \
    "$IPSEC_TEMPLATE_FILE" \
    "$IPSEC_CONFIG_FILE" \
    PRIMARY_PUBLIC_IP \
    SECONDARY_PUBLIC_IP \
    PRIMARY_PRIVATE_IP \
    SECONDARY_PRIVATE_IP \
    LOCAL_ENCRYPTION_DOMAIN \
    REMOTE_GATEWAY \
    REMOTE_SUBNETS

cat > /etc/ipsec.conf <<'EOF'
config setup
    uniqueids=yes

include /etc/ipsec.d/*.conf
EOF

ESCAPED_IPSEC_PSK="$(
    printf '%s' "$IPSEC_PSK" |
    escape_ipsec_psk
)"

printf '%s %s : PSK "%s"\n' \
    "$PRIMARY_PUBLIC_IP" \
    "$REMOTE_GATEWAY" \
    "$ESCAPED_IPSEC_PSK" \
    > "$IPSEC_SECRETS_FILE"

cat > /etc/ipsec.secrets <<'EOF'
include /etc/ipsec.d/*.secrets
EOF

chown root:root \
    "$IPSEC_CONFIG_FILE" \
    "$IPSEC_SECRETS_FILE" \
    /etc/ipsec.conf \
    /etc/ipsec.secrets

chmod 0600 \
    "$IPSEC_CONFIG_FILE" \
    "$IPSEC_SECRETS_FILE" \
    /etc/ipsec.secrets

chmod 0644 /etc/ipsec.conf

unset IPSEC_PSK
unset ESCAPED_IPSEC_PSK

# Validate and start Libreswan
ipsec addconn --checkconfig

systemctl restart ipsec

retry 20 3 systemctl is-active --quiet ipsec

# Configure Apache application account
usermod \
    --home /var/www \
    --shell /bin/bash \
    "$GIT_USER"

install -d \
    -o "$GIT_USER" \
    -g "$GIT_USER" \
    -m 0755 \
    /var/www

runuser -u "$GIT_USER" -- \
    git config --global credential.helper \
    '!aws codecommit credential-helper $@'

runuser -u "$GIT_USER" -- \
    git config --global credential.UseHttpPath true

# Clone CodeCommit repositories
for index in "${!REPOSITORY_URLS[@]}"; do
    repository_url="${REPOSITORY_URLS[$index]}"
    repository_directory="${REPOSITORY_DIRECTORIES[$index]}"

    if [[ -z "$repository_url" ||
          -z "$repository_directory" ]]; then

        echo "Invalid repository configuration at index ${index}."
        exit 1
    fi

    rm -rf "$repository_directory"

    runuser -u "$GIT_USER" -- \
        git clone \
        "$repository_url" \
        "$repository_directory"

    chown -R \
        "$GIT_USER:$GIT_USER" \
        "$repository_directory"
done

if command -v restorecon >/dev/null 2>&1; then
    restorecon -RF /var/www || true
fi

# Validate repository health-check file
if [[ ! -f "$HEALTHCHECK_DOCUMENT" ]]; then
    echo "NLB health-check file does not exist:"
    echo "$HEALTHCHECK_DOCUMENT"
    exit 1
fi

if [[ ! -r "$HEALTHCHECK_DOCUMENT" ]]; then
    echo "NLB health-check file is not readable:"
    echo "$HEALTHCHECK_DOCUMENT"
    exit 1
fi

# Retrieve and render Apache configuration
get_secure_parameter_with_retry "$SSM_HTTPD_CONFIG" \
    > "$HTTPD_TEMPLATE_FILE"

export HTTPD_SERVER_NAME
export SYSTEM_HOSTNAME

render_template \
    "$HTTPD_TEMPLATE_FILE" \
    "$HTTPD_CONFIG_FILE" \
    HTTPD_SERVER_NAME \
    SYSTEM_HOSTNAME \
    PRIMARY_PUBLIC_IP \
    SECONDARY_PUBLIC_IP \
    PRIMARY_PRIVATE_IP \
    SECONDARY_PRIVATE_IP

chown root:root "$HTTPD_CONFIG_FILE"
chmod 0644 "$HTTPD_CONFIG_FILE"

if [[ ! -d /var/www/webservice/ws ]]; then
    echo "Apache DocumentRoot does not exist:"
    echo "/var/www/webservice/ws"
    exit 1
fi

# Exclude NLB health checks from Apache logs
cat > "$HTTPD_HEALTHCHECK_LOG_CONFIG" <<'EOF'
# Identify NLB HTTP health-check requests.
SetEnvIf Request_URI "^/healthCheck\.php$" nlb_healthcheck=1
EOF

chown root:root "$HTTPD_HEALTHCHECK_LOG_CONFIG"
chmod 0644 "$HTTPD_HEALTHCHECK_LOG_CONFIG"

python3 - /etc/httpd/conf/httpd.conf <<'PYTHON'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
content = path.read_text()

pattern = re.compile(
    r'^(\s*CustomLog\s+"?logs/access_log"?\s+combined)'
    r'(?!\s+env=!\S+)(\s*)$',
    re.MULTILINE,
)

content, replacements = pattern.subn(
    r'\1 env=!nlb_healthcheck\2',
    content,
)

if replacements > 1:
    raise RuntimeError(
        "More than one default global CustomLog directive was modified"
    )

path.write_text(content)
PYTHON

# The VirtualHost log must explicitly use the condition.
if ! grep -Eq \
    '^[[:space:]]*CustomLog[[:space:]].*env=!nlb_healthcheck' \
    "$HTTPD_CONFIG_FILE"; then

    echo "The Apache VirtualHost CustomLog does not exclude NLB health checks."
    echo
    echo "Required directive:"
    echo
    echo \
        'CustomLog /var/log/httpd/${HTTPD_SERVER_NAME}_access_log combined env=!nlb_healthcheck'
    exit 1
fi

# Validate Apache configuration
httpd -t

# Start application services
systemctl restart php-fpm
systemctl restart httpd

retry 20 3 systemctl is-active --quiet php-fpm
retry 20 3 systemctl is-active --quiet httpd

# Validate NLB health-check endpoint
HEALTHCHECK_STATUS="$(
    curl \
        --silent \
        --output /dev/null \
        --write-out '%{http_code}' \
        --connect-timeout 2 \
        --max-time 10 \
        --header "Host: ${HTTPD_SERVER_NAME}" \
        "http://127.0.0.1${HEALTHCHECK_PATH}"
)"

if [[ "$HEALTHCHECK_STATUS" != "200" ]]; then
    echo \
        "Health-check endpoint returned HTTP ${HEALTHCHECK_STATUS}."

    exit 1
fi

# Also validate using a non-canonical Host header.

HEALTHCHECK_NLB_STYLE_STATUS="$(
    curl \
        --silent \
        --output /dev/null \
        --write-out '%{http_code}' \
        --connect-timeout 2 \
        --max-time 10 \
        --header "Host: ${PRIMARY_PRIVATE_IP}:80" \
        "http://127.0.0.1${HEALTHCHECK_PATH}"
)"

if [[ "$HEALTHCHECK_NLB_STYLE_STATUS" != "200" ]]; then
    echo \
        "Health-check endpoint failed with a non-canonical Host header. " \
        "HTTP ${HEALTHCHECK_NLB_STYLE_STATUS}."

    exit 1
fi

# Final validation
echo "Bootstrap completed successfully."
echo "Instance ID: ${INSTANCE_ID}"
echo "ENI ID: ${ENI_ID}"
echo "Network interface: ${NETWORK_INTERFACE}"
echo "System hostname: ${SYSTEM_HOSTNAME}"
echo "Primary private IP: ${PRIMARY_PRIVATE_IP}"
echo "Secondary private IP: ${SECONDARY_PRIVATE_IP}"
echo "Primary public IP: ${PRIMARY_PUBLIC_IP}"
echo "Secondary public IP: ${SECONDARY_PUBLIC_IP}"
echo "Local encryption domain: ${LOCAL_ENCRYPTION_DOMAIN}"
echo "Remote IPsec gateway: ${REMOTE_GATEWAY}"
echo "Default gateway: ${DEFAULT_GATEWAY}"
echo "Apache ServerName: ${HTTPD_SERVER_NAME}"
echo "NLB health-check path: ${HEALTHCHECK_PATH}"
echo "NLB health-check document: ${HEALTHCHECK_DOCUMENT}"

echo
echo "Runtime routes:"

for remote_host in "${REMOTE_HOSTS[@]}"; do
    ip -4 route get "$remote_host"
done

echo
echo "Service state:"

systemctl --no-pager --full status ipsec
systemctl --no-pager --full status php-fpm
systemctl --no-pager --full status httpd

echo
echo "IPsec traffic state:"

ipsec trafficstatus || true