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
    
    # Check if virtual environment exists and use it, or create one if needed
    if [ -d "venv" ]; then
        echo "📦 Using existing virtual environment..."
        source venv/bin/activate
    else
        echo "📦 Creating virtual environment and installing dependencies..."
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt
    fi
    
    python -m pytest tests/ -v
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

