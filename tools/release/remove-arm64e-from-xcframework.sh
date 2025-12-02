#!/bin/zsh

# Usage:
# $ ./tools/release/remove-arm64e-from-xcframework.sh -h
# Removes arm64e slices from all framework binaries within an XCFramework.

# Options:
#   --xcframework: Path to the XCFramework directory to process.

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh

set_description "Removes arm64e slices from all framework binaries within an XCFramework."
define_arg "xcframework" "" "Path to the XCFramework directory to process." "string" "true"

check_for_help "$@"
parse_args "$@"

XCFRAMEWORK_DIR="$xcframework"

# Validates that the XCFramework directory exists.
#
# Exits with error code 1 if the directory does not exist.
validate_xcframework() {
    if [ ! -d "$XCFRAMEWORK_DIR" ]; then
        echo_err "Error:" "XCFramework not found at $XCFRAMEWORK_DIR"
        exit 1
    fi
}

# Removes the arm64e architecture slice from a single framework binary.
#
# Arguments:
#   $1 - Path to the framework binary
remove_arm64e_from_binary() {
    local BINARY_PATH="$1"
    local TEMP_OUTPUT=$(mktemp)

    # Remove arm64e slice
    lipo -remove arm64e "$BINARY_PATH" -o "$TEMP_OUTPUT"

    # Replace original with modified binary
    mv "$TEMP_OUTPUT" "$BINARY_PATH"
}

# Processes all framework binaries within the XCFramework.
#
# This function finds all .framework bundles in the XCFramework and removes
# the arm64e architecture slice from each binary that contains it.
# Frameworks without arm64e slices are skipped.
process_xcframework_binaries() {
    # Find all framework binaries in the XCFramework
    find "$XCFRAMEWORK_DIR" -type d -name "*.framework" | while read -r FRAMEWORK_DIR; do
        # Get the framework name (without .framework extension)
        local FRAMEWORK_NAME=$(basename "$FRAMEWORK_DIR" .framework)
        local BINARY_PATH="$FRAMEWORK_DIR/$FRAMEWORK_NAME"

        if [ ! -f "$BINARY_PATH" ]; then
            continue
        fi

        # Check if arm64e exists and remove it
        if lipo -info "$BINARY_PATH" 2>/dev/null | grep -q "arm64e"; then
            remove_arm64e_from_binary "$BINARY_PATH"
        fi
    done
}

validate_xcframework
process_xcframework_binaries
