#!/bin/bash

if [ ! -f "Package.swift" ]; then
    echo "\`generate-http-server-mock-config.sh\` must be run in repository root folder: \`./tools/config/generate-http-server-mock-config.sh\`"; exit 1
fi

SERVER_ADDRESS=$(./tools/http-server-mock/python/server_address.py)
XCCONFIG_FILE="./xcconfigs/MockServerAddress.local.xcconfig"

echo "MOCK_SERVER_ADDRESS=${SERVER_ADDRESS}" > "${XCCONFIG_FILE}"
