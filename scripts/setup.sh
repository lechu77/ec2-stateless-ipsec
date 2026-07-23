#!/bin/bash
# setup.sh — Initializes local configuration files from .example templates.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SSM_DIR="${REPO_ROOT}/ssm"
TERRAFORM_DIR="${REPO_ROOT}/terraform"

echo "=========================================="
echo " Initializing Local Configuration Files"
echo "=========================================="

copy_if_missing() {
    local example_file="$1"
    local target_file="${example_file%.example}"

    if [[ ! -f "$target_file" ]]; then
        echo "Creating $(basename "$target_file") from example..."
        cp "$example_file" "$target_file"
    else
        echo "$(basename "$target_file") already exists, skipping."
    fi
}

# Copy SSM example templates
for example in "${SSM_DIR}"/*.example; do
    [[ -f "$example" ]] || continue
    copy_if_missing "$example"
done

# Copy terraform.tfvars.example
if [[ -f "${TERRAFORM_DIR}/terraform.tfvars.example" && ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]]; then
    echo "Creating terraform/terraform.tfvars from example..."
    cp "${TERRAFORM_DIR}/terraform.tfvars.example" "${TERRAFORM_DIR}/terraform.tfvars"
fi

echo ""
echo "Setup initialized successfully!"
echo ""
echo "Next steps:"
echo "1. Edit parameters in ${SSM_DIR}/ with your actual environment details & secrets."
echo "2. Edit ${TERRAFORM_DIR}/terraform.tfvars with your target AWS subnet, AMI, and SG."
echo "3. Run ./scripts/ssm-put-parameters.sh --region <region> [--profile <profile>] to upload parameters to AWS SSM."
echo "4. Run 'cd terraform && terraform apply' to deploy the infrastructure."
