#!/bin/zsh

# Usage:
# $ ./tools/ufc-decoder-check/run.sh --plugin-path <path to protoc-gen-swift>

set -e
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh

set_description "Check the hand-written ufc.proto decoder of DatadogFlags against SwiftProtobuf.

This script:
1. Generates SwiftProtobuf types from DatadogFlags/Protos/ufc.proto into the tool (not committed)
2. Builds the tool with the hand-written decoder sources of DatadogFlags
3. Decodes the same bytes with both decoders, compares every field, and compares decoding speed

Run it after every change to ufc.proto or to DatadogFlags/Sources/Rules."

define_arg "plugin-path" "protoc-gen-swift" "Path to the protoc-gen-swift plugin (default: from PATH)" "string" "false"

check_for_help "$@"
parse_args "$@"

TOOL_DIR="tools/ufc-decoder-check"
GENERATED_DIR="$TOOL_DIR/Sources/UFCDecoderCheck/Generated"

if ! command -v protoc &> /dev/null; then
    echo_err "protoc is not installed or not in PATH"
    echo_info "brew install protobuf"
    exit 1
fi

plugin=$(command -v "$plugin_path" || true)
if [[ -z "$plugin" ]]; then
    echo_err "protoc-gen-swift not found: $plugin_path"
    echo_info "Build it from SwiftProtobuf: swift build -c release --product protoc-gen-swift"
    exit 1
fi

mkdir -p "$GENERATED_DIR"
protoc \
    --plugin=protoc-gen-swift="$plugin" \
    --proto_path=DatadogFlags/Protos \
    --swift_out="$GENERATED_DIR" \
    --swift_opt=Visibility=Internal \
    --swift_opt=UseAccessLevelOnImports=false \
    --swift_opt=FileNaming=DropPath \
    ufc.proto

swift run --package-path "$TOOL_DIR" -c release UFCDecoderCheck
