#!/bin/bash

CURRENT_DIR=${PWD##*/}

if [ "$CURRENT_DIR" != "dd-sdk-ios" ]; then 
	echo "\`kickoff.sh\` must be run in repository root folder: \`./tools/kickoff.sh\`"; exit 1
fi

# Generate `Datadog.xcodeproj`
swift package generate-xcodeproj --enable-code-coverage --xcconfig-overrides Datadog.xcconfig

# Install `swiftlint`
brew install swiftlint

# Install Datadog Xcode templates
./tools/xcode-templates/install-xcode-templates.sh

echo "💡 If you are running \`kickoff.sh\` for the first time, it will create \`examples/examples-secret.xcconfig\` file template for you."
cp -i ./tools/config/examples-secret-template.xcconfig ./examples/examples-secret.xcconfig

echo "💪 All good"
