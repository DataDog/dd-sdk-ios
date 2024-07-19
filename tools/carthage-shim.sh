#!/bin/zsh

# Usage:
# - in repo root:
# $ ./tools/carthage-shim.sh [carthage commands and parameters]
# - in different directory:
# $ REPO_ROOT="../../" ../../tools/carthage-shim.sh [carthage commands and parameters]
#
# Shims Carthage commands with avoiding rate-limiting on CI.

source "${REPO_ROOT:-.}/tools/secrets/get-secret.sh"

# "In shared environment where several virtual machines are using the same public ip address (like CI),
# carthage user could hit a Github API rate limit. By providing a Github API access token, carthage can get
# a higher rate limit."
# Ref.: https://github.com/Carthage/Carthage/pull/605
if [ "$CI" = "true" ]; then
    export GITHUB_ACCESS_TOKEN=$(get_secret $DD_IOS_SECRET__CARTHAGE_GH_TOKEN)
fi

carthage "$@"
