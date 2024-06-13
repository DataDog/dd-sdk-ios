#!/bin/zsh

# Usage:
# $ ./tools/runner-setup.sh -h
# This script is for TEMPORARY. It supplements missing components on the runner. It will be removed once all configurations are integrated into the AMI.

# Options:
#   --ios: Flag that prepares the runner instance for iOS testing. Disabled by default.
#   --tvos: Flag that prepares the runner instance for tvOS testing. Disabled by default.

source ./tools/utils/echo_color.sh
source ./tools/utils/argparse.sh

set_description "This script is for TEMPORARY. It supplements missing components on the runner. It will be removed once all configurations are integrated into the AMI."
define_arg "ios" "false" "Flag that prepares the runner instance for iOS testing. Disabled by default." "store_true"
define_arg "tvos" "false" "Flag that prepares the runner instance for tvOS testing. Disabled by default." "store_true"

check_for_help "$@"
parse_args "$@"

set -eo pipefail

xcodebuild -version

if [ "$ios" = "true" ]; then
    echo "Check current runner for any iPhone Simulator runtime supporting OS 17.x."
    if ! xcodebuild -workspace "Datadog.xcworkspace" -scheme "DatadogCore iOS" -showdestinations -quiet | grep -q 'platform:iOS Simulator.*OS:17'; then
        echo_warn "Found no iOS Simulator runtime supporting OS 17.x. Installing..."
        # xcodebuild -downloadPlatform iOS -quiet | xcbeautify
    else
        echo_succ "Found some iOS Simulator runtime supporting OS 17.x. Skipping..."
    fi
fi

if [ "$tvos" = "true" ]; then
    echo "Check current runner for any tvOS Simulator runtime supporting OS 17.x."
    if ! xcodebuild -workspace "Datadog.xcworkspace" -scheme "DatadogCore tvOS" -showdestinations -quiet | grep -q 'platform:tvOS Simulator.*OS:17'; then
        echo_warn "Found no tvOS Simulator runtime supporting OS 17.x. Installing..."
        # xcodebuild -downloadPlatform tvOS -quiet | xcbeautify
    else
        echo_succ "Found some tvOS Simulator runtime supporting OS 17.x. Skipping..."
    fi
fi
