#!/bin/zsh

# Usage:
# $ ./tools/protoc-ufc.sh --plugin-path <path to protoc-gen-swift>

set -e
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh

set_description "Generate Swift types for the rules-based flags configuration from ufc.proto.

This script:
1. Takes DatadogFlags/Protos/ufc.proto as input
2. Uses protoc and the protoc-gen-swift plugin to generate ufc.pb.swift with internal types
3. Keeps the SwiftProtobuf import internal, so SwiftProtobuf is not part of the DatadogFlags public interface
4. Changes the Foundation imports to plain imports, as in the other DatadogFlags files

The protoc-gen-swift version must be the minimum SwiftProtobuf version in Package.swift."

define_arg "plugin-path" "protoc-gen-swift" "Path to the protoc-gen-swift plugin (default: from PATH)" "string" "false"

check_for_help "$@"
parse_args "$@"

EXPECTED_PLUGIN_VERSION="1.38.1"
PROTO_DIR="DatadogFlags/Protos"
OUTPUT_DIR="DatadogFlags/Sources/Rules/Generated"

echo_title "Generating Swift types for ufc.proto"

if ! command -v protoc &> /dev/null; then
    echo_err "protoc is not installed or not in PATH"
    echo_info "Please install protocol buffer compiler:"
    echo_info "brew install protobuf"
    exit 1
fi

plugin=$(command -v "$plugin_path" || true)
if [[ -z "$plugin" ]]; then
    echo_err "protoc-gen-swift not found: $plugin_path"
    echo_info "Build it from SwiftProtobuf $EXPECTED_PLUGIN_VERSION:"
    echo_info "swift build -c release --product protoc-gen-swift"
    exit 1
fi

plugin_version=$("$plugin" --version | awk '{print $2}')
if [[ "$plugin_version" != "$EXPECTED_PLUGIN_VERSION" ]]; then
    echo_err "protoc-gen-swift $plugin_version found, but $EXPECTED_PLUGIN_VERSION is required"
    exit 1
fi

echo_succ "Found protoc: $(command -v protoc)"
echo_succ "Found protoc-gen-swift $plugin_version: $plugin"

protoc \
    --plugin=protoc-gen-swift="$plugin" \
    --proto_path="$PROTO_DIR" \
    --swift_out="$OUTPUT_DIR" \
    --swift_opt=Visibility=Internal \
    --swift_opt=UseAccessLevelOnImports=true \
    --swift_opt=FileNaming=DropPath \
    ufc.proto

# Other DatadogFlags files import Foundation without an access level. Swift rejects
# a module that is imported with an implicit level in one file and `internal` in another.
sed -i '' -E 's/^internal import (Foundation|FoundationEssentials)$/import \1/' "$OUTPUT_DIR/ufc.pb.swift"

echo_succ "Complete! Generated file:"
echo_info "  - $OUTPUT_DIR/ufc.pb.swift"
