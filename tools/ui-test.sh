#!/bin/zsh

# Usage:
# $ ./tools/ui-test.sh -h
# Executes UI tests for a specified --test-plan using the provided --os, --platform, and --device.

# Options:
#   --device: Specifies the simulator device for running tests, e.g. 'iPhone 15 Pro'
#   --platform: Defines the type of simulator platform for the tests, e.g. 'iOS Simulator'
#   --os: Sets the operating system version for the tests, e.g. '17.5'
#   --test-plan: Identifies the test plan to run
#   --mode: 'build-and-test' (default), 'build-for-testing' or 'test-without-building'
#   --products-path: Build products location shared by 'build-for-testing' and 'test-without-building'

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh

set_description "Executes UI tests for a specified --test-plan using the provided --os, --platform, and --device."
define_arg "test-plan" "" "Identifies the test plan to run (not used with '--mode build-for-testing')" "string" "false"
define_arg "os" "" "Sets the operating system version for the tests, e.g. '17.5'" "string" "true"
define_arg "platform" "" "Defines the type of simulator platform for the tests, e.g. 'iOS Simulator'" "string" "true"
define_arg "device" "" "Specifies the simulator device for running tests, e.g. 'iPhone 15 Pro'" "string" "true"
define_arg "mode" "build-and-test" "'build-and-test' builds and runs --test-plan. 'build-for-testing' builds all test plans into --products-path. 'test-without-building' runs --test-plan from --products-path." "string" "false"
define_arg "products-path" "build/ui-tests" "Build products location shared by 'build-for-testing' and 'test-without-building'" "string" "false"

check_for_help "$@"
parse_args "$@"

disable_apple_crash_reporter() {
    launchctl unload -w /System/Library/LaunchAgents/com.apple.ReportCrash.plist
    echo_warn "Disabling Apple Crash Reporter before running UI tests."
    echo "This action disables the system prompt ('Runner quit unexpectedly') if an app crashes in the simulator, which"
    echo "is expected behavior when running UI tests for 'DatadogCrashReporting'."
}

enable_apple_crash_reporter() {
    launchctl load -w /System/Library/LaunchAgents/com.apple.ReportCrash.plist
    echo_succ "Apple Crash Reporter has been re-enabled after the UI tests."
}

# Runs `xcodebuild <arguments> <action>`. On CI, it also writes a result bundle and the raw log to `ResultBundles/`.
run_tests() {
    local action="$1"
    shift
    if [ "$CI" = "true" ]; then
        mkdir -p ResultBundles
        RESULT_BUNDLE_PATH="ResultBundles/${SCHEME}-${TEST_PLAN}.xcresult"
        rm -rf "$RESULT_BUNDLE_PATH"
        # Tee the raw xcodebuild log to disk (flushed line-by-line) so it survives even if the
        # process gets killed mid-run, e.g. by RUNNER_SCRIPT_TIMEOUT on a hung test. The raw
        # .xcresult bundle and this log are uploaded as-is (no need to zip): GitLab's artifact
        # uploader already archives whatever paths match, zip or not.
        xcodebuild "$@" -resultBundlePath "$RESULT_BUNDLE_PATH" "$action" 2>&1 | tee "ResultBundles/${SCHEME}-${TEST_PLAN}.log" | xcbeautify
    else
        xcodebuild "$@" "$action" | xcbeautify
    fi
}

if [[ "$mode" != "build-for-testing" && -z "$test_plan" ]]; then
    echo_err "Missing required argument --test-plan for --mode '$mode'"
    exit 1
fi

set -x

export DD_SDK_COMPILED_FOR_TESTING=1
export DD_TEST_UTILITIES_ENABLED=1

WORKSPACE="IntegrationTests/IntegrationTests.xcworkspace"
DESTINATION="platform=$platform,name=$device,OS=$os"
SCHEME="IntegrationScenarios"
TEST_PLAN="$test_plan"

xcodebuild -version

case "$mode" in
    build-and-test)
        ./tools/config/generate-http-server-mock-config.sh

        disable_apple_crash_reporter
        trap enable_apple_crash_reporter EXIT INT

        run_tests test -workspace "$WORKSPACE" -destination "$DESTINATION" -scheme "$SCHEME" -testPlan "$TEST_PLAN"
        ;;

    build-for-testing)
        # The IntegrationScenarios xcconfigs include the generated xcconfig.
        ./tools/config/generate-http-server-mock-config.sh

        # The products run on another machine, where 'test-without-building' starts the mock server on localhost.
        # Passed as a build setting, it overrides the private IP written to the xcconfig.
        MOCK_SERVER_ADDRESS=$(./tools/http-server-mock/python/server_address.py --prefer-localhost)

        rm -rf "$products_path"
        xcodebuild -workspace "$WORKSPACE" -destination "$DESTINATION" -scheme "$SCHEME" -derivedDataPath "$products_path" MOCK_SERVER_ADDRESS="$MOCK_SERVER_ADDRESS" build-for-testing | xcbeautify
        ;;

    test-without-building)
        XCTESTRUN_PATH=$(ls "$products_path"/Build/Products/${SCHEME}_${TEST_PLAN}_*.xctestrun)

        # `-xctestrun` runs no scheme pre-action, so the mock server is started here, on the localhost
        # address built into the products by 'build-for-testing'.
        ./tools/http-server-mock/python/start_mock_server.py --prefer-localhost &
        MOCK_SERVER_PID=$!

        disable_apple_crash_reporter
        trap "kill $MOCK_SERVER_PID; enable_apple_crash_reporter" EXIT INT

        run_tests test-without-building -xctestrun "$XCTESTRUN_PATH" -destination "$DESTINATION"
        ;;

    *)
        echo_err "Unknown --mode '$mode'"
        exit 1
        ;;
esac
