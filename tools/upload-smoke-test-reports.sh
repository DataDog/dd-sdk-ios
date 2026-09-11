#!/bin/zsh

# Uploads smoke-test JUnit reports to Datadog Test Visibility.

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/secrets/get-secret.sh

reports_path="artifacts/smoke-test-reports"
report_files=("$reports_path"/**/*.xml(N))

if (( ${#report_files} == 0 )); then
    echo_warn "No smoke-test JUnit reports found. Skipping Test Visibility upload."
    exit 0
fi

export DATADOG_API_KEY="$(get_secret "$DD_IOS_SECRET__TEST_VISIBILITY_API_KEY")"
export DD_ENV="ci"

datadog-ci junit upload \
    --service "dd-sdk-ios" \
    --git-repository-url "git@github.com:DataDog/dd-sdk-ios.git" \
    "$reports_path"
