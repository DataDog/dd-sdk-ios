#!/bin/zsh

# Usage:
# $ ./tools/release/build.sh -h
# Builds artifacts for specified tag.

# Options:
#   --tag: The tag to release.
#   --artifacts-path: Path to store artifacts.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh

set_description "Builds artifacts for specified tag."
define_arg "tag" "" "The tag to release." "string" "true" 
define_arg "artifacts-path" "" "Path to store artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

ARTIFACTS_PATH="$artifacts_path"
REPO_CLONE_PATH="$ARTIFACTS_PATH/dd-sdk-ios"
XCF_DIR_NAME="Datadog.xcframework"
XCF_ZIP_NAME="Datadog.xcframework.zip"

# Clone a fresh version of the repo to the artifacts path to ensure that release tools
# operate on a clean version of the repo, unaltered by any configuration changes.
clone_repo () {
    echo_subtitle "Clone repo for '$tag' into '$ARTIFACTS_PATH'"
    git clone --depth 1 --branch $tag --single-branch git@github.com:DataDog/dd-sdk-ios.git $REPO_CLONE_PATH
}

# Create XCFrameworks for the repo clone using release tools from the current repo.
create_xcframeworks () {
    echo_subtitle "Create '$XCF_DIR_NAME' in '$ARTIFACTS_PATH'"
    ./tools/release/build-xcframeworks.sh --repo-path "$REPO_CLONE_PATH" \
        --ios --tvos \
        --output-path "$ARTIFACTS_PATH/$XCF_DIR_NAME"

    echo_info "Contents of '$ARTIFACTS_PATH/$XCF_DIR_NAME':"
    ls $ARTIFACTS_PATH/$XCF_DIR_NAME
}

create_zip_archive () {
    echo_subtitle "Create '$XCF_ZIP_NAME' in '$ARTIFACTS_PATH'"
    cd "$ARTIFACTS_PATH" && zip -r -q $XCF_ZIP_NAME $XCF_DIR_NAME
    cd -
}

rm -rf "$ARTIFACTS_PATH"
mkdir -p "$ARTIFACTS_PATH"

clone_repo
create_xcframeworks
create_zip_archive

# Cleanup:
rm -rf "$ARTIFACTS_PATH/$XCF_DIR_NAME"

echo_succ "Success. Artifacts ready in '$ARTIFACTS_PATH':"
ls -lh $ARTIFACTS_PATH
