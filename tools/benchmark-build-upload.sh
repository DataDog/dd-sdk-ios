#!/bin/zsh

# Usage:
# $ ./tools/benchmark-build-upload.sh -h
# Publishes IPA of a new version of the Benchmark app to synthetics.

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

set_description "Publishes IPA a new version of the Benchamrk app to synthetics."
define_arg "artifacts-path" "" "Path where the IPA artifact will be exported." "string" "true"

check_for_help "$@"
parse_args "$@"

BENCHMARK_DIR="BenchmarkTests"
BENCHMARK_XCCONFIG_PATH="$BENCHMARK_DIR/xcconfigs/Benchmarks.local.xcconfig"
BENCHMARK_CODESIGN_DIR="$BENCHMARK_DIR/benchmark-signing"
P12_PATH="$BENCHMARK_CODESIGN_DIR/cert.p12"
PP_PATH="$BENCHMARK_CODESIGN_DIR/runner.mobileprovision"

ARTIFACTS_PATH="$(realpath .)/$artifacts_path"

create_xcconfig() {
    echo_subtitle "Create '$BENCHMARK_XCCONFIG_PATH'"
    get_secret $DD_IOS_SECRET__BENCHMARK_XCCONFIG_BASE64 | base64 --decode -o $BENCHMARK_XCCONFIG_PATH
    echo_succ "▸ '$BENCHMARK_XCCONFIG_PATH' ready"
}

create_codesign_files() {
    echo_subtitle "Create codesign files in '$BENCHMARK_CODESIGN_DIR'"
    rm -rf "$BENCHMARK_CODESIGN_DIR"
    mkdir -p "$BENCHMARK_CODESIGN_DIR"
    get_secret $DD_IOS_SECRET__E2E_CERTIFICATE_P12_BASE64 | base64 --decode -o $P12_PATH
    echo_succ "▸ $P12_PATH - ready"
    get_secret $DD_IOS_SECRET__BENCHMARK_PROVISIONING_PROFILE_BASE64 | base64 --decode -o $PP_PATH
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

echo_subtitle "Run 'make clean archive export upload ARTIFACTS_PATH=\"$ARTIFACTS_PATH\"' in '$BENCHMARK_DIR'"
cd "$BENCHMARK_DIR" 
make clean archive export ARTIFACTS_PATH="$ARTIFACTS_PATH"

if [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "true" ]; then
    echo_warn "Running in DRY RUN mode. Skipping 'make upload'."
else
    export DATADOG_API_KEY=$(get_secret $DD_IOS_SECRET__E2E_S8S_API_KEY)
    export DATADOG_APP_KEY=$(get_secret $DD_IOS_SECRET__E2E_S8S_APP_KEY)
    export S8S_APPLICATION_ID=$(get_secret $DD_IOS_SECRET__BENCHMARK_S8S_APPLICATION_ID)
    make upload ARTIFACTS_PATH="$ARTIFACTS_PATH"
fi
