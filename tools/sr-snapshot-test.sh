#!/bin/zsh

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh

set_description "."
define_arg "pull" "false" "..." "store_true"
define_arg "push" "false" "..." "store_true"
define_arg "open-project" "false" "..." "store_true"
define_arg "test" "false" "..." "store_true"
define_arg "os" "" "Sets the operating system version for the tests, e.g. '17.5'" "string" "false"
define_arg "platform" "" "Defines the type of simulator platform for the tests, e.g. 'iOS Simulator'" "string" "false"
define_arg "device" "" "Specifies the simulator device for running tests, e.g. 'iPhone 15 Pro'" "string" "false"
define_arg "artifacts-path" "" "Path to artifacts for failed tests." "string" "false"

check_for_help "$@"
parse_args "$@"

REPO_ROOT=$(realpath .)

SNAPSHOTS_CLI_PATH="$REPO_ROOT/tools/sr-snapshots"
SNAPSHOTS_DIR="$REPO_ROOT/DatadogSessionReplay/SRSnapshotTests/SRSnapshotTests/_snapshots_"
SNAPSHOTS_REPO_PATH="$REPO_ROOT/../dd-mobile-session-replay-snapshots"

TEST_SCHEME="SRSnapshotTests"
TEST_WORKSPACE="$REPO_ROOT/DatadogSessionReplay/SRSnapshotTests/SRSnapshotTests.xcworkspace"
TEST_ARTIFACTS_PATH="$REPO_ROOT/$artifacts_path/sr-snapshot-tests"

pull_snapshots() {
    echo_subtitle "Pull SR snapshots to '$SNAPSHOTS_DIR'"
    cd "$SNAPSHOTS_CLI_PATH"
    swift run sr-snapshots pull \
			--local-folder "$SNAPSHOTS_DIR" \
			--remote-folder "$SNAPSHOTS_REPO_PATH" \
			--remote-branch "main"
    cd -
}

push_snapshots() {
    echo_subtitle "Push SR snapshots through '$SNAPSHOTS_REPO_PATH'"
    cd "$SNAPSHOTS_CLI_PATH"
    swift run sr-snapshots push \
			--local-folder "$SNAPSHOTS_DIR" \
			--remote-folder "$SNAPSHOTS_REPO_PATH" \
			--remote-branch "main"
    cd -
}

test_snapshots() {
    local destination="platform=$platform,name=$device,OS=$os"
    echo_subtitle "Test SR snapshots using destination='$destination'"

    rm -rf "$TEST_ARTIFACTS_PATH"
    mkdir -p "$TEST_ARTIFACTS_PATH"

    export DD_TEST_UTILITIES_ENABLED=1 # it is used in `dd-sdk-ios/Package.swift` to enable `TestUtilities` module
    xcodebuild -version
    xcodebuild -workspace "$TEST_WORKSPACE" -destination "$destination" -scheme "$TEST_SCHEME" -resultBundlePath "$TEST_ARTIFACTS_PATH/$TEST_SCHEME.xcresult" test | xcbeautify
}

echo_info "Using"
echo_info "▸ SNAPSHOTS_CLI_PATH = '$SNAPSHOTS_CLI_PATH'"
echo_info "▸ SNAPSHOTS_PATH = '$SNAPSHOTS_DIR'"
echo_info "▸ SNAPSHOTS_REPO_PATH = '$SNAPSHOTS_REPO_PATH'"
echo_info "▸ TEST_SCHEME = '$TEST_SCHEME'"
echo_info "▸ TEST_WORKSPACE = '$TEST_WORKSPACE'"
echo_info "▸ TEST_ARTIFACTS_PATH = '$TEST_ARTIFACTS_PATH'"

if [ "$pull" = "true" ]; then
    pull_snapshots
fi

if [ "$push" = "true" ]; then
    push_snapshots
fi

if [ "$test" = "true" ]; then
    if [[ -z "$os" || -z "$device" || -z "$platform" || -z "$artifacts_path" ]]; then
        echo_err "Error:" "--os, --device, --platform and --artifacts-path must be set along with --test."
        exit 1
    fi
    test_snapshots
fi
