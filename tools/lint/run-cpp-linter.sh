#!/bin/zsh

if [ ! -f ".clang-tidy" ]; then
	echo "\`run-cpp-linter.sh\` must be run in repository root folder: \`./tools/lint/run-cpp-linter.sh\`"; exit 1
fi

automatic_fix=""
while :; do
    case $1 in
        --fix) automatic_fix="--fix"            
        ;;
        *) break
    esac
    shift
done

# Find clang-tidy in common Homebrew locations (Apple Silicon and Intel)
CLANG_TIDY=""
for prefix in /opt/homebrew /usr/local; do
    if [ -x "${prefix}/opt/llvm/bin/clang-tidy" ]; then
        CLANG_TIDY="${prefix}/opt/llvm/bin/clang-tidy"
        break
    fi
done

if [ -z "$CLANG_TIDY" ]; then
	echo "warning: clang-tidy not found. Install with: brew install llvm. Skipping C++ linting."; exit 0
fi

SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
CPP_SOURCE_DIR="./DatadogProfiling/Mach"
INCLUDE_DIR="${CPP_SOURCE_DIR}/include"

# Collect source files, excluding generated protobuf code
CPP_FILES=()
for file in ${CPP_SOURCE_DIR}/*.cpp; do
	CPP_FILES+=("$file")
done

if [ ${#CPP_FILES[@]} -eq 0 ]; then
	echo "No C++ source files found in ${CPP_SOURCE_DIR}"; exit 0
fi

EXTRA_ARGS=(
	"--extra-arg=-isysroot${SDK_PATH}"
	"--extra-arg=-I${INCLUDE_DIR}"
	"--extra-arg=-std=c++17"
	"--extra-arg=-target"
	"--extra-arg=arm64-apple-ios12.0"
)

HEADER_FILTER=".*DatadogProfiling/Mach/include/(?!protobuf-c\.h|profile\.pb-c\.h).*"

if [[ -z "${XCODE_VERSION_ACTUAL}" ]]; then
	# when run from command line
	set -e
	echo "Running clang-tidy on C++ sources..."
	$CLANG_TIDY "${EXTRA_ARGS[@]}" --header-filter="$HEADER_FILTER" $automatic_fix ${CPP_FILES[@]} --
else
	# when run by Xcode in Build Phase
	$CLANG_TIDY "${EXTRA_ARGS[@]}" --header-filter="$HEADER_FILTER" ${CPP_FILES[@]} --
fi
