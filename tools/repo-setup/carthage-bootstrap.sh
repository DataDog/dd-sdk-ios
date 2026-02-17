#!/bin/zsh

set -eo pipefail

source ./tools/utils/echo-color.sh

# OpenTelemetryApi 2.3.0 had its binary artifact replaced to add missing platform slices.
# Bust the Carthage cache for this specific version so the updated binary is always fetched.
OTEL_STALE_CACHE=~/Library/Caches/org.carthage.CarthageKit/binaries/OpenTelemetryApi/2.3.0
if [ -d "$OTEL_STALE_CACHE" ]; then
    echo_info "Clearing stale Carthage binary cache for OpenTelemetryApi 2.3.0..."
    rm -rf "$OTEL_STALE_CACHE"
fi

./tools/carthage-shim.sh bootstrap --platform iOS,tvOS,watchOS,visionOS --use-xcframeworks

echo_succ "Using OpenTelemetryApi version: $(cat ./Carthage/Build/.OpenTelemetryApi.version | grep 'commitish' | awk -F'"' '{print $4}')"