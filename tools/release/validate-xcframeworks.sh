#!/bin/zsh

# Usage:
# $ ./tools/release/validate-xcframeworks.sh -h 
# Validates contents of xcframeworks.

# Options:
#   --artifacts-path: The path to build artifacts.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh

set_description "Validates contents of xcframeworks."
define_arg "artifacts-path" "" "The path to build artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

XCF_ZIP_NAME="Datadog.xcframework.zip"
XCF_ZIP_PATH="$artifacts_path/$XCF_ZIP_NAME"

unzip_archive() {
    local zip_path=$1
    local output_dir=$2

    echo_info "Uncompressing '$zip_path' to '$output_dir'"
    unzip -q "$zip_path" -d "$output_dir"
}

# Checks if the main xcframework bundle directory exists.
#
# Arguments:
#   $1 - Path to the xcframework bundle
check_xcframework_bundle_exists() {
    local xcframework_path=$1

    if [[ -d "$xcframework_path" ]]; then
        echo_succ "▸ '$xcframework_path' found."
    else
        echo_err "▸ '$xcframework_path' not found."
        exit 1
    fi
}

# Validates files matching glob patterns within an xcframework.
# Removes matched files after validation (as part of the deletion strategy).
#
# Arguments:
#   $1 - Path to the xcframework bundle
#   $2 - Framework name (for error messages)
#   $@ - Array of glob patterns to validate
validate_patterns() {
    local framework_path=$1
    local framework_name=$2
    shift 2
    local patterns=("$@")

    echo "Checking required files in '$framework_name':"
    for pattern in "${patterns[@]}"; do
        local found_files=($(find "$framework_path" -path "$framework_path/$pattern"))
        if [[ ${#found_files[@]} -eq 0 ]]; then
            echo_err "▸ '$pattern' not found."
            exit 1
        else
            echo_succ "▸ '$pattern' found and removed."
            for file in "${found_files[@]}"; do
                rm -rf "$file"
            done
        fi
    done
}

# Lists any remaining files in an xcframework after validation.
# These files are considered unexpected and will be reported as warnings.
#
# Arguments:
#   $1 - Path to the xcframework bundle
#   $2 - Framework name (for display)
list_remaining_files() {
    local framework_path=$1
    local framework_name=$2

    echo "Listing remaining files in '$framework_name':"
    find "$framework_path" -type f | while read -r file; do
        echo_warn "▸ ${file#$framework_path/}"
    done
}

# Validates the complete structure and content of an xcframework.
# This includes:
#   - Info.plist at the root
#   - Swift module interfaces for specified platforms
#   - dSYM debug symbols for specified platforms
#   - Framework binaries inside each .framework bundle
#   - Detection of unexpected files
#
# The validation uses a deletion strategy: known files are removed as they're
# validated, and any remaining files are reported as unexpected.
#
# Arguments:
#   $1 - Framework name (e.g., "DatadogInternal.xcframework")
#   $2 - Comma-separated platform list (e.g., "iOS,tvOS" or "iOS")
#
# Examples:
#   validate_xcframework "DatadogCore.xcframework" "iOS,tvOS"
#   validate_xcframework "DatadogSessionReplay.xcframework" "iOS"
validate_xcframework() {
    local framework_name=$1
    local platforms=$2

    echo_subtitle2 "Validate contents of '$framework_name'"

    local framework_path="$XCF_PATH/$framework_name"
    if [[ ! -d "$framework_path" ]]; then
        echo_err "▸ '$framework_path' not found."
        exit 1
    fi

    local framework_basename="${framework_name%.xcframework}"

    # Build all validation patterns
    local all_patterns=("Info.plist")

    IFS=',' read -rA platform_array <<< "$platforms"
    for platform in "${platform_array[@]}"; do
        local prefix=$(echo "$platform" | tr '[:upper:]' '[:lower:]')
        all_patterns+=(
            "${prefix}-*/$framework_basename.framework/Modules/$framework_basename.swiftmodule/*.swiftinterface"
            "${prefix}-*/dSYMs/$framework_basename.framework.dSYM"
            "${prefix}-*/$framework_basename.framework/$framework_basename"
        )
    done

    # Validate all patterns at once
    validate_patterns "$framework_path" "$framework_name" "${all_patterns[@]}"

    # List any remaining unexpected files
    list_remaining_files "$framework_path" "$framework_name"

    # Step 65: Clean up
    rm -rf "$framework_path"
}

# Checks if there are any remaining files after validation (during validation, all known files are deleted).
check_remaining_files() {
    local xcframework_path=$1

    echo_subtitle "Check unexpected files in '$XCF_ZIP_NAME'"
    remaining_files=$(find "$xcframework_path" -mindepth 1 -maxdepth 1)
    if [[ -n "$remaining_files" ]]; then
        echo_err "Error:" "Remaining files found but not expected:"
        find "$xcframework_path" -mindepth 1 -maxdepth 1 | while read -r file; do
            echo "▸ ${file#$xcframework_path/}"
        done
        exit 1
    else
        echo_succ "No extra files found. All good."
    fi
}

# Uncompress the archive to temporary directory
temp_dir=$(mktemp -d)
trap "rm -rf $temp_dir" EXIT INT

echo_subtitle "Validate xcframeworks in '$XCF_ZIP_NAME'"
unzip_archive "$XCF_ZIP_PATH" "$temp_dir"

# Check if the main bundle exists in the archive
XCF_PATH="$temp_dir/Datadog.xcframework"
check_xcframework_bundle_exists "$XCF_PATH"

# Validate xcframeworks from the archive
# Each framework is validated for specified platforms (iOS, tvOS, or both)
validate_xcframework "DatadogInternal.xcframework"          "iOS,tvOS"
validate_xcframework "DatadogCore.xcframework"              "iOS,tvOS"
validate_xcframework "DatadogLogs.xcframework"              "iOS,tvOS"
validate_xcframework "DatadogTrace.xcframework"             "iOS,tvOS"
validate_xcframework "DatadogRUM.xcframework"               "iOS,tvOS"
validate_xcframework "DatadogCrashReporting.xcframework"    "iOS,tvOS"
validate_xcframework "DatadogFlags.xcframework"             "iOS,tvOS"
validate_xcframework "DatadogSessionReplay.xcframework"     "iOS"
validate_xcframework "DatadogWebViewTracking.xcframework"   "iOS"
validate_xcframework "OpenTelemetryApi.xcframework"         "iOS,tvOS"

# Check if archive has any remaining files
check_remaining_files "$XCF_PATH"
