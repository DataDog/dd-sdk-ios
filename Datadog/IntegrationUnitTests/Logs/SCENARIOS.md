# DatadogLogs Harness Scenarios

> List of behavioural scenarios driving DatadogLogs from 0% → >90% coverage via the harness. Each item becomes one test method (with optional permutations) written in a separate Claude Code session via the `dd-sdk-ios:add-harness-test` skill.

## Conventions

- **One bullet = one behaviour.** Permutations (e.g., "for each log level") stay inside the scenario, not split into N items.
- **Readiness flag** at end of each bullet:
  - *`ready`* — no harness extension required; test can be written directly using inline closures (`Logs.enable(in: app.core)`, `app.logger = Logger.create(...)`) against the existing harness.
  - *`needs-fixture: <name>`* — harness must be extended first (e.g., console output capture, network state mock, `enableTrace`, launch arguments).
- **Implementation link**: once a scenario is covered by a test, append `→ `<TestMethodName>`` to the bullet. Bullet without a link = not yet implemented. Multi-permutation scenarios (e.g., "for each log level") link to the single permutating method.
- **Format**: `**<title>** — <1–2 sentence behaviour description>. _<flag>_ [→ `<TestMethodName>`]`

Framework reference: `docs/HARNESS_TESTING.md`. Write a test: invoke `dd-sdk-ios:add-harness-test`.

## File layout

The 14 sections below distribute across 5 test files, grouped by behavioural concern. New scenarios go into the file matching their section.

| File | Sections | Concern |
|---|---|---|
| `LogsConfigTests.swift` | §1, §2 | Setup: `Logs.enable` timing/idempotency, `Logger.create` paths, `Logger.Configuration` options |
| `LogsRecordingTests.swift` | §3, §4, §5, §6 | What ends up in the recorded log: levels, message content, tags, attributes, errors |
| `LogsFilteringTests.swift` | §7, §8, §9, §10 | What gets dropped or transformed before recording: sampling, threshold, console, event mapper |
| `LogsBundlingTests.swift` | §11, §12 | Cross-feature integration: RUM `view.id` / `user_action.id`, Trace `dd.trace_id` / `dd.span_id` |
| `LogsContextEnrichmentTests.swift` | §13, §14 | Core SDK context baked into logs: user/account info, network info |

---

## 1. Setup & enablement → `LogsConfigTests.swift`

- **Logs feature enable after SDK init** — `Logs.enable(in: app.core)` after `Datadog.initialize(...)` registers the feature; subsequent `Logger.create(in: app.core)` produces a working remote logger. _ready_ → `testGivenSDKInitialized_whenLogsEnabledAfterInit_loggerProducesRecordedLogs()`
- **Logger creation before Logs feature enabled** — `Logger.create` returns a `NOPLogger` (no logs recorded) when `Logs.enable` was never called. _ready_ → `testGivenLogsFeatureNotEnabled_whenLoggerIsCreated_itProducesNoRecordedLogs()`
- **Logs feature enabled twice** — second `Logs.enable(in: app.core)` is a no-op; previously-created loggers continue working. _ready_ → `testGivenLogsFeatureEnabled_whenEnabledASecondTime_previouslyCreatedLoggerStillWorks()`

## 2. Logger creation & configuration → `LogsConfigTests.swift`

- **Default Logger.Configuration** — log emitted from default-config logger has `serviceName` from SDK env, `loggerName` from main bundle id, `bundleWithRumEnabled=true`, `bundleWithTraceEnabled=true`, `networkInfoEnabled=false`, no console output. _ready_ → `testGivenDefaultLoggerConfiguration_whenLogIsEmitted_itHasDefaultServiceAndLoggerName()`
- **Logger.Configuration.service overrides default** — explicit `service: "checkout"` appears in event `service` field. _ready_ → `testGivenLoggerConfigurationWithExplicitService_whenLogIsEmitted_itUsesProvidedServiceName()`
- **Logger.Configuration.name overrides default** — explicit `name: "auth-logger"` appears in `logger.name`. _ready_ → `testGivenLoggerConfigurationWithExplicitName_whenLogIsEmitted_itUsesProvidedLoggerName()`
- **Multiple named loggers — independent tag state** — two loggers created with different names; tag added on logger A doesn't appear on logger B's logs. _ready_ → `testGivenTwoLoggers_whenTagIsAddedOnOneOfThem_itDoesNotAppearOnOtherLoggersLogs()`
- **Multiple named loggers — independent attribute state** — same as above for attributes. _ready_ → `testGivenTwoLoggers_whenAttributeIsAddedOnOneOfThem_itDoesNotAppearOnOtherLoggersLogs()`
- **Logger with `remoteSampleRate=0` and no console** — `Logger.create` returns NOPLogger; no logs recorded. _ready_ → `testGivenLoggerWithZeroRemoteSampleRateAndNoConsole_whenLogsAreEmitted_noLogsAreRecorded()`
- **Logger with `consoleLogFormat` only (`.short`, `remoteSampleRate=0`)** — no logs sent remotely; console output produced. _needs-fixture: console capture_
- **Combined logger (console + remote)** — both outputs receive each log emission. _needs-fixture: console capture_
- **`loggerVersion` populated from SDK version** — every log carries the current SDK version in `logger.version`. _ready_ → `testGivenAnyLogger_whenLogIsEmitted_itCarriesCurrentSDKVersionInLoggerVersion()`

## 3. Log emission (levels & content) → `LogsRecordingTests.swift`

- **Each log level maps to matching status** — for each of `debug/info/notice/warn/error/critical`, the event `status` matches; permutate inside one test. _ready_ → `testGivenLoggerWithDefaultThreshold_whenLogsAreEmittedAtEachLevel_eachLogCarriesMatchingStatus()`
- **Base `log(level:message:error:attributes:)` method** — emitting via the protocol-level method produces same output as convenience methods. _ready_ → `testGivenTwoLoggers_whenOneUsesBaseLogMethodAndOtherUsesConvenience_payloadsMatch()`
- **Info log emission** — `info("user signed in")` produces a single recorded log with status "info" and matching message. _ready_ → `testGivenLogger_whenInfoLogIsEmitted_itHasInfoStatusAndMatchingMessage()`
- **Message text preserved verbatim** — special characters, unicode, multi-line messages survive end-to-end. _ready_ → `testGivenLogger_whenMessageContainsUnicodeAndMultilineContent_itIsPreservedVerbatim()`
- **`date` matches simulated time** — log emitted at simulated time T carries `date` field equal to T; verifies that harness time-mocking flows through to the log payload. _needs-fixture: `Logs.Configuration.dateProvider` override_
- **`threadName` populated** — log emitted from a named thread reports that thread name in `logger.thread_name`. _ready_ → `testGivenNamedThread_whenLogIsEmitted_loggerThreadNameMatches()`
- **`applicationVersion` and `applicationBuildNumber`** — populated from bundle context on every log (`version`, `build_version` fields). _ready_ → `testGivenLogger_whenLogIsEmitted_itCarriesApplicationVersionAndBuildNumber()`
- **`build_id` field handling** — log carries `build_id` consistent with the binary loaded in the harness environment: present if SDK detects the binary's code-integrity hash, otherwise absent (assert whichever the harness produces — both shapes are valid SDK behaviour). _ready_ → `testGivenHarnessWithoutCrossPlatformBuildId_whenLogIsEmitted_buildIdIsAbsent()`
- **`environment`** — populated from `Datadog.Configuration.env` on every log; encoded as the `env:<value>` entry in `ddtags` (the encoder does not emit a top-level `env` field). _ready_ → `testGivenSDKConfiguredWithCustomEnv_whenLogIsEmitted_itCarriesThatEnvInDdTags()`
- **`device` and `os` fields populated** — every log carries `device` and `os` blocks consistent with `AppRunner` simulated environment. _ready_ → `testGivenLogger_whenLogIsEmitted_itCarriesDeviceAndOsBlocks()`
- **`_dd` internal block present** — every log JSON contains the `_dd` key with internal SDK metadata. Minimum assertion: `_dd` is present as a JSON object on every recorded log; nested shape can be discovered during test authoring. _ready_ → `testGivenLogger_whenLogIsEmitted_itCarriesInternalDdBlock()`

## 4. Tags → `LogsRecordingTests.swift`

- **`addTag(withKey:value:)` persists** — tag added once appears on all subsequent logs from the same logger. _ready_ → `testGivenLogger_whenTagIsAddedWithKeyValue_itPersistsAcrossSubsequentLogs()`
- **`removeTag(withKey:)`** — after removal, tag with that key disappears from subsequent logs (prior logs unaffected). _ready_ → `testGivenLoggerWithTag_whenTagIsRemovedByKey_subsequentLogsDoNotCarryIt()`
- **`add(tag:)` raw tag** — raw value appears in `ddtags` of subsequent logs. _ready_ → `testGivenLogger_whenRawTagIsAdded_itAppearsInDdTags()`
- **`remove(tag:)` raw tag** — after removal, raw tag disappears from subsequent logs. _ready_ → `testGivenLoggerWithRawTag_whenRawTagIsRemoved_subsequentLogsDoNotCarryIt()`
- **Tag sanitization — special characters** — characters outside `[a-z0-9_:./-]` are converted to underscores in the emitted `ddtags` (one-for-one substitution; see `LogEventSanitizer.replaceIllegalCharactersIn`). _ready_ → `testGivenLogger_whenTagContainsIllegalCharacters_eachIsReplacedWithUnderscore()`
- **Tag sanitization — uppercase to lowercase** — uppercase characters in tag key/value are lowercased. _ready_ → `testGivenLogger_whenTagContainsUppercase_itIsLowercasedInDdTags()`
- **Tag truncation at 200 chars** — tags whose joined `key:value` length exceeds 200 are truncated to the first 200 characters (limit applies to the full tag string, not just the value). _ready_ → `testGivenLogger_whenTagExceeds200Characters_itIsTruncatedToTheFirst200()`
- **SDK-managed tags always present** — the core injects `service:<value>`, `version:<value>`, `sdk_version:<value>`, `env:<value>` (and optional `variant:<value>`) into `ddtags` regardless of user tags (see `DatadogContext.buildDDTags()`). `host`, `device`, `source` are *reserved tag keys* (rejected if a user tries to use them) but the SDK does not auto-emit them. _ready_ → `testGivenLoggerWithoutUserTags_whenLogIsEmitted_ddtagsCarriesSDKManagedEntries()`
- **Two loggers — tag isolation** — tag added on logger A absent from logger B's logs (overlap with §2 "independent tag state" but stated as tag-specific assertion). _ready_ → `testGivenTwoLoggers_whenTagIsAddedOnOneOfThem_itDoesNotAppearOnOtherLoggersLogs()` (in `LogsConfigTests.swift`, shared with §2)

## 5. Attributes → `LogsRecordingTests.swift`

- **`Logger.addAttribute(forKey:value:)` persists** — attribute added once appears on all subsequent logs from that logger. _ready_ → `testGivenLogger_whenAttributeIsAddedWithKeyAndValue_itPersistsAcrossSubsequentLogs()`
- **`Logger.removeAttribute(forKey:)`** — attribute removed disappears from subsequent logs (prior logs unaffected). _ready_ → `testGivenLoggerWithAttribute_whenAttributeIsRemovedByKey_subsequentLogsDoNotCarryIt()`
- **`Logs.addAttribute(forKey:value:)` (global)** — global attribute propagates to all loggers' subsequent logs. _ready_ → `testGivenLogsFeatureEnabled_whenGlobalAttributeIsAdded_allLoggersIncludeItOnSubsequentLogs()`
- **`Logs.removeAttribute(forKey:)` (global)** — global attribute removed propagates as removal. _ready_ → `testGivenGlobalAttribute_whenGlobalAttributeIsRemoved_subsequentLogsDoNotCarryIt()`
- **Per-log `attributes` parameter overrides logger-scoped** — same key passed at emission time wins over logger-attached value (only for that log). _ready_ → `testGivenLoggerWithAttribute_whenSameKeyIsPassedPerLog_perLogValueWins()`
- **Per-log `attributes` doesn't pollute logger state** — subsequent logs without the per-log attribute don't carry it. _ready_ → `testGivenLogger_whenAttributeIsPassedPerLog_subsequentLogsDoNotCarryIt()`
- **Attribute precedence: per-log > logger > global** — same key set at all three scopes; per-log value wins. _ready_ → `testGivenAttributeAtAllThreeScopes_whenLogIsEmitted_perLogValueWinsOverLoggerAndGlobal()`
- **Nested attribute keys with dot syntax** — `addAttribute(forKey: "user.profile.id", …)` is encoded as a *flat* top-level JSON key (literal dots preserved in the property name) — the SDK does not expand dotted keys into nested objects. The sanitizer only collapses dots to underscores once nesting exceeds 10 levels. _ready_ → `testGivenAttributeWithDottedKey_whenLogIsEmitted_keyAppearsAsFlatLiteralKeyInJson()`
- **Encodable value types** — `Int`, `String`, `Bool`, `Date`, custom `Encodable` struct, nested dictionaries — all preserved through encoding. _ready_ → `testGivenAttributesOfVariousEncodableTypes_whenLogIsEmitted_eachTypeRoundtripsCleanly()`
- **Two loggers — attribute isolation** — attribute added on logger A absent from logger B's logs. _ready_ → `testGivenTwoLoggers_whenAttributeIsAddedOnOneOfThem_itDoesNotAppearOnOtherLoggersLogs()` (in `LogsConfigTests.swift`, shared with §2)

## 6. Errors → `LogsRecordingTests.swift`

- **`error.kind` from Swift `Error` type name** — passing `let e: TestError = …` populates `error.kind` with the Swift type name (`"\(type(of: error))"`). _ready_ → `testGivenSwiftErrorPassedToLogger_whenLogIsEmitted_errorKindMatchesSwiftErrorTypeName()`
- **`error.message` populated** — passing a Swift (non-`NSError`) `Error` populates `error.message` with `String(describing: error)` (i.e. `CustomStringConvertible.description` when conformed, otherwise the synthesised representation). `localizedDescription` is only used for `NSError` subclasses. _ready_ → `testGivenSwiftErrorWithCustomDescription_whenLogIsEmitted_errorMessageMatchesStringDescription()`
- **`error.stack` populated** — for Swift (non-`NSError`) `Error`, `error.stack` is populated from `String(describing: error)` — the **same source as `error.message`**, not a runtime backtrace. The SDK does not capture `Thread.callStackSymbols` here. _ready_ → `testGivenSwiftErrorPassedToLogger_whenLogIsEmitted_errorStackEqualsErrorDescription()`
- **`error.sourceType` is always "ios"** — for any error log emitted from this SDK. _ready_ → `testGivenAnySwiftErrorPassedToLogger_whenLogIsEmitted_errorSourceTypeIsIos()`
- **`error.fingerprint` from `Logs.Attributes.errorFingerprint` per-log attribute** — setting the `_dd.error.fingerprint` per-log attribute (constant exposed as `Logs.Attributes.errorFingerprint`) produces an `error.fingerprint` field; the attribute itself is consumed and does not leak as a user attribute. _ready_ → `testGivenErrorLogWithFingerprintAttribute_whenLogIsEmitted_errorFingerprintIsPopulated()`
- **No error parameter — no error fields** — log without `error:` argument has no `error.*` fields in event (kind, message, stack, source_type, fingerprint, binary_images all absent). _ready_ → `testGivenLogWithoutErrorParameter_whenLogIsEmitted_noErrorFieldsArePresent()`
- **`critical()` with error captures error fields; binary images require crash-reporting fixture** — critical-level emission populates `error.kind` / `error.message` / `error.stack` / `error.source_type` like other levels. `error.binary_images` is populated only when (a) the user opts in via `_dd.error.include_binary_images: true` per-log attribute *and* (b) a `BacktraceReporting` is registered on the core (via `DatadogCrashReporting`). The harness does not register a backtrace reporter, so `error.binary_images` is absent on every recorded log. _ready_ (binary_images branch is "Out of harness" — see below) → `testGivenCriticalLogWithError_whenLogIsEmitted_errorFieldsArePopulatedAndBinaryImagesAreAbsentInHarness()`

## 7. Sampling (`remoteSampleRate`) → `LogsFilteringTests.swift`

- **`remoteSampleRate=0` drops all logs** — no logs in `recordedLogs()` regardless of how many emitted. _ready_ → `testGivenLoggerWithZeroRemoteSampleRateAndConsoleOutput_whenLogsAreEmitted_noLogsAreRecorded()`
- **`remoteSampleRate=100` keeps all logs** — every emitted log appears in `recordedLogs()`. _ready_ → `testGivenLoggerWithMaxRemoteSampleRate_whenLogsAreEmitted_allLogsAreRecorded()`
- **Debug launch argument forces 100** — when `LaunchArguments.Debug` is in process arguments, `remoteSampleRate=0` is overridden to send all. _needs-fixture: launch arguments_

## 8. Log threshold (`remoteLogThreshold`) → `LogsFilteringTests.swift`

- **Threshold `.warn` filters lower levels** — `debug`, `info`, `notice` not in recorded logs; `warn`, `error`, `critical` present. _ready_ → `testGivenLoggerWithWarnThreshold_whenLogsAreEmittedAtEachLevel_onlyWarnAndAboveAreRecorded()`
- **Threshold `.critical` filters all but critical** — only critical logs present in recorded logs. _ready_ → `testGivenLoggerWithCriticalThreshold_whenLogsAreEmittedAtEachLevel_onlyCriticalIsRecorded()`
- **Threshold `.debug` (default) accepts all levels** — every level passes. _ready_ → `testGivenLoggerWithDefaultThreshold_whenLogsAreEmittedAtEachLevel_allLevelsAreRecorded()`
- **Threshold doesn't affect console output** — below-threshold logs still printed to console, only remote sending is filtered. _needs-fixture: console capture_

## 9. Console output → `LogsFilteringTests.swift`

- **`.short` format** — log printed as `[<TIMESTAMP>] [<STATUS>] <MESSAGE>` (or equivalent canonical form) to console. _needs-fixture: console capture_
- **`.shortWith(prefix:)` format** — log printed with the configured prefix prepended. _needs-fixture: console capture_
- **Error log on console includes error block** — error kind/message/stack rendered. _needs-fixture: console capture_
- **Console output ignores `remoteSampleRate` and `remoteLogThreshold`** — all logs printed regardless. _needs-fixture: console capture_

## 10. Event mapper → `LogsFilteringTests.swift`

- **Mapper modifies `message`** — `eventMapper` returns event with modified message; recorded log has the mapped message. _ready_ → `testGivenLogsConfigurationWithMessageMapper_whenLogIsEmitted_recordedMessageIsMapped()`
- **Mapper modifies `attributes`** — mapper adds/changes user attributes; recorded log reflects the changes. _ready_ → `testGivenLogsConfigurationWithAttributesMapper_whenLogIsEmitted_recordedAttributesReflectMapperChanges()`
- **Mapper returns nil → log dropped** — events for which mapper returns `nil` are absent from `recordedLogs()`. _ready_ → `testGivenLogsConfigurationWithMapperReturningNil_whenLogsAreEmitted_noLogsAreRecorded()`
- **Mapper passes through unchanged** — mapper returns the input unchanged; recorded log identical to baseline. _ready_ → `testGivenLogsConfigurationWithIdentityMapper_whenLogIsEmitted_recordedPayloadMatchesBaseline()`
- **Mapper applies to all loggers globally** — multiple loggers all subject to the same `Logs.Configuration.eventMapper`. _ready_ → `testGivenLogsConfigurationMapper_whenMultipleLoggersEmit_mapperAppliesToAll()`

## 11. RUM bundling → `LogsBundlingTests.swift`

- **`bundleWithRumEnabled=true` + active view → `view.id` injected** — log emitted during an active RUM view carries `view.id` matching the session view. _ready_ → `testGivenBundleWithRumEnabledAndActiveManualView_whenLogIsEmitted_logCarriesViewIdMatchingRUMSession()`
- **`bundleWithRumEnabled=true` + no active view** — log carries `application_id` and `session_id` but no `view.id`. _ready_ → `testGivenBundleWithRumEnabledAndNoManualView_whenLogIsEmitted_logCarriesApplicationAndSessionIdsMatchingRUMSession()` (adapted: SDK auto-creates an `ApplicationLaunch` view on user launch — there is no truly view-less window in this scenario, so the test asserts `view.id` matches the auto-created view rather than being absent)
- **`bundleWithRumEnabled=false`** — log carries none of the RUM context attributes even with RUM enabled. _ready_ → `testGivenBundleWithRumEnabledFalseAndActiveView_whenLogIsEmitted_logCarriesNoRUMContextAttributes()`
- **RUM feature not enabled** — log carries no RUM context attributes regardless of `bundleWithRumEnabled` value. _ready_ → `testGivenRUMFeatureNotEnabled_whenLogIsEmitted_logCarriesNoRUMContextAttributesRegardlessOfBundleFlag()`
- **Active user action → `user_action.id` injected** — log emitted while a RUM action is active carries `user_action.id`. _ready_ → `testGivenActiveUserAction_whenLogIsEmitted_logCarriesUserActionIdMatchingActiveAction()`

## 12. Trace bundling (active span) → `LogsBundlingTests.swift`

- **`bundleWithTraceEnabled=true` + active span** — log carries `dd.trace_id` and `dd.span_id` matching the active span. _needs-fixture: enableTrace_
- **`bundleWithTraceEnabled=false` + active span** — log carries no trace context attributes. _needs-fixture: enableTrace_
- **No active span** — log carries no `dd.trace_id` / `dd.span_id`. _needs-fixture: enableTrace_
- **Trace not enabled in SDK** — log carries no trace context regardless of `bundleWithTraceEnabled`. _ready_ → `testGivenTraceFeatureNotEnabled_whenLogsAreEmitted_logsCarryNoTraceContextRegardlessOfBundleFlag()`

## 13. User info & account info → `LogsContextEnrichmentTests.swift`

- **`Datadog.setUserInfo(id:name:email:)` propagates to logs** — subsequent logs carry `usr.id`, `usr.name`, `usr.email`. _ready_ → `testGivenSDKInitialized_whenUserInfoIsSet_subsequentLogsCarryUsrIdNameAndEmail()`
- **`extraInfo` keys appear under `usr.<key>`** — extra info keys propagate as `usr.<custom>` attributes. _ready_ → `testGivenUserInfoWithExtraInfo_whenLogIsEmitted_extraInfoKeysAppearUnderUsrPrefix()`
- **`Datadog.addUserExtraInfo` merges** — adding extra info preserves existing user fields. _ready_ → `testGivenUserInfoSet_whenAddUserExtraInfoIsCalled_subsequentLogsCarryMergedFields()`
- **`Datadog.addUserExtraInfo` with nil removes a key** — passing `nil` for a key removes that key from subsequent logs. _ready_ → `testGivenUserExtraInfoKey_whenAddUserExtraInfoSetsThatKeyToNil_subsequentLogsDoNotCarryIt()`
- **`Datadog.clearUserInfo` strips user info** — subsequent logs have no `usr.id`/`name`/`email` and no extra `usr.<key>`; `usr.anonymous_id` is preserved across the clear (when RUM is enabled to populate it in the first place — see "Anonymous user id" entry below). _ready_ → `testGivenUserInfoSet_whenClearUserInfoIsCalled_subsequentLogsHaveNoUsrIdNameOrEmail()`
- **User info change after logs already emitted** — earlier logs keep prior user info; later logs reflect the change. _ready_ → `testGivenLogEmittedBeforeUserInfoSet_whenLaterLogIsEmitted_onlyLaterLogCarriesUsrId()`
- **Anonymous user id present even without explicit user info** — `usr.anonymous_id` is in the event when no user info is set. The anonymous-id pipeline is owned by RUM (`AnonymousIdentifierManager`); it does not run for Logs-only setups, so this scenario asserts the field's presence with RUM enabled. _ready_ → `testGivenNoExplicitUserInfo_whenLogIsEmitted_logCarriesNonEmptyAnonymousId()`
- **Account info populates `account.id` / `account.name`** — when set globally, subsequent logs carry account fields. _ready_ → `testGivenAccountInfoSet_whenLogIsEmitted_logCarriesAccountIdAndAccountName()`

## 14. Network info enrichment → `LogsContextEnrichmentTests.swift`

- **`networkInfoEnabled=false` (default)** — log has no `network.client.*` or `network.client.sim_carrier.*` attributes. _ready_ → `testGivenDefaultLoggerConfiguration_whenLogIsEmitted_logCarriesNoNetworkClientFields()`
- **`networkInfoEnabled=true` + WiFi reachability** — log carries `network.client.reachability="yes"`, `available_interfaces` includes "wifi", and connection-meta fields: `supports_ipv4`, `supports_ipv6`, `is_expensive`, `is_constrained`, `link_quality`. _needs-fixture: network state mock_
- **`networkInfoEnabled=true` + cellular + carrier** — log carries cellular reachability and `network.client.sim_carrier.*` (name, iso_country, technology, allows_voip). _needs-fixture: network state mock_
- **Reachability change between logs** — log A emitted while online; log B emitted while offline; reflects different `reachability`. _needs-fixture: network state mock_

---

## Out of harness

Behaviours from the public `DatadogLogs` API the harness cannot exercise via `recordedLogs()` matchers (and where they are/should be tested instead):

- **NOPLogger fallback when SDK is uninitialized.** `AppRunner` always initializes the SDK; the `core is NOPDatadogCore` branch in `Logger.create` is unreachable here. Covered by `LoggerTests.swift` (unit).
- **`error.binary_images` for `error()` / `critical()` logs.** Populating `error.binary_images` requires (a) the per-log opt-in attribute `_dd.error.include_binary_images: true`, and (b) a `BacktraceReporting` registered on the core via `DatadogCrashReporting`. `AppRunner` does not register `DatadogCrashReporting`, so `binary_images` is always nil regardless of attribute. The harness verifies the negative shape; the positive shape (binary_images populated end-to-end) belongs to a future fixture-dependent batch or to crash-reporting unit tests.
- **`Logs.Configuration.customEndpoint`.** Endpoint URL is consumed by the upload layer, not the storage layer that `DatadogCoreProxy` intercepts. `recordedLogs()` returns events regardless of endpoint. Covered by `LogsTests.swift` / network unit tests.
- **WebView log receiver.** `WebViewLogReceiver` consumes events from a JS bridge — there is no `WKWebView` running inside `AppRunner`. Covered by `WebViewLogReceiverTests.swift` (unit).
- **Cross-platform / Objective-C bridge surface** (`Logs+objc.swift`, `LogsDataModels+objc.swift`). Not driven through the Swift API surface that `AppRunner` exposes. Covered by `LogsDataModels+objcTests.swift` (unit).
- **Internal event mapper API** (`InternalExtension.setLogEventMapper`). Internal-only — the harness sticks to public APIs.
- **Stochastic sampling correctness** (`remoteSampleRate=50` produces ~50% acceptance over many runs). Behaviour is non-deterministic; `Sampler` unit tests cover the math. The harness only asserts the boundary cases (0 and 100).

---

## Observations & Notes

Findings surfaced while writing harness tests — non-blocking, but worth tracking so they don't get lost. Each entry: short title + 1–3 sentences + optional follow-up.

- **Dead key `env` in `LogEventEncoder.StaticCodingKeys`** (surfaced in Batch 3, §3 `environment` scenario). The encoder declares `case environment = "env"` (`DatadogLogs/Sources/Log/LogEventEncoder.swift:180`) but never calls `try container.encode(log.environment, forKey: .environment)`. The `env` value reaches the wire only as an `env:<value>` entry in `ddtags`, never as a top-level `env` field. The coding key is unused — candidate for cleanup in `LogEventEncoder.swift`. Follow-up: drop the unused case (or actually emit the field if intended).

- **`Logs.Configuration.dateProvider` not pluggable from harness** (surfaced in Batch 3, §3 `date` scenario). `Logs.Configuration.dateProvider` defaults to `SystemDateProvider()` and is `internal`, so `Logs.enable(in: app.core)` ignores the `DateProviderMock` registered via `Datadog.Configuration` — log payloads carry wall-clock timestamps regardless of harness time-mocking. Forces the `date matches simulated time` scenario to be a fixture-dependent test. Follow-up: add a harness fixture (Batch 18 in plan) that overrides `Logs.Configuration.dateProvider` via `@testable import DatadogLogs` so simulated time flows through to log payloads.

- **`host`/`device`/`source` are reserved tag keys, not auto-emitted SDK-managed tags** (surfaced in Batch 4, §4 "SDK-managed tags always present"). `LogEventSanitizer.Constraints.reservedTagKeys` contains `host`, `device`, `source`, `service`, `env` — meaning user-supplied tags using those keys are dropped on the way out. But the *core* (`DatadogContext.buildDDTags()`) only auto-injects `service`, `version`, `sdk_version`, `env` (and optional `variant`). So `ddtags` on every log carries those four entries, plus any user tags, plus the SDK-managed reserves *that are also auto-emitted* (i.e. just `service` and `env`) — never `host`/`device`/`source`. SCENARIOS.md description for §4 was inaccurate; updated to match implementation. No code change needed.

- **Dotted attribute keys are encoded as flat literal JSON keys, not expanded into nested objects** (surfaced in Batch 5, §5 "Nested attribute keys with dot syntax"). User attributes are written via `DynamicCodingKey(name)` in `LogEventEncoder.encode(_:to:)` step 3 — `name` is the literal key string, including dots. So `addAttribute(forKey: "user.profile.id", value: 42)` produces a JSON object containing the literal key `"user.profile.id": 42`, not `{"user": {"profile": {"id": 42}}}`. `AttributesSanitizer.sanitizeKeys` only intervenes once nesting count exceeds `maxNestedLevelsInAttributeName = 10`, replacing extra dots with `_`. Datadog's backend treats `key.subkey` patterns as nested for query/visualisation, so the on-the-wire shape is functionally equivalent — but the *JSON document* itself is flat, and any test that asserts an actual nested object structure will fail. SCENARIOS.md description for §5 was misleading ("nested JSON structure"); updated. No code change needed.

- **`error.stack` is `String(describing: error)` for Swift Errors, not a captured backtrace** (surfaced in Batch 6, §6 `error.stack` scenario). `DDError(error:)` (`DatadogInternal/Sources/Utils/DDError.swift`) populates both `message` and `stack` from `"\(error)"` for any non-`NSError` Swift `Error`. There is no `Thread.callStackSymbols` capture — `error.stack` mirrors the error's textual description. For `NSError`, `stack` is `"\(nsError)"` (similar to message). True backtraces only land on logs via `error.binary_images` in combination with `DatadogCrashReporting` — not via `error.stack`. SCENARIOS.md description for §6 was misleading ("captures current stack trace symbols"); updated. No code change needed; consider documenting the behaviour publicly so SDK users don't expect a runtime backtrace.

- **`error.message` falls back to `String(describing:)`, not `localizedDescription`, for Swift Errors** (surfaced in Batch 6, §6 `error.message` scenario). `DDError(error:)` only consults `localizedDescription` for `NSError` subclasses. For pure Swift `Error`s — even ones conforming to `LocalizedError` — `error.message` is `"\(error)"`, which uses `CustomStringConvertible.description` if present, otherwise the runtime-synthesised representation. SCENARIOS.md description for §6 was ambiguous ("`localizedDescription` or `String(describing:)`"); updated to be precise about which path applies.

- **`critical()` does not auto-capture binary images** (surfaced in Batch 6, §6 "`critical()` with error captures stack and binary images"). The `critical(message:error:attributes:)` entry point in `RemoteLogger` calls the same `internalLog(...)` path as `error(...)`. Binary images are gated on the per-log attribute `_dd.error.include_binary_images: true` (constant `CrossPlatformAttributes.includeBinaryImages`) — the level alone does not trigger collection. Even with the opt-in, capture requires a `BacktraceReporting` (provided by `DatadogCrashReporting`) registered on the core. The harness does not register one, so binary images are always nil here regardless of how the user emits. SCENARIOS.md description for §6 was inaccurate ("critical-level emission populates ... `error.binary_images`"); split into a covered "error fields populated" branch and a documented "Out of harness" branch.

- **Pipeline order for §10 `eventMapper`: sampler → threshold → mapper** (surfaced in Batch 9, §10). `RemoteLogger.internalLog(...)` short-circuits on `sampler.sample()` first, then `level.rawValue >= threshold.rawValue`, and only then builds the `LogEvent` and runs `eventMapper.map(event:callback:)` (`LogEventBuilder.createLogEvent` step at the end). So the mapper never sees logs that were dropped by sampling or threshold — it only observes the ones that would otherwise be written. User-facing implication: a mapper cannot resurrect a dropped log, and a mapper that observes counts will not see below-threshold or sub-sampled traffic. No code change needed.

- **`Logs.Configuration.eventMapper` is per-feature, not per-logger** (surfaced in Batch 9, §10 "Mapper applies to all loggers globally"). The mapper stored on `Logs.Configuration` is wrapped into `SyncLogEventMapper` and saved on `LogsFeature.logEventMapper` at `Logs.enable(with:in:)` time. Every `Logger.create(...)` call afterwards reads `feature.logEventMapper` and wires it into the `RemoteLogger.Configuration` it builds — so all loggers share the single feature-level mapper. There is no per-logger override on the public surface (only the internal `Logs.Configuration.dd.setLogEventMapper(...)` exists, also feature-scoped). No code change needed.

- **RUM auto-creates an `ApplicationLaunch` view on user launch — there is no view-less window in user-launch scenarios** (surfaced in Batch 10, §11 "no active view"). At `RUM.enable(...)` time on a `userLaunchInSceneDelegateBasedApp` / `userLaunchInAppDelegateBasedApp` flow, `RUMApplicationScope.startApplicationLaunchView(on: RUMSDKInitCommand)` immediately starts the `ApplicationLaunch` view because `launchInfo.launchReason == .userLaunch` (the foreground/background guard only gates prewarm/background-launch, not user launch). Consequence: `RUMCoreContext.viewID` is non-nil for any log emitted after `RUM.enable(...)` in user-launch scenarios — even before any manual `startView`. Scenario §11 "no active view" was adapted to assert `view.id` matches the auto-created view (rather than being absent). No code change needed; documented for future cross-feature batches that need a strictly view-less RUM context — those would require `prewarmedSession` or `backgroundSession` launch types.

- **`bundleWithRumEnabled=false` and RUM-not-enabled both omit all four RUM keys atomically** (surfaced in Batch 10, §11). The injection in `RemoteLogger.swift` is gated by a single `if self.rumContextIntegration, let rum = context.additionalContext(ofType: RUMCoreContext.self), rum.sessionSampler.isSampled` — when any leg is false, *none* of `application_id` / `session_id` / `view.id` / `user_action.id` is written. So the negative shape for both "bundle disabled" and "RUM disabled" is identical: zero RUM keys on the log. No code change needed.

- **`usr.anonymous_id` is owned by the RUM feature, not the core** (surfaced in Batch 12, §13). `UserInfo.anonymousId` defaults to `nil` and only gets populated when `RUM.enable(...)` runs `AnonymousIdentifierManager.manageAnonymousIdentifier(shouldTrack:)` — which is gated on `RUMConfiguration.trackAnonymousUser` (default `true`). For Logs-only setups (no `RUM.enable(...)`), every recorded log has *no* `usr.anonymous_id` field at all. The §13 scenarios "Anonymous user id present even without explicit user info" and "`clearUserInfo` strips user info (anonymous id may remain)" therefore both require `enableRUM` to run; without RUM the assertion shape collapses to "no `usr.*` fields whatsoever". Follow-up: consider whether the anonymous-id pipeline belongs in core (so it runs for any feature, including Logs alone) — current placement makes the SCENARIOS.md "anonymous id" guarantee feature-conditional.
