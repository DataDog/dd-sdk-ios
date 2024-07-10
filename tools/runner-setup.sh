#!/bin/zsh

# Usage:
# $ ./tools/runner-setup.sh -h
# This script is for TEMPORARY. It supplements missing components on the runner. It will be removed once all configurations are integrated into the AMI.

# Options:
#   --xcode: Sets the Xcode version on the runner.
#   --iOS: Flag that prepares the runner instance for iOS testing. Disabled by default.
#   --tvOS: Flag that prepares the runner instance for tvOS testing. Disabled by default.
#   --visionOS: Flag that prepares the runner instance for visionOS testing. Disabled by default.
#   --os: Sets the expected OS version for installed simulators when --iOS, --tvOS or --visionOS flag is set. Default: '17.4'.
#   --ssh: Flag that adds ssh configuration for interacting with GitHub repositories. Disabled by default.

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh
source ./tools/secrets/get-secret.sh

set_description "This script is for TEMPORARY. It supplements missing components on the runner. It will be removed once all configurations are integrated into the AMI."
define_arg "xcode" "" "Sets the Xcode version on the runner." "string" "false"
define_arg "iOS" "false" "Flag that prepares the runner instance for iOS testing. Disabled by default." "store_true"
define_arg "tvOS" "false" "Flag that prepares the runner instance for tvOS testing. Disabled by default." "store_true"
define_arg "visionOS" "false" "Flag that prepares the runner instance for visionOS testing. Disabled by default." "store_true"
define_arg "os" "17.4" "Sets the expected OS version for installed simulators when --iOS, --tvOS or --visionOS flag is set. Default: '17.4'." "string" "false"
define_arg "ssh" "false" "Flag that adds ssh configuration for interacting with GitHub repositories. Disabled by default." "store_true"

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

if [ "$iOS" = "true" ]; then
    echo_subtitle "Supply iPhone Simulator runtime ($os)"
    echo "Check current runner for any iPhone Simulator runtime supporting OS '$os':"
    if ! xctrace list devices | grep "iPhone.*Simulator ($os)"; then
        echo_warn "Found no iOS Simulator runtime supporting OS '$os'. Installing..."
        xcodebuild -downloadPlatform iOS -quiet | xcbeautify
    else
        echo_succ "Found some iOS Simulator runtime supporting OS '$os'. Skipping..."
    fi
fi

if [ "$tvOS" = "true" ]; then
    echo_subtitle "Supply tvOS Simulator runtime ($os)"
    echo "Check current runner for any tvOS Simulator runtime supporting OS '$os':"
    if ! xctrace list devices | grep "Apple TV.*Simulator ($os)"; then
        echo_warn "Found no tvOS Simulator runtime supporting OS '$os'. Installing..."
        xcodebuild -downloadPlatform tvOS -quiet | xcbeautify
    else
        echo_succ "Found some tvOS Simulator runtime supporting OS '$os'. Skipping..."
    fi
fi

if [ "$visionOS" = "true" ]; then
    echo_subtitle "Supply visionOS Simulator runtime ($os)"
    echo "Check current runner for any visionOS Simulator runtime supporting OS '$os':"
    if ! xctrace list devices | grep "Apple Vision.*($os)"; then
        echo_warn "Found no visionOS Simulator runtime supporting OS '$os'. Installing..."
        xcodebuild -downloadPlatform visionOS -quiet | xcbeautify
    else
        echo_succ "Found some visionOS Simulator runtime supporting OS '$os'. Skipping..."
    fi
fi

if [ "$ssh" = "true" ]; then
    # Adds SSH config, so we can git clone GH repos.
    echo_subtitle "Add SSH configuration"
    SSH_KEY_PATH="$HOME/.ssh/id_ed25519"
    SSH_CONFIG_PATH="$HOME/.ssh/config"

    if [ ! -f "$SSH_KEY_PATH" ] || [ ! -f "$SSH_CONFIG_PATH" ]; then
        echo_warn "Found no SSH key or SSH config file. Configuring..."
        get_secret $DD_IOS_SECRET__SSH_KEY > $SSH_KEY_PATH
        chmod 600 "$SSH_KEY_PATH"

        cat <<EOF > "$HOME/.ssh/config"
Host github.com
    HostName github.com
    User git
    IdentityFile $SSH_KEY_PATH
    StrictHostKeyChecking no
EOF
        echo_succ "Finished SSH setup."
    else
        echo_succ "Found both SSH key and SSH config file. Skipping..."
    fi
fi
