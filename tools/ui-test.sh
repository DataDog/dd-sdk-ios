#!/bin/zsh

# Usage:
# $ ./tools/ui-test.sh -h
# Executes UI tests for a specified --test-plan using the provided --os, --platform, and --device.

# Options:
#   --device: Specifies the simulator device for running tests, e.g. 'iPhone 15 Pro'
#   --platform: Defines the type of simulator platform for the tests, e.g. 'iOS Simulator'
#   --os: Sets the operating system version for the tests, e.g. '17.5'
#   --test-plan: Identifies the test plan to run

set -eo pipefail
source ./tools/utils/echo_color.sh
source ./tools/utils/argparse.sh

set_description "Executes UI tests for a specified --test-plan using the provided --os, --platform, and --device."
define_arg "test-plan" "" "Identifies the test plan to run" "string" "true"
define_arg "os" "" "Sets the operating system version for the tests, e.g. '17.5'" "string" "true"
define_arg "platform" "" "Defines the type of simulator platform for the tests, e.g. 'iOS Simulator'" "string" "true"
define_arg "device" "" "Specifies the simulator device for running tests, e.g. 'iPhone 15 Pro'" "string" "true"

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

set -x

DIR=$(pwd)
cd IntegrationTests/ && bundle exec pod install
cd "$DIR"

WORKSPACE="IntegrationTests/IntegrationTests.xcworkspace"
DESTINATION="platform=$platform,name=$device,OS=$os"
SCHEME="IntegrationScenarios"
TEST_PLAN="$test_plan"

./tools/config/generate-http-server-mock-config.sh

disable_apple_crash_reporter
trap enable_apple_crash_reporter EXIT INT

xcodebuild -version
xcodebuild -workspace "$WORKSPACE" -destination "$DESTINATION" -scheme "$SCHEME" -testPlan "$TEST_PLAN" test | xcbeautify
