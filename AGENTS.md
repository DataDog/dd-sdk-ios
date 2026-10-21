# AI Agents Guide for dd-sdk-ios

> This file is a **map**, not an encyclopedia. It provides the entry point and pointers to deeper documentation. Start here, then follow the links relevant to your task.

## SDK Philosophy

The SDK powers mission-critical telemetry for thousands of customer apps. All changes must preserve stability, compatibility, and performance. See `ZEN.md` for the full philosophy:

1. **Zero crashes caused by SDK code** — prefer making the SDK non-operational over throwing exceptions
2. **Small footprint** — minimize runtime performance impact, library size, and network load
3. **Stability** — avoid breaking changes; minor updates must be transparent
4. **Compatibility** — support iOS 15.0+, both Swift and Objective-C

## Documentation Map

The full documentation map is [`docs/README.md`](docs/README.md). It routes to SDK-wide docs, per-feature docs, and performance benchmarks.

## Where to Look First

| Task | Start with |
|------|-----------|
| Understand module boundaries & data flow | [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) |
| Add a new feature, command, or provider | [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) |
| Write or fix tests | [`docs/TESTING.md`](docs/TESTING.md) |
| Check naming, lint, commit format | [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md) |
| Touch swizzling code | [`docs/SWIZZLING.md`](docs/SWIZZLING.md) |
| Report an error to internal telemetry | [`docs/ERROR_HANDLING.md`](docs/ERROR_HANDLING.md) |
| Modify a fragile area | [`docs/KNOWN_CONCERNS.md`](docs/KNOWN_CONCERNS.md) |
| Work on RUM specifically | [`DatadogRUM/RUM_FEATURE.md`](DatadogRUM/RUM_FEATURE.md) |
| Work on Session Replay specifically | [`DatadogSessionReplay/SESSION_REPLAY_FEATURE.md`](DatadogSessionReplay/SESSION_REPLAY_FEATURE.md) |
| Work on Trace (APM) specifically | [`DatadogTrace/TRACE_FEATURE.md`](DatadogTrace/TRACE_FEATURE.md) |
| Work on Profiling specifically | [`DatadogProfiling/PROFILING_FEATURE.md`](DatadogProfiling/PROFILING_FEATURE.md) |
| Work on Logs specifically | [`DatadogLogs/LOGS_FEATURE.md`](DatadogLogs/LOGS_FEATURE.md) |
| Update a `*_FEATURE.md` file | [`docs/LLM_FEATURE_DOCS_GUIDELINES.md`](docs/LLM_FEATURE_DOCS_GUIDELINES.md) |

## Critical Rules (always apply)

- **Never crash customer apps.** Use NOP implementations when the SDK is not initialized.
- **Feature modules must not import each other.** Only `DatadogCore` orchestrates.
- **Always search for usages across the entire codebase** before considering a change complete — update call sites in `DatadogCore`, `DatadogInternal`, encoders, ObjC bridges, and `.pbxproj`.
- **Do NOT modify generated files** (RUM and Session Replay models in `DatadogInternal/Sources/Models/`).
- **Do NOT add new dependencies** without explicit approval.
- **Do NOT change networking formats or endpoints.**
- **Do NOT introduce new public API** without RFC review.
- **Do NOT edit build scripts** unless instructed.
- **Do NOT name branches with `codex`.** Use repo branch naming conventions instead.
- **Never mention AI assistant names** (Claude, ChatGPT, Cursor, Copilot, etc.) in commit messages, PR descriptions, code comments, or co-author tags.
- **Never write or modify a swizzle without reading `docs/SWIZZLING.md` first.** Past incidents have caused production crashes.
- **Never report a raw `Error` to internal telemetry.** `"\(error)"` can embed customer data (e.g. `EncodingError.invalidValue` embeds the offending value). Always go through `Telemetry.error(_:)`, which sanitizes via `TelemetrySanitizableError`; see `docs/ERROR_HANDLING.md`. Past incidents have leaked customer PII and auth tokens this way.

## Quick Reference

| Task | Command |
|------|---------|
| Setup | `make` |
| Lint | `./tools/lint/run-linter.sh` |
| Test iOS | `make test-ios SCHEME="<scheme>"` |
| All iOS tests | `make test-ios-all` |
| Test watchOS | `make test-watchos SCHEME="<scheme>"` |
| Test visionOS | `make test-visionos SCHEME="<scheme>"` |
| Build SPM | `make spm-build-ios` |
| API surface | `make api-surface` |

Full command reference: `docs/DEVELOPMENT.md`
