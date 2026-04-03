# AI Agents Guide for dd-sdk-ios

> This file is a **map**, not an encyclopedia. It provides the entry point and pointers to deeper documentation. Start here, then follow the links relevant to your task.

## SDK Philosophy

The SDK powers mission-critical telemetry for thousands of customer apps. All changes must preserve stability, compatibility, and performance. See `ZEN.md` for the full philosophy:

1. **Zero crashes caused by SDK code** — prefer making the SDK non-operational over throwing exceptions
2. **Small footprint** — minimize runtime performance impact, library size, and network load
3. **Stability** — avoid breaking changes; minor updates must be transparent
4. **Compatibility** — support iOS 12.0+, both Swift and Objective-C

## Documentation Map

```
AGENTS.md                ← You are here (entry point)
ZEN.md                   ← SDK philosophy and principles
CONTRIBUTING.md          ← General contribution guidelines

docs/
├── ARCHITECTURE.md      ← Module structure, data flow, key abstractions, protocols,
│                          error handling, thread safety, HTTP upload, dependencies
├── CONVENTIONS.md       ← Naming, SwiftLint rules, conditional compilation,
│                          generated models, file headers, commit/PR format
├── DEVELOPMENT.md       ← Recipes for adding features/commands/providers,
│                          RFC process, build & test quick reference
├── TESTING.md           ← Test conventions, mock infrastructure (.mockAny(),
│                          .mockRandom(), .mockWith()), DatadogCoreProxy usage
├── KNOWN_CONCERNS.md    ← Fragile areas requiring extra caution
├── SWIZZLING.md         ← Mandatory swizzling patterns and real incidents
├── LLM_FEATURE_DOCS_GUIDELINES.md  ← How to update *_FEATURE.md files
├── sdk_performance.md              ← SDK performance benchmarks
└── session_replay_performance.md   ← Session Replay performance benchmarks

Feature-specific docs (in each module directory):
├── DatadogRUM/RUM_FEATURE.md
└── DatadogSessionReplay/SESSION_REPLAY_FEATURE.md
```

## Where to Look First

| Task | Start with |
|------|-----------|
| Understand module boundaries & data flow | `docs/ARCHITECTURE.md` |
| Add a new feature, command, or provider | `docs/DEVELOPMENT.md` |
| Write or fix tests | `docs/TESTING.md` |
| Check naming, lint, commit format | `docs/CONVENTIONS.md` |
| Touch swizzling code | `docs/SWIZZLING.md` |
| Modify a fragile area | `docs/KNOWN_CONCERNS.md` |
| Work on RUM specifically | `DatadogRUM/RUM_FEATURE.md` |
| Work on Session Replay specifically | `DatadogSessionReplay/SESSION_REPLAY_FEATURE.md` |
| Update a `*_FEATURE.md` file | `docs/LLM_FEATURE_DOCS_GUIDELINES.md` |

## Critical Rules (always apply)

- **Never crash customer apps.** Use NOP implementations when the SDK is not initialized.
- **Feature modules must not import each other.** Only `DatadogCore` orchestrates.
- **Always search for usages across the entire codebase** before considering a change complete — update call sites in `DatadogCore`, `DatadogInternal`, encoders, ObjC bridges, and `.pbxproj`.
- **Do NOT modify generated files** (RUM and Session Replay models in `DatadogInternal/Sources/Models/`).
- **Do NOT add new dependencies** without explicit approval.
- **Do NOT change networking formats or endpoints.**
- **Do NOT introduce new public API** without RFC review.
- **Do NOT edit build scripts** unless instructed.
- **NEVER mention AI assistant names** (Claude, ChatGPT, Cursor, Copilot, etc.) in commit messages, PR descriptions, code comments, or co-author tags.

## Quick Reference

| Task | Command |
|------|---------|
| Setup | `make` |
| Lint | `./tools/lint/run-linter.sh` |
| Test iOS | `make test-ios SCHEME="<scheme>"` |
| All iOS tests | `make test-ios-all` |
| Build SPM | `make spm-build-ios` |
| API surface | `make api-surface` |

Full command reference: `docs/DEVELOPMENT.md`
