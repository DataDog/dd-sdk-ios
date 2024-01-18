#!/bin/bash

function usage() {
  cat << EOF
Usage: $(basename)

Build and bundle the opentelemetry-swift xcframeworks.

Available options:

-h, --help          Print this help and exit.
-v, --version       Version of the opentelemetry-swift to build, default to '1.9.1'.
-c, --configuration Build configuration, default to 'Release'.
-o, --output        Destination path of the bundles.
--destinations      Comma separated list of destinations to build for, default to 'iOS Simulator,iOS,tvOS Simulator,tvOS'.
-d, --debug         Run script in debug mode.

EOF
    exit
}

# default arguments
VERSION="1.9.1"
OUTPUT="./build"
CONFIGURATION="Release"
DESTINATIONS=( "iOS Simulator" "iOS" "tvOS Simulator" "tvOS" )
REPO_NAME="opentelemetry-swift"
DEBUG=false
TARGET_NAME="OpenTelemetryApi"
FRAMEWORK_NAME="OpenTelemetryApi.xcframework"
# read cmd arguments
while :; do
    case $1 in
        -h|-\?|--help)
            usage
            exit
            ;;
        -v|--version)
            if [ "$2" ]; then
                VERSION=$2
                shift
            else
                echo 'ERROR: "--version" requires a non-empty option argument.'
                exit 1
            fi
            ;;
        -c|--configuration)
            if [ "$2" ]; then
                CONFIGURATION=$2
                shift
            else
                echo 'ERROR: "--configuration" requires a non-empty option argument.'
                exit 1
            fi
            ;;
        -o|--output)
            if [ "$2" ]; then
                OUTPUT=$2
                shift
            else
                echo 'ERROR: "--output" requires a non-empty option argument.'
                exit 1
            fi
            ;;
        --destinations)
            if [ "$2" ]; then
                DESTINATIONS=()
                IFS=',' read -ra DESTINATIONS <<< "$2"
                shift
            else
                echo 'ERROR: "--destinations" requires a non-empty option argument.'
                exit 1
            fi
            ;;
        -d|--debug)
            DEBUG=true
            ;;
        --) # End of all options.
            shift
            break
            ;;
        -?*)
            echo 'WARN: Unknown option (ignored): %s\n' "$1" >&2
            ;;
        *) # Default case: If no more options then break out of the loop.
            break
    esac
    shift
done

echo "Configurations"
echo "  Version: $VERSION"
echo "  Configuration: $CONFIGURATION"
echo "  Output: $OUTPUT"
echo "  Destinations: ${DESTINATIONS[@]}"

# go to each directory in output to build the library arguments for xcframework
# and then build the xcframework
function bundle {
    TARGET_NAME=$1

    echo "Building $TARGET_NAME"
    for DESTINATION in "${DESTINATIONS[@]}"; do
        echo "Building $TARGET_NAME for $DESTINATION"
        xcodebuild build \
            -destination "generic/platform=$DESTINATION" \
            -scheme $TARGET_NAME \
            -configuration $CONFIGURATION \
            BUILD_DIR=build
    done

    for DIR in build/*; do
        echo "Archiving $DIR/$TARGET_NAME"
        ar -crs $DIR/$TARGET_NAME.a $DIR/$TARGET_NAME.o
    done

    LIBRARY_ARG=""
    for DIR in build/*; do
        LIBRARY_ARG="$LIBRARY_ARG -library $DIR/$TARGET_NAME.a"
    done

    echo "Creating $TARGET_NAME.xcframework"
    xcodebuild -create-xcframework \
        -allow-internal-distribution \
        -output build/frameworks/$TARGET_NAME.xcframework $LIBRARY_ARG
}

# clone the repo to output
function clone {
    git clone --branch $VERSION --depth 1 https://github.com/open-telemetry/$REPO_NAME
}

# copy all frameworks from build/frameworks/*.framework to output
function copy {
    mkdir -p $OUTPUT
    FRAMEWORKS=$(find $TEMP_DIR/$REPO_NAME/build/frameworks -name "*.xcframework")
    for framework in $FRAMEWORKS; do
        cp -r $framework $OUTPUT
    done
}

ORIGINAL_PWD=$(pwd)
TEMP_DIR=$(mktemp -d)
cd $TEMP_DIR
echo "Using $TEMP_DIR for temporary files"
if [ "$DEBUG" = true ]; then
    open $TEMP_DIR
fi

clone
cd $REPO_NAME
bundle OpenTelemetryApi
cd $ORIGINAL_PWD
copy

if [ "$DEBUG" = false ]; then
    rm -rf $TEMP_DIR
fi