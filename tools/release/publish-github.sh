#!/bin/zsh

# Usage:
# $ ./tools/release/publish-github.sh -h
# Publishes GitHub assets to GH release.

# Options:
#   --tag: The tag to publish GitHub assets to.
#   --artifacts-path: Path to build artifacts.
#   --overwrite-existing: Overwrite existing GH assets.

# ENVs:
# - DRY_RUN: Set to '1' to do everything except publishing the GitHub assets.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh
source ./tools/secrets/get-secret.sh

set_description "Publishes GitHub assets to GH release."
define_arg "tag" "" "The tag to publish GitHub assets to." "string" "true"
define_arg "overwrite-existing" "false" "Overwrite existing GH assets." "store_true"
define_arg "artifacts-path" "" "Path to build artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

ARTIFACTS_PATH="$artifacts_path"
GH_ASSET_WITH_ARM64E="$ARTIFACTS_PATH/Datadog-with-arm64e.xcframework.zip"
GH_ASSET_WITHOUT_ARM64E="$ARTIFACTS_PATH/Datadog.xcframework.zip"
REPO_NAME="DataDog/dd-sdk-ios"

verify_gh_auth() {
    gh auth status &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo_err "Error:" "GitHub CLI is not authenticated."
        exit 1
    fi
}

upload() {
    echo_subtitle "Uploading assets to '$tag' release"
    local ghoptions=()
    if [ "$overwrite_existing" = "true" ]; then
        ghoptions+=(--clobber)
    fi

    if [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "true" ]; then
        echo_warn "DRY RUN mode:" "Skipping upload"
    else
        gh release upload "$tag" "$GH_ASSET_WITH_ARM64E" "$GH_ASSET_WITHOUT_ARM64E" \
            --repo "$REPO_NAME" ${ghoptions[@]}
        echo_succ "Uploaded successfully"
    fi
}

export GITHUB_TOKEN=$(dd-octo-sts --disable-tracing token --scope DataDog/dd-sdk-ios --policy self.release)
verify_gh_auth
upload
dd-octo-sts --disable-tracing revoke
