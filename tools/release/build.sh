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
XCFRAMEWORKS_OUTPUT_PATH="$artifacts_path"

echo_subtitle "Building artifacts for '$tag' in '$artifacts_path'"
git clone --depth 1 --branch $tag --single-branch git@github.com:DataDog/dd-sdk-ios.git $REPO_CLONE_PATH
./tools/release/build-xcframeworks.sh --repo-path "$REPO_CLONE_PATH" --ios --tvos --output-path $XCFRAMEWORKS_OUTPUT_PATH
echo_succ "Artifacts are ready in '$artifacts_path':"
ls $artifacts_path
