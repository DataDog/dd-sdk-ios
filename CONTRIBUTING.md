# Contributing

## Prerequisites

* Xcode 11.2.1 or later
* [`homebrew`](https://brew.sh)

## Preparation

The easiest way to start is to use `kickoff` tool. It will prepare your machine for contributions. Simply run the tool from repository root folder:
```bash
./tools/kickoff.sh
```

To have linter warnings and errors appear in Xcode (which is highly convenient and recommended), create the "New Run Script Phase" for "Datadog" target and put following shell script in it:
```bash
if which swiftlint >/dev/null; then
  ${SOURCE_ROOT}/tools/lint.sh
fi
```
This will invoke [`swiftlint`](https://github.com/realm/SwiftLint) tool with the rules we enforce for our project. You can also run linter from command line in repository root folder:
```bash
./tools/lint.sh
```

### What does `kickoff` do?

This project uses [Swift Package Manager](https://swift.org/package-manager/). The `kickoff` tool will **generate `Datadog.xcodeproj`** and configure it for development.

If you don't have [`swiftlint`](https://github.com/realm/SwiftLint) installed, `brew` will be used to install it. 

As part of our coding convention, we use **custom Xcode file templates** for creating `.swift` and unit test files. Templates will be automatically installed and available from Xcode's "New File..." menu (search for "Datadog" section).

To send real logs from the example app, you must configure `./examples/examples-secret.xcconfig` file with your own secret obtained on Datadog website. The file template will be automatically generated for you by `kickoff`.

## Contributing to `Datadog` SDK

Make sure  you **always lint the code** before submitting contribution, otherwise your PR won't be accepted. You can either run `./tools/lint.sh` directly from command line or run it in Xcode's Build Phase (recommended). See _"Preparation"_ section for details on the build phase. 

## Contributing to Project Tools

Tools are located in `tools` directory. They are set of scripts dedicated to project setup and development automation. 

Be aware of these conventions when contributing to tools:
* each tool is located under separate directory in `tools/`, `kebab-case` convention is used for naming;
* each script must work as it is executed from repository root folder (so they can be eventually used by `./tools/kickoff.sh`).
