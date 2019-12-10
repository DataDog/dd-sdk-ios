# Contributing

## Installation

### `kickoff` tool

The easiest way to start is to use `kickoff` tool. It will prepare your machine for contributions. Simply run the tool from repository root folder:
```bash
./tools/kickoff.sh
```

### What does `kickoff` do?

This project uses [Swift Package Manager](https://swift.org/package-manager/). `kickoff` will **generate `Datadog.xcodeproj`** for you.

As part of our coding convention, we use **custom Xcode file templates** for creating `.swift` and unit test files. Templates will be automatically installed and available from Xcode's "New File..." menu (search for "Datadog" section).

## Contributing to `Datadog` SDK

_TBD_

## Contributing to Project Tools

Tools are located in `tools` directory. They are set of scripts dedicated to project setup and development automation. 

Be aware of these conventions when contributing to tools:
* each tool is located under separate directory in `tools/`, `kebab-case` convention is used for naming;
* each script must work as it is executed from repository root folder (so they can be eventually used by `./tools/kickoff.sh`).
