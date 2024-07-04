#!/bin/zsh

# Usage:
# $ ./tools/secrets/set-secret.sh
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
    echo "To add a new secret, first define it in 'tools/secrets/config.sh' and retry."
}

select_secret() {
    echo
    while true; do
        echo_info "Enter the number of the secret you want to set:"
        read "secret_number"
        if [[ -n ${DD_IOS_SECRETS[$secret_number]} ]]; then
            IFS=" | " read -r SECRET_NAME SECRET_DESC <<< "${DD_IOS_SECRETS[$secret_number]}"
            break
        else
            echo_err "Invalid selection. Please enter a valid number."
        fi
    done
}

get_secret_value_from_input() {
    echo_info "Enter the new value for '$SECRET_NAME':"
    read "SECRET_VALUE"
    echo
}

get_secret_value_from_file() {
    echo_info "Enter the file path to read the value for '$SECRET_NAME':"
    read "SECRET_FILE"
    echo

    SECRET_FILE=${SECRET_FILE/#\~/$HOME} # Expand ~ to home directory if present
    echo_info "Using '$SECRET_FILE'"

    if [[ -f "$SECRET_FILE" ]]; then
        SECRET_VALUE=$(cat "$SECRET_FILE")
    else
        echo_err "Error: File '$SECRET_FILE' does not exist."
        exit 1
    fi
}

select_input_method() {
    echo
    echo_info "How would you like to provide the secret value?"
    echo "1) Enter manually"
    echo "2) Read from a file"
    while true; do
        echo_info "Enter your choice (1 or 2):"
        read "input_method"
        case $input_method in
            1)
                get_secret_value_from_input
                break
                ;;
            2)
                get_secret_value_from_file
                break
                ;;
            *)
                echo_err "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done
}

set_secret_value() {
    echo_info "You will now be authenticated with OIDC in your web browser. Press ENTER to continue."
    read
    export VAULT_ADDR=$DD_VAULT_ADDR
    vault login -method=oidc -no-print
    vault kv put "$DD_IOS_SECRETS_PATH_PREFIX/$SECRET_NAME" value="$SECRET_VALUE"
    echo_succ "Secret '$SECRET_NAME' set successfully."
}

list_secrets
select_secret
select_input_method
set_secret_value
