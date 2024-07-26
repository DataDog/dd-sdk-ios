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
source ./tools/utils/code-sign.sh
source ./tools/secrets/get-secret.sh

set_description "Publishes IPA a new version of the E2E app to synthetics."
define_arg "artifacts-path" "" "Path where the IPA artifact will be exported." "string" "true"

check_for_help "$@"
parse_args "$@"

E2E_DIR="E2ETests"
E2E_XCCONFIG_PATH="$E2E_DIR/xcconfigs/E2E.local.xcconfig"
E2E_CODESIGN_DIR="$E2E_DIR/code-signing"
P12_PATH="$E2E_CODESIGN_DIR/e2e_cert.p12"
PP_PATH="$E2E_CODESIGN_DIR/e2e.mobileprovision"

ARTIFACTS_PATH="$(realpath .)/$artifacts_path"

create_xcconfig() {
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

trap cleanup_codesigning EXIT INT # clean up keychain on exit

create_xcconfig
create_codesign_files
install_provisioning_profile $PP_PATH

create_keychain
keychain_import \
    --p12 $P12_PATH \
    --p12-password $(get_secret "$DD_IOS_SECRET__E2E_CERTIFICATE_P12_PASSWORD")

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
