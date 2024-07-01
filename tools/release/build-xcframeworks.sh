#!/bin/zsh

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo_color.sh

set_description "Builds the Datadog xcframework for given --product name."
define_arg "repo-path" "" "The path to the root of dd-sdk-ios repo." "string" "true"
define_arg "ios" "false" "Includes iOS platform slices in the xcframework." "store_true"
define_arg "tvos" "false" "Includes tvOS platform slices in the xcframework." "store_true"
define_arg "output-path" "" "The path to the output directory to create 'xcframeworks/' directory in." "string" "true"

check_for_help "$@"
parse_args "$@"

rm -rf "$output_path"
mkdir -p "$output_path/archives"
mkdir -p "$output_path/xcframeworks"

REPO_PATH=$(realpath "$repo_path")
ARCHIVES_OUTPUT="$(realpath "$output_path")/archives"
XCFRAMEWORKS_OUTPUT="$(realpath "$output_path")/xcframeworks"

echo_info "Building xcframeworks"
echo_info "- REPO_PATH = '$REPO_PATH'"
echo_info "- ARCHIVES_OUTPUT = '$ARCHIVES_OUTPUT'"
echo_info "- XCFRAMEWORKS_OUTPUT = '$XCFRAMEWORKS_OUTPUT'"

function check_repo {
    echo_subtitle "Checking repo at '$REPO_PATH'"
    [ -d "Datadog.xcworkspace" ] && echo_succ "Found 'Datadog.xcworkspace' in '$REPO_PATH'" \
        || { echo_err "Error:" "Could not find 'Datadog.xcworkspace' in '$REPO_PATH'." ; exit 1; }

    [ -f "Cartfile" ] && echo_succ "Found 'Cartfile' in '$REPO_PATH'" \
        || { echo_err "Error:" "Could not find 'Cartfile' in '$REPO_PATH'." ; exit 1; }

    [ -f "Cartfile.resolved" ] && echo_succ "Found 'Cartfile.resolved' in '$REPO_PATH'" \
        || { echo_err "Error:" "Could not find 'Cartfile.resolved' in '$REPO_PATH'." ; exit 1; }

    local config_files=$(find . -name "*.local.xcconfig")
    if [[ -n $config_files ]]; then
        echo_err "Error:" "The repo at '$REPO_PATH' is not in a clean state."
        echo "It has following local config files:"
        echo "$config_files" | awk '{print "- " $0}'
        exit 1
    else
        echo_succ "The repository is in a clean state (no '*.local.xcconfig' files are present)."
    fi
}

function archive {
    local scheme="$1"
    local destination="$2"
    local archive_path="$3"

    echo_subtitle2 "Archiving scheme: '$scheme' for destination: '$destination'"

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

function build_xcframework {
    local product="$1"
    local platform="$2"
    xcoptions=()

    echo_subtitle "Building '$product.xcframework' using platform='$platform"

    if [[ $platform == *"iOS"* ]]; then
        echo "▸ Archive $product iOS"

        archive "$product iOS" "generic/platform=iOS" "$ARCHIVES_OUTPUT/$product/ios"
        xcoptions+=(-archive "$ARCHIVES_OUTPUT/$product/ios.xcarchive" -framework "$product.framework")

        archive "$product iOS" "generic/platform=iOS Simulator" "$ARCHIVES_OUTPUT/$product/ios-simulator"
        xcoptions+=(-archive "$ARCHIVES_OUTPUT/$product/ios-simulator.xcarchive" -framework "$product.framework")
    fi

    if [[ $platform == *"tvOS"* ]]; then
        echo "▸ Archive $product tvOS"

        archive "$product tvOS" "generic/platform=tvOS" "$ARCHIVES_OUTPUT/$product/tvos"
        xcoptions+=(-archive "$ARCHIVES_OUTPUT/$product/tvos.xcarchive" -framework "$product.framework")

        archive "$product tvOS" "generic/platform=tvOS Simulator" "$ARCHIVES_OUTPUT/$product/tvos-simulator"
        xcoptions+=(-archive "$ARCHIVES_OUTPUT/$product/tvos-simulator.xcarchive" -framework "$product.framework")
    fi

    # Datadog class conflicts with module name and Swift emits invalid module interface
    # cf. https://github.com/apple/swift/issues/56573
    #
    # Therefore, we cannot provide ABI stability and we have to supply '-allow-internal-distribution'.
    xcodebuild -create-xcframework -allow-internal-distribution ${xcoptions[@]} -output "$XCFRAMEWORKS_OUTPUT/$product.xcframework" | xcbeautify

    echo_succ "The '$product.xcframework' was created successfully in '$XCFRAMEWORKS_OUTPUT'"
}

DIR=$(pwd)

echo_info "cd '$REPO_PATH'"
cd $REPO_PATH

# Check if repo is in clean state
check_repo

# Select PLATFORMS to build ('iOS' | 'tvOS' | 'iOS,tvOS')
PLATFORMS=""
[[ "$ios" == "true" ]] && PLATFORMS+="iOS"
[[ "$tvos" == "true" ]] && { [ -n "$PLATFORMS" ] && PLATFORMS+=","; PLATFORMS+="tvOS"; }

# Build third-party dependencies
echo_subtitle "Running 'carthage bootstrap --platform $PLATFORMS --use-xcframeworks'"
carthage bootstrap --platform $PLATFORMS --use-xcframeworks
cp -r "Carthage/Build/CrashReporter.xcframework" "$XCFRAMEWORKS_OUTPUT"
cp -r "Carthage/Build/OpenTelemetryApi.xcframework" "$XCFRAMEWORKS_OUTPUT"

# Build Datadog XCFrameworks
build_xcframework DatadogInternal "$PLATFORMS"
build_xcframework DatadogCore "$PLATFORMS"
build_xcframework DatadogLogs "$PLATFORMS"
build_xcframework DatadogTrace "$PLATFORMS"
build_xcframework DatadogRUM "$PLATFORMS"
build_xcframework DatadogObjc "$PLATFORMS"
build_xcframework DatadogCrashReporting "$PLATFORMS"

# Build iOS-only Datadog XCFrameworks
if [[ "$ios" == "true" ]]; then
    build_xcframework DatadogWebViewTracking "iOS"
    build_xcframework DatadogSessionReplay "iOS"
fi

cd "$DIR"
