#!/bin/zsh

# Usage:
# $ ./tools/env_check.sh
# Prints environment information and checks if required tools are installed.

set -e
source ./tools/utils/echo-color.sh

check_if_installed() {
    if ! command -v $1 >/dev/null 2>&1; then
        echo_err "Error" "$1 is not installed but it is required for development. Install it and try again."
        exit 1
    fi
}

echo_subtitle "Check versions of installed tools"

echo_succ "Git clone:"
echo_info "git rev-parse --abbrev-ref HEAD"
git rev-parse --abbrev-ref HEAD

echo "\n"
echo_info "git --no-pager branch -a:"
git --no-pager branch -a

echo "\n"
echo_info "export -p"
export -p

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
echo_succ "vault:"
check_if_installed vault
vault -v

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

if [ "$CI" = "true" ]; then
    echo ""
    echo_succ "npm:"
    check_if_installed npm
    npm --version

    echo ""
    echo_succ "datadog-ci:"
    check_if_installed datadog-ci
    datadog-ci version

    # Check if all secrets are available:
    ./tools/secrets/check-secrets.sh

    echo_subtitle "Print CI env"
    echo "▸ CI_COMMIT_TAG = ${CI_COMMIT_TAG:-(not set or empty)}"
    echo "▸ CI_COMMIT_BRANCH = ${CI_COMMIT_BRANCH:-(not set or empty)}"
    echo "▸ CI_COMMIT_SHA = ${CI_COMMIT_SHA:-(not set or empty)}"
    echo "▸ RELEASE_GIT_TAG = ${RELEASE_GIT_TAG:-(not set or empty)}"
    echo "▸ RELEASE_DRY_RUN = ${RELEASE_DRY_RUN:-(not set or empty)}"
fi

echo "done"
exit 1
