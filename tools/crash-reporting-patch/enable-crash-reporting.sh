#!/bin/zsh

if [ ! -f "Package.swift" ]; then
    echo "\`enable-crash-reporting.sh\` must be run in repository root folder: \`./tools/crash-reporting-patch/enable-crash-reporting.sh\`"; exit 1
fi

echo "⚙️ Enabling development setup for Crash Reporting feature..."

# Install `DatadogCrashReporting.xcscheme` to `xcuserdata` folder
SCHEME_SOURCE="tools/crash-reporting-patch/DatadogCrashReporting.xcscheme"
SCHEME_TARGET="Datadog/Datadog.xcodeproj/xcuserdata/$(whoami).xcuserdatad/xcschemes"
mkdir -p "${SCHEME_TARGET}"
cp "${SCHEME_SOURCE}" "${SCHEME_TARGET}"
