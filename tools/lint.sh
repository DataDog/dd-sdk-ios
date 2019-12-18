#!/bin/bash

CURRENT_DIR=${PWD##*/}

if [ "$CURRENT_DIR" != "dd-sdk-ios" ]; then 
	echo "\`lint.sh\` must be run in repository root folder: \`./tools/lint.sh\`"; exit 1
fi

[[ -z "${XCODE_VERSION_ACTUAL}" ]] && REPORTER='emoji' || REPORTER="xcode"

swiftlint lint --config ./tools/lint/sources.swiftlint.yml --reporter "$REPORTER"
swiftlint lint --config ./tools/lint/tests.swiftlint.yml --reporter "$REPORTER"
