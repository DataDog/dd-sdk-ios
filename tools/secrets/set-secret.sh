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

set_description "Sets or updates CI secret."
define_arg "name" "" "The name of the secret" "string" "true"
define_arg "value" "" "The value of the secret" "string" "true"

check_for_help "$@"
parse_args "$@"

if [[ -z "$name" || -z "$value" ]]; then
    echo_err "Error" "Missing secret name or secret value."
    return 1
fi

if ! command -v vault &> /dev/null; then
    echo_err "Error" "vault is not installed or not in the PATH. Install: https://formulae.brew.sh/formula/vault"
    return 1
fi

export VAULT_ADDR=https://vault.us1.ddbuild.io
vault login -method=oidc
vault kv put 'kv/aws/arn:aws:iam::486234852809:role/ci-dd-sdk-ios/common' "$name"="$value"
local exit_code=$?

if [[ $exit_code -ne 0 ]]; then
    echo_err "Error" "Failed to set the secret '$name' with vault."
    return 1
fi

echo_succ "Secret '$name' was set successfully."
