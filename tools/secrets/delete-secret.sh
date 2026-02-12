#!/bin/zsh

# Usage:
# $ ./tools/secrets/delete-secret.sh
#
# Note:
# - Requires `vault` to be installed

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/secrets/config.sh

list_secrets() {
    GREEN="\e[32m"
    RESET="\e[0m"

    echo "Available secrets:"
    for key in ${(k)DD_IOS_SECRETS}; do
        IFS=" | " read -r name description <<< "${DD_IOS_SECRETS[$key]}"
        echo "$key) ${GREEN}$name${RESET} - $description"
    done | sort -n

    echo ""
    echo "⚠️  WARNING: Deleting a secret is a destructive operation that cannot be undone."
}

select_secret() {
    echo
    while true; do
        echo_info "Enter the number of the secret you want to delete (or 'q' to quit):"
        read "secret_number"

        if [[ "$secret_number" == "q" ]]; then
            echo "Deletion cancelled."
            exit 0
        fi

        if [[ -n ${DD_IOS_SECRETS[$secret_number]} ]]; then
            IFS=" | " read -r SECRET_NAME SECRET_DESC <<< "${DD_IOS_SECRETS[$secret_number]}"
            break
        else
            echo_err "Invalid selection. Please enter a valid number."
        fi
    done
}

confirm_deletion() {
    echo
    echo_warn "You are about to delete the secret: '$SECRET_NAME'"
    echo_warn "Description: $SECRET_DESC"
    echo
    echo_info "Are you sure you want to delete this secret? (yes/no):"
    read "confirmation"

    case "$confirmation" in
        yes|YES|y|Y)
            return 0
            ;;
        *)
            echo "Deletion cancelled."
            exit 0
            ;;
    esac
}

delete_secret_value() {
    echo_info "You will now be authenticated with OIDC in your web browser. Press ENTER to continue."
    read
    export VAULT_ADDR=$DD_VAULT_ADDR
    vault login -method=oidc -no-print
    vault kv delete "$DD_IOS_SECRETS_PATH_PREFIX/$SECRET_NAME"
    echo_succ "Secret '$SECRET_NAME' deleted successfully."
    echo
    echo_warn "Remember to update 'tools/secrets/config.sh' if this secret is no longer needed."
}

list_secrets
select_secret
confirm_deletion
delete_secret_value
