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

### Review process

Every Pull Request goes through two review stages: AI code review first, then human review.

1. **Open your PR as a draft** while you are still working on it.
2. **Review your own changes, then mark the PR as "Ready for review"** once it is complete and CI is green. This triggers AI code reviews.
3. **Address the AI code review comments.** Fix the valid findings, and reply to (and resolve) the ones you disagree with, so the human reviewer can see what was considered. Every push triggers a new round of AI code reviews, so repeat this step until a round completes without new findings. A thorough self-review before marking the PR as ready keeps this to a single round.
4. **Hand the PR over to human review:**
   - **Datadog team members:** add the `ready-for-human-review` label. Every morning, a bot assigns a project member as reviewer to PRs carrying this label.
   - **External contributors:** wait for a member of the team to pick up your PR and take it through human review.
5. **Iterate with the human reviewer** until the PR is approved and merged.

Do not hand the PR over before the last round of AI code reviews is addressed. Human reviewers expect the PR to be in its final shape.

AI code review findings on later pushes are addressed the same way alongside the human review; there is no need to remove the label. The exception is when the human review leads to a significant rework of your solution: remove the `ready-for-human-review` label, go back to step 3, and add the label again once the reworked PR has been through AI code review.

## Shall we start?

🏗 The easiest way to start is to run `make` command:

```bash
$ make
```

### Repo structure

#### `Datadog.xcworkspace`

The workspace for SDK development and integration (tests, benchmarks, example app).

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
