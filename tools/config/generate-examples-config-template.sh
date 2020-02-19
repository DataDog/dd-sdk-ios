#!/bin/bash

if [ ! -f "Package.swift" ]; then
    echo "\`generate-examples-config-template.sh\` must be run in repository root folder: \`./tools/config/generate-examples-config-template.sh\`"; exit 1
fi

cp ./tools/config/examples-secret-template.xcconfig ./examples/examples-secret.xcconfig
