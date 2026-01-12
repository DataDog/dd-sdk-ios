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

check_xcframework_bundle_exists() {
    local xcframework_path=$1

    if [[ -d "$xcframework_path" ]]; then
        echo_succ "▸ '$xcframework_path' found."
    else
        echo_err "▸ '$xcframework_path' not found."
        exit 1
    fi
}

validate_xcframework() {
    local framework_name=$1; shift
    local slice=("$@")

    echo_subtitle2 "Validate contents of '$framework_name'"

    local framework_path="$XCF_PATH/$framework_name"
    if [[ ! -d "$framework_path" ]]; then
        echo_err "▸ '$framework_path' not found."
        exit 1
    fi

    echo "Checking required files in '$framework_name':"
    for pattern in "${slice[@]}"; do
        local found_files=($(find "$framework_path" -path "$framework_path/$pattern"))
        if [[ ${#found_files[@]} -eq 0 ]]; then
            echo_err "▸ '$pattern' not found."
            exit 1
        else
            echo_succ "▸ '$pattern' found and removed."
            for file in "${found_files[@]}"; do
                rm -rf "$file" # remove so we can list unmatched files later
            done
        fi
    done

    echo "Listing remaining files in '$framework_name':"
    find "$framework_path" -type f | while read -r file; do
        echo_warn "▸ ${file#$framework_path/}"
    done

    rm -rf "$framework_path" # remove so we can list remaining xcframeworks later
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

# Define slices for validation
IOS=(
    "ios-arm64_arm64e"
    "ios-arm64_x86_64-simulator"
)

IOS_SWIFT=(
    "ios-arm64_arm64e/**/*.swiftinterface"
    "ios-arm64_x86_64-simulator/**/*.swiftinterface"
)

IOS_DSYMs=(
    "ios-arm64_arm64e/dSYMs/*.dSYM"
    "ios-arm64_x86_64-simulator/dSYMs/*.dSYM"
)

TVOS=(
    "tvos-arm64"
    "tvos-arm64_x86_64-simulator"
)

TVOS_SWIFT=(
    "tvos-arm64/**/*.swiftinterface"
    "tvos-arm64_x86_64-simulator/**/*.swiftinterface"
)

TVOS_DSYMs=(
    "tvos-arm64/dSYMs/*.dSYM"
    "tvos-arm64_x86_64-simulator/dSYMs/*.dSYM"
)

DATADOG_IOS=("${IOS_SWIFT[@]}" "${IOS_DSYMs[@]}" "${IOS[@]}")
DATADOG_TVOS=("${TVOS_SWIFT[@]}" "${TVOS_DSYMs[@]}" "${TVOS[@]}")

# Validate xcframeworks from the archive
validate_xcframework "DatadogInternal.xcframework"          "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogCore.xcframework"              "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogLogs.xcframework"              "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogTrace.xcframework"             "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogRUM.xcframework"               "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogCrashReporting.xcframework"    "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogFlags.xcframework"             "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogProfiling.xcframework"          "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogSessionReplay.xcframework"     "${DATADOG_IOS[@]}"
validate_xcframework "DatadogWebViewTracking.xcframework"   "${DATADOG_IOS[@]}"
validate_xcframework "OpenTelemetryApi.xcframework"         "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"

# Check if archive has any remaining files
check_remaining_files "$XCF_PATH"
