#!/bin/zsh

# Usage:
# $ ./tools/factorykit/setup.sh -h
# Installs the pinned FactoryKit runtime used by `make docs-gate`.

set -eo pipefail
source ./tools/utils/echo-color.sh
source ./tools/utils/argparse.sh
source ./tools/factorykit/common.sh

set_description "Installs the pinned FactoryKit runtime used by 'make docs-gate'."

check_for_help "$@"
parse_args "$@"

if [ -x "$FACTORYKIT_RUNTIME/bin/factorykit" ]; then
    echo_succ "FactoryKit $FACTORYKIT_SHA is already installed in '$FACTORYKIT_RUNTIME'."
    exit 0
fi

find_python() {
    for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
        if command -v "$candidate" >/dev/null 2>&1 &&
            "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)'; then
            command -v "$candidate"
            return 0
        fi
    done
    return 1
}

PYTHON=$(find_python) || {
    echo_err "Error:" "FactoryKit requires Python 3.10 or newer."
    exit 1
}

# ddoghq/factorykit is an internal repository, so install over SSH with the developer's GitHub access.
SOURCE="git+ssh://git@github.com/ddoghq/factorykit.git@$FACTORYKIT_SHA"

echo_subtitle "Install FactoryKit $FACTORYKIT_SHA with $($PYTHON --version)"
# A virtual environment cannot be moved after creation, so build it in place
# and remove it if the install fails. The `factorykit` executable is written
# last, which makes it the marker of a completed install.
"$PYTHON" -m venv "$FACTORYKIT_RUNTIME"
if ! "$FACTORYKIT_RUNTIME/bin/python3" -m pip install --disable-pip-version-check --quiet "factorykit @ $SOURCE"; then
    rm -rf "$FACTORYKIT_RUNTIME"
    echo_err "Error:" "Failed to install FactoryKit from ddoghq/factorykit. Check your GitHub access to that repository."
    exit 1
fi

echo_succ "FactoryKit is ready in '$FACTORYKIT_RUNTIME'."
