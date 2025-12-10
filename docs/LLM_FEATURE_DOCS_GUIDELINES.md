# LLM Guidelines for Feature Documentation Updates

This document provides guidelines for LLMs updating feature documentation files (`*_FEATURE.md`) in the Datadog iOS SDK repository.

## Purpose of Feature Documentation Files

These files serve as **LLM-optimized entry points** to the codebase. They are NOT meant to replicate public documentation but rather:
- Provide quick navigation to key source files
- Document configuration options with working examples
- Highlight troubleshooting patterns
- Show feature interactions and dependencies

## Feature Documentation Files

Each feature module contains a `*_FEATURE.md` file at its root:

```
DatadogRUM/RUM_FEATURE.md
DatadogSessionReplay/SESSION_REPLAY_FEATURE.md
DatadogTrace/TRACE_FEATURE.md          # (future)
DatadogLogs/LOGS_FEATURE.md            # (future)
DatadogWebViewTracking/WEBVIEW_FEATURE.md  # (future)
```

Each feature documentation file contains a **"Key Files"** section listing all relevant source files for that feature. Use this section as the source of truth for which files to read during updates.

## File Metadata

Each feature documentation file should include a metadata header at the top:

```markdown
---
last_updated: YYYY-MM-DD
sdk_version: X.Y.Z
verified_against_commit: <short_commit_hash>
---
```

- **last_updated**: Date when the file was last reviewed/updated
- **sdk_version**: SDK version the documentation was verified against
- **verified_against_commit**: Git commit hash of the source files used for verification

When updating, always update these metadata fields to reflect the current state.

## Update Checklist

### 1. Configuration Options

**Source of Truth**: The `init()` method in the Configuration struct (e.g., `RUMConfiguration.swift`, `SessionReplayConfiguration.swift`)

- [ ] **List ALL configuration options** - Do not omit any parameters from the initializer
- [ ] **Correct parameter order** - Match the exact order in the source `init()` method
- [ ] **Working example values** - Use valid, realistic values (not placeholders like `...`)
- [ ] **Accurate defaults** - Verify default values match the source code
- [ ] **Accurate descriptions** - Verify option descriptions match source code comments

```swift
// ✅ CORRECT: All options listed in correct order with working values
RUM.Configuration(
    applicationID: "<rum_application_id>",
    sessionSampleRate: 100.0,
    uiKitViewsPredicate: DefaultUIKitRUMViewsPredicate(),
    // ... all other options in order
)

// ❌ WRONG: Options out of order or missing
RUM.Configuration(
    applicationID: "...",
    trackFrustrations: true,  // Wrong position
    sessionSampleRate: 100.0,
    // Missing options
)
```

### 2. Platform Support

**Source of Truth**: Compiler directives (`#if os(iOS)`, etc.) in source files

- [ ] Verify supported platforms match `#if` directives in source
- [ ] Update "Platform" note in Overview section if changed

### 3. Public APIs

**Source of Truth**: Public protocol/class definitions (e.g., `RUMMonitorProtocol.swift`)

- [ ] Verify all public methods are documented
- [ ] Check for new APIs added
- [ ] Check for deprecated APIs

### 4. Feature Interactions

- [ ] Verify dependency requirements (e.g., "Session Replay requires RUM")
- [ ] Check for new feature integrations

### 5. Quick Start Example

The code snippet must:
- [ ] Compile without errors (syntactically correct Swift)
- [ ] Show realistic usage patterns
- [ ] Include all required initialization steps in correct order
- [ ] Have accurate inline comments

## Validation Steps

Before finalizing updates, perform these checks:

### Step 1: Read Source Files Entirely
1. Open the feature's `*_FEATURE.md` file
2. Find the **"Key Files"** section
3. Read **all** source files listed there entirely

From these files, extract:
- The `public init(...)` method - ALL parameters in order
- Default values for each parameter
- Documentation comments for each property
- Nested types and enums (including `FeatureFlag`)
- Platform conditionals (`#if os(iOS)`, etc.)
- Public methods (start/stop recording, etc.)

### Step 2: Compare with Feature Documentation
For each item found in Step 1, verify against the feature markdown:

**Configuration options:**
- Is it documented?
- Is it in the correct position (matching init order)?
- Does the documented default match the source?
- Is the description accurate?

**Feature flags:**
- Are all `FeatureFlag` enum cases documented?
- Are defaults accurate?

**Platform support:**
- Does the documented platform match `#if` conditionals?

**Public APIs:**
- Are all public methods documented?
- Are there new or deprecated APIs?

Flag any discrepancies:
- Missing items (in source but not in docs)
- Removed items (in docs but not in source)
- Reordered options
- Changed defaults or descriptions

## Common Pitfalls to Avoid

### ❌ DON'T
- Guess parameter order - always verify against source
- Assume defaults haven't changed
- Skip optional parameters in examples
- Use placeholder values like `"..."` or `nil` without explanation
- Replicate public documentation verbatim
- Add features that don't exist in the source

### ✅ DO
- Read the actual source files before updating
- Include ALL configuration options
- Use realistic example values
- Document behavioral nuances (e.g., SwiftUI image bundling heuristic)
- Keep troubleshooting patterns based on real customer issues
- Update file paths if source files are moved/renamed

## Section-by-Section Guide

### Overview
- Brief description of feature purpose
- Platform availability
- Key dependencies

### Quick Start Example
- Complete, compilable code snippet
- All configuration options with comments
- Initialization order matters
- Include optional features (manual control, per-view overrides)

### Key Files
- Entry points and configuration files
- Full relative paths from repository root
- Brief description of each file's purpose

### Configuration Categories
- Group related options
- Reference defaults
- Explain interactions between options

### Common Troubleshooting Patterns
- Format: Symptom → Causes → Solutions
- Based on real customer issues
- Include non-obvious behaviors

### Feature Interactions
- Dependencies on other features
- Integration points (WebView, Tracing, etc.)
- Required configuration for integrations

### Additional Context
- Non-obvious behavioral notes
- Platform-specific differences
- Limitations and caveats

## Automation Notes

When running automated updates:

1. **Parse Configuration Init**: Extract all parameters from the `init()` method
2. **Compare with Documentation**: Identify added/removed/reordered parameters
3. **Verify Defaults**: Check default values in source vs documentation
4. **Check Enums**: Compare enum cases in source vs documentation
5. **Validate Code Snippet**: Ensure example compiles (optional: use Swift syntax checker)

---

**When to update this guidelines document:**
- When the documentation structure or format changes
- When new validation patterns are needed
- When new features are added that require different documentation approaches

**When to update feature documentation files (`*_FEATURE.md`):**
- For each SDK release
- When public APIs are added, changed, or deprecated
- When configuration options are modified
- When feature behavior changes
