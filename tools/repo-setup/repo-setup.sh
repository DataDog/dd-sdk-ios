#!/bin/zsh

# Usage:
# $ ./tools/repo-setup/repo-setup.sh -h
# Prepares the repository for development and testing in given ENV.

# Options:
#   --env: Specifies the environment for preparation. Use 'dev' for local development and 'ci' for CI.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh

set_description "Prepares the repository for development and testing in given ENV."
define_arg "env" "" "Specifies the environment for preparation. Use 'dev' for local development and 'ci' for CI." "string" "true"

check_for_help "$@"
parse_args "$@"

ENV_DEV="dev"
ENV_CI="ci"

if [[ "$env" != "$ENV_CI" && "$env" != "$ENV_DEV" ]]; then
  echo_err "Error: env variable must be 'ci' or 'dev'."
  exit 1
fi

# Materialize CI xcconfig:
cp -vi "./tools/repo-setup/Base.ci.xcconfig.src" ./xcconfigs/Base.ci.local.xcconfig

# Materialize DEV xcconfig:
if [[ "$env" == "$ENV_DEV" ]]; then
  cp -vi "./tools/repo-setup/Base.dev.xcconfig.src" ./xcconfigs/Base.dev.local.xcconfig
fi

bundle install
carthage bootstrap --platform iOS,tvOS --use-xcframeworks

echo_succ "Using OpenTelemetryApi version: $(cat ./Carthage/Build/.OpenTelemetryApi.version | grep 'commitish' | awk -F'"' '{print $4}')"
echo_succ "Using PLCrashReporter version: $(cat ./Carthage/Build/.plcrashreporter.version | grep 'commitish' | awk -F'"' '{print $4}')"
