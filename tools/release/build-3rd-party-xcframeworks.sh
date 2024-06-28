#!/bin/zsh

# Usage:
# ./tools/release/build-3rd-party-xcframeworks.sh -h
# Builds third-party xcframeworks to be shipped with Datadog SDK.

# Options:
#   --cartfile-path: The path to the Cartfile that lists third-party dependencies.
#   --output-dir: The output directory for the xcframework artifacts.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo_color.sh

set_description "Builds third-party xcframeworks to be shipped with Datadog SDK."
define_arg "cartfile-path" "" "The path to the Cartfile listing 3rd party dependencies." "string" "true"
define_arg "output-dir" "" "Sets the output directory for the xcframework artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

echo_subtitle2 "Prepare '$output_dir' for building XCFrameworks"
CARTHAGE_OUTPUT="$output_dir/carthage-build"
XCFRAMEWORK_OUTPUT="$output_dir/xcframeworks"
set -x
mkdir -p "$CARTHAGE_OUTPUT"
mkdir -p "$XCFRAMEWORK_OUTPUT"
rm -f "$CARTHAGE_OUTPUT/Cartfile"
rm -f "$CARTHAGE_OUTPUT/Cartfile.resolved"
cp "$cartfile_path" $CARTHAGE_OUTPUT
cp "${cartfile_path%/*}/Cartfile.resolved" $CARTHAGE_OUTPUT
set +x

echo_subtitle2 "Build third-party XCFrameworks"
set -x
rm -rf "$CARTHAGE_OUTPUT/Carthage"
DIR=$(pwd)
cd $CARTHAGE_OUTPUT
echo_info "Running 'bootstrap --platform iOS,tvOS --use-xcframeworks' in $(PWD)" 
carthage bootstrap --platform iOS,tvOS --use-xcframeworks
cd "$DIR"
set +x

echo_subtitle2 "Copy third-party XCFrameworks to '$XCFRAMEWORK_OUTPUT'"
set -x
rm -rf "$XCFRAMEWORK_OUTPUT/CrashReporter.xcframework"
rm -rf "$XCFRAMEWORK_OUTPUT/OpenTelemetryApi.xcframework"
cp -r "Carthage/Build/CrashReporter.xcframework" "$XCFRAMEWORK_OUTPUT"
cp -r "Carthage/Build/OpenTelemetryApi.xcframework" "$XCFRAMEWORK_OUTPUT"
set +x

echo_succ "$XCFRAMEWORK_OUTPUT/CrashReporter.xcframework created"
echo_succ "$XCFRAMEWORK_OUTPUT/OpenTelemetryApi.xcframework created"
