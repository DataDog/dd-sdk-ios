#!/bin/zsh

# Usage:
# $ ./tools/spm.sh -h
# Builds the SDK only using Package.swift.

set -eo pipefail
source ./tools/utils/echo_color.sh
source ./tools/utils/argparse.sh

define_arg "platform" "" "Defines the type of simulator platform for the tests, e.g. 'iOS', 'tvOS, 'visionOS'" "string" "true"

check_for_help "$@"
parse_args "$@"

WORKSPACE="Datadog.xcworkspace"
WORKSPACE_RENAMED="Datadog.xcworkspace.old"
SCHEME="Datadog-Package"

set -x

rename_workspace() {
    if [ ! -d "$WORKSPACE" ]; then
        echo_warn "Workspace $WORKSPACE does not exist"
        return 0
    fi

    echo_warn "Renaming workspace to $WORKSPACE_RENAMED"
    mv "$WORKSPACE" "$WORKSPACE_RENAMED"
}

restore_workspace() {
    if [ ! -d "$WORKSPACE_RENAMED" ]; then
        echo_warn "Workspace $WORKSPACE_RENAMED does not exist"
        return 0
    fi

    echo_warn "Restoring workspace to $WORKSPACE"
    mv "$WORKSPACE_RENAMED" "$WORKSPACE"
}

rename_workspace
# try to restore the files even if the script fails
trap restore_workspace EXIT INT

echo "Building SDK for platform $platform"
xcodebuild build -scheme $SCHEME -destination generic/platform="$platform" | xcbeautify