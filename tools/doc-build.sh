#!/usr/bin/env zsh

# Usage:
# $ ./tools/doc-build.sh -h
# This script runs xcodebuild docbuild for targets listed in a .spi.yml file to ensure SDK compatibility with https://swiftpackageindex.com/ documentation builds.

# Options:
#  --spi-path: Path to the .spi.yml file

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh

set_description "This script runs xcodebuild docbuild for targets listed in a .spi.yml file to ensure SDK compatibility with https://swiftpackageindex.com/ documentation builds."
define_arg "spi-path" "" "Path to the .spi.yml file" "string" "false"

check_for_help "$@"
parse_args "$@"

# Extract platform (first one)
platform=$(sed -n '/platform:/s/.*platform: *//p' "$spi_path" | head -n 1)

if [[ -z "$platform" ]]; then
  echo_err "Error: platform not found in $spi_path"
  exit 1
fi

# Extract documentation_targets block (YAML list):
# - Find line with 'documentation_targets:'
# - From that line, grab all lines that start with '  - ' (two spaces + dash)
# - Trim leading spaces and dash

targets_list=()
inside_targets=0
while IFS= read -r line; do
  if [[ $inside_targets -eq 0 && "$line" =~ documentation_targets: ]]; then
    inside_targets=1
    continue
  fi

  if [[ $inside_targets -eq 1 ]]; then
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*)$ ]]; then
      target="${line#*- }"
      targets_list+=("$target")
    else
      # End of list (non-list line or empty)
      break
    fi
  fi
done < "$spi_path"

if [[ ${#targets_list[@]} -eq 0 ]]; then
  echo_err "Error: documentation_targets not found or empty in $spi_path"
  exit 1
fi

for target in "${targets_list[@]}"; do
  echo_subtitle "Building docs for target: '$target' on platform: '$platform'"
  xcodebuild \
    -skipMacroValidation \
    -skipPackagePluginValidation \
    docbuild \
    -scheme "$target" \
    -destination "generic/platform=$platform" | xcbeautify
done
