#!/bin/zsh

# Usage:
# $ ./tools/test.sh -h
# Executes unit tests for a specified --scheme, using the provided --os, --platform, and --device.

# Options:
#   --device: Specifies the simulator device for running tests, e.g. 'iPhone 15 Pro'
#   --scheme: Identifies the test scheme to execute
#   --platform: Defines the type of simulator platform for the tests, e.g. 'iOS Simulator'
#   --os: Sets the operating system version for the tests, e.g. '17.5'

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh
source ./tools/utils/current-git.sh
source ./tools/secrets/get-secret.sh

set_description "Executes unit tests for a specified --scheme, using the provided --os, --platform, and --device."
define_arg "scheme" "" "Identifies the test scheme to execute" "string" "true"
define_arg "os" "" "Sets the operating system version for the tests, e.g. '17.5'" "string" "true"
define_arg "platform" "" "Defines the type of simulator platform for the tests, e.g. 'iOS Simulator'" "string" "true"
define_arg "device" "" "Specifies the simulator device for running tests, e.g. 'iPhone 15 Pro'" "string" "true"

check_for_help "$@"
parse_args "$@"

WORKSPACE="Datadog.xcworkspace"
DESTINATION="platform=$platform,name=$device,OS=$os"
SCHEME=$scheme

# Enables Datadog Test Visibility to trace tests execution
# Ref.: https://docs.datadoghq.com/tests/setup/swift/
setup_test_visibility() {
    export DD_TEST_RUNNER=1

    # Base:
    export DD_API_KEY=$(get_secret $DD_IOS_SECRET__TEST_VISIBILITY_API_KEY)
    export DD_ENV=$([[ "$CI" = "true" ]] && echo "ci" || echo "local")
    export DD_SERVICE=dd-sdk-ios
    export SRCROOT="$\(SRCROOT\)"

    # Auto-instrumentation:
    export DD_ENABLE_STDOUT_INSTRUMENTATION=0
    export DD_ENABLE_STDERR_INSTRUMENTATION=0
    export DD_DISABLE_NETWORK_INSTRUMENTATION=1
    export DD_DISABLE_RUM_INTEGRATION=1
    export DD_DISABLE_SOURCE_LOCATION=0
    export DD_DISABLE_CRASH_HANDLER=0

    # Git metadata:
    # - While `dd-sdk-swift-testing` can read Git metadata from `.git` folder, following info must be overwritten
    # due to our GH → GitLab mirroring configuration.
    export DD_GIT_REPOSITORY_URL="git@github.com:DataDog/dd-sdk-ios.git"
    export DD_GIT_BRANCH=$(current_git_branch)
    export DD_GIT_TAG=$(current_git_tag)

    echo_info "CI Test Visibility setup:"
    echo "▸ DD_TEST_RUNNER=$DD_TEST_RUNNER"
    echo "▸ DD_ENV=$DD_ENV"
    echo "▸ DD_SERVICE=$DD_SERVICE"
    echo "▸ SRCROOT=$SRCROOT"
    echo "▸ DD_ENABLE_STDOUT_INSTRUMENTATION=$DD_ENABLE_STDOUT_INSTRUMENTATION"
    echo "▸ DD_ENABLE_STDERR_INSTRUMENTATION=$DD_ENABLE_STDERR_INSTRUMENTATION"
    echo "▸ DD_DISABLE_NETWORK_INSTRUMENTATION=$DD_DISABLE_NETWORK_INSTRUMENTATION"
    echo "▸ DD_DISABLE_RUM_INTEGRATION=$DD_DISABLE_RUM_INTEGRATION"
    echo "▸ DD_DISABLE_SOURCE_LOCATION=$DD_DISABLE_SOURCE_LOCATION"
    echo "▸ DD_DISABLE_CRASH_HANDLER=$DD_DISABLE_CRASH_HANDLER"
    echo "▸ DD_GIT_REPOSITORY_URL=$DD_GIT_REPOSITORY_URL"
    echo "▸ DD_GIT_BRANCH=$DD_GIT_BRANCH"
    echo "▸ DD_GIT_TAG=$DD_GIT_TAG"
}

if [ "$USE_TEST_VISIBILITY" = "1" ]; then
    setup_test_visibility
fi

set -x

xcodebuild -version
xcodebuild -workspace "$WORKSPACE" -destination "$DESTINATION" -scheme "$SCHEME" test | xcbeautify
