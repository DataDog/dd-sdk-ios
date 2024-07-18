#!/bin/zsh

# Usage:
# $ ./tools/dogfooding/dogfood.sh -h                                                                                   
# Updates the 'dd-sdk-ios' version in a dependent project and creates a dogfooding PR in its repository.

# Options:
#   --shopist       Dogfood in the Shopist iOS project.
#   --datadog-app   Dogfood in the Datadog iOS app.

set -eo pipefail
source ./tools/utils/argparse.sh
source ./tools/utils/echo-color.sh
source ./tools/utils/current-git.sh
source ./tools/secrets/get-secret.sh

set_description "Updates 'dd-sdk-ios' version in dependant project and opens dogfooding PR to its repo."
define_arg "shopist" "false" "Dogfood in Shopist iOS." "store_true"
define_arg "datadog-app" "false" "Dogfood in Datadog iOS app." "store_true"

check_for_help "$@"
parse_args "$@"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo_info "cd '$SCRIPT_DIR'" && cd "$SCRIPT_DIR"

DEPENDANT_REPO_CLONE_DIR="repos"

SDK_PACKAGE_PATH=$(realpath "../..")
SDK_VERSION_FILE_PATH=$(realpath "../../DatadogCore/Sources/Versioning.swift")
DOGFOODED_BRANCH="$(current_git_branch)"
DOGFOODED_COMMIT="$(current_git_commit)"
DOGFOODED_COMMIT_SHORT="$(current_git_commit_short)"
DOGFOODING_BRANCH_NAME="dogfooding-$DOGFOODED_COMMIT_SHORT" # the name of the branch to create in dependant repo

if [[ "$DOGFOODED_BRANCH" != "develop" ]]; then
    DRY_RUN=1
    echo_warn "DOGFOODED_BRANCH is not 'develop'. Enforcing DRY_RUN=1."
fi

echo_info "▸ PWD = '$(pwd)'"
echo_info "▸ DRY_RUN = '$DRY_RUN'"
echo_info "▸ SDK_PACKAGE_PATH = '$SDK_PACKAGE_PATH'"
echo_info "▸ SDK_VERSION_FILE_PATH = '$SDK_VERSION_FILE_PATH'"
echo_info "▸ DOGFOODED_BRANCH = '$DOGFOODED_BRANCH'"
echo_info "▸ DOGFOODED_COMMIT = '$DOGFOODED_COMMIT'"
echo_info "▸ DOGFOODED_COMMIT_SHORT = '$DOGFOODED_COMMIT_SHORT'"
echo_info "▸ DOGFOODING_BRANCH_NAME = '$DOGFOODING_BRANCH_NAME'"

# Prepares dogfooding package.
prepare() {
    echo_subtitle "Prepare dogfooding package"
    rm -rf "$DEPENDANT_REPO_CLONE_DIR"
    mkdir -p "$DEPENDANT_REPO_CLONE_DIR"
    make clean install
}

# Cleans up dogfooding package.
cleanup() {
    echo_subtitle "Clean dogfooding package"
    make clean
    rm -rf "$DEPENDANT_REPO_CLONE_DIR"
}

# Clones dependant repo.
clone_repo() {
    local ssh="$1"
    local branch="$2"
    local clone_path="$3"
    echo_subtitle "Clone '$REPO_NAME' repo (branch: '$branch')"
    git clone --branch $branch --single-branch $1 $clone_path
}

# Creates dogfooding commit in dependant repo.
commit_repo() {
    local repo_path="$1"
    echo_subtitle "Commit '$REPO_NAME' repo"
    cd "$repo_path"
    git checkout -b "$DOGFOODING_BRANCH_NAME"
    git add .
    git commit -m "Dogfooding dd-sdk-ios commit: $DOGFOODED_COMMIT"
    cd -
}

# Pushes dogfooding branch to dependant repo.
push_repo() {
    local repo_path="$1"
    echo_subtitle "Push '$DOGFOODING_BRANCH_NAME' to '$REPO_NAME' repo"
    cd "$repo_path"
    if [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "true" ]; then
        echo_warn "Running in DRY RUN mode. Skipping 'git push'."
    else
        git push -u origin "$DOGFOODING_BRANCH_NAME" --force
    fi
    cd -
}

# Creates dogfooding PR in dependant repo.
create_pr() {
    local repo_path="$1"
    local changelog="$2"
    local target_branch="$3"
    echo_subtitle "Create PR in '$REPO_NAME' repo"
    echo_info "▸ Exporting 'GITHUB_TOKEN' for CI"
    export GITHUB_TOKEN=$(get_secret $DD_IOS_SECRET__GH_CLI_TOKEN)
    echo_info "▸ gh auth status"
    gh auth status
    if [[ $? -ne 0 ]]; then
        echo_err "Error:" "GitHub CLI is not authenticated."
        exit 1
    fi

    PR_TITLE="[Dogfooding] Upgrade dd-sdk-ios to \`$DOGFOODED_SDK_VERSION\`"
    PR_DESCRIPTION="$(cat <<EOF
⚙️ This is an automated PR upgrading the version of 'dd-sdk-ios' to:
- https://github.com/DataDog/dd-sdk-ios/commit/$DOGFOODED_COMMIT

### 🎁 What's new:
$changelog
EOF
)"

    echo "▸ Using PR_TITLE = '$PR_TITLE'"
    echo "▸ Using PR_DESCRIPTION = '$PR_DESCRIPTION'"

    cd "$repo_path"
    if [ "$DRY_RUN" = "1" ] || [ "$DRY_RUN" = "true" ]; then
        echo_warn "Running in DRY RUN mode. Skipping 'gh pr create'."
    else
        gh pr create --title "$PR_TITLE" --body "$PR_DESCRIPTION" --draft --head "$DOGFOODING_BRANCH_NAME" --base "$target_branch"
    fi
    cd -
}

# Resolves dependencies version in `dd-sdk-ios`.
resolve_dd_sdk_ios_package() {
    echo_subtitle "Resolve dd-sdk-ios package in '$SDK_PACKAGE_PATH'"
    swift package --package-path "$SDK_PACKAGE_PATH" resolve
    echo "dd-sdk-ios dependencies:"
    swift package --package-path "$SDK_PACKAGE_PATH" show-dependencies
}

# Reads sdk_version from current commit and stores it in DOGFOODED_SDK_VERSION variable.
read_dogfooded_version() {
    echo_subtitle "Read sdk_version from '$SDK_VERSION_FILE_PATH'"
    sdk_version=$(grep 'internal let __sdkVersion' "$SDK_VERSION_FILE_PATH" | awk -F'"' '{print $2}')
    DOGFOODED_SDK_VERSION="$sdk_version-$DOGFOODED_COMMIT_SHORT" # e.g. '2.14.1-b5215c02'
    echo_info "▸ SDK version is '$sdk_version'"
    echo_succ "▸ Using '$DOGFOODED_SDK_VERSION' for dogfooding"
}

# Reads the hash of previously dogfooded commit to LAST_DOGFOODED_COMMIT variable.
read_last_dogfooded_commit() {
    local package_resolved_path="$1"
    echo_subtitle "Get last dogfooded commit hash in '$REPO_NAME' repo"
    output=$(make run PARAMS="read-dogfooded-hash.py --repo-package-resolved-path '$package_resolved_path'")
    echo "$output"
    LAST_DOGFOODED_COMMIT=$(echo "$output" | awk -F 'DOGFOODED_HASH=' '/DOGFOODED_HASH/ {print $2}')
}

# Prints changes since LAST_DOGFOODED_COMMIT.
print_changelog_since_last_dogfooded_commit() {
    echo_subtitle "Generate changelog" >&2

    if [ "$CI" = "true" ]; then
        # Fetch branch history and unshallow in GitLab which only does shallow clone by default
        echo_info "▸ Fetching git history " >&2
        git fetch -q --unshallow >&2
    fi

    # Read git history from last dogfooded commit to current:
    echo_info "▸ Reading commits ($LAST_DOGFOODED_COMMIT..HEAD):" >&2
    git_log=$(git --no-pager log \
                    --pretty=oneline "$LAST_DOGFOODED_COMMIT..HEAD" \
                    --ancestry-path "origin/$DOGFOODED_BRANCH"
    )
    echo_info ">>> git log begin" >&2
    echo "$git_log" >&2
    echo_info "<<< git log end" >&2

    # Extract only merge commits:
    CHANGELOG=$(echo "$git_log" | grep -o 'Merge pull request #[0-9]\+' | awk -F'#' '{print "- https://github.com/DataDog/dd-sdk-ios/pull/"$2}' || true)
    if [ -z "$CHANGELOG" ]; then
        CHANGELOG="- Empty (no PRs merged since https://github.com/DataDog/dd-sdk-ios/commit/$LAST_DOGFOODED_COMMIT)"
    fi

    echo_info "▸ Changelog:" >&2
    echo_info ">>> changelog begin" >&2
    echo_succ "$CHANGELOG" >&2
    echo_info "<<< changelog end" >&2

    echo "$CHANGELOG"
}

# Updates dd-sdk-ios version in dependant project to DOGFOODED_COMMIT.
update_dependant_package_resolved() {
    local package_resolved_path="$1"
    echo_subtitle "Update dd-sdk-ios version in '$package_resolved_path'"
    make run PARAMS="update-dependency.py \
        --repo-package-resolved-path '$package_resolved_path' \
        --dogfooded-package-resolved-path '$SDK_PACKAGE_PATH/Package.resolved' \
        --dogfooded-branch '$DOGFOODED_BRANCH' \
        --dogfooded-commit '$DOGFOODED_COMMIT'"
}

# Updates 'sdk_version' in dependant project to DOGFOODED_SDK_VERSION.
update_dependant_sdk_version() {
    local version_file="$1"
    echo_subtitle "Update 'sdk_version' in '$version_file'"

    echo_info ">>> '$version_file' before"
    cat "$version_file"
    echo_info "<<< '$version_file' before"

    # sed -i '' "s/internal let __dogfoodedSDKVersion = \".*\"/internal let __dogfoodedSDKVersion = \"$DOGFOODED_SDK_VERSION\"/" "$version_file"
    sed -i '' -E "s/(let __dogfoodedSDKVersion = \")[^\"]*(\")/\1${DOGFOODED_SDK_VERSION}\2/" "$version_file"
    echo_succ "▸ Updated '$version_file' to:"

    echo_info ">>> '$version_file' after"
    cat "$version_file"
    echo_info "<<< '$version_file' after"
}

prepare
trap "cleanup" EXIT INT

read_dogfooded_version
resolve_dd_sdk_ios_package

if [ "$shopist" = "true" ]; then
    REPO_NAME="shopist-ios"
    CLONE_PATH="$DEPENDANT_REPO_CLONE_DIR/$REPO_NAME"
    DEFAULT_BRANCH="main"

    clone_repo "git@github.com:DataDog/shopist-ios.git" $DEFAULT_BRANCH $CLONE_PATH

    # Generate CHANGELOG:
    read_last_dogfooded_commit "$CLONE_PATH/Shopist/Shopist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    CHANGELOG=$(print_changelog_since_last_dogfooded_commit)
    
    # Update dd-sdk-ios version:
    update_dependant_package_resolved "$CLONE_PATH/Shopist/Shopist.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    update_dependant_sdk_version "$CLONE_PATH/Shopist/Shopist/DogfoodingConfig.swift"

    # Push & create PR:
    commit_repo $CLONE_PATH
    push_repo $CLONE_PATH
    create_pr $CLONE_PATH $CHANGELOG $DEFAULT_BRANCH
fi

if [ "$datadog_app" = "true" ]; then
    REPO_NAME="datadog-ios"
    CLONE_PATH="$DEPENDANT_REPO_CLONE_DIR/$REPO_NAME"
    DEFAULT_BRANCH="develop"

    clone_repo "git@github.com:DataDog/datadog-ios.git" $DEFAULT_BRANCH $CLONE_PATH

    # Generate CHANGELOG:
    read_last_dogfooded_commit "$CLONE_PATH/DatadogApp.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    CHANGELOG=$(print_changelog_since_last_dogfooded_commit)
    
    # Update dd-sdk-ios version:
    update_dependant_package_resolved "$CLONE_PATH/DatadogApp.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    update_dependant_package_resolved "$CLONE_PATH/.package.resolved"
    update_dependant_sdk_version "$CLONE_PATH/Targets/DogLogger/Datadog/DogfoodingConfig.swift"

    # Push & create PR:
    commit_repo $CLONE_PATH
    push_repo $CLONE_PATH
    create_pr $CLONE_PATH $CHANGELOG $DEFAULT_BRANCH
fi
