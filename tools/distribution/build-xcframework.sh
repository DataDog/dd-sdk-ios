#!/bin/bash

function usage() {
  cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h|--help] [-p|--platform] iOS,tvOS [-o|--output] path/to/bundles

Build and bundle the Datdog SDK xcframeworks.

Available options:

-h, --help      Print this help and exit.
-p, --platform  Select platform slices to include in the xcframework bundle. Use comma seperated list, default to 'iOS,tvOS'.
-o, --output    Destination path of the bundles.

EOF
  exit
}

# default arguments
OUTPUT="build"
PLATFORM="iOS,tvOS"

# read cmd arguments
while :; do
    case $1 in
        -p|--platform) PLATFORM=$2
        shift
        ;;
        -o|--output) OUTPUT_FILE=$2
        shift
        ;;
        -h|--help) usage
        shift
        ;;
        *) break
    esac
    shift
done

ARCHIVE_OUTPUT="$OUTPUT/archives"
XCFRAMEWORK_OUTPUT="$OUTPUT/xcframeworks"

function archive {
    echo "▸ Starts archiving the scheme: $1 for destination: $2;\n▸ Archive path: $3.xcarchive"
    xcodebuild archive \
        -workspace Datadog.xcworkspace \
        -scheme "$1" \
        -destination "$2" \
        -archivePath "$3" \
        SKIP_INSTALL=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        ONLY_ACTIVE_ARCH=NO \
    | xcpretty
}

function bundle {
    PRODUCT=$1
    xcoptions=()

    if [[ $PLATFORM == *"iOS"* ]]; then
        echo "▸ Archive $PRODUCT iOS"

        archive "$PRODUCT iOS" "generic/platform=iOS" "$ARCHIVE_OUTPUT/$PRODUCT/ios"
        xcoptions+=(-archive "$ARCHIVE_OUTPUT/$PRODUCT/ios.xcarchive" -framework "$PRODUCT.framework")

        archive "$PRODUCT iOS" "generic/platform=iOS Simulator" "$ARCHIVE_OUTPUT/$PRODUCT/ios-simulator"
        xcoptions+=(-archive "$ARCHIVE_OUTPUT/$PRODUCT/ios-simulator.xcarchive" -framework "$PRODUCT.framework")
    fi

    if [[ $PLATFORM == *"tvOS"* ]]; then
        echo "▸ Archive $PRODUCT tvOS"

        archive "$PRODUCT tvOS" "generic/platform=tvOS" "$ARCHIVE_OUTPUT/$PRODUCT/tvos"
        xcoptions+=(-archive "$ARCHIVE_OUTPUT/$PRODUCT/tvos.xcarchive" -framework "$PRODUCT.framework")

        archive "$PRODUCT tvOS" "generic/platform=tvOS Simulator" "$ARCHIVE_OUTPUT/$PRODUCT/tvos-simulator"
        xcoptions+=(-archive "$ARCHIVE_OUTPUT/$PRODUCT/tvos-simulator.xcarchive" -framework "$PRODUCT.framework")
    fi

    echo "▸ Create $PRODUCT.xcframework"

    # Datadog class conflicts with module name and Swift emits invalid module interface
    # cf. https://github.com/apple/swift/issues/56573
    #
    # Therefore, we cannot provide ABI stability and we have to supply '-allow-internal-distribution'.
    xcodebuild -create-xcframework -allow-internal-distribution ${xcoptions[@]} -output "$XCFRAMEWORK_OUTPUT/$PRODUCT.xcframework"
}

rm -rf $OUTPUT
carthage bootstrap --platform $PLATFORM --use-xcframeworks
mkdir -p "$XCFRAMEWORK_OUTPUT"
cp -r "Carthage/Build/CrashReporter.xcframework" "$XCFRAMEWORK_OUTPUT"

bundle DatadogInternal
bundle DatadogCore
bundle DatadogLogs
bundle DatadogTrace
bundle DatadogRUM
bundle DatadogObjc
bundle DatadogCrashReporting
cp -r /Users/ganesh.jangir/Developer/opentelemetry-swift/OpenTelemetryApi.xcframework "$XCFRAMEWORK_OUTPUT/OpenTelemetryApi.xcframework"

# Build iOS-only XCFrameworks
if [[ $PLATFORM == *"iOS"* ]]; then
    PLATFORM="iOS"
    bundle DatadogWebViewTracking
    bundle DatadogSessionReplay
fi