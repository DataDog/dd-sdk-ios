#!/bin/zsh

# Usage:
# ./tools/release/build-dd-xcframework.sh -h
# Builds the Datadog xcframework for given --product name.

# Options:
#   --workspace: The path to the Xcode workspace file.
#   --product: The name of the product to build (e.g., 'DatadogLogs').
#   --ios: Includes iOS platform slices in the xcframework.
#   --tvos: Includes tvOS platform slices in the xcframework.
#   --output-dir: The output directory for the xcframework and archive artifacts.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo_color.sh

set_description "Builds the Datadog xcframework for given --product name."
define_arg "workspace" "" "The path to the Xcode workspace file." "string" "true"
define_arg "product" "" "The name of the product to build (e.g., 'DatadogLogs')." "string" "true"
define_arg "ios" "false" "Includes iOS platform slices in the xcframework." "store_true"
define_arg "tvos" "false" "Includes tvOS platform slices in the xcframework." "store_true"
define_arg "output-dir" "" "The output directory for the xcframework and archive artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

ARCHIVE_OUTPUT="$output_dir/archives"
XCFRAMEWORK_OUTPUT="$output_dir/xcframeworks"

mkdir -p "$ARCHIVE_OUTPUT"
mkdir -p "$XCFRAMEWORK_OUTPUT"

rm -rf "$ARCHIVE_OUTPUT/$product"
rm -rf "$XCFRAMEWORK_OUTPUT/$product.xcframework"

if [[ "$ios" != "true" && "$tvos" != "true" ]]; then
  echo_err "Error" "You must specify at least one platform (--ios or --tvos)."
  exit 1
fi

function archive {
    echo "▸ Starts archiving the scheme: $1 for destination: $2;\n▸ Archive path: $3.xcarchive"
    xcodebuild archive \
        -workspace "$workspace" \
        -scheme "$1" \
        -destination "$2" \
        -archivePath "$3" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        ONLY_ACTIVE_ARCH=NO \
    | xcbeautify
}

xcoptions=()

if [ "$ios" = "true" ]; then
    echo_subtitle2 "Archive $product iOS"

    archive "$product iOS" "generic/platform=iOS" "$ARCHIVE_OUTPUT/$product/ios" | xcbeautify
    xcoptions+=(-archive "$ARCHIVE_OUTPUT/$product/ios.xcarchive" -framework "$product.framework")

    archive "$product iOS" "generic/platform=iOS Simulator" "$ARCHIVE_OUTPUT/$product/ios-simulator" | xcbeautify
    xcoptions+=(-archive "$ARCHIVE_OUTPUT/$product/ios-simulator.xcarchive" -framework "$product.framework")
fi

if [ "$tvos" = "true" ]; then
    echo_subtitle2 "Archive $product tvOS"

    archive "$product tvOS" "generic/platform=tvOS" "$ARCHIVE_OUTPUT/$product/tvos" | xcbeautify
    xcoptions+=(-archive "$ARCHIVE_OUTPUT/$product/tvos.xcarchive" -framework "$product.framework")

    archive "$product tvOS" "generic/platform=tvOS Simulator" "$ARCHIVE_OUTPUT/$product/tvos-simulator" | xcbeautify
    xcoptions+=(-archive "$ARCHIVE_OUTPUT/$product/tvos-simulator.xcarchive" -framework "$product.framework")
fi

echo_subtitle2 "Create $product.xcframework"

# Datadog class conflicts with module name and Swift emits invalid module interface
# cf. https://github.com/apple/swift/issues/56573
#
# Therefore, we cannot provide ABI stability and we have to supply '-allow-internal-distribution'.
xcodebuild -create-xcframework -allow-internal-distribution ${xcoptions[@]} -output "$XCFRAMEWORK_OUTPUT/$product.xcframework" | xcbeautify

echo_succ "$XCFRAMEWORK_OUTPUT/$product.xcframework created"
