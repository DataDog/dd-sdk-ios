#!/bin/zsh

# Usage:
# $ ./tools/utils/current_git.sh -h 
# Prints the current Git reference, either a tag or a branch name.

# Options:
#   --print: Outputs the current Git reference to STDOUT

set -eo pipefail

function current_git_ref() {
    if [[ -n "$CI_COMMIT_TAG" ]]; then
        echo "$CI_COMMIT_TAG"
    elif [[ -n "$CI_COMMIT_BRANCH" ]]; then
        echo "$CI_COMMIT_BRANCH"
    else
        local git_branch=$(git rev-parse --abbrev-ref HEAD)
        echo "$git_branch"
    fi
}

case "$1" in
    --print)
        current_git_ref
        ;;
    *)
        ;;
esac
