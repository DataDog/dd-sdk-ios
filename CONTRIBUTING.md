# Contributing

First of all, thanks for contributing!

This document provides some basic guidelines for contributing to this repository.
To propose improvements, feel free to submit a PR or open an Issue.

## Have a feature request or idea?

Many great ideas for new features come from the community, and we'd be happy to consider yours 👍.

To share your idea or request, [open a GitHub Issue](https://github.com/DataDog/dd-sdk-ios/issues/new)  using dedicated issue template.

## Found a bug?

For any urgent matters (such as outages) or issues concerning the Datadog service or UI, contact our support team via https://docs.datadoghq.com/help/ for direct, faster assistance.

You may submit a bug report concerning the Datadog SDK for iOS by [opening a GitHub Issue](https://github.com/DataDog/dd-sdk-android/issues/new). Use dedicated bug-issue template and provide all listed details to let us solve it better. 


## Have a patch?

We welcome all code contributions to the library. If you have a patch adding value to the SDK, let us know 💪! Before you [submit a Pull Request](https://github.com/DataDog/dd-sdk-ios/pull/new/master), make sure that you first create an Issue to explain the bug or the feature your patch covers, then make sure similar Issue or PR doesn't already exist.

Your Pull Request will be run through our CI pipeline, and a project member will review the changes with you. At a minimum, to be accepted and merged, Pull Requests must:
 - have a stated goal and detailed description of the changes made;
 - include thorough test coverage and documentation, where applicable;
 - pass all tests and code quality checks on CI;
 - receive at least one approval from a project member with push permissions.

Make sure that your code is clean and readable, that your commits are small and atomic, with a proper commit message.

### Getting started

The only things you need for contributing to this repository are:
* Xcode 11.3.1+
* [`homebrew`](https://brew.sh)

The easiest way to start is to run `make` command:
```bash
make
```

This will install `swiftlint` and configure custom Datadog file templates for Xcode. Also, `examples-secret.xcconfig` file will be created - update it with a client token obtained on Datadog website.

Then, open `Datadog/Datadog.xcodeproj` and you are ready to go 🚀.

### Testing

It is important to be sure that our library works properly in any scenario. All non trivial code must be tested. If you're not used to writing tests, you can take a look at the `Tests/` folder to get some ideas on how we write them at Datadog.

Unit tests are part of the `Datadog.xcodeproj` project. Integration tests and benchmarks are located in separate projects in `instrumented-tests` folder.

The CI also runs UI tests for projects in `examples/` directory.
