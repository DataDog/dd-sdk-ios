#!/bin/bash

if [ ! -f "Package.swift" ]; then
    echo "\`install-xcode-templates.sh\` must be run in repository root folder: \`./tools/xcode-templates/install-xcode-templates.sh\`"; exit 1
fi

XCODE_LOCATION=$(xcode-select -p)
XCODE_TEMPLATES_LOCATION="$XCODE_LOCATION/Library/Xcode/Templates/File Templates/"

if [ -z "$XCODE_LOCATION" ]; then
	echo "🔥 Failed to install Xcode templates - cannot determine Xcode installation with \`xcode-select -p\`."
	exit 1
fi

rm -r "$XCODE_TEMPLATES_LOCATION/Datadog" 2> /dev/null
cp -R "./tools/xcode-templates/Datadog" "$XCODE_TEMPLATES_LOCATION"
