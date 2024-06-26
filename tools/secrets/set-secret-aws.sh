#!/bin/zsh

# Usage:
# $ ./tools/secrets/set-secret.sh --name <secret_name> --value <secret_value>
# Sets or updates a CI secret.
#
# Options:
#   --name <secret_name>   Specifies the name of the secret.
#   --value <secret_value> Specifies the value of the secret.
#
# Note:
# - Requires `aws-vault` installed and configured.
# - Requires DATADOG_ROOT environment variable set to the directory containing `devtools/bin/ci-secrets`.

set -eo pipefail
source ./tools/utils/echo_color.sh
source ./tools/utils/argparse.sh

while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            name=$2
            shift 2
            ;;
        --value)
            value=$2
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

if [[ -z "$name" || -z "$value" ]]; then
    echo_err "Error" "Missing secret name or secret value."
    return 1
fi

if [[ -z "$DATADOG_ROOT" || ! -d "$DATADOG_ROOT" ]]; then
    echo_err "Error" "DATADOG_ROOT is not set or points to a non-existent directory."
    return 1
fi

if ! command -v aws-vault &> /dev/null; then
    echo_err "Error" "aws-vault is not installed or not in the PATH."
    return 1
fi

if [[ ! -x "$DATADOG_ROOT/devtools/bin/ci-secrets" ]]; then
    echo_err "Error" "ci-secrets tool is not found or not executable at $DATADOG_ROOT/devtools/bin/ci-secrets."
    return 1
fi

export AWS_PAGER="" # do not block terminal with the pager
echo $value | aws-vault exec sso-build-stable-developer -- $DATADOG_ROOT/devtools/bin/ci-secrets set ci.dd-sdk-ios.$name
local exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    echo_err "Error" "Failed to set the secret '$name' with aws-vault."
    return 1
fi

echo_succ "Secret '$name' was set successfully."
