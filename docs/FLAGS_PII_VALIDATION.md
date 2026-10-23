# Flags evaluation privacy (FFL-3432)

Only literal `data.attributes.observeFullEvaluationData: true` enables full evaluation data. Absent, false, null and invalid values remain protected without rejecting the configuration. Consent belongs to the cached configuration used for evaluation, including missing flags and type errors. Disk restoration preserves it; older cache entries default to protected. Normal refresh changes future evaluations. Pending events retain their captured mode. Subject-level telemetry opt-out remains independent: when enabled in SDK configuration, a literal-true subject opt-out suppresses evaluation telemetry and RUM flag reporting even with full-data consent; exposure behavior is unchanged.

The native SDK hashes nonempty protected targeting keys as `sha256_` plus lowercase SHA-256 of the exact UTF-8 bytes and omits `context.evaluation`. Empty keys remain empty; evaluations before any context exists omit the targeting key. `AnyValue` and its arrays/dictionaries already have value semantics. No new context limits, queues or flattening were added. Assignment requests, targeting inputs and exposure behavior are unchanged.

Evaluation telemetry accepts only PROVIDER_NOT_READY, PROVIDER_FATAL, FLAG_NOT_FOUND, PARSE_ERROR, TYPE_MISMATCH, TARGETING_KEY_MISSING, INVALID_CONTEXT and GENERAL. Unknown errors become GENERAL in either consent mode. A successful evaluation has no error. Aggregation uses the sanitized error and protected context, separates consent modes and default results, and retains existing flush/retry/tracking-disable behavior.

## Adapter interface

Swift provider reads `FlagDetails.observeFullEvaluationData` through `@_spi(Internal)` and forwards it as `__dd_observe_full_evaluation_data`. It must not emit or hash again.

React Native must use `getFlagAssignmentsWithConsent()` to read assignments and response-level consent together, cache both, and retain consent on success/error/default evaluation metadata. `sendFlagEvaluation(key:assignment:context:observeFullEvaluationData:flagError:)` accepts that captured value and a stable error code (unknown strings are sanitized). It never reads live configuration. Existing `getFlagAssignments()`/`sendFlagEvaluation` remain available; assignments now carry consent, and reconstructed legacy assignments default to protected. An empty assignment map still has response-level consent through the new snapshot API.

Swift `String` contains valid Unicode scalars, and the public native/OpenFeature context requires a nonoptional string. Native hashing preserves exact UTF-8, including decomposed text and literal U+FFFD. Missing/null/malformed raw keys cannot be represented by that API. React Native must validate raw UTF-16 before bridging, without replacement/coercion. Validation alone cannot express omission through the current native bridge SPI: its context requires a string, and the native missing-key sentinel is internal. Before RN rollout, add a telemetry-only SPI representation of absent targeting keys (for example, an optional key where nil means omit and an empty string remains explicit empty), then validate missing/null/malformed versus empty/literal U+FFFD through the actual bridge while preserving evaluation counts. This change does not claim that downstream bridge validation has shipped. No React Native repository was changed.

## Validation and release gate

Apple validation uses the native repository's Xcode 26 / Swift 6.2 runner. The local editing workspace has no Swift, Xcode, Apple SDKs or simulator, so the merged source and new regression tests have not been compiled or executed locally.

### Historical pre-merge evidence

[Artifact validation job 2167527865](https://gitlab.ddbuild.io/DataDog/dd-sdk-ios/-/jobs/2167527865) passed at native commit `ed1ca0de3fecf4b07e118f97fc3929092f09d026`, paired with provider commit `a90606193c1fc27fdab43cdd5f466575cf2f7b01`. Its recorded results are 55 provider tests, 72 evaluations in 35 buckets and 24 unchanged assignment requests, plus static and dynamic CocoaPods iOS simulator probes with OpenFeature 0.3.0. Wire assertions cover retry after HTTP 500, protected/full consent, refresh before flush, offline restoration, default/error results, disabled tracking and DoLog false. Source identities, binary hashes, lockfiles, command logs and captured wire bodies are retained as job artifacts. The green job status was checked; these artifacts were not independently downloaded or replayed during the merge review.

The same pre-merge head had green native Flags unit tests, platform unit suites, smoke/UI, SPM, lint, API surface and SPI documentation jobs. These historical statuses do not validate the merge with develop `5b351983abaa54c0b5fba8d94d29d1378fd69fd7`. The merged revision requires fresh Apple CI, including the new consent/subject-opt-out regression tests and paired artifact validation. The existing full iOS unit job runs the DatadogFlags scheme; no separate duplicate Flags unit job is required.

The provider's normal Xcode 16.2 CI cannot build the paired native package's Swift 6.2 tools manifest and still requires a compatible runner. The macOS wire probe is not proof of every supported platform.

On macOS with Xcode 26 / Swift 6.2 (already required by this SDK):

1. Run repository setup and `xcrun simctl list devices available`.
2. Run `make test-ios SCHEME="DatadogFlags" DEVICE="<installed simulator>"`, the existing `FlagsEvaluationIntegrationTests` in the integration test target, and applicable supported-platform CI builds.
3. Run `./tools/lint/run-linter.sh` and `make api-surface`; inspect generated API changes, including internal bridge compatibility.
4. Run the paired provider's `IntegrationTests/PII/run.py` with this checkout and an output directory. It compiles local SDK/provider packages, runs provider tests, executes direct and real OpenFeature calls, captures HTTP bodies, asserts consent changes before flush, offline restoration, errors/defaults, DoLog false, tracking disable and upload retry. Its CocoaPods mode executes the same direct-native/OpenFeature probe inside the existing UIKit smoke apps, using app-hosted XCTest with both static and dynamic local SDK/provider podspecs. Each iOS app run independently verifies all 72 evaluations and preserves its wire capture, app/framework/test-binary hashes and xcresult bundle.
5. Retain the runner's source identities, binary SHA-256, lockfiles, command log and wire assertions. Obtain SDK-owner review and record the first protected published SDK version before approving downstream releases.

The loopback runner uses a macOS SPM executable and, when CocoaPods mode is requested, app-hosted tests in an iOS simulator. It does not replace physical-device, tvOS, watchOS or visionOS builds, live-backend dogfooding, or React Native malformed-input validation. Release cutoff, review owner and protected published version are not yet confirmed. FFL-3428 is already complete; no special revocation mechanism or backend changes are needed.
