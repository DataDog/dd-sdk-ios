#!/bin/zsh

# Usage:
# ./tools/tools-test.sh
# Runs tests for repo tools.

set -eo pipefail
source ./tools/utils/echo-color.sh

test_swift_package() {
    local package_path="$1"
    echo_subtitle "swift test --package-path \"$package_path\" | xcbeautify"
    swift test --package-path "$package_path" | xcbeautify
}

# Test swift packages
test_swift_package tools/http-server-mock
test_swift_package tools/rum-models-generator
test_swift_package tools/sr-snapshots

# Test platform compatibility validation:
echo_subtitle "Run platform compatibility validator tests"
python3 -m unittest discover --start-directory tools/tests --pattern "test_*.py"

# Test dogfooding automation:
echo_subtitle "Run 'make clean install test' in ./tools/dogfooding"
cd tools/dogfooding && make clean install test
cd -
