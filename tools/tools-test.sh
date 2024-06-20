#!/bin/zsh

# Usage:
# ./tools/tools-test.sh
# Runs tests for CLI tools in the repo.

set -eo pipefail
source ./tools/utils/echo_color.sh

test_swift_package() {
    local package_path="$1"
    echo_subtitle "swift test --package-path \"$package_path\" | xcbeautify"
    swift test --package-path "$package_path" | xcbeautify
}

# Test swift packages
test_swift_package tools/http-server-mock
test_swift_package tools/rum-models-generator
test_swift_package tools/sr-snapshots

# Test release & dogfood automation:
echo_subtitle "Run 'make clean install test' in ./tools/distribution"
cd tools/distribution && make clean install test
cd -

