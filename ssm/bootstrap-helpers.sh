retry() {
    local maximum_attempts="$1"
    local delay_seconds="$2"

    shift 2

    local attempt=1

    until "$@"; do
        if (( attempt >= maximum_attempts )); then
            echo "Command failed after ${maximum_attempts} attempts: $*"
            return 1
        fi

        echo \
            "Attempt ${attempt}/${maximum_attempts} failed. " \
            "Retrying in ${delay_seconds} seconds."

        sleep "$delay_seconds"
        ((attempt++))
    done
}

imds_get() {
    local path="$1"

    curl \
        --fail \
        --silent \
        --show-error \
        --connect-timeout 2 \
        --max-time 10 \
        --header "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
        "http://169.254.169.254/latest/${path}"
}

render_template() {
    local source_file="$1"
    local destination_file="$2"

    shift 2

    python3 - "$source_file" "$destination_file" "$@" <<'PYTHON'
import os
import re
import sys
from pathlib import Path

source_file = Path(sys.argv[1])
destination_file = Path(sys.argv[2])
variable_names = sys.argv[3:]

content = source_file.read_text()

for variable_name in variable_names:
    if variable_name not in os.environ:
        raise RuntimeError(
            f"Required template variable is not exported: {variable_name}"
        )

    placeholder = "${" + variable_name + "}"

    content = content.replace(
        placeholder,
        os.environ[variable_name],
    )

unresolved = sorted(
    set(
        re.findall(
            r"\$\{[A-Z][A-Z0-9_]*\}",
            content,
        )
    )
)

if unresolved:
    raise RuntimeError(
        "Unresolved template variables: " + ", ".join(unresolved)
    )

destination_file.write_text(content)
PYTHON
}

validate_ipv4_addresses() {
    python3 - "$@" <<'PYTHON'
import ipaddress
import sys

for value in sys.argv[1:]:
    try:
        ipaddress.IPv4Address(value)
    except ipaddress.AddressValueError as error:
        raise SystemExit(
            f"Invalid IPv4 address: {value}: {error}"
        )
PYTHON
}

escape_ipsec_psk() {
    python3 -c '
import sys

value = sys.stdin.read()
value = value.rstrip("\n")
value = value.replace("\\", "\\\\")
value = value.replace("\"", "\\\"")

sys.stdout.write(value)
'
}
