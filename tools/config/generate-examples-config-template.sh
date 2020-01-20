#!/bin/bash

if [ ! -f "Package.swift" ]; then
    echo "\`generate-examples-config-template.sh\` must be run in repository root folder: \`./tools/config/generate-examples-config-template.sh\`"; exit 1
fi

echo "💡 If you are running \`kickoff.sh\` for the first time, it will create \`examples/examples-secret.xcconfig\` file template for you."
cp -i ./tools/config/examples-secret-template.xcconfig ./examples/examples-secret.xcconfig
