#!/bin/bash

CURRENT_DIR=${PWD##*/}

if [ "$CURRENT_DIR" != "dd-sdk-ios" ]; then 
	echo "\`kickoff.sh\` must be run in repository root folder: \`./tools/kickoff.sh\`"; exit 1
fi

# Generate `Datadog.xcodeproj`
swift package generate-xcodeproj

# Install `swiftlint`
brew install swiftlint

# Install Datadog Xcode templates
./tools/xcode-templates/install-xcode-templates.sh

echo "💪 All good"