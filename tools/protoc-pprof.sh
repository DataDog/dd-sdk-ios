#!/bin/zsh

# Usage:
# $ ./tools/pprof-protoc.sh --proto-path DatadogProfiling/Protos/profile.proto --output-dir DatadogProfiling/Mach

set -e
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh

set_description "Generate protobuf-c implementation from pprof proto with symbol prefixing.

This script:
1. Takes a profile.proto file (Google pprof format) as input
2. Uses protoc to generate standard protobuf-c files (profile.pb-c.h and profile.pb-c.c)
3. Applies symbol prefix transformations to avoid conflicts with other protobuf-c libraries
4. Changes the include from system <protobuf-c/protobuf-c.h> to local \"protobuf-c.h\"
5. Replaces protobuf_c_ symbols with PROTOBUF_C_SYMBOL() macros for configurable prefixing

This prevents symbol collisions when statically linking with other libraries that also 
embed protobuf-c (e.g., PLCrashReporter)."

define_arg "proto-path" "" "Path to the profile.proto file" "string" "true"
define_arg "output-dir" "" "Output directory for generated files (include/ and .c files)" "string" "true"

check_for_help "$@"
parse_args "$@"

REPO_ROOT=$(realpath .)

echo_title "🔄 Generating pprof protobuf-c implementation with symbol prefixing"

# Check if protoc is available
if ! command -v protoc &> /dev/null; then
    echo_err "protoc is not installed or not in PATH"
    echo_info "Please install protocol buffer compiler:"
    echo_info "  brew install protobuf"
    exit 1
fi

echo_succ "Found protoc: $(which protoc)"

# Convert paths to absolute using REPO_ROOT
proto_path="$REPO_ROOT/$proto_path"
output_dir="$REPO_ROOT/$output_dir"

# Validate input file
if [[ ! -f "$proto_path" ]]; then
    echo_err "Proto file not found: $proto_path"
    exit 1
fi

# Validate output directory
if [[ ! -d "$output_dir" ]]; then
    echo_err "Output directory not found: $output_dir"
    exit 1
fi

# Create include directory if it doesn't exist
mkdir -p "$output_dir/include"

echo_info "Using profile.proto from: $proto_path"
echo_info "Generating protobuf-c files directly to output directory..."

# Generate files directly to output directory
protoc --proto_path="$(dirname "$proto_path")" --c_out="$output_dir" "$(basename "$proto_path")"
mv "$output_dir/profile.pb-c.h" "$output_dir/include/"

echo_info "Applying profiling transformations..."

# 1. Update prefix: protobuf_c_ → PROTOBUF_C_SYMBOL()
sed -i '' -E 's/protobuf_c_([a-z_]+)/PROTOBUF_C_SYMBOL(\1)/g' "$output_dir/include/profile.pb-c.h"
sed -i '' -E 's/protobuf_c_([a-z_]+)/PROTOBUF_C_SYMBOL(\1)/g' "$output_dir/profile.pb-c.c"
# 2. Change the include: <protobuf-c/protobuf-c.h> → "protobuf-c.h"
sed -i '' 's/#include <protobuf-c\/protobuf-c.h>/#include "protobuf-c.h"/' "$output_dir/include/profile.pb-c.h"

echo_succ "Complete! Generated files:"
echo_info "  - $output_dir/include/profile.pb-c.h"
echo_info "  - $output_dir/profile.pb-c.c"
echo ""
echo_info "The generated files use PROTOBUF_C_SYMBOL() macros which will be"
echo_info "prefixed according to the setting in protobuf-c.h"
