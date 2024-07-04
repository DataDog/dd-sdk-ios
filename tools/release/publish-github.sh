#!/bin/zsh

# Usage:
# $ ./tools/release/publish-github.sh -h
# Publishes GitHub asset to GH release.

# Options:
#   --tag: The tag to publish GitHub asset to.
#   --artifacts-path: Path to build artifacts.
#   --overwrite-existing: Overwrite existing GH asset.
#   --dry-run: Do everything except publishing the GitHub asset.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh
source ./tools/secrets/get-secret.sh

set_description "Publishes GitHub asset to GH release."
define_arg "tag" "" "The tag to publish GitHub asset to." "string" "true"
define_arg "overwrite-existing" "false" "Overwrite existing GH asset." "store_true"
define_arg "dry-run" "false" "Do everything except publishing the GitHub asset." "store_true"
define_arg "artifacts-path" "" "Path to build artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

GH_ASSET_PATH="$artifacts_path/Datadog.xcframework.zip"
REPO_NAME="DataDog/dd-sdk-ios"

authenticate() {
    echo_subtitle "Authenticate 'gh' CLI"
    echo_info "Exporting 'GITHUB_TOKEN' for CI"
    export GITHUB_TOKEN=$(get_secret $DD_IOS_SECRET__GH_CLI_TOKEN)
    echo_info "▸ gh auth status"
    gh auth status
    if [[ $? -ne 0 ]]; then
        echo_err "Error:" "GitHub CLI is not authenticated."
        exit 1
    fi
}

upload() {
    echo_subtitle "Upload GH asset to '$tag' release"
    ghoptions=()
    if [ "$OVERWRITE_EXISTING" = "1" ] || [ "$OVERWRITE_EXISTING" = "true" ]; then
        ghoptions+=(--clobber)
    fi

    echo_info "▸ gh release upload $tag '$GH_ASSET_PATH' --repo '$REPO_NAME' ${ghoptions[@]}"
    if [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "true" ]; then
        echo_warn "Running in DRY RUN mode. Skipping."
    else
        gh release upload $tag "$GH_ASSET_PATH" --repo "$REPO_NAME" ${ghoptions[@]}
    fi
}

echo_info "Publishing '$GH_ASSET_PATH' to '$tag' release in '$REPO_NAME'"
echo "▸ Using DRY_RUN = $DRY_RUN"
echo "▸ Using OVERWRITE_EXISTING = $OVERWRITE_EXISTING"

authenticate
upload
