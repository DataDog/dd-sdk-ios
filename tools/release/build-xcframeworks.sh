#!/bin/zsh

# Usage:
# $ ./tools/release/build-xcframeworks.sh -h
# Builds XCFrameworks from the specified repository and exports them to the designated output directory.

# Options:
#   --repo-path: The path to the root of the 'dd-sdk-ios' repository.
#   --ios: Includes iOS platform slices in the exported XCFrameworks.
#   --tvos: Includes tvOS platform slices in the exported XCFrameworks.
#   --output-path: The path to the output directory where XCFrameworks will be stored.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh

set_description "Builds XCFrameworks from the specified repository and exports them to the designated output directory."
define_arg "repo-path" "" "The path to the root of the 'dd-sdk-ios' repository." "string" "true"
define_arg "ios" "false" "Includes iOS platform slices in the exported XCFrameworks." "store_true"
define_arg "tvos" "false" "Includes tvOS platform slices in the exported XCFrameworks." "store_true"
define_arg "output-path" "" "The path to the output directory where XCFrameworks will be stored." "string" "true"

check_for_help "$@"
parse_args "$@"


REPO_PATH=$(realpath "$repo_path")
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo_info "Clean '$REPO_PATH' with 'git clean -fxd'"
cd "$REPO_PATH" && git clean -fxd && cd -

echo_info "Create '$output_path'"
rm -rf "$output_path" && mkdir -p "$output_path"

XCFRAMEWORKS_OUTPUT=$(realpath "$output_path")
ARCHIVES_TEMP_OUTPUT="$XCFRAMEWORKS_OUTPUT/archives"

archive() {
    local scheme="$1"
    local destination="$2"
    local archive_path="$3"

    echo_subtitle2 "➔ Archive scheme: '$scheme' for destination: '$destination'"

    xcodebuild archive \
        -workspace "Datadog.xcworkspace" \
        -scheme $scheme \
        -destination $destination \
        -archivePath $archive_path \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        ONLY_ACTIVE_ARCH=NO \
        | xcbeautify

    echo_succ "The archive was created successfully at '$archive_path.xcarchive'"
}

build_xcframework() {
    local product="$1"
    local platform="$2"
    xcoptions=()

    echo_subtitle2 "Build '$product.xcframework' using platform='$platform'"

    if [[ $platform == *"iOS"* ]]; then
        echo_info "▸ Archive $product iOS"

        archive "$product iOS" "generic/platform=iOS" "$ARCHIVES_TEMP_OUTPUT/$product/ios"
        xcoptions+=(-archive "$ARCHIVES_TEMP_OUTPUT/$product/ios.xcarchive" -framework "$product.framework")

        archive "$product iOS" "generic/platform=iOS Simulator" "$ARCHIVES_TEMP_OUTPUT/$product/ios-simulator"
        xcoptions+=(-archive "$ARCHIVES_TEMP_OUTPUT/$product/ios-simulator.xcarchive" -framework "$product.framework")
    fi

    if [[ $platform == *"tvOS"* ]]; then
        echo_info "▸ Archive $product tvOS"

        archive "$product tvOS" "generic/platform=tvOS" "$ARCHIVES_TEMP_OUTPUT/$product/tvos"
        xcoptions+=(-archive "$ARCHIVES_TEMP_OUTPUT/$product/tvos.xcarchive" -framework "$product.framework")

        archive "$product tvOS" "generic/platform=tvOS Simulator" "$ARCHIVES_TEMP_OUTPUT/$product/tvos-simulator"
        xcoptions+=(-archive "$ARCHIVES_TEMP_OUTPUT/$product/tvos-simulator.xcarchive" -framework "$product.framework")
    fi

    xcodebuild -create-xcframework ${xcoptions[@]} -output "$XCFRAMEWORKS_OUTPUT/$product.xcframework" | xcbeautify

    echo_succ "The '$product.xcframework' was created successfully in '$XCFRAMEWORKS_OUTPUT'"
}

echo_info "cd '$REPO_PATH'"
cd $REPO_PATH

# Select PLATFORMS to build ('iOS' | 'tvOS' | 'iOS,tvOS')
PLATFORMS=""
[[ "$ios" == "true" ]] && PLATFORMS+="iOS"
[[ "$tvos" == "true" ]] && { [ -n "$PLATFORMS" ] && PLATFORMS+=","; PLATFORMS+="tvOS"; }

echo_info "Building xcframeworks"
echo_info "▸ REPO_PATH = '$REPO_PATH'"
echo_info "▸ ARCHIVES_TEMP_OUTPUT = '$ARCHIVES_TEMP_OUTPUT'"
echo_info "▸ XCFRAMEWORKS_OUTPUT = '$XCFRAMEWORKS_OUTPUT'"
echo_info "▸ PLATFORMS = '$PLATFORMS'"

# Build third-party XCFrameworks
echo_subtitle2 "Run 'carthage bootstrap --platform $PLATFORMS --use-xcframeworks'"
export REPO_ROOT=$(realpath "$SCRIPT_DIR/../..") 
$REPO_ROOT/tools/carthage-shim.sh bootstrap --platform $PLATFORMS --use-xcframeworks
cp -r "Carthage/Build/CrashReporter.xcframework" "$XCFRAMEWORKS_OUTPUT"
cp -r "Carthage/Build/OpenTelemetryApi.xcframework" "$XCFRAMEWORKS_OUTPUT"

# Build Datadog XCFrameworks
build_xcframework DatadogInternal "$PLATFORMS"
build_xcframework DatadogCore "$PLATFORMS"
build_xcframework DatadogLogs "$PLATFORMS"
build_xcframework DatadogTrace "$PLATFORMS"
build_xcframework DatadogRUM "$PLATFORMS"
build_xcframework DatadogCrashReporting "$PLATFORMS"
build_xcframework DatadogFlags "$PLATFORMS"
build_xcframework DatadogProfiler "$PLATFORMS"

# Build iOS-only Datadog XCFrameworks
if [[ "$ios" == "true" ]]; then
    build_xcframework DatadogWebViewTracking "iOS"
    build_xcframework DatadogSessionReplay "iOS"
fi

rm -rf "$ARCHIVES_TEMP_OUTPUT"
