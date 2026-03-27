# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Datadog SDK for iOS and tvOS — a modular Swift/Objective-C library for observability (Logs, Traces, RUM, Session Replay, Crash Reporting, WebView Tracking, and Feature Flags).

**Read `AGENTS.md` for architecture, conventions, and development rules.** All changes must follow those guidelines.

## Available Skills

Use these skills (via `/skill-name`) for common workflows:

| Skill | When to use |
|---|---|
| `dd-sdk-ios:git-branch` | Creating a new branch for a JIRA ticket or feature |
| `dd-sdk-ios:git-commit` | Committing changes (signed commits, message format) |
| `dd-sdk-ios:open-pr` | Opening a pull request against `develop` |
| `dd-sdk-ios:running-tests` | Running unit, module, or integration tests |
| `dd-sdk-ios:xcode-file-management` | Adding, removing, moving, or renaming Swift source files |

## Build & Test Quick Reference

```bash
# Setup
make                                              # Full setup (env-check, repo-setup, dependencies)

# Testing
make test-ios SCHEME="DatadogCore iOS"            # Run specific iOS scheme
make test-ios-all                                  # Run all iOS unit tests
make test-tvos-all                                 # Run all tvOS unit tests
make ui-test TEST_PLAN="Default"                  # Run UI test plan
make sr-snapshot-test                              # Run Session Replay snapshot tests

# Building
make spm-build-ios                                 # Build for iOS via SPM

# Code Quality
make lint                                          # Run SwiftLint
./tools/lint/run-linter.sh --fix                  # Auto-fix lint violations
make api-surface                                   # Generate API surface files
make api-surface-verify                            # Verify API surface hasn't changed
make license-check                                 # Check license headers

# Model Generation (DO NOT hand-edit generated models)
make rum-models-generate GIT_REF=master           # Generate RUM data models
make sr-models-generate GIT_REF=master            # Generate Session Replay models

# Cleanup
make clean                                         # Clean derived data, pods, xcconfigs
```

## Module-Specific Documentation

For deep dives into specific modules, read the `*_FEATURE.md` file in the module directory:

- `DatadogRUM/RUM_FEATURE.md` — RUM public API, configuration, key files, troubleshooting
- `DatadogSessionReplay/SESSION_REPLAY_FEATURE.md` — Session Replay configuration and usage

## CI Environment

The `ENV=ci` flag enables CI-specific behaviors (e.g., different API surface output paths). Set this when debugging CI failures locally.
