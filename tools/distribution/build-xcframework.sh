#!/bin/bash

OUTPUT="build"
PLATFORM="iOS,tvOS"

while :; do
    case $1 in
        -o|--output) OUTPUT_FILE=$2
        shift
        ;;
        -p|--platform) PLATFORM=$2
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
        SKIP_INSTALL=NO \
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
    xcodebuild -create-xcframework ${xcoptions[@]} -output "$XCFRAMEWORK_OUTPUT/$PRODUCT.xcframework"
}

rm -rf $OUTPUT
carthage bootstrap --platform $PLATFORM --use-xcframeworks
mkdir -p "$XCFRAMEWORK_OUTPUT" 
cp -r "Carthage/Build/CrashReporter.xcframework" "$XCFRAMEWORK_OUTPUT"

bundle Datadog
bundle DatadogObjc
bundle DatadogCrashReporting
