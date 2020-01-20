#!/bin/bash

if [ ! -f "Package.swift" ]; then
	echo "\`kickoff.sh\` must be run in repository root folder: \`./tools/kickoff.sh\`"; exit 1
fi

# Generate `Datadog.xcodeproj`
swift package generate-xcodeproj --enable-code-coverage --xcconfig-overrides Datadog.xcconfig

# Install `swiftlint`
brew install swiftlint

# Install Datadog Xcode templates
./tools/xcode-templates/install-xcode-templates.sh

# Generate example apps config template
./tools/config/generate-examples-config-template.sh

echo "💪 All good"
