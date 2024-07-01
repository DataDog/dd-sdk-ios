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
XCFRAMEWORKS_OUTPUT_PATH="$artifacts_path/xcframeworks"
XCFRAMEWORKS_ZIP_NAME="Datadog.xcframework.zip"
XCFRAMEWORKS_ZIP_PATH="$artifacts_path/$XCFRAMEWORKS_ZIP_NAME"

# Clone a fresh version of the repo to artifacts path. This is to ensure that distribution tool
# from current repo will operate on a clean version of the repo not altered by any configuration changes.
echo_subtitle "Cloning repo for '$tag' into '$artifacts_path'"
git clone --depth 1 --branch $tag --single-branch git@github.com:DataDog/dd-sdk-ios.git $REPO_CLONE_PATH

# Build XCFrameworks using distribution tools from current repo.
echo_subtitle "Creating XCFrameworks for '$tag' in '$XCFRAMEWORKS_OUTPUT_PATH'"
./tools/release/build-xcframeworks.sh --repo-path "$REPO_CLONE_PATH" \
    --ios --tvos \
    --output-path $XCFRAMEWORKS_OUTPUT_PATH

# Zip XCFrameworks
echo_subtitle "Creating '$XCFRAMEWORKS_ZIP_PATH' for '$tag'"
DIR=$(pwd)
cd $XCFRAMEWORKS_OUTPUT_PATH && zip -q --symlinks -r $XCFRAMEWORKS_ZIP_NAME *.xcframework
cd $DIR
mv -v "$XCFRAMEWORKS_OUTPUT_PATH/$XCFRAMEWORKS_ZIP_NAME" "$XCFRAMEWORKS_ZIP_PATH"
rm -rf $XCFRAMEWORKS_OUTPUT_PATH

echo_succ "Artifacts are ready in '$artifacts_path':"
ls $artifacts_path
