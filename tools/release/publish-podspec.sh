#!/bin/zsh

# Usage:
# $ ./tools/release/publish-podspec.sh -h
# Publishes podspec to Cocoapods trunk.

# Options:
#   --artifacts-path: The path to build artifacts.
#   --podspec-name: The name of podspec file to publish.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh
source ./tools/secrets/get-secret.sh

set_description "Publishes podspec to Cocoapods trunk."
define_arg "podspec-name" "" "The name of podspec file to publish." "string" "true"
define_arg "artifacts-path" "" "The path to build artifacts." "string" "true"

check_for_help "$@"
parse_args "$@"

REPO_PATH="$artifacts_path/dd-sdk-ios"
PODSPEC_PATH="$REPO_PATH/$podspec_name"

authenticate() {
    echo_subtitle "Authenticate 'pod trunk' CLI"
    echo_info "Exporting 'COCOAPODS_TRUNK_TOKEN' for CI"
    export COCOAPODS_TRUNK_TOKEN=$(get_secret $DD_IOS_SECRET__CP_TRUNK_TOKEN)
    echo_info "▸ bundle exec pod trunk me" && bundle exec pod trunk me
    if [[ $? -ne 0 ]]; then
        echo_err "Error: 'pod trunk' is not authenticated."
        exit 1
    fi
}

lint() {
    echo_subtitle "Lint '$podspec_name'"
    echo_info "▸ cd '$REPO_PATH'" && cd "$REPO_PATH"
    echo_info "▸ bundle exec pod repo update --silent" && bundle exec pod repo update --silent
    echo_info "▸ bundle exec pod spec lint --allow-warnings '$podspec_name'"
    LAST_POD_OUTPUT=$(bundle exec pod spec lint --allow-warnings "$podspec_name" 2>&1)
    LAST_POD_EXIT_CODE=$?
    echo_info "▸ cd -" && cd -
}

push() {
    echo_subtitle "Push '$podspec_name' to trunk"
    echo_info "▸ cd '$REPO_PATH'" && cd "$REPO_PATH"
    echo_info "▸ bundle exec pod trunk push --synchronous --allow-warnings '$podspec_name'"
    if [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "true" ]; then
        echo_warn "Running in DRY RUN mode. Skipping."
        LAST_POD_OUTPUT=""
        LAST_POD_EXIT_CODE=0
    else
        LAST_POD_OUTPUT=$(bundle exec pod trunk push --synchronous --allow-warnings "$podspec_name" 2>&1)
        LAST_POD_EXIT_CODE=$?
    fi
    echo_info "▸ cd -" && cd -
}

# Track the exit state of the last `pod` command:
LAST_POD_OUTPUT=""
LAST_POD_EXIT_CODE=-1

# Status indicating the pod command returned success.
POD_STATUS__SUCCESS=0

# Status indicating the pod command needs a retry due to a podspec dependency issue.
# Likely one of the dependencies is still being processed in trunk so we need to wait and retry.
POD_STATUS__NEEDS_RETRY=1

# Status indicating the podspec already exists in the trunk.
# Likely we're trying to re-publish a podspec that previously succeeded so we should skip.
POD_STATUS__ALREADY_EXISTS=2

# Status indicating an unexpected error occurred when processing the podspec.
POD_STATUS__ERROR=3

# Checks the status of the last executed `pod` command.
#
# It validates LAST_POD_EXIT_CODE and parses the LAST_POD_OUTPUT in order to look for known reasons for
# pod command failure. It returns one of the predefined POD_STATUS__ values.
#
# Returns:
#   POD_STATUS__SUCCESS     : If the command succeeds.
#   POD_STATUS__NEEDS_RETRY : If the command fails due to a dependency issue and requires retrying.
#   POD_STATUS__ALREADY_EXISTS : If the podspec already exists in the trunk.
#   POD_STATUS__ERROR       : If an unexpected error occured in the last `pod` command.
check_pod_command_status() {
    # This error likely indicates that podspec for one of dependencies isn not yet available
    #
    # Example:
    # ```
    #  -> DatadogObjc (2.11.1)
    #     - ERROR | [iOS] unknown: Encountered an unknown error (CocoaPods could not find compatible versions for pod "DatadogRUM":
    #   In Podfile:
    #     DatadogObjc (from `/private/var/.../dd-sdk-ios/DatadogObjc.podspec`) was resolved to 2.11.1, which depends on
    #       DatadogRUM (= 2.11.1)
    # ```
    # Ref.: https://github.com/CocoaPods/Molinillo/blob/1d62d7d5f448e79418716dc779a4909509ccda2a/lib/molinillo/errors.rb#L106
    POD_DEPENDENCY_ERROR="CocoaPods could not find compatible versions for pod"

    # Example:
    # ```
    # Validating podspec
    #  -> DatadogInternal
    #  -> DatadogInternal (2.11.1)
    #    - NOTE  | ...
    # [!] Unable to accept duplicate entry for: DatadogInternal (2.11.1)
    # ```
    # Ref.: https://github.com/CocoaPods/trunk.cocoapods.org/blob/b6c897b53dd7a33e5fb2715e08a72d47901fe85f/app/controllers/api/pods_controller.rb#L174
    POD_DUPLICATE_ERROR="Unable to accept duplicate entry for: ${podspec_name%.*}"

    echo "▸ Parsing output for last pod command (exit code: $LAST_POD_EXIT_CODE)"

    if [ "$LAST_POD_EXIT_CODE" = "0" ]; then
        echo_succ "▸ returning POD_STATUS__SUCCESS"
        return $POD_STATUS__SUCCESS
    fi

    if echo "$LAST_POD_OUTPUT" | grep -q "$POD_DEPENDENCY_ERROR"; then
        echo_warn "▸ Matched dependency error:"
        echo "..."
        echo "$LAST_POD_OUTPUT" | grep -C 3 "$POD_DEPENDENCY_ERROR"
        echo "..."
        echo_warn "▸ Returning POD_STATUS__NEEDS_RETRY"
        return $POD_STATUS__NEEDS_RETRY
    fi

    if echo "$LAST_POD_OUTPUT" | grep -q "$POD_DUPLICATE_ERROR"; then
        echo_warn "▸ Matched duplicated entry error:"
        echo "..."
        echo "$LAST_POD_OUTPUT" | grep -C 3 "$POD_DUPLICATE_ERROR"
        echo "..."
        echo_warn "▸ Returning POD_STATUS__ALREADY_EXISTS"
        return $POD_STATUS__ALREADY_EXISTS
    fi

    echo_err "▸ Encountered unexpected pod output:"
    echo "$LAST_POD_OUTPUT"
    echo_err "▸ Returning POD_STATUS__ERROR"
    return $POD_STATUS__ERROR
}

# This function attempts to execute a specified pod command, checking its status after each execution. 
# If the command fails due to a dependency issue, it retries the command up to a specified number of times
# with a delay between each attempt.
#
# Parameters:
#   command (string)    : The pod command to be executed.
#   max_retries (int)   : The maximum number of retry attempts if the command needs to be retried.
#   retry_delay (int)   : The delay (in seconds) between retry attempts.
#
# Returns:
#   POD_STATUS__SUCCESS     : If the command succeeds.
#   POD_STATUS__NEEDS_RETRY : If the command fails due to a dependency issue and requires retrying.
#   POD_STATUS__ALREADY_EXISTS : If the podspec already exists in the trunk.
#   POD_STATUS__ERROR       : If an unexpected error occurs or if the maximum number of retries is exceeded.
#
retry_pod_command() {
    local command=$1
    local max_retries=$2
    local retry_delay=$3
    local retry_count=0

    while [ $retry_count -lt $max_retries ]; do
        $command
        check_pod_command_status
        local pod_status=$?
        if [ $pod_status -eq $POD_STATUS__SUCCESS ]; then
            echo_succ "▸ Success"
            return $POD_STATUS__SUCCESS
        elif [ $pod_status -eq $POD_STATUS__NEEDS_RETRY ]; then
            echo_info "▸ Retrying due to dependency issue (attempt $((retry_count + 1))/$max_retries)..."
            retry_count=$((retry_count + 1))
            sleep $retry_delay
        elif [ $pod_status -eq $POD_STATUS__ALREADY_EXISTS ]; then
            echo_succ "▸ Podspec already exists in trunk. Skipping."
            return $POD_STATUS__ALREADY_EXISTS
        elif [ $pod_status -eq $POD_STATUS__ERROR ]; then
            echo_err "▸ Error encountered. Exiting."
            return $POD_STATUS__ERROR
        fi
    done

    echo_err "▸ Exceeded maximum retries. Exiting."
    return $POD_STATUS__ERROR
}

echo_info "Publishing '$podspec_name'"
echo "▸ Using PODSPEC_PATH = $PODSPEC_PATH"
echo "▸ Using DRY_RUN = $DRY_RUN"

echo_info "▸ cd '$REPO_PATH'" && cd "$REPO_PATH"
echo_info "▸ bundle install --quiet" && bundle install --quiet
echo_info "▸ cd -" && cd -

authenticate

set +e  # disable exit on error because we do custom error handling here

# Retry lint command (up to 50 times with 1 minute delay)
retry_pod_command lint 50 60
lint_status=$?
if [ $lint_status -ne $POD_STATUS__SUCCESS ] && [ $lint_status -ne $POD_STATUS__ALREADY_EXISTS ]; then
    exit 1
fi

# Retry push command (up to 50 times with 1 minute delay)
retry_pod_command push 50 60
push_status=$?
if [ $push_status -ne $POD_STATUS__SUCCESS ] && [ $push_status -ne $POD_STATUS__ALREADY_EXISTS ]; then
    exit 1
fi

set -e
