#!/bin/zsh

# Usage:
# ./tools/env_check.sh
# Prints environment information and checks if required tools are installed.

set -e
source ./tools/utils/echo_color.sh

check_if_installed() {
  if ! command -v $1 >/dev/null 2>&1; then
    echo_err "Error" "$1 is not installed but it is required for development. Install it and try again."
    exit 1
  fi
}

echo_succ "System info:"
system_profiler SPSoftwareDataType

echo ""
echo_succ "Active Xcode:"
check_if_installed xcodebuild
xcode-select -p
xcodebuild -version

echo ""
echo_succ "Other Xcodes:"
ls /Applications/ | grep Xcode

echo ""
echo_succ "xcbeautify:"
check_if_installed xcbeautify
xcbeautify --version

echo ""
echo_succ "swiftlint:"
check_if_installed swiftlint
swiftlint --version

echo ""
echo_succ "carthage:"
check_if_installed carthage
carthage version

echo ""
echo_succ "gh:"
check_if_installed gh
gh --version

echo ""
echo_succ "bundler:"
check_if_installed bundler
bundler --version

echo ""
echo_succ "python3:"
check_if_installed python3
python3 -V

echo ""
echo_succ "Available iOS Simulators:"
xctrace list devices | grep "iPhone.*Simulator" || true

echo ""
echo_succ "Available tvOS Simulators:"
xctrace list devices | grep "Apple TV.*Simulator" || true

if command -v brew >/dev/null 2>&1; then
    echo ""
    echo_succ "brew:"
    brew -v
fi
