#!/bin/zsh

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo_color.sh

set_description "Builds artifacts for specified tag."
define_arg "tag" "" "Specifies the tag to release." "string" "true"
define_arg "artifacts-path" "" "Path to store artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

rm -rf "$artifacts_path"
mkdir -p "$artifacts_path"

REPO_CLONE_PATH="$artifacts_path/dd-sdk-ios"
XCF_DIR_NAME="Datadog.xcframework"
XCF_ZIP_NAME="Datadog.xcframework.zip"

# Clone a fresh version of the repo to artifacts path. This is to ensure that distribution tool
# from current repo will operate on a clean version of the repo not altered by any configuration changes:
echo_subtitle "Cloning repo for '$tag' into '$artifacts_path'"
git clone --depth 1 --branch $tag --single-branch git@github.com:DataDog/dd-sdk-ios.git $REPO_CLONE_PATH

# Build xcframeworks using distribution tools from current repo:
echo_subtitle "Creating '$XCF_DIR_NAME' in '$artifacts_path'"
./tools/release/build-xcframeworks.sh --repo-path "$REPO_CLONE_PATH" \
    --ios --tvos \
    --output-path "$artifacts_path/$XCF_DIR_NAME"

echo_info "Contents of '$artifacts_path/$XCF_DIR_NAME':"
ls $artifacts_path/$XCF_DIR_NAME

# Create zip archive:
echo_subtitle "Creating '$XCF_ZIP_NAME' in '$artifacts_path'"
cd "$artifacts_path" && zip -r -q $XCF_ZIP_NAME $XCF_DIR_NAME
cd -

# Cleanup:
rm -rf "$artifacts_path/$XCF_DIR_NAME"

echo_succ "Success. Artifacts ready in '$artifacts_path':"
ls $artifacts_path
