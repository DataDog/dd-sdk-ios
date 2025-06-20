#!/bin/zsh

set -eo pipefail

source ./tools/utils/echo-color.sh

clean_dir() {
    local dir="$1"
    if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then
        echo_warn "Removing contents:" "'$dir'"
        rm -rf "$dir"/*
    else
        echo_warn "Nothing to clean:" "'$dir' does not exist or it is already empty"
    fi
}

clean_dir ~/Library/Caches/org.carthage.CarthageKit/dependencies/
clean_dir ./Carthage/Build
clean_dir ./Carthage/Checkouts

./tools/carthage-shim.sh bootstrap --platform iOS,tvOS --use-xcframeworks

echo_succ "Using OpenTelemetryApi version: $(cat ./Carthage/Build/.OpenTelemetryApi.version | grep 'commitish' | awk -F'"' '{print $4}')"
echo_succ "Using PLCrashReporter version: $(cat ./Carthage/Build/.plcrashreporter.version | grep 'commitish' | awk -F'"' '{print $4}')"