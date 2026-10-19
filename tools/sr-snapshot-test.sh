#!/bin/zsh

# Usage:
# $ ./tools/sr-snapshot-test.sh -h
# Interacts with the SR Snapshot Tests project.

# Options:
#   --pull: Pulls snapshot images from the snapshots repository
#   --push: Pushes snapshot images to the snapshots repository
#   --open-project: Opens the SR Snapshot Tests project in Xcode with the required environment variables
#   --test: Runs snapshot tests against snapshot images in the current repository
#   --suite: Defines the snapshot test suite to use, e.g., 'view-tree' or 'layer-tree'
#   --snapshot-env: Selects a layer-tree snapshot environment for pull, push, and test
#   --os: Sets the operating system version for --test, e.g., '17.5'
#   --platform: Defines the type of simulator platform for --test, e.g., 'iOS Simulator'
#   --device: Specifies the simulator device for --test, e.g., 'iPhone 15'
#   --artifacts-path: Path to store the test bundle result

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh

set_description "Interacts with the SR Snapshot Tests project."
define_arg "pull" "false" "Pulls snapshot images from the snapshots repository" "store_true"
define_arg "push" "false" "Pushes snapshot images to the snapshots repository" "store_true"
define_arg "open-project" "false" "Opens the SR Snapshot Tests project in Xcode with the required environment variables" "store_true"
define_arg "test" "false" "Runs snapshot tests against snapshot images in the current repository" "store_true"
define_arg "suite" "view-tree" "Defines the snapshot test suite to use, e.g., 'view-tree' or 'layer-tree'" "string" "false"
define_arg "snapshot-env" "" "Selects a layer-tree snapshot environment; defaults to SnapshotEnvironments.json" "string" "false"
define_arg "os" "" "Sets the operating system version for --test, e.g., '17.5'" "string" "false"
define_arg "platform" "" "Defines the type of simulator platform for --test, e.g., 'iOS Simulator'" "string" "false"
define_arg "device" "" "Specifies the simulator device for --test, e.g., 'iPhone 15'" "string" "false"
define_arg "artifacts-path" "" "Path to store the test bundle result" "string" "false"

check_for_help "$@"
parse_args "$@"

REPO_ROOT=$(realpath .)

SNAPSHOTS_CLI_PATH="$REPO_ROOT/tools/sr-snapshots"
SNAPSHOTS_REPO_PATH="$REPO_ROOT/../dd-mobile-session-replay-snapshots"
TEST_WORKSPACE="$REPO_ROOT/DatadogSessionReplay/SRSnapshotTests/SRSnapshotTests.xcworkspace"

case "$suite" in
    "view-tree")
        if [[ -n "$snapshot_env" ]]; then
            echo_err "Error:" "--snapshot-env is only supported with --suite layer-tree."
            exit 1
        fi
        SNAPSHOTS_DIR="$REPO_ROOT/DatadogSessionReplay/SRSnapshotTests/SRSnapshotTests/_snapshots_"
        TEST_SCHEME="SRSnapshotTests"
        TEST_ARTIFACTS_SUBPATH="sr-snapshot-tests"
        ;;
    "layer-tree")
        LAYER_TESTS_DIR="$REPO_ROOT/DatadogSessionReplay/SRSnapshotTests/SRLayerSnapshotTests"
        ENVIRONMENTS_FILE="$LAYER_TESTS_DIR/SnapshotEnvironments.json"
        if [[ -z "$snapshot_env" ]]; then
            snapshot_env=$(/usr/bin/plutil -extract defaultEnvironment raw -o - "$ENVIRONMENTS_FILE")
        fi

        environment_index=0
        selected_environment_index=""
        while environment_name=$(/usr/bin/plutil -extract "environments.$environment_index.name" raw -o - "$ENVIRONMENTS_FILE" 2>/dev/null); do
            if [[ "$environment_name" == "$snapshot_env" ]]; then
                selected_environment_index="$environment_index"
                break
            fi
            ((environment_index += 1))
        done
        if [[ -z "$selected_environment_index" ]]; then
            echo_err "Error:" "Unsupported layer snapshot environment '$snapshot_env'. See $ENVIRONMENTS_FILE."
            exit 1
        fi

        expected_os=$(/usr/bin/plutil -extract "environments.$selected_environment_index.simulator.osVersion" raw -o - "$ENVIRONMENTS_FILE")
        expected_device=$(/usr/bin/plutil -extract "environments.$selected_environment_index.simulator.name" raw -o - "$ENVIRONMENTS_FILE")
        if [[ (-n "$os" && "$os" != "$expected_os") || (-n "$device" && "$device" != "$expected_device") || (-n "$platform" && "$platform" != "iOS Simulator") ]]; then
            echo_err "Error:" "Environment '$snapshot_env' requires iOS $expected_os on $expected_device Simulator. Select another environment with --snapshot-env."
            exit 1
        fi
        os="$expected_os"
        device="$expected_device"
        platform="iOS Simulator"

        SNAPSHOTS_DIR="$LAYER_TESTS_DIR/_snapshots_/$snapshot_env"
        TEST_SCHEME="SRLayerSnapshotTests"
        TEST_ARTIFACTS_SUBPATH="sr-layer-snapshot-tests/$snapshot_env"
        ;;
    *)
        echo_err "Error:" "--suite must be 'view-tree' or 'layer-tree'."
        exit 1
        ;;
esac

TEST_ARTIFACTS_PATH="$REPO_ROOT/$artifacts_path/$TEST_ARTIFACTS_SUBPATH"

# On CI, get GitHub token for accessing snapshots repository
if [ "$CI" = "true" ]; then
    export GH_TOKEN=$(dd-octo-sts --disable-tracing token --scope DataDog/dd-mobile-session-replay-snapshots --policy dd-sdk-ios)
    # Set up trap to always revoke token on script exit (success, failure, or interruption)
    trap 'dd-octo-sts --disable-tracing revoke --token $GH_TOKEN' EXIT
fi

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
    local environment_settings=()
    if [[ "$suite" == "layer-tree" ]]; then
        environment_settings+=("SNAPSHOT_ENV=$snapshot_env")
    fi
    echo_subtitle "Test SR snapshots using destination='$destination'"

    rm -rf "$TEST_ARTIFACTS_PATH"
    mkdir -p "$TEST_ARTIFACTS_PATH"

    export DD_TEST_UTILITIES_ENABLED=1 # it is used in `dd-sdk-ios/Package.swift` to enable `TestUtilities` module
    xcodebuild -version
    # Tee the raw xcodebuild log to disk (flushed line-by-line) so it survives even if the
    # process gets killed mid-run, e.g. by RUNNER_SCRIPT_TIMEOUT on a hung test.
    xcodebuild -workspace "$TEST_WORKSPACE" -destination "$destination" -scheme "$TEST_SCHEME" -resultBundlePath "$TEST_ARTIFACTS_PATH/$TEST_SCHEME.xcresult" "${environment_settings[@]}" test 2>&1 | tee "$TEST_ARTIFACTS_PATH/$TEST_SCHEME.log" | xcbeautify
}

open_snapshot_tests_project() {
    echo_info "Opening SRSnapshotTests with DD_TEST_UTILITIES_ENABLED ..."
    open --new --env DD_TEST_UTILITIES_ENABLED "$TEST_WORKSPACE"
}

if [ "$open_project" = "true" ]; then
    open_snapshot_tests_project
    exit 0
fi

echo_info "Using"
echo_info "▸ SUITE = '$suite'"
if [[ "$suite" == "layer-tree" ]]; then
    echo_info "▸ SNAPSHOT_ENV = '$snapshot_env'"
fi
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
