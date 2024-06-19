#!/bin/zsh

# Usage:
# $ ./tools/clean.sh

set -e
source ./tools/utils/echo_color.sh

clean_dir() {
    local dir="$1"
    if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then
        echo_warn "Removing contents:" "'$dir'"
        rm -rf "$dir"/*
    else
        echo_warn "Nothing to clean:" "'$dir' does not exist or it is already empty"
    fi
}

clean_dir ~/Library/Developer/Xcode/DerivedData
clean_dir ./Carthage/Build
clean_dir ./Carthage/Checkouts
clean_dir ./IntegrationTests/Pods

echo_warn "Cleaning local xcconfigs"
rm -vf ./xcconfigs/Base.ci.local.xcconfig
rm -vf ./xcconfigs/Base.dev.local.xcconfig
