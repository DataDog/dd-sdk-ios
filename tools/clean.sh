#!/bin/zsh

# Usage:
# $ ./tools/clean.sh

set -e
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh

set_description "Cleans up the local environment."
define_arg "derived-data" "false" "Clean Xcode derived data." "store_true"
define_arg "pods" "false" "Clean Pods." "store_true"
define_arg "xcconfigs" "false" "Clean local xcconfigs." "store_true"
define_arg "carthage" "false" "Clean Carthage cache." "store_true"

clean_dir() {
    local dir="$1"
    if [ -d "$dir" ] && [ "$(ls -A "$dir")" ]; then
        echo_warn "Removing contents:" "'$dir'"
        rm -rf "$dir"/*
    else
        echo_warn "Nothing to clean:" "'$dir' does not exist or it is already empty"
    fi
}

check_for_help "$@"
parse_args "$@"

if [[ "$derived_data" == "true" ]]; then
    echo_subtitle "Cleaning Xcode derived data"
    clean_dir ~/Library/Developer/Xcode/DerivedData
    clean_dir ~/Library/org.swift.swiftpm
fi

if [[ "$pods" == "true" ]]; then
    echo_subtitle "Cleaning Pods"
    clean_dir ./IntegrationTests/Pods
fi

if [[ "$xcconfigs" == "true" ]]; then
    echo_subtitle "Cleaning local xcconfigs"
    rm -vf ./xcconfigs/Base.ci.local.xcconfig
    rm -vf ./xcconfigs/Base.dev.local.xcconfig
fi

if [[ "$carthage" == "true" ]]; then
    echo_subtitle "Cleaning Carthage cache"
    clean_dir ~/Library/Caches/org.carthage.CarthageKit/dependencies/
    clean_dir ./Carthage/Build
    clean_dir ./Carthage/Checkouts
fi
