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

test_python_package() {
    local package_path="$1"
    echo_subtitle "python -m pytest \"$package_path/tests/\""
    cd "$package_path"
    
    # Check if Python 3 is available
    if ! command -v python3 >/dev/null 2>&1; then
        echo_err "Python 3 not found. Python tests cannot run."
        cd -
        exit 1
    fi
    
    # Check if virtual environment exists and use it
    if [ -d "venv" ]; then
        echo "📦 Using existing virtual environment..."
        source venv/bin/activate
        python -m pytest tests/ -v
    else
        echo_err "Virtual environment not found in $package_path. Python tests cannot run."
        echo_err "Please ensure the virtual environment is set up before running tests."
        cd -
        exit 1
    fi
    
    cd -
}

# Test swift packages
test_swift_package tools/http-server-mock
test_swift_package tools/rum-models-generator
test_swift_package tools/sr-snapshots

# Test Python packages
test_python_package tools/issue_handler

# Test dogfooding automation:
echo_subtitle "Run 'make clean install test' in ./tools/dogfooding"
cd tools/dogfooding && make clean install test
cd -

