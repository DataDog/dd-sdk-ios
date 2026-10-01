#!/bin/zsh

# Usage:
# $ ./tools/release/validate-version.sh -h
# Validates the SDK version against the release tag.

# Options:
#   --tag: The tag to validate versions.
#   --artifacts-path: The path to build artifacts.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh

set_description "Validates the SDK version against the release tag."
define_arg "tag" "" "The tag to validate versions." "string" "true"
define_arg "artifacts-path" "" "The path to build artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

REPO_PATH="$artifacts_path/dd-sdk-ios"
SDK_VERSION_FILE="$REPO_PATH/DatadogCore/Sources/Versioning.swift"

check_sdk_version () {
    echo_subtitle "Check 'sdk_version'"
    sdk_version=$(grep '__sdkVersion' $SDK_VERSION_FILE | awk -F '"' '{print $2}')
    if [[ "$sdk_version" == "$tag" ]]; then
        echo_succ "▸ SDK version in '$SDK_VERSION_FILE' ('$sdk_version') matches the tag '$tag'"
    else
        echo_err "▸ Error:" "SDK version in '$SDK_VERSION_FILE' ('$sdk_version') does not match tag '$tag'"
        exit 1
    fi
}

check_sdk_version
