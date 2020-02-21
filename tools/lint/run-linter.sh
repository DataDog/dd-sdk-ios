#!/bin/bash

if [ ! -f "Package.swift" ]; then
	echo "\`run-linter.sh\` must be run in repository root folder: \`./tools/lint/run-linter.sh\`"; exit 1
fi

if [[ -z "${XCODE_VERSION_ACTUAL}" ]]; then
	# when run from command line
	set -e # exit with error code if `swiftlint lint` fails
	swiftlint lint --config ./tools/lint/sources.swiftlint.yml --reporter "emoji" --strict
	swiftlint lint --config ./tools/lint/tests.swiftlint.yml --reporter "emoji" --strict
else
	# when run by Xcode in Build Phase
	swiftlint lint --config ./tools/lint/sources.swiftlint.yml --reporter "xcode"
	swiftlint lint --config ./tools/lint/tests.swiftlint.yml --reporter "xcode"
fi
