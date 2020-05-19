fastlane documentation
================
# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```
xcode-select --install
```

Install _fastlane_ using
```
[sudo] gem install fastlane -NV
```
or alternatively using `brew cask install fastlane`

# Available Actions
## iOS
### ios build_for_testing
```
fastlane ios build_for_testing
```
Create an iOS build which can be used to execute ui and unit tests
### ios unit_test
```
fastlane ios unit_test
```
Run iOS unit tests with the option to rerun the build or use the previous one

----

## Mac
### mac build_for_testing
```
fastlane mac build_for_testing
```
Create a macOS build which can be used to execute ui and unit tests
### mac unit_test
```
fastlane mac unit_test
```
Run macOS unit tests with the option to rerun the build or use the previous one

----

This README.md is auto-generated and will be re-generated every time [fastlane](https://fastlane.tools) is run.
More information about fastlane can be found on [fastlane.tools](https://fastlane.tools).
The documentation of fastlane can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
