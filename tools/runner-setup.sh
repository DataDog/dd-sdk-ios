#!/bin/zsh

# Usage:
# $ ./tools/runner-setup.sh -h
# This script supplements missing components on the runner before they are included through the AMI.

# Options:
#   --xcode: Specify the Xcode version to activate.
#   --iOS: Install the iOS platform with the latest simulator if not already installed. Default: disabled.
#   --tvOS: Install the tvOS platform with the latest simulator if not already installed. Default: disabled.
#   --visionOS: Install the visionOS platform with the latest simulator if not already installed. Default: disabled.
#   --watchOS: Install the watchOS platform with the latest simulator if not already installed. Default: disabled.
#   --ssh: Configure SSH for GitHub repository access. Default: disabled.
#   --datadog-ci: Install 'datadog-ci' on the runner. Default: disabled.

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh
source ./tools/secrets/get-secret.sh

set_description "This script supplements missing components on the runner before they are included through the AMI."
define_arg "xcode" "" "Specify the Xcode version to activate." "string" "false"
define_arg "iOS" "false" "Install the iOS platform with the latest simulator if not already installed. Default: disabled." "store_true"
define_arg "tvOS" "false" "Install the tvOS platform with the latest simulator if not already installed. Default: disabled." "store_true"
define_arg "visionOS" "false" "Install the visionOS platform with the latest simulator if not already installed. Default: disabled." "store_true"
define_arg "watchOS" "false" "Install the watchOS platform with the latest simulator if not already installed. Default: disabled." "store_true"
define_arg "ssh" "false" "Configure SSH for GitHub repository access. Default: disabled." "store_true"
define_arg "datadog-ci" "false" "Install 'datadog-ci' on the runner. Default: disabled." "store_true"

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
    echo_subtitle "Install iOS platform"
    echo "▸ xcodebuild -downloadPlatform iOS -quiet"
    xcodebuild -downloadPlatform iOS -quiet
fi

if [ "$tvOS" = "true" ]; then
    echo_subtitle "Install tvOS platform"
    echo "▸ xcodebuild -downloadPlatform tvOS -quiet"
    xcodebuild -downloadPlatform tvOS -quiet
fi

if [ "$visionOS" = "true" ]; then
    echo_subtitle "Install visionOS platform"
    echo "▸ xcodebuild -downloadPlatform visionOS -quiet"
    xcodebuild -downloadPlatform visionOS -quiet
fi

if [ "$watchOS" = "true" ]; then
    echo_subtitle "Install watchOS platform"
    echo "▸ xcodebuild -downloadPlatform watchOS -quiet"
    xcodebuild -downloadPlatform watchOS -quiet
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

if [ "$datadog_ci" = "true" ]; then
    echo_subtitle "Supply datadog-ci"
    echo "Check current runner for existing 'datadog-ci' installation:"
    if ! command -v datadog-ci >/dev/null 2>&1; then
        echo_warn "Found no 'datadog-ci'. Installing..."
        npm install -g @datadog/datadog-ci
    else
        echo_succ "'datadog-ci' already installed. Skipping..."
        echo "datadog-ci version:"
        datadog-ci version
    fi
fi
