#!/bin/zsh

# Usage:
# $ ./tools/factorykit/gate.sh -h
# Runs the FactoryKit documentation gate (scripts/foundation_check.py).
# The gate blocks only on documentation findings that the checked content introduces.

# Options:
#   --snapshot: Content to check: 'worktree', 'index', or a Git revision. Default: 'worktree'.
#   --against: Revision to compare with. Default: merge-base of HEAD and origin/develop.
#   --optional: Skip with a notice when the FactoryKit runtime is not installed.

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh
source ./tools/factorykit/common.sh

set_description "Runs the FactoryKit documentation gate through scripts/foundation_check.py."
define_arg "snapshot" "worktree" "Content to check: 'worktree', 'index', or a Git revision." "string" "false"
define_arg "against" "" "Revision to compare with. Default: merge-base of HEAD and origin/develop." "string" "false"
define_arg "optional" "false" "Skip with a notice when the FactoryKit runtime is not installed." "store_true"
check_for_help "$@"
parse_args "$@"

if [ ! -x "$FACTORYKIT_RUNTIME/bin/factorykit" ]; then
    if [ "$optional" = "true" ]; then
        echo_warn "Skipping the documentation gate:" "FactoryKit is not installed. Run 'make factorykit-setup' to enable it."
        exit 0
    fi
    echo_err "Error:" "FactoryKit is not installed. Run 'make factorykit-setup' first."
    exit 1
fi

if [ -z "$against" ]; then
    against=$(git merge-base HEAD origin/develop) || {
        echo_err "Error:" "Cannot compute the merge-base with origin/develop. Pass --against explicitly."
        exit 1
    }
fi

echo_info "Checking '$snapshot' against '$against'"
"$FACTORYKIT_RUNTIME/bin/python3" scripts/foundation_check.py --snapshot "$snapshot" --against "$against" --format text
