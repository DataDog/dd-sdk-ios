#!/bin/zsh

# Usage:
# ./tools/smoke-test.sh -h
# Executes smoke tests in the specified --test-directory, using the provided --os, --platform, and --device.

# Options:
#   --device: Specifies the simulator device for running tests, e.g., 'iPhone 15 Pro'
#   --platform: Defines the type of simulator platform for the tests, e.g., 'iOS Simulator'
#   --os: Sets the operating system version for the tests, e.g., '17.5'
#   --test-directory: Specifies the directory where the smoke tests are located

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo_color.sh
source ./tools/utils/current_git.sh

set_description "Executes smoke tests in the specified --test-directory, using the provided --os, --platform, and --device."
define_arg "test-directory" "" "Specifies the directory where the smoke tests are located" "string" "true"
define_arg "os" "" "Sets the operating system version for the tests, e.g., '17.5'" "string" "true"
define_arg "platform" "" "Defines the type of simulator platform for the tests, e.g., 'iOS Simulator'" "string" "true"
define_arg "device" "" "Specifies the simulator device for running tests, e.g., 'iPhone 15 Pro'" "string" "true"

check_for_help "$@"
parse_args "$@"

echo_subtitle "Run 'make clean install test OS=\"$os\" PLATFORM=\"$platform\" DEVICE=\"$device\"' in '$test_directory'"
echo_succ "Smoke testing for git ref: '$(current_git_ref)'"
cd "$test_directory" && make clean install test OS="$os" PLATFORM="$platform" DEVICE="$device"
cd -
