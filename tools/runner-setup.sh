#!/bin/zsh

# Usage:
# $ ./tools/runner-setup.sh -h
# This script is for TEMPORARY. It supplements missing components on the runner. It will be removed once all configurations are integrated into the AMI.

# Options:
#   --ios: Flag that prepares the runner instance for iOS testing. Disabled by default.
#   --tvos: Flag that prepares the runner instance for tvOS testing. Disabled by default.
#   --os: Sets the expected OS version for installed simulators. Default: '17.4'.

set -eo pipefail
source ./tools/utils/echo_color.sh
source ./tools/utils/argparse.sh

set_description "This script is for TEMPORARY. It supplements missing components on the runner. It will be removed once all configurations are integrated into the AMI."
define_arg "ios" "false" "Flag that prepares the runner instance for iOS testing. Disabled by default." "store_true"
define_arg "tvos" "false" "Flag that prepares the runner instance for tvOS testing. Disabled by default." "store_true"
define_arg "os" "17.4" "Sets the expected OS version for installed simulators. Default: '17.4'." "string" "false"

check_for_help "$@"
parse_args "$@"

xcodebuild -version

if [ "$ios" = "true" ]; then
    echo "Check current runner for any iPhone Simulator runtime supporting OS '$os'."
    if ! xctrace list devices | grep "iPhone.*Simulator ($os)"; then
        echo_warn "Found no iOS Simulator runtime supporting OS '$os'. Installing..."
        xcodebuild -downloadPlatform iOS -quiet | xcbeautify
    else
        echo_succ "Found some iOS Simulator runtime supporting OS '$os'. Skipping..."
    fi
fi

if [ "$tvos" = "true" ]; then
    echo "Check current runner for any tvOS Simulator runtime supporting OS '$os'."
    if ! xctrace list devices | grep "Apple TV.*Simulator ($os)"; then
        echo_warn "Found no tvOS Simulator runtime supporting OS '$os'. Installing..."
        xcodebuild -downloadPlatform tvOS -quiet | xcbeautify
    else
        echo_succ "Found some tvOS Simulator runtime supporting OS '$os'. Skipping..."
    fi
fi
