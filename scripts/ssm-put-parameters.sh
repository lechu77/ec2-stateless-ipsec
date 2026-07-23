#!/bin/bash
# ssm-put-parameters.sh
#
# Uploads bootstrap scripts and configuration to AWS SSM Parameter Store.
# All parameters are stored as SecureString.
#
# Usage:
#   ./scripts/ssm-put-parameters.sh [--region us-east-1] [--profile myprofile]

set -Eeuo pipefail

REGION="us-east-1"
PROFILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $0 [--region REGION] [--profile AWS_PROFILE]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --region)  REGION="$2";  shift 2 ;;
        --profile) PROFILE="$2"; shift 2 ;;
        *) usage ;;
    esac
done

AWS_ARGS=(--region "$REGION")
if [[ -n "$PROFILE" ]]; then
    AWS_ARGS+=(--profile "$PROFILE")
fi

put_parameter() {
    local name="$1"
    local value="$2"

    echo "Uploading: ${name}"

    aws ssm put-parameter \
        "${AWS_ARGS[@]}" \
        --name "$name" \
        --type "SecureString" \
        --value "$value" \
        --overwrite
}

# bootstrap-helpers.sh — shell functions sourced by user-data at boot
if [[ -f "${REPO_ROOT}/ssm/bootstrap-helpers.sh" ]]; then
    put_parameter \
        "/vpn-gateway/bootstrap/helpers" \
        "$(cat "${REPO_ROOT}/ssm/bootstrap-helpers.sh")"
fi

# bootstrap-vars.sh — variable extraction and validation sourced by user-data
if [[ -f "${REPO_ROOT}/ssm/bootstrap-vars.sh" ]]; then
    put_parameter \
        "/vpn-gateway/bootstrap/vars" \
        "$(cat "${REPO_ROOT}/ssm/bootstrap-vars.sh")"
fi

# bootstrap-config.json — JSON with hostname, EIPs, repos
if [[ -f "${REPO_ROOT}/ssm/bootstrap-config.json" ]]; then
    put_parameter \
        "/vpn-gateway/bootstrap/config" \
        "$(cat "${REPO_ROOT}/ssm/bootstrap-config.json")"
fi

# ipsec.conf — Libreswan connection template
if [[ -f "${REPO_ROOT}/ssm/ipsec.conf" ]]; then
    put_parameter \
        "/vpn-gateway/ipsec/ipsec.conf" \
        "$(cat "${REPO_ROOT}/ssm/ipsec.conf")"
fi

# psk — IPsec pre-shared key
if [[ -f "${REPO_ROOT}/ssm/psk" ]]; then
    put_parameter \
        "/vpn-gateway/ipsec/psk" \
        "$(cat "${REPO_ROOT}/ssm/psk")"
fi

# vhost.conf — Apache VirtualHost template
if [[ -f "${REPO_ROOT}/ssm/vhost.conf" ]]; then
    put_parameter \
        "/vpn-gateway/httpd/vhost.conf" \
        "$(cat "${REPO_ROOT}/ssm/vhost.conf")"
fi

# remote-gateway — IPsec remote gateway IP
if [[ -f "${REPO_ROOT}/ssm/remote-gateway" ]]; then
    put_parameter \
        "/vpn-gateway/ipsec/remote-gateway" \
        "$(cat "${REPO_ROOT}/ssm/remote-gateway")"
fi

# remote-hosts — Comma-separated list of remote IPsec hosts
if [[ -f "${REPO_ROOT}/ssm/remote-hosts" ]]; then
    put_parameter \
        "/vpn-gateway/ipsec/remote-hosts" \
        "$(cat "${REPO_ROOT}/ssm/remote-hosts")"
fi

echo ""
echo "Done. All SSM parameters uploaded successfully."
