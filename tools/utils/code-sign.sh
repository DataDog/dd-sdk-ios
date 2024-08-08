#!/bin/zsh

set +x 
set -eo pipefail
source ./tools/utils/echo-color.sh

KEYCHAIN=datadog.keychain
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"

PROFILE=datadog.mobileprovision
USER_PP_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
USER_PP_PATH="$USER_PP_DIR/$PROFILE"

cleanup_codesigning() {
    echo_subtitle "Cleanup code signing"

    rm -f "$PP_PATH"
    echo_info "▸ '$PP_PATH' deleted"

    if security delete-keychain "$KEYCHAIN" 2>/dev/null; then
        echo_info "▸ '$KEYCHAIN' deleted"
    else
        echo_warn "▸ Keychain '$KEYCHAIN' not found or failed to delete"
    fi
}

create_keychain() {
    # Create temporary keychain
    if ! security delete-keychain "$KEYCHAIN" 2>/dev/null; then
        echo_warn "▸ Keychain '$KEYCHAIN' not found, nothing to delete"
    fi
    if ! security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"; then
        echo_err "▸ Error:" "Failed to create keychain '$KEYCHAIN'"
        return 1
    fi
    if ! security set-keychain-settings -lut 21600 "$KEYCHAIN"; then
        echo_err "▸ Error:" "Failed to set keychain settings for '$KEYCHAIN'"
        return 1
    fi
    if ! security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"; then
        echo "▸ Error:" "Failed to unlock keychain '$KEYCHAIN'"
        return 1
    fi
    echo_succ "▸ '$KEYCHAIN' created and unlocked"
}

keychain_import() {
    # read cmd arguments
    while :; do
        case $1 in
            --p12) P12_PATH=$2
            shift
            ;;
            --p12-password) P12_PASSWORD=$2
            shift
            ;;
            *) break
        esac
        shift
    done

    # Import certificate to keychain
    if ! security import "$P12_PATH" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"; then
        echo_err "▸ Error:" "Failed to import certificate from '$p12' to '$KEYCHAIN'"
        return 1
    fi
    echo_succ "▸ '$P12_PATH' certificate imported to '$KEYCHAIN'"

    if ! security list-keychain -d user -s "$KEYCHAIN" "login.keychain" "System.keychain"; then
        echo_err "▸ Error:" "Failed to configure keychain search list for '$KEYCHAIN'"
        return 1
    fi
    echo_succ "▸ '$KEYCHAIN' keychain search configured"

    if ! security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1; then
        echo_err "▸ Error:" "Failed to set key partition list for '$KEYCHAIN'"
        return 1
    fi
    echo_succ "▸ Permission granted for '$KEYCHAIN' keychain"
}

install_provisioning_profile() {
    # Install provisioning profile
    mkdir -p "$USER_PP_DIR"
    if ! cp "$1" "$USER_PP_PATH"; then
        echo_err "▸ Error:" "Failed to install provisioning profile from '$1' to '$USER_PP_PATH'"
        return 1
    fi
    echo_succ "▸ '$1' provisioning profile installed in '$USER_PP_PATH'"
}
