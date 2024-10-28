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

    # Debugging:
    # - If `DD_TRACE_DEBUG` is enabled, the `dd-sdk-swift-testing` will print extra debug logs.
    export DD_TRACE_DEBUG=0

    # Git metadata:
    # - While `dd-sdk-swift-testing` can read Git metadata from `.git` folder, following info must be overwritten
    # due to our GH → GitLab mirroring configuration (otherwise it will point to GitLab mirror not GH repo).
    export DD_GIT_REPOSITORY_URL="git@github.com:DataDog/dd-sdk-ios.git"

    echo_info "CI Test Visibility setup:"
    echo "▸ DD_TEST_RUNNER=$DD_TEST_RUNNER"
    echo "▸ DD_API_KEY=$([[ -n "$DD_API_KEY" ]] && echo '***' || echo '')"
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
    echo "▸ DD_TRACE_DEBUG=$DD_TRACE_DEBUG"
    echo "▸ GITLAB_CI=$GITLAB_CI"
    echo "▸ CI_PROJECT_DIR=$CI_PROJECT_DIR"
    echo "▸ CI_JOB_STAGE=$CI_JOB_STAGE"
    echo "▸ CI_JOB_NAME=$CI_JOB_NAME"
    echo "▸ CI_JOB_URL=$CI_JOB_URL"
    echo "▸ CI_PIPELINE_ID=$CI_PIPELINE_ID"
    echo "▸ CI_PIPELINE_IID=$CI_PIPELINE_IID"
    echo "▸ CI_PIPELINE_URL=$CI_PIPELINE_URL"
    echo "▸ CI_PROJECT_PATH=$CI_PROJECT_PATH"
    echo "▸ CI_COMMIT_SHA=$CI_COMMIT_SHA"
    echo "▸ CI_COMMIT_BRANCH=$CI_COMMIT_BRANCH"
    echo "▸ CI_COMMIT_TAG=$CI_COMMIT_TAG"
    echo "▸ CI_COMMIT_MESSAGE=$CI_COMMIT_MESSAGE"
    echo "▸ CI_COMMIT_AUTHOR=$CI_COMMIT_AUTHOR"
    echo "▸ CI_COMMIT_TIMESTAMP=$CI_COMMIT_TIMESTAMP"
}

if [ "$USE_TEST_VISIBILITY" = "1" ]; then
    setup_test_visibility
fi

set -x

mkdir -p artifacts

rm -rf ~/Library/org.swift.swiftpm

xcodebuild -version
xcodebuild -workspace "$WORKSPACE" -destination "$DESTINATION" -scheme "$SCHEME" test | xcbeautify
xcodebuild -workspace "$WORKSPACE" -destination "$DESTINATION" -scheme "$SCHEME" test > artifacts/xcodebuild.log 2>&1
