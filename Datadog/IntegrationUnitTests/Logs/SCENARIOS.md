# DatadogLogs Harness Scenarios

> List of behavioural scenarios driving DatadogLogs from 0% → >90% coverage via the harness. Each item becomes one test method (with optional permutations) written in a separate Claude Code session via the `dd-sdk-ios:add-harness-test` skill.

## Conventions

- **One bullet = one behaviour.** Permutations (e.g., "for each log level") stay inside the scenario, not split into N items.
- **Readiness flag** at end of each bullet:
  - *`ready`* — no harness extension required; test can be written directly using inline closures (`Logs.enable(in: app.core)`, `app.logger = Logger.create(...)`) against the existing harness.
  - *`needs-fixture: <name>`* — harness must be extended first (e.g., console output capture, network state mock, `enableTrace`, launch arguments).
- **Format**: `**<title>** — <1–2 sentence behaviour description>. _<flag>_`

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

- **Logs feature enable after SDK init** — `Logs.enable(in: app.core)` after `Datadog.initialize(...)` registers the feature; subsequent `Logger.create(in: app.core)` produces a working remote logger. _ready_
- **Logger creation before Logs feature enabled** — `Logger.create` returns a `NOPLogger` (no logs recorded) when `Logs.enable` was never called. _ready_
- **Logs feature enabled twice** — second `Logs.enable(in: app.core)` is a no-op; previously-created loggers continue working. _ready_

## 2. Logger creation & configuration → `LogsConfigTests.swift`

- **Default Logger.Configuration** — log emitted from default-config logger has `serviceName` from SDK env, `loggerName` from main bundle id, `bundleWithRumEnabled=true`, `bundleWithTraceEnabled=true`, `networkInfoEnabled=false`, no console output. _ready_
- **Logger.Configuration.service overrides default** — explicit `service: "checkout"` appears in event `service` field. _ready_
- **Logger.Configuration.name overrides default** — explicit `name: "auth-logger"` appears in `logger.name`. _ready_
- **Multiple named loggers — independent tag state** — two loggers created with different names; tag added on logger A doesn't appear on logger B's logs. _ready_
- **Multiple named loggers — independent attribute state** — same as above for attributes. _ready_
- **Logger with `remoteSampleRate=0` and no console** — `Logger.create` returns NOPLogger; no logs recorded. _ready_
- **Logger with `consoleLogFormat` only (`.short`, `remoteSampleRate=0`)** — no logs sent remotely; console output produced. _needs-fixture: console capture_
- **Combined logger (console + remote)** — both outputs receive each log emission. _needs-fixture: console capture_
- **`loggerVersion` populated from SDK version** — every log carries the current SDK version in `logger.version`. _ready_

## 3. Log emission (levels & content) → `LogsRecordingTests.swift`

- **Each log level maps to matching status** — for each of `debug/info/notice/warn/error/critical`, the event `status` matches; permutate inside one test. _ready_
- **Base `log(level:message:error:attributes:)` method** — emitting via the protocol-level method produces same output as convenience methods. _ready_
- **Info log emission** — `info("user signed in")` produces a single recorded log with status "info" and matching message. _ready_
- **Message text preserved verbatim** — special characters, unicode, multi-line messages survive end-to-end. _ready_
- **`threadName` populated** — log emitted from a named thread reports that thread name in `logger.thread_name`. _ready_
- **`applicationVersion` and `applicationBuildNumber`** — populated from bundle context on every log. _ready_
- **`environment`** — populated from `Datadog.Configuration.env` ("env" field) on every log. _ready_
- **`device` and `os` fields populated** — every log carries `device` and `os` blocks consistent with `AppRunner` simulated environment. _ready_

## 4. Tags → `LogsRecordingTests.swift`

- **`addTag(withKey:value:)` persists** — tag added once appears on all subsequent logs from the same logger. _ready_
- **`removeTag(withKey:)`** — after removal, tag with that key disappears from subsequent logs (prior logs unaffected). _ready_
- **`add(tag:)` raw tag** — raw value appears in `ddtags` of subsequent logs. _ready_
- **`remove(tag:)` raw tag** — after removal, raw tag disappears from subsequent logs. _ready_
- **Tag sanitization — special characters** — characters outside `[a-z0-9_:./-]` are converted to underscores in the emitted `ddtags`. _ready_
- **Tag sanitization — uppercase to lowercase** — uppercase characters in tag key/value are lowercased. _ready_
- **Tag truncation at 200 chars** — tags longer than 200 are truncated. _ready_
- **SDK-managed tags always present** — `env`, `version`, `service`, `host`, `device`, `source` are present in `ddtags` regardless of user tags. _ready_
- **Two loggers — tag isolation** — tag added on logger A absent from logger B's logs (overlap with §2 "independent tag state" but stated as tag-specific assertion). _ready_

## 5. Attributes → `LogsRecordingTests.swift`

- **`Logger.addAttribute(forKey:value:)` persists** — attribute added once appears on all subsequent logs from that logger. _ready_
- **`Logger.removeAttribute(forKey:)`** — attribute removed disappears from subsequent logs (prior logs unaffected). _ready_
- **`Logs.addAttribute(forKey:value:)` (global)** — global attribute propagates to all loggers' subsequent logs. _ready_
- **`Logs.removeAttribute(forKey:)` (global)** — global attribute removed propagates as removal. _ready_
- **Per-log `attributes` parameter overrides logger-scoped** — same key passed at emission time wins over logger-attached value (only for that log). _ready_
- **Per-log `attributes` doesn't pollute logger state** — subsequent logs without the per-log attribute don't carry it. _ready_
- **Attribute precedence: per-log > logger > global** — same key set at all three scopes; per-log value wins. _ready_
- **Nested attribute keys with dot syntax** — `addAttribute(forKey: "user.profile.id", …)` produces nested JSON structure. _ready_
- **Encodable value types** — `Int`, `String`, `Bool`, `Date`, custom `Encodable` struct, nested dictionaries — all preserved through encoding. _ready_
- **Two loggers — attribute isolation** — attribute added on logger A absent from logger B's logs. _ready_

## 6. Errors → `LogsRecordingTests.swift`

- **`error.kind` from Swift `Error` type name** — passing `let e: TestError = …` populates `error.kind` with the type name. _ready_
- **`error.message` populated** — passing an `Error` populates `error.message` with `localizedDescription` or `String(describing:)`. _ready_
- **`error.stack` populated** — error log captures current stack trace symbols. _ready_
- **`error.sourceType` is always "ios"** — for any error log emitted from this SDK. _ready_
- **`error.fingerprint` from `_dd.error.fingerprint` attribute** — setting `Logs.Attributes.errorFingerprint` per-log produces `error.fingerprint` field. _ready_
- **No error parameter — no error fields** — log without `error:` argument has no `error.*` fields in event. _ready_
- **`critical()` with error captures stack and binary images** — critical-level emission populates error fields plus `error.binary_images`. _ready_

## 7. Sampling (`remoteSampleRate`) → `LogsFilteringTests.swift`

- **`remoteSampleRate=0` drops all logs** — no logs in `recordedLogs()` regardless of how many emitted. _ready_
- **`remoteSampleRate=100` keeps all logs** — every emitted log appears in `recordedLogs()`. _ready_
- **Debug launch argument forces 100** — when `LaunchArguments.Debug` is in process arguments, `remoteSampleRate=0` is overridden to send all. _needs-fixture: launch arguments_

## 8. Log threshold (`remoteLogThreshold`) → `LogsFilteringTests.swift`

- **Threshold `.warn` filters lower levels** — `debug`, `info`, `notice` not in recorded logs; `warn`, `error`, `critical` present. _ready_
- **Threshold `.critical` filters all but critical** — only critical logs present in recorded logs. _ready_
- **Threshold `.debug` (default) accepts all levels** — every level passes. _ready_
- **Threshold doesn't affect console output** — below-threshold logs still printed to console, only remote sending is filtered. _needs-fixture: console capture_

## 9. Console output → `LogsFilteringTests.swift`

- **`.short` format** — log printed as `[<TIMESTAMP>] [<STATUS>] <MESSAGE>` (or equivalent canonical form) to console. _needs-fixture: console capture_
- **`.shortWith(prefix:)` format** — log printed with the configured prefix prepended. _needs-fixture: console capture_
- **Error log on console includes error block** — error kind/message/stack rendered. _needs-fixture: console capture_
- **Console output ignores `remoteSampleRate` and `remoteLogThreshold`** — all logs printed regardless. _needs-fixture: console capture_

## 10. Event mapper → `LogsFilteringTests.swift`

- **Mapper modifies `message`** — `eventMapper` returns event with modified message; recorded log has the mapped message. _ready_
- **Mapper modifies `attributes`** — mapper adds/changes user attributes; recorded log reflects the changes. _ready_
- **Mapper returns nil → log dropped** — events for which mapper returns `nil` are absent from `recordedLogs()`. _ready_
- **Mapper passes through unchanged** — mapper returns the input unchanged; recorded log identical to baseline. _ready_
- **Mapper applies to all loggers globally** — multiple loggers all subject to the same `Logs.Configuration.eventMapper`. _ready_

## 11. RUM bundling → `LogsBundlingTests.swift`

- **`bundleWithRumEnabled=true` + active view → `view.id` injected** — log emitted during an active RUM view carries `view.id` matching the session view. _ready_
- **`bundleWithRumEnabled=true` + no active view** — log carries `application_id` and `session_id` but no `view.id`. _ready_
- **`bundleWithRumEnabled=false`** — log carries none of the RUM context attributes even with RUM enabled. _ready_
- **RUM feature not enabled** — log carries no RUM context attributes regardless of `bundleWithRumEnabled` value. _ready_
- **Active user action → `user_action.id` injected** — log emitted while a RUM action is active carries `user_action.id`. _ready_

## 12. Trace bundling (active span) → `LogsBundlingTests.swift`

- **`bundleWithTraceEnabled=true` + active span** — log carries `dd.trace_id` and `dd.span_id` matching the active span. _needs-fixture: enableTrace_
- **`bundleWithTraceEnabled=false` + active span** — log carries no trace context attributes. _needs-fixture: enableTrace_
- **No active span** — log carries no `dd.trace_id` / `dd.span_id`. _needs-fixture: enableTrace_
- **Trace not enabled in SDK** — log carries no trace context regardless of `bundleWithTraceEnabled`. _ready_

## 13. User info & account info → `LogsContextEnrichmentTests.swift`

- **`Datadog.setUserInfo(id:name:email:)` propagates to logs** — subsequent logs carry `usr.id`, `usr.name`, `usr.email`. _ready_
- **`extraInfo` keys appear under `usr.<key>`** — extra info keys propagate as `usr.<custom>` attributes. _ready_
- **`Datadog.addUserExtraInfo` merges** — adding extra info preserves existing user fields. _ready_
- **`Datadog.addUserExtraInfo` with nil removes a key** — passing `nil` for a key removes that key from subsequent logs. _ready_
- **`Datadog.clearUserInfo` strips user info** — subsequent logs have no `usr.*` (anonymous id may remain). _ready_
- **User info change after logs already emitted** — earlier logs keep prior user info; later logs reflect the change. _ready_
- **Anonymous user id present even without explicit user info** — `usr.anonymous_id` is in the event when no user info is set. _ready_
- **Account info populates `account.id` / `account.name`** — when set globally, subsequent logs carry account fields. _ready_

## 14. Network info enrichment → `LogsContextEnrichmentTests.swift`

- **`networkInfoEnabled=false` (default)** — log has no `network.client.*` or `network.client.sim_carrier.*` attributes. _ready_
- **`networkInfoEnabled=true` + WiFi reachability** — log carries `network.client.reachability="yes"`, `available_interfaces` includes "wifi". _needs-fixture: network state mock_
- **`networkInfoEnabled=true` + cellular + carrier** — log carries cellular reachability and `network.client.sim_carrier.*` (name, iso_country, technology, allows_voip). _needs-fixture: network state mock_
- **Reachability change between logs** — log A emitted while online; log B emitted while offline; reflects different `reachability`. _needs-fixture: network state mock_

---

## Out of harness

Behaviours from the public `DatadogLogs` API the harness cannot exercise via `recordedLogs()` matchers (and where they are/should be tested instead):

- **NOPLogger fallback when SDK is uninitialized.** `AppRunner` always initializes the SDK; the `core is NOPDatadogCore` branch in `Logger.create` is unreachable here. Covered by `LoggerTests.swift` (unit).
- **`Logs.Configuration.customEndpoint`.** Endpoint URL is consumed by the upload layer, not the storage layer that `DatadogCoreProxy` intercepts. `recordedLogs()` returns events regardless of endpoint. Covered by `LogsTests.swift` / network unit tests.
- **WebView log receiver.** `WebViewLogReceiver` consumes events from a JS bridge — there is no `WKWebView` running inside `AppRunner`. Covered by `WebViewLogReceiverTests.swift` (unit).
- **Cross-platform / Objective-C bridge surface** (`Logs+objc.swift`, `LogsDataModels+objc.swift`). Not driven through the Swift API surface that `AppRunner` exposes. Covered by `LogsDataModels+objcTests.swift` (unit).
- **Internal event mapper API** (`InternalExtension.setLogEventMapper`). Internal-only — the harness sticks to public APIs.
- **Stochastic sampling correctness** (`remoteSampleRate=50` produces ~50% acceptance over many runs). Behaviour is non-deterministic; `Sampler` unit tests cover the math. The harness only asserts the boundary cases (0 and 100).
