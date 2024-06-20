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

set -x

xcodebuild -version
xcodebuild -workspace "$WORKSPACE" -destination "$DESTINATION" -scheme "$SCHEME" test | xcbeautify
