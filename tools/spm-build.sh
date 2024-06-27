#!/bin/zsh

# Usage:
# $ ./tools/spm-build.sh -h
# Builds Package.swift for a specified --scheme and --destination.

# Options:
#   --destination: Defines the xcodebuild destination for Package.swift build, e.g. 'generic/platform=visionOS', 'platform=macOS,variant=Mac Catalyst'
#   --scheme: Identifies the scheme to build

set -eo pipefail
source ./tools/utils/echo_color.sh
source ./tools/utils/argparse.sh

set_description "Builds SPM package for a specified --scheme and --destination."
define_arg "destination" "" "Defines the xcodebuild destination for SPM build, e.g. 'generic/platform=visionOS', 'platform=macOS,variant=Mac Catalyst'" "string" "true"
define_arg "scheme" "" "Identifies the scheme to build" "string" "true"

check_for_help "$@"
parse_args "$@"

WORKSPACE="Datadog.xcworkspace"
WORKSPACE_RENAMED="Datadog.xcworkspace.old"

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

echo_subtitle "Run 'xcodebuild build -scheme $scheme -destination "$destination" | xcbeautify'"

set -x
xcodebuild build -scheme "$scheme" -destination "$destination" | xcbeautify
