#!/bin/zsh

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo_color.sh

set_description "Validates xcframeworks."
define_arg "artifacts-path" "" "Path to build artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

XCF_ZIP_NAME="Datadog.xcframework.zip"
XCF_ZIP_PATH="$artifacts_path/$XCF_ZIP_NAME"

# Uncompress the archive to temporary directory
temp_dir=$(mktemp -d)
trap "rm -rf $temp_dir" EXIT INT

echo_info "Uncompressing '$XCF_ZIP_PATH' to '$temp_dir'"
unzip -q "$XCF_ZIP_PATH" -d "$temp_dir"

# Check if the main bundle exists in archive
XCF_PATH="$temp_dir/Datadog.xcframework"
if [[ -d "$XCF_PATH" ]]; then
    echo_succ "▸ '$XCF_PATH' found."
else
    echo_err "▸ '$XCF_PATH' not found."
    exit 1
fi

# Validate single xcframework by ensuring it bundles requried files
function validate_xcframework {
    local framework_name=$1; shift
    local slice=("$@")

    echo_subtitle2 "Validating contents of '$framework_name'"

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
echo_subtitle "Validating xcframeworks in '$XCF_ZIP_NAME'"
validate_xcframework "DatadogInternal.xcframework"          "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogCore.xcframework"              "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogLogs.xcframework"              "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogTrace.xcframework"             "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogRUM.xcframework"               "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogObjc.xcframework"              "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogCrashReporting.xcframework"    "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "DatadogSessionReplay.xcframework"     "${DATADOG_IOS[@]}"
validate_xcframework "DatadogWebViewTracking.xcframework"   "${DATADOG_IOS[@]}"
validate_xcframework "OpenTelemetryApi.xcframework"         "${DATADOG_IOS[@]}" "${DATADOG_TVOS[@]}"
validate_xcframework "CrashReporter.xcframework"            "${IOS[@]}" "${TVOS[@]}"

# Check if archive has any unexpected files
echo_subtitle "Checking remaining files in '$XCF_ZIP_NAME'"
remaining_files=$(find "$XCF_PATH" -mindepth 1 -maxdepth 1)
if [[ -n "$remaining_files" ]]; then
    echo_err "Error:" "Remaining files found but not expected:"
    find "$XCF_PATH" -mindepth 1 -maxdepth 1 | while read -r file; do
        echo "▸ ${file#$XCF_PATH/}"
    done
    exit 1
else
    echo_succ "No remaining files found. All good."
fi
