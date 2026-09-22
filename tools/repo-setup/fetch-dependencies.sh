#!/bin/zsh

# Usage:
# $ ./tools/repo-setup/fetch-dependencies.sh
# Fetches the prebuilt third-party XCFrameworks that `Datadog.xcodeproj` links by path.

set -eo pipefail

source ./tools/utils/echo-color.sh

OTEL_API_VERSION="2.5.0"
OTEL_API_URL="https://github.com/DataDog/opentelemetry-swift-packages/releases/download/${OTEL_API_VERSION}/OpenTelemetryApi.zip"

DEPENDENCIES_DIR="./Dependencies"
XCFRAMEWORK="${DEPENDENCIES_DIR}/OpenTelemetryApi.xcframework"
VERSION_FILE="${DEPENDENCIES_DIR}/.OpenTelemetryApi.version"

if [[ -d "$XCFRAMEWORK" && "$(cat "$VERSION_FILE" 2>/dev/null)" == "$OTEL_API_VERSION" ]]; then
    echo_succ "Using OpenTelemetryApi version: $OTEL_API_VERSION" "(already fetched)"
    exit 0
fi

echo_info "Fetching OpenTelemetryApi:" "$OTEL_API_URL"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

curl --fail --location --silent --show-error --output "${tmp_dir}/OpenTelemetryApi.zip" "$OTEL_API_URL"
unzip -q "${tmp_dir}/OpenTelemetryApi.zip" -d "$tmp_dir"

mkdir -p "$DEPENDENCIES_DIR"
rm -rf "$XCFRAMEWORK"
mv "${tmp_dir}/OpenTelemetryApi/OpenTelemetryApi.xcframework" "$XCFRAMEWORK"
echo "$OTEL_API_VERSION" > "$VERSION_FILE"

echo_succ "Using OpenTelemetryApi version: $OTEL_API_VERSION"
