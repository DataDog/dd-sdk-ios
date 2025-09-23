#!/bin/bash
# Test runner script for the issue handler tool
# This script is designed to run in CI environments

set -eo pipefail

echo "🧪 Running issue handler tests..."

# Check if Python 3 is available
if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ Python 3 not found. Please ensure Python 3 is installed."
    exit 1
fi

echo "✅ Python 3 found: $(python3 --version)"

# Check if we're in the right directory
if [ ! -f "requirements.txt" ]; then
    echo "❌ requirements.txt not found. Please run this script from the tools/issue_handler directory."
    exit 1
fi

# Check if virtual environment exists and activate it
if [ -d "venv" ]; then
    echo "📦 Using existing virtual environment..."
    source venv/bin/activate
else
    echo "📦 Creating virtual environment and installing dependencies..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
fi

# Run tests
echo "🚀 Running pytest..."
python -m pytest tests/ -v --tb=short

echo "✅ All tests completed successfully!"
