#!/bin/zsh

set -eo pipefail

source ./tools/utils/echo-color.sh

./tools/carthage-shim.sh bootstrap --platform iOS,tvOS,watchOS,visionOS --use-xcframeworks

echo_succ "Using OpenTelemetryApi version: $(cat ./Carthage/Build/.OpenTelemetryApi.version | grep 'commitish' | awk -F'"' '{print $4}')"