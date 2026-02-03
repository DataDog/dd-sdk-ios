#!/bin/zsh

# Usage:
# $ ./tools/release/remove-arm64e-from-release.sh -h
# Downloads XCFramework from GitHub release for the specified tag and removes arm64e slices.

# Options:
#   --tag: The tag to download and process.
#   --artifacts-path: Path to store artifacts.

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh

set_description "Downloads XCFramework from GitHub release for the specified tag and removes arm64e slices."
define_arg "tag" "" "The tag to download and process." "string" "true"
define_arg "artifacts-path" "" "Path to store artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

REPO_NAME="DataDog/dd-sdk-ios"
ASSET_NAME="Datadog.xcframework.zip"
ARTIFACTS_PATH="$artifacts_path"
ORIGINAL_OUTPUT="$ARTIFACTS_PATH/Datadog-with-arm64e.xcframework.zip"
FINAL_OUTPUT="$ARTIFACTS_PATH/Datadog.xcframework.zip"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Verifies that the GitHub CLI is authenticated and ready to use.
# Exits with error code 1 if authentication fails.
verify_gh_auth() {
    if ! gh auth status &>/dev/null; then
        echo_err "Error:" "GitHub CLI is not authenticated. Run 'gh auth login' first."
        exit 1
    fi
    echo_succ "Authenticated" "with GitHub CLI"
}

# Downloads the XCFramework asset from the specified GitHub release tag.
#
# This function downloads the Datadog.xcframework.zip asset from the release
# matching the provided tag in the DataDog/dd-sdk-ios repository.
# The original downloaded file is saved to the artifacts path as
# Datadog-with-arm64e.xcframework.zip.
#
# Exits with error code 1 if:
#   - The release tag does not exist
#   - The asset is not found in the release
#   - The download fails for any reason
download_xcframework() {
    echo "Downloading XCFramework from release"

    if ! gh release download "$tag" \
        --repo "$REPO_NAME" \
        --pattern "$ASSET_NAME" \
        --dir "$ARTIFACTS_PATH"; then
        echo_err "Error:" "Failed to download $ASSET_NAME from $tag"
        exit 1
    fi

    # Save original with arm64e
    mv "$ARTIFACTS_PATH/$ASSET_NAME" "$ORIGINAL_OUTPUT"
}

# Extracts, processes, and re-zips the XCFramework.
process_xcframework() {
    echo "Extracting XCFramework"
    local TEMP_DIR=$(mktemp -d)
    local XCF_DIR="$TEMP_DIR/Datadog.xcframework"

    unzip -q "$ORIGINAL_OUTPUT" -d "$TEMP_DIR"

    echo "Removing arm64e slices"
    "$SCRIPT_DIR/remove-arm64e-from-xcframework.sh" \
        --xcframework "$XCF_DIR"

    echo "Creating modified XCFramework archive"
    (cd "$TEMP_DIR" && zip -r -q "$(basename "$FINAL_OUTPUT")" "Datadog.xcframework")
    mv "$TEMP_DIR/$(basename "$FINAL_OUTPUT")" "$FINAL_OUTPUT"

    # Cleanup
    rm -rf "$TEMP_DIR"
}

# Prompts the user for confirmation before uploading artifacts.
#
# Returns:
#   0 if user confirms (y/Y)
#   1 if user declines (n/N)
confirm_upload() {
    echo ""
    echo_warn "WARNING:" "This will overwrite the existing XCFramework assets on the release!"
    echo ""
    echo_info "The following files will be uploaded to release '$tag':"
    echo "  - $(basename "$ORIGINAL_OUTPUT")"
    echo "  - $(basename "$FINAL_OUTPUT")"
    echo ""

    read "response?Do you want to proceed? (y/N): "

    case "$response" in
        [yY][eE][sS]|[yY])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Uploads both artifacts to the GitHub release, replacing existing assets.
upload_artifacts() {
    echo_subtitle "Uploading artifacts to GitHub release"

    # Upload original (with arm64e)
    echo_info "Uploading:" "$(basename "$ORIGINAL_OUTPUT")"
    if ! gh release upload "$tag" "$ORIGINAL_OUTPUT" \
        --repo "$REPO_NAME" \
        --clobber; then
        echo_err "Error:" "Failed to upload $(basename "$ORIGINAL_OUTPUT")"
        exit 1
    fi

    # Upload modified (without arm64e)
    echo_info "Uploading:" "$(basename "$FINAL_OUTPUT")"
    if ! gh release upload "$tag" "$FINAL_OUTPUT" \
        --repo "$REPO_NAME" \
        --clobber; then
        echo_err "Error:" "Failed to upload $(basename "$FINAL_OUTPUT")"
        exit 1
    fi

    echo_succ "Uploaded both artifacts successfully"
}

# Displays success message with artifact locations.
show_completion_message() {
echo ""
echo_title "Success!"
echo_succ "Artifacts created in:" "$ARTIFACTS_PATH"
echo ""
echo_info "Original (with arm64e):" "$(basename "$ORIGINAL_OUTPUT")"
echo_info "Modified (without arm64e):" "$(basename "$FINAL_OUTPUT")"
echo ""
echo_succ "Both artifacts uploaded to release:" "$tag"
}

echo_title "Removing arm64e from XCFramework Release"
echo_info "Tag:" "$tag"
echo_info "Artifacts path:" "$ARTIFACTS_PATH"
echo ""

# Create artifacts directory if it doesn't exist
mkdir -p "$ARTIFACTS_PATH"

verify_gh_auth
download_xcframework
echo ""
process_xcframework

# Ask for confirmation before uploading
if confirm_upload; then
    upload_artifacts
    echo_title "Success!"
    echo_succ "Artifacts created in:" "$ARTIFACTS_PATH"
    echo_info "Original (with arm64e):" "$(basename "$ORIGINAL_OUTPUT")"
    echo_info "Modified (without arm64e):" "$(basename "$FINAL_OUTPUT")"
    echo_succ "Both artifacts uploaded to release:" "$tag"
else
    echo_warn "Upload cancelled." "Artifacts are available in $ARTIFACTS_PATH"
    echo_info "Original (with arm64e):" "$(basename "$ORIGINAL_OUTPUT")"
    echo_info "Modified (without arm64e):" "$(basename "$FINAL_OUTPUT")"
fi
