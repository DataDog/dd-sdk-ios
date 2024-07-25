#!/bin/zsh

# Usage:
# $ ./tools/e2e-build-upload.sh -h
# Publishes IPA of a new version of the E2E app to synthetics.

# Options:
#   --artifacts-path: Path where the IPA artifact will be exported.

# ENVs:
# - DRY_RUN: Set to '1' to do everything except uploading the IPA to synthetics.

set +x 
set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh
source ./tools/secrets/get-secret.sh

set_description "Publishes IPA a new version of the E2E app to synthetics."
define_arg "artifacts-path" "" "Path where the IPA artifact will be exported." "string" "true"

check_for_help "$@"
parse_args "$@"

KEYCHAIN=datadog.e2e.keychain
KEYCHAIN_PASSWORD="$(openssl rand -base64 32)"
PROFILE=datadog.e2e.mobileprovision

E2E_DIR="E2ETests"
E2E_XCCONFIG_PATH="$E2E_DIR/xcconfigs/E2E.local.xcconfig"
E2E_CODESIGN_DIR="$E2E_DIR/code-signing"
P12_PATH="$E2E_CODESIGN_DIR/e2e_cert.p12"
PP_PATH="$E2E_CODESIGN_DIR/e2e.mobileprovision"
PP_INSTALL_DIR="$HOME/Library/MobileDevice/Provisioning Profiles"
PP_INSTALL_PATH="$PP_INSTALL_DIR/$PROFILE"

ARTIFACTS_PATH="$(realpath .)/$artifacts_path"

create_e2e_xcconfig() {
    echo_subtitle "Create '$E2E_XCCONFIG_PATH'"
    get_secret $DD_IOS_SECRET__E2E_XCCONFIG_BASE64 | base64 --decode -o $E2E_XCCONFIG_PATH
    echo_succ "▸ '$E2E_XCCONFIG_PATH' ready"
}

create_codesign_files() {
    echo_subtitle "Create codesign files in '$E2E_CODESIGN_DIR'"
    rm -rf "$E2E_CODESIGN_DIR"
    mkdir -p "$E2E_CODESIGN_DIR"
    get_secret $DD_IOS_SECRET__E2E_CERTIFICATE_P12_BASE64 | base64 --decode -o $P12_PATH
    echo_succ "▸ $P12_PATH - ready"
    get_secret $DD_IOS_SECRET__E2E_PROVISIONING_PROFILE_BASE64 | base64 --decode -o $PP_PATH
    echo_succ "▸ $PP_PATH - ready"
}

setup_codesigning() {
    echo_subtitle "Setup code signing"

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

    # Import certificate to keychain
    P12_PASSWORD=$(get_secret "$DD_IOS_SECRET__E2E_CERTIFICATE_P12_PASSWORD")
    if ! security import "$P12_PATH" -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"; then
        echo_err "▸ Error:" "Failed to import certificate from '$P12_PATH' to '$KEYCHAIN'"
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

    # Install provisioning profile
    mkdir -p "$PP_INSTALL_DIR"
    if ! cp "$PP_PATH" "$PP_INSTALL_PATH"; then
        echo_err "▸ Error:" "Failed to install provisioning profile from '$PP_PATH' to '$PP_INSTALL_PATH'"
        return 1
    fi
    echo_succ "▸ '$PP_PATH' provisioning profile installed in '$PP_INSTALL_PATH'"
}

cleanup_codesigning() {
    echo_subtitle "Cleanup code signing"

    rm -f "$PP_INSTALL_PATH"
    echo_info "▸ '$PP_INSTALL_PATH' deleted"

    if security delete-keychain "$KEYCHAIN" 2>/dev/null; then
        echo_info "▸ '$KEYCHAIN' deleted"
    else
        echo_warn "▸ Keychain '$KEYCHAIN' not found or failed to delete"
    fi
}

create_e2e_xcconfig
create_codesign_files
trap cleanup_codesigning EXIT INT # clean up keychain on exit
setup_codesigning

echo_subtitle "Run 'make clean archive export upload ARTIFACTS_PATH=\"$ARTIFACTS_PATH\"' in '$E2E_DIR'"
cd "$E2E_DIR" 
make clean archive export ARTIFACTS_PATH="$ARTIFACTS_PATH"

if [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "true" ]; then
    echo_warn "Running in DRY RUN mode. Skipping 'make upload'."
else
    export DATADOG_API_KEY=$(get_secret $DD_IOS_SECRET__E2E_S8S_API_KEY)
    export DATADOG_APP_KEY=$(get_secret $DD_IOS_SECRET__E2E_S8S_APP_KEY)
    export S8S_APPLICATION_ID=$(get_secret $DD_IOS_SECRET__E2E_S8S_APPLICATION_ID)
    make upload ARTIFACTS_PATH="$ARTIFACTS_PATH"
fi
