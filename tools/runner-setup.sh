#!/bin/zsh

# Usage:
# $ ./tools/runner-setup.sh -h
# This script is for TEMPORARY. It supplements missing components on the runner. It will be removed once all configurations are integrated into the AMI.

# Options:
#   --xcode: Sets the Xcode version on the runner.
#   --ios: Flag that prepares the runner instance for iOS testing. Disabled by default.
#   --tvos: Flag that prepares the runner instance for tvOS testing. Disabled by default.
#   --os: Sets the expected OS version for installed simulators when --ios or --tvos flag is set. Default: '17.4'.

set -eo pipefail
source ./tools/utils/echo_color.sh
source ./tools/utils/argparse.sh

set_description "This script is for TEMPORARY. It supplements missing components on the runner. It will be removed once all configurations are integrated into the AMI."
define_arg "xcode" "" "Sets the Xcode version on the runner." "string" "false"
define_arg "ios" "false" "Flag that prepares the runner instance for iOS testing. Disabled by default." "store_true"
define_arg "tvos" "false" "Flag that prepares the runner instance for tvOS testing. Disabled by default." "store_true"
define_arg "os" "17.4" "Sets the expected OS version for installed simulators when --ios or --tvos flag is set. Default: '17.4'." "string" "false"

check_for_help "$@"
parse_args "$@"

change_xcode_version() {
    local version="$1"

    echo_subtitle "Change Xcode version to: '$version'"
    local XCODE_PATH="/Applications/Xcode-$version.app/Contents/Developer"
    local CURRENT_XCODE_PATH=$(xcode-select -p)

    if [[ "$CURRENT_XCODE_PATH" == "$XCODE_PATH" ]]; then
        echo_succ "Already using Xcode version '$version'."
    elif [[ -d "$XCODE_PATH" ]]; then
        echo "Found Xcode at '$XCODE_PATH'."
        if sudo xcode-select -s "$XCODE_PATH"; then
            echo_succ "Switched to Xcode version '$version'."
        else
            echo_err "Failed to switch to Xcode version '$version'."
            exit 1
        fi
    else
        echo_err "Xcode version '$version' not found at $XCODE_PATH."
        echo "Available Xcode versions:"
        ls /Applications/ | grep Xcode
        exit 1
    fi

    if sudo xcodebuild -license accept; then
        echo_succ "Xcode license accepted."
    else
        echo_err "Failed to accept the Xcode license."
        exit 1
    fi

    if sudo xcodebuild -runFirstLaunch; then
        echo_succ "Installed Xcode packages."
    else
        echo_err "Failed to install Xcode packages."
        exit 1
    fi
}

if [[ -n "$xcode" ]]; then
    change_xcode_version $xcode
fi

echo_succ "Using 'xcodebuild -version':"
xcodebuild -version

if [ "$ios" = "true" ]; then
    echo_subtitle "Supply iPhone Simulator runtime ($os)"
    echo "Check current runner for any iPhone Simulator runtime supporting OS '$os'."
    if ! xctrace list devices | grep "iPhone.*Simulator ($os)"; then
        echo_warn "Found no iOS Simulator runtime supporting OS '$os'. Installing..."
        xcodebuild -downloadPlatform iOS -quiet | xcbeautify
    else
        echo_succ "Found some iOS Simulator runtime supporting OS '$os'. Skipping..."
    fi
fi

if [ "$tvos" = "true" ]; then
    echo_subtitle "Supply tvOS Simulator runtime ($os)"
    echo "Check current runner for any tvOS Simulator runtime supporting OS '$os'."
    if ! xctrace list devices | grep "Apple TV.*Simulator ($os)"; then
        echo_warn "Found no tvOS Simulator runtime supporting OS '$os'. Installing..."
        xcodebuild -downloadPlatform tvOS -quiet | xcbeautify
    else
        echo_succ "Found some tvOS Simulator runtime supporting OS '$os'. Skipping..."
    fi
fi
