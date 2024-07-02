#!/bin/zsh

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo_color.sh

set_description "Validates SDK and podspec versions."
define_arg "tag" "" "Specifies the tag to validate versions." "string" "true"
define_arg "artifacts-path" "" "Path to build artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

REPO_PATH="$artifacts_path/dd-sdk-ios"
SDK_VERSION_FILE="$REPO_PATH/DatadogCore/Sources/Versioning.swift"

# Check if SDK version matches the tag
echo_subtitle "Check 'sdk_version'"
sdk_version=$(grep '__sdkVersion' $SDK_VERSION_FILE | awk -F '"' '{print $2}')
if [[ "$sdk_version" == "$tag" ]]; then
    echo_succ "▸ SDK version in '$SDK_VERSION_FILE' ('$sdk_version') matches the tag '$tag'"
else
    echo_err "▸ Error:" "SDK version in '$SDK_VERSION_FILE' ('$sdk_version') does not match tag '$tag'"
    exit 1
fi

# Check if podspec versions do match the tag
echo_subtitle "Check podspec versions in '$REPO_PATH/*.podspec'"
for podspec_file in $(find $REPO_PATH -type f -name "*.podspec" -maxdepth 1); do
    spec_name=$(basename "$podspec_file")
    spec_version=$(grep -E '^\s*s\.version\s*=' $podspec_file | awk -F '"' '{print $2}')
  
    if [[ "$spec_version" == "$tag" ]]; then
        echo_succ "▸ '$spec_name' version ('$spec_version') matches the tag '$tag'"
    else
        echo_err "▸ Error:" "'$spec_name' version ('$spec_version') does not match tag '$tag'"
        exit 1
    fi
done
