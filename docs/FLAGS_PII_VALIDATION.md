# Flags evaluation privacy (FFL-3432)

Only literal `data.attributes.observeFullEvaluationData: true` enables full evaluation data. Absent, false, null and invalid values remain protected without rejecting the configuration. Consent belongs to the cached configuration used for evaluation, including missing flags and type errors. Disk restoration preserves it; older cache entries default to protected. Normal refresh changes future evaluations. Pending events retain their captured mode.

The native SDK hashes nonempty protected targeting keys as `sha256_` plus lowercase SHA-256 of the exact UTF-8 bytes and omits `context.evaluation`. Empty keys remain empty; evaluations before any context exists omit the targeting key. `AnyValue` and its arrays/dictionaries already have value semantics. No new context limits, queues or flattening were added. Assignment requests, targeting inputs and exposure behavior are unchanged.

Evaluation telemetry accepts only PROVIDER_NOT_READY, PROVIDER_FATAL, FLAG_NOT_FOUND, PARSE_ERROR, TYPE_MISMATCH, TARGETING_KEY_MISSING, INVALID_CONTEXT and GENERAL. Unknown errors become GENERAL in either consent mode. A successful evaluation has no error. Aggregation uses the sanitized error and protected context, separates consent modes and default results, and retains existing flush/retry/tracking-disable behavior.

## Adapter interface

Swift provider reads `FlagDetails.observeFullEvaluationData` through `@_spi(Internal)` and forwards it as `__dd_observe_full_evaluation_data`. It must not emit or hash again.

React Native must use `getFlagAssignmentsWithConsent()` to read assignments and response-level consent together, cache both, and retain consent on success/error/default evaluation metadata. `sendFlagEvaluation(key:assignment:context:observeFullEvaluationData:flagError:)` accepts that captured value and a stable error code (unknown strings are sanitized). It never reads live configuration. Existing `getFlagAssignments()`/`sendFlagEvaluation` remain available; assignments now carry consent, and reconstructed legacy assignments default to protected. An empty assignment map still has response-level consent through the new snapshot API.

Swift `String` contains valid Unicode scalars, and the public native/OpenFeature context requires a nonoptional string. Native hashing preserves exact UTF-8, including decomposed text and literal U+FFFD. Missing/null/malformed raw keys cannot be represented by that API. React Native must validate raw UTF-16 before bridging, without replacement/coercion; its missing/malformed-key omission path needs joint integration validation. This change does not claim that downstream bridge validation has shipped. No React Native repository was changed.

## Validation and release gate

This change was prepared on Linux aarch64, with no Swift, Xcode, Apple SDKs, CocoaPods or simulator. Swift grammar checks are not compilation. Native XCTest, lint, API surface generation and actual artifact/wire execution remain **unverified** here.

On macOS with Xcode 26 / Swift 6.2 (already required by this SDK):

1. Run repository setup and `xcrun simctl list devices available`.
2. Run `make test-ios SCHEME="DatadogFlags" DEVICE="<installed simulator>"`, the existing `FlagsEvaluationIntegrationTests` in the integration test target, and applicable supported-platform CI builds.
3. Run `./tools/lint/run-linter.sh` and `make api-surface`; inspect generated API changes, including internal bridge compatibility.
4. Run the paired provider's `IntegrationTests/PII/run.py` with this checkout and an output directory. It compiles local SDK/provider packages, runs provider tests, executes direct and real OpenFeature calls, captures HTTP bodies, asserts consent changes before flush, offline restoration, errors/defaults, DoLog false, tracking disable and upload retry. Its optional CocoaPods mode builds/tests both static and dynamic iOS consumers using the local podspecs.
5. Retain the runner's source identities, binary SHA-256, lockfiles, command log and wire assertions. Obtain SDK-owner review and record the first protected published SDK version before approving downstream releases.

The loopback runner uses macOS execution for its wire probe. It does not replace iOS simulator/device, tvOS, watchOS or visionOS builds, nor prove React Native malformed-input behavior. Release cutoff, review owner and protected published version are not yet confirmed. FFL-3428 is already complete; no special revocation mechanism or backend changes are needed.
