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
    # GitLab:
    echo "▸ GITLAB_CI = ${GITLAB_CI:-(not set or empty)}"
    echo "▸ CI_PROJECT_DIR = ${CI_PROJECT_DIR:-(not set or empty)}"
    echo "▸ CI_JOB_STAGE = ${CI_JOB_STAGE:-(not set or empty)}"
    echo "▸ CI_JOB_NAME = ${CI_JOB_NAME:-(not set or empty)}"
    echo "▸ CI_JOB_URL = ${CI_JOB_URL:-(not set or empty)}"
    echo "▸ CI_PIPELINE_ID = ${CI_PIPELINE_ID:-(not set or empty)}"
    echo "▸ CI_PIPELINE_IID = ${CI_PIPELINE_IID:-(not set or empty)}"
    echo "▸ CI_PIPELINE_URL = ${CI_PIPELINE_URL:-(not set or empty)}"
    echo "▸ CI_PROJECT_PATH = ${CI_PROJECT_PATH:-(not set or empty)}"
    echo "▸ CI_PROJECT_URL = ${CI_PROJECT_URL:-(not set or empty)}"
    echo "▸ CI_COMMIT_SHA = ${CI_COMMIT_SHA:-(not set or empty)}"
    echo "▸ CI_REPOSITORY_URL = ${CI_REPOSITORY_URL:-(not set or empty)}"
    echo "▸ CI_COMMIT_BRANCH = ${CI_COMMIT_BRANCH:-(not set or empty)}"
    echo "▸ CI_COMMIT_TAG = ${CI_COMMIT_TAG:-(not set or empty)}"
    echo "▸ CI_COMMIT_MESSAGE = ${CI_COMMIT_MESSAGE:-(not set or empty)}"
    echo "▸ CI_COMMIT_AUTHOR = ${CI_COMMIT_AUTHOR:-(not set or empty)}"
    echo "▸ CI_COMMIT_TIMESTAMP = ${CI_COMMIT_TIMESTAMP:-(not set or empty)}"
    # Custom:
    echo "▸ RELEASE_GIT_TAG = ${RELEASE_GIT_TAG:-(not set or empty)}"
    echo "▸ RELEASE_DRY_RUN = ${RELEASE_DRY_RUN:-(not set or empty)}"
fi
