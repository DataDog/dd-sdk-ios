# `*_FEATURE.md` Specification

This document provides guidelines for LLMs updating feature documentation files (`*_FEATURE.md`) in the Datadog iOS SDK repository.

> For the *workflow* around these docs (verification, publishing, the update skill), see the *Feature Docs System* page in Confluence. The canonical update procedure lives in [`.claude/skills/update-feature-docs/SKILL.md`](../.claude/skills/update-feature-docs/SKILL.md).

## Purpose

These files serve as **LLM-optimized entry points** to the codebase:
- Quick navigation to key source files
- Documented configuration options with working examples
- Troubleshooting patterns
- Feature interactions and dependencies

They are NOT a replacement for customer-facing documentation.

## File Inventory

Each feature module contains a `*_FEATURE.md` file at its root:

```
DatadogRUM/RUM_FEATURE.md
DatadogSessionReplay/SESSION_REPLAY_FEATURE.md
DatadogTrace/TRACE_FEATURE.md
DatadogProfiling/PROFILING_FEATURE.md
DatadogLogs/LOGS_FEATURE.md
DatadogWebViewTracking/WEBVIEW_FEATURE.md  # (future)
```

## Frontmatter

Each feature documentation file must include a YAML frontmatter header at the top:

```markdown
---
last_updated: YYYY-MM-DD
sdk_version: X.Y.Z
verified_against_commit: <short_commit_hash>
tracked_files:
  - Module/Sources/PublicAPI.swift
  - Module/Sources/AnotherPublicAPI.swift
---
```

- **last_updated**: Date when the file was last reviewed/updated.
- **sdk_version**: SDK version the documentation was verified against.
- **verified_against_commit**: Short git commit hash at which the doc was last verified to match the source. The verify script uses `git diff <verified_against_commit>..HEAD -- <tracked_files>` to detect drift.
- **tracked_files**: List of public API and configuration source files whose changes should trigger a doc update. Cross-feature APIs should be tracked by the feature doc that owns them. Internal implementation files can be referenced in "Key Files" for navigation without being tracked.

## Sections

Every feature doc contains these core sections, in order. Optional sections are called out below and should keep the same relative position when used.

### Overview
- Brief description of feature purpose
- Platform availability — use the format `**Platform**: iOS, tvOS, watchOS, visionOS` (list only platforms declared in the podspec; add a note for platforms where functionality is limited or absent)
- Key dependencies (e.g. "requires RUM")

### Quick Start Example
A complete, compilable Swift code snippet that:
- Includes all required initialization steps in correct order
- Lists every configuration option with a working example value
- Has accurate inline comments describing each option and its default
- Includes optional features (manual control, per-view overrides) where applicable

### Architecture Overview (optional)
Use an `## Architecture Overview` section after Quick Start when the feature spans multiple runtime components, message flows, native layers, or cross-feature coordination. Keep it high-level and use "Key Files" for source navigation.

### Key Files
Full relative paths from repository root, with a brief description of each file's purpose. Include public API and configuration files, and the most useful internal implementation files for navigation. Group by role (Feature Entry Point, Configuration, Public API, Implementation).

### Configuration Categories
Logical groupings of configuration options (Sampling, Privacy, Performance Monitoring, Event Modification, etc.). Reference defaults and explain interactions between options.

### Common Troubleshooting Patterns
Format: Symptom → Causes → Solutions. Based on real customer issues; include non-obvious behaviors.

### Feature Interactions
Dependencies on other features, integration points, and any required configuration for integrations.

### Additional Context
Non-obvious behavioral notes, platform-specific differences, limitations and caveats.

## Quality Standards

### Configuration options
- List ALL options from the Configuration struct's `init()` method — no omissions.
- Match the exact parameter order from the `init()` signature. Swift named-argument calls must follow declaration order; the snippet won't compile otherwise.
- Use realistic, working values. Avoid `"..."` or untyped `nil` without explanation.
- Defaults and descriptions must match the source.

### Examples must compile
The Quick Start snippet should be valid Swift against the current SDK version. Placeholder identifiers (`<client_token>`, `MyCustomViewsPredicate`, `myView`) and user-defined helpers (`scrubURL`) are illustrative and need not resolve — only SDK API calls must be valid.

### Deprecated public surface
Cases marked `@available(*, deprecated, message:)` — enum cases, methods, properties — must appear in the doc with a clear deprecation note. They remain on the public API and customers can still encounter them.

### Coverage
Every public API or configuration source file referenced in the "Key Files" section should also appear in `tracked_files` (the `update-feature-docs` skill audits this). Internal implementation files in "Key Files" are navigation references and do not need to be frontmatter drift triggers.

### What to skip
- Don't replicate customer-facing public documentation verbatim — these files are LLM-optimized, not customer-facing.
- Don't document features that don't exist in the source.

---

**When to update this guidelines document:**
- When the documentation structure or format changes
- When new validation patterns are needed
- When new features are added that require different documentation approaches
