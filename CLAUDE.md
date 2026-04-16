# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the Datadog SDK for iOS and tvOS — a modular Swift/Objective-C library for observability (Logs, Traces, RUM, Session Replay, Crash Reporting, WebView Tracking, and Feature Flags).

**Start with `AGENTS.md`** — it is the entry point to all SDK documentation. Follow its pointers to `docs/` for deeper context on architecture, conventions, testing, and development recipes.

## Available Skills

Use these skills (via `/skill-name`) for common workflows:

| Skill | When to use |
|---|---|
| `dd-sdk-ios:git-branch` | Creating a new branch for a JIRA ticket or feature |
| `dd-sdk-ios:git-commit` | Committing changes (signed commits, message format) |
| `dd-sdk-ios:open-pr` | Opening a pull request against `develop` |
| `dd-sdk-ios:running-tests` | Running unit, module, or integration tests |
| `dd-sdk-ios:xcode-file-management` | Adding, removing, moving, or renaming Swift source files |

## CI Environment

The `ENV=ci` flag enables CI-specific behaviors (e.g., different API surface output paths). Set this when debugging CI failures locally.
