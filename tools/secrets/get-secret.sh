#!/bin/zsh

source ./tools/utils/echo-color.sh
source ./tools/secrets/config.sh

# Usage:
#   get_secret <secret_name>
#
# Notes:
# - For <secret_name> use constants defined in 'tools/secrets/config.sh'
# - Requires `vault` to be installed
get_secret() {
    local secret_name="$1"

    export VAULT_ADDR=$DD_VAULT_ADDR
    if [ "$CI" = "true" ]; then
        vault login -method=aws -no-print
    else
        if vault token lookup &>/dev/null; then
            echo_succ "Reading '$secret_name' secret in local env. You are already authenticated with 'vault'." >&2
        else
            echo_warn "Reading '$secret_name' secret in local env. You will now be authenticated with OIDC in your web browser." >&2
            vault login -method=oidc -no-print
        fi
    fi

    local secret_value=$(vault kv get -field=value "$DD_IOS_SECRETS_PATH_PREFIX/$secret_name")

    if [[ -z "$secret_value" ]]; then
        echo_err "Error" "Failed to retrieve the '$secret_name' secret or the secret is empty." >&2
        exit 1
    fi

    echo $secret_value
}
