#!/bin/zsh

# Log the setup of current CI environment

echo "System info:"
system_profiler SPSoftwareDataType

echo "xcodebuild version:"
xcodebuild -version

echo "Default Xcode:"
xcode-select -p

echo "Other Xcodes:"
ls /Applications/ | grep Xcode

echo "Available iOS Simulators:"
xcodebuild -workspace "Datadog.xcworkspace" -scheme "DatadogCore iOS" -showdestinations -quiet

echo "Available tvOS Simulators:"
xcodebuild -workspace "Datadog.xcworkspace" -scheme "DatadogCore tvOS" -showdestinations -quiet

echo "xcbeautify version:"
xcbeautify --version

echo "swiftlint version:"
swiftlint --version

echo "carthage version:"
carthage version

echo "gh version:"
gh --version

echo "brew version:"
brew -v

echo "bundler version:"
bundler --version

echo "python3 version:"
python3 -V
