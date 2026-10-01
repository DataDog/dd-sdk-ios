# Contributing

First of all, thanks for contributing!

This document provides some basic guidelines for contributing to this repository.
To propose improvements, feel free to submit a PR or open an Issue.

**Note:** Datadog requires that all commits within this repository must be signed, including those within external contribution PRs. Please ensure you have followed GitHub's [Signing Commits](https://docs.github.com/en/authentication/managing-commit-signature-verification/signing-commits) guide before proposing a contribution. PRs lacking signed commits will not be processed and may be rejected.

## Have a feature request or idea?

Many great ideas for new features come from the community, and we'd be happy to consider yours 👍.

To share your idea or request, [open a GitHub Issue](https://github.com/DataDog/dd-sdk-ios/issues/new/choose) using dedicated issue template.

## Found a bug?

For any urgent matters (such as outages) or issues concerning the Datadog service or UI, contact our support team via https://docs.datadoghq.com/help/ for direct, faster assistance.

You may submit a bug report concerning the Datadog SDK for iOS by [opening a GitHub Issue](https://github.com/DataDog/dd-sdk-ios/issues/new/choose). Use appropriate template and provide all listed details to help us resolve the issue.

## Have a patch?

We welcome all code contributions to the library. If you have a patch adding value to the SDK, let us know 💪! Before you [submit a Pull Request](https://github.com/DataDog/dd-sdk-ios/pull/new/master), make sure that you first create an Issue to explain the bug or the feature your patch covers, then make sure similar Issue or PR doesn't already exist.

Your Pull Request will be run through our CI pipeline, and a project member will review the changes with you. At a minimum, to be accepted and merged, Pull Requests must:

- have a stated goal and detailed description of the changes made;
- include thorough test coverage and documentation, where applicable;
- pass all tests and code quality checks on CI;
- receive at least one approval from a project member with push permissions.

Make sure that your code is clean and readable, that your commits are small and atomic, with a proper commit message.

## Shall we start?

🏗 The easiest way to start is to run `make` command:

```bash
$ make
```

### Repo structure

#### `Datadog.xcworkspace`

The workspace for SDK development and integration (tests, benchmarks, example app).

To try the Example app's First Flags evaluation, select the `Example` scheme in Xcode and add
`DD_FLAG_KEY` under **Run > Arguments > Environment Variables**. Its value must be the key of an
existing **boolean** flag in the environment configured for the app's client token. No key (or a
blank value) skips the Flags example entirely. The app reuses its existing Core configuration
(`env: "tests"`) and evaluates for its existing sample user, `abcd-1234`, with a default of `false`.
The configured client token must have access to that flag environment; the sample does not create
flags or provision access.

The `onFirstFlags` closure schedules one evaluation on the main queue, after client creation and
registration have completed. It logs the supplied flag keys directly (`[]` for an empty list,
`not supplied` when absent), followed by the evaluation result or an explicit fallback warning,
through the existing `[iOS App]` logger/console display. Context initialization still fetches the network
configuration. The first notification may come from cache; a later refresh does not repeat the
first-flags evaluation. The deferred evaluation reads the client's current configuration.


#### Sources

`Datadog` source files

#### Tests

`DatadogTests` (unit tests), `IntegrationTests`, and `DatadogBenchmarkTests` (benchmarks) source files

#### Lint

We're using `swiftlint` to ensure our codebase follows Swift standard syntax. You can run the lint with our custom rules with the following command line:

```shell
$ ./tools/lint/run-linter.sh
```

In order to apply automatic correction of violations use `--fix` flag:

```shell
$ ./tools/lint/run-linter.sh --fix
```

#### Dependency manager tests

Isolated example apps using `cocoapods`, `carthage` and `spm` to ensure SDK is well integrated with all supported dependency managers.
