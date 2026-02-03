#!/bin/bash

function usage() {
  cat << EOF
Usage: $(basename "${BASH_SOURCE[0]}") -d /path/to/files <new podspec version>

Set version in podspecs.

Available options:

-h, --help      Print this help and exit.
-d, --directory The directory with podspecs. Current dir by default.

EOF
  exit
}

# default arguments
DIRECTORY=.

# read cmd arguments
while :; do
    case $1 in
        -d|--directory) DIRECTORY=$2
        shift
        ;;
        -h|--help) usage
        shift
        ;;
        *) break
    esac
    shift
done

if [ -z "$1" ]; then usage; fi

# Find all podspecs in dir and replace occurrence of '"*"' in lines containing 's.version '.
find $DIRECTORY -maxdepth 1 -type f -name "*.podspec" -exec sed -i '' -e '/s\.version[[:space:]]/s/"[^"]*"/"'$1'"/' {} +
