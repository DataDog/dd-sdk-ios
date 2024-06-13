#!/bin/zsh

# Usage:
# $ ./tools/clean.sh

source ./tools/utils/echo_color.sh

echo_warn "Cleaning" "~/Library/Developer/Xcode/DerivedData/"
rm -rf ~/Library/Developer/Xcode/DerivedData/*

echo_warn "Cleaning" "./Carthage/"
rm -rf ./Carthage/Build/*
rm -rf ./Carthage/Checkouts/*

echo_warn "Cleaning" "./IntegrationTests/Pods/"
rm -rf ./IntegrationTests/Pods/*

echo_warn "Cleaning" "local xcconfigs"
rm -vf ./xcconfigs/Base.ci.local.xcconfig
rm -vf ./xcconfigs/Base.dev.local.xcconfig
