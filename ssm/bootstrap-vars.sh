SYSTEM_HOSTNAME="$(
    jq -er '.hostname' <<< "$BOOTSTRAP_CONFIG"
)"

HTTPD_SERVER_NAME="$(
    jq -er '.httpd_server_name' <<< "$BOOTSTRAP_CONFIG"
)"

PRIMARY_EIP_ALLOCATION_ID="$(
    jq -er '.primary_eip_allocation_id' <<< "$BOOTSTRAP_CONFIG"
)"

SECONDARY_EIP_ALLOCATION_ID="$(
    jq -er '.secondary_eip_allocation_id' <<< "$BOOTSTRAP_CONFIG"
)"

REMOTE_GATEWAY="$(
    get_secure_parameter_with_retry "/vpn-gateway/ipsec/remote-gateway"
)"

REMOTE_HOSTS_RAW="$(
    get_secure_parameter_with_retry "/vpn-gateway/ipsec/remote-hosts"
)"

mapfile -t REMOTE_HOSTS < <(
    tr ',' '\n' <<< "$REMOTE_HOSTS_RAW" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -v '^$'
)

mapfile -t REPOSITORY_URLS < <(
    jq -er '.repositories[].url' <<< "$BOOTSTRAP_CONFIG"
)

mapfile -t REPOSITORY_DIRECTORIES < <(
    jq -er '.repositories[].directory' <<< "$BOOTSTRAP_CONFIG"
)

if [[ -z "$SYSTEM_HOSTNAME" ]]; then
    echo "The system hostname is empty."
    exit 1
fi

if [[ -z "$HTTPD_SERVER_NAME" ]]; then
    echo "The Apache ServerName is empty."
    exit 1
fi

if [[ ! "$PRIMARY_EIP_ALLOCATION_ID" =~ ^eipalloc-[a-zA-Z0-9]+$ ]]; then
    echo "Invalid primary EIP allocation ID."
    exit 1
fi

if [[ ! "$SECONDARY_EIP_ALLOCATION_ID" =~ ^eipalloc-[a-zA-Z0-9]+$ ]]; then
    echo "Invalid secondary EIP allocation ID."
    exit 1
fi

if (( ${#REMOTE_HOSTS[@]} == 0 )); then
    echo "No remote IPsec hosts were defined."
    exit 1
fi

if (( ${#REPOSITORY_URLS[@]} == 0 )); then
    echo "No CodeCommit repositories were defined."
    exit 1
fi

if (( ${#REPOSITORY_URLS[@]} != ${#REPOSITORY_DIRECTORIES[@]} )); then
    echo "Repository URL and directory counts do not match."
    exit 1
fi

validate_ipv4_addresses \
    "$REMOTE_GATEWAY" \
    "${REMOTE_HOSTS[@]}"
