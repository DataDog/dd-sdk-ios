#!/bin/zsh

# Usage:
# $ ./tools/utils/current-git.sh -h 
# Prints the current Git reference, either a tag or a branch name.

# Options:
#   --print: Outputs the current Git reference to STDOUT (tag if available, branch otherwise)
#   --print-tag: Outputs the current Git tag to STDOUT (if available)
#   --print-branch: Outputs the current Git branch to STDOUT

set -eo pipefail

# Prints current git tag (if any)
function current_git_tag() {
    if [[ -n "$CI_COMMIT_TAG" ]]; then
        echo "$CI_COMMIT_TAG"
    fi
}

# Prints current git branch
function current_git_branch() {
    if [[ -n "$CI_COMMIT_BRANCH" ]]; then
        echo "$CI_COMMIT_BRANCH"
    else
        local git_branch=$(git rev-parse --abbrev-ref HEAD)
        echo "$git_branch"
    fi
}

# Prints current commit sha (short)
function current_git_commit_short() {
    if [[ -n "$CI_COMMIT_SHORT_SHA" ]]; then
        echo "$CI_COMMIT_SHORT_SHA"
    else
        local git_commit_short=$(git rev-parse --short HEAD)
        echo "$git_commit_short"
    fi
}

# Prints current tag (if any) and current branch otherwise.
function current_git_ref() {
    local tag=$(current_git_tag)
    if [[ -n "$tag" ]]; then
        echo $tag
    else
        current_git_branch
    fi
}

case "$1" in
    --print)
        current_git_ref
        ;;
    --print-tag)
        current_git_tag
        ;;
    --print-branch)
        current_git_branch
        ;;
    --print-commit-short)
        current_git_commit_short
        ;;
    *)
        ;;
esac
