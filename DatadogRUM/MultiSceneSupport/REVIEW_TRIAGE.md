# Production safety review triage

Assessed on2026-09-17 at af63657f08dbecb66e7c3ae97ed53fc8f7b065b9 against
92f021ba7e4a866f84a52da93ed8b63f3dc75882.
The [review cycle](PRODUCTION_SAFETY_REVIEW.md) is completed; its finding-to-gate
decisions and evidence limits remain here. This document has no execution queue.

All reported findings were relevant to compatibility, stability or ownership.
Initial source/compiler/extracted probes did not establish mounted SwiftUI or
physical OS ordering; subsequent evidence is identified separately in the table.
Initial “no runtime result” wording describes the original assessment, not an
open repair. Review IDs R01–R12 map to D01–D12, distinct from component R01–R06.

## Finding decisions

| Review / gate | Initial assessment at reviewed source | Repair boundary and decisive regression | Disposition evidence |
| --- | --- | --- | --- |
| R01 / D01, P1 | Confirmed platform compile defect. Resource `modify` references `RUMUIEventNetworkContext` at line 135 while its declaration is excluded on watchOS. Package supports watchOS 9. Isolated conditional/reference probe reproduces missing symbol. | Move the accessor to platform-neutral Internal ownership or guard the UIKit-only extraction while preserving absent-context behavior. Full DatadogRUM watchOS compile, not just the expression, must pass. Keep its interface compatible with D04's core-scoped contract. | CLOSED in EXP-162, signed `e420528f7`; full Debug/Release watchOS builds and 70 iOS tests. |
| R02 / D02, P1 | Confirmed platform compile defect. `DDScriptMessageHandler` is available under WebKit on macOS, but unconditionally follows `NSWindow.windowScene`. Narrowed compiler probe fails; normal NSWindow access control passes. | Guard UIKit scene extraction and use absent metadata on macOS. Build DatadogWebViewTracking on macOS and retain iOS message/ownership tests. | CLOSED in EXP-162, signed `af8864528`; full Debug/Release macOS builds and 28 iOS tests. |
| R03 / D03, P1 | Source confirms the strong closure/State cycle at SwiftUI modifier lines 4456/4698 and registration lines 2621/2644. The original review's ARC-shape probe supports it; no mounted SDK teardown result exists yet. | Replace bound-modifier captures with a small cancellable context and weak handler/state/arbiter ownership. Mount/remove a real keyed host, release the core and prove weak registration/instrumentation release and teardown. | CLOSED in EXP-168, signed `7b77f60eb`; 25 retained registrations/states become zero on27/26.5, instrumentation releases and three real method implementations restore. P03 registry retirement closes separately in EXP-172. |
| R04 / D04, P1 | Confirmed isolation gap. `RUMContextHandoff` has one process-wide TaskLocal/thread slot; Monitor/subscriber, Logs, Trace and network consumers have no core identity check. A foreign authoritative nil is wrong too. | Shared internal core-instance/generation key, nested per-owner entries and lookup only by the consuming core. Cover different cores, identical application IDs/different sessions, no-RUM cores, nested dispatch, inherited work after stop/reinitialize. | CLOSED in EXP-166, signed `5eb3c1aac`; 282 tests, core lifetime and every consumer covered, allocation1/64 and latency/reentrancy budgets pass on27/26.5. |
| R05 / D05, P1 | Source-confirmed target-resolution defect. `startNewSession` excludes the old last representative, then the unchanged process target resolves against restored peers. Existing restart coverage supplies an explicit scene and misses this path. | Resolve the old owner once before restoration; carry that exact decision through new-session dispatch. Test A/B, representative B, stopSession, source-less start C; also identity-stop A with B preserved. | CLOSED in EXP-167, signed `0aaafa7bd`; six failing scope controls, 198 tests and two-native-scene 47/47 acceptance. |
| R06 / D06, P1 | Source-confirmed lazy-expiration divergence. Lifecycle-triggered expiration postpones creation; the next start/stop has restart=false and resumes no peers. Immediate refresh has the concurrent-view rule that the lazy path lacks. | Reuse D05's resolution/restoration policy for explicit stop, immediate refresh and lazy timeout/max-duration paths. Controlled-clock lifecycle-then-navigation tests must preserve eligible B in the new session and respect background policy. | CLOSED in EXP-167 with D05; 44 new matrix cases distinguish timeout/max duration, immediate/delayed creation, background policy and legacy shape. |
| R07 / D07, P1 | Confirmed explicit/capability pending-authority gap. Host line 5272 calls suppression appear before an empty source delivers a snapshot. Observed input's nil-until-ready path is different; its passing test is not a control for empty explicit sources. | Separate subscribing from acquiring effective authority. Real registry tests before/after first accepted state; absent instrumentation must remain harmless. | CLOSED in EXP-169, local unsigned `a9aaf25a7`; four failing controls, 119 tests and mounted explicit/capability29/29 versus19/29. D08 remains separate. |
| R08 / D08, P1 | Relevant conditional state defect. Host line 5369 records a generation after a void handler call even when handler line 361 rejects the disconnected scene; trait line 6063 can supply the stale attachment. Exact framework ordering still requires a live test. | Connection/remount epoch plus accepted-publication bookkeeping. Deterministic stale-trait → reconnect → reader-mount regression first; H09 retains genuine OS ordering and immediate-telemetry verification. | CLOSED in EXP-170, signed `66d1ccb02`; actual handler controls,314 tests and mounted51/51 versus39/51, including fresh Resource/Log owners. H09 physical ordering remains open. |
| R09 / D09, P1 | Confirmed newly reachable unsafe hierarchy read. Existing nonisolated public controller APIs have no main-thread requirement; stop previously used identity only. `sceneTarget` now reads viewIfLoaded/window/windowScene synchronously on the caller. No crash is reproduced here. | Main-thread-only extraction; off-main immutable identity lookup or legacy inferred fallback. No sync-to-main wait or source-breaking actor annotation. Background getter-spy and Main Thread Checker regression plus main-thread exact targeting. | CLOSED in EXP-164 at local `a9abc092b`; 31 tests and 19/19 mounted checks, zero background reads/Main Thread Checker diagnostics. |
| R10 / D10, P2 | Confirmed accepted-state mismatch. Presentation line 6445 reconciles the proposal before customer Binding write; path line 5589 forwards then reads accepted state. A rejecting/canonicalizing setter is legal. | Accepted-state boundary for presentations, preserving transaction and immediate callback ownership. Reject nil/canonicalize item, emit work in setter, and verify exactly-once dismissal. Cover same-ID style replacement as a separate ordering discriminator. | CLOSED in EXP-173, signed `7619eb8a2`: six failing controls plus reproduced content rematerialization,337 tests and mounted77/77 versus55/77; exact accepted return and native dismissal owners. |
| R11 / D11, P2 | Confirmed compatibility mismatch. A string-key manual view can remain scene-less; a mounted WebView supplies a scene. Strict cache filtering at line 143 rejects that sole legacy view, removing existing container correlation. | Known single-scene/unambiguous legacy fallback only; never arbitrary cross-scene fallback. Replay-enabled native/WebView correlation test plus two-scene negative control. | CLOSED in EXP-165, signed `9a1ee83a5`; failing legacy control, 102 affected tests, 19/19 mounted bridge/Replay checks and four collector controls. T10 remains separate. |
| R12 / D12, P2 | Confirmed metadata regression by source comparison. Session line 373 expires every action with a synthetic empty keepalive before the real recipient processes its stop. `sendActionEvent` merges stop attributes only for action commands. | Resolve actual recipients before timeout advancement; recipients consume original command and only peers receive time-only advancement. Controlled t=0 start/t=11 stop preserves own attributes while foreign peer attributes remain excluded. | CLOSED in EXP-163, signed `084dff4c1`; failing controls and 212 affected tests. T02 restored; EXP-159's 15 accepted checks retained. |

The compiler evidence is in [review-triage-probes.json](Results/review-triage-probes.json).
The full chained macOS expression first triggered a Swift diagnostic-generation
failure; the narrowed member check and valid-window control disambiguated it.
Neither compiler probe substitutes for a supported-platform module build.
EXP-162 supplies failing full-target controls and passing Debug/Release builds:
[platform result](Results/EXP-162-platform-compatibility.json).
SwiftUI invariants and current test seams are detailed in
[COMPONENT_REVIEW.md](COMPONENT_REVIEW.md).

## Additional risks and exclusions

| Concern | Disposition and release gate |
| --- | --- |
| Disconnected scene dictionaries grow without retirement | CLOSED P03 in EXP-172 at signed `4653e0a72`: all four Release controls retain220 entries per history registry; all four candidates have zero retired entries/weak survivors within unchanged heap limits on27/26.5. Stale-callback and initial-peer controls, ordinary app smoke and watchOS Release build pass. |
| Final detach uses one queue turn | R04 closes in EXP-171 after two failing no-body controls and native retained-reader57/57 versus43/57. First mount precedes body/source rebind and owns fresh telemetry. H08/H09 genuine OS lifetime ordering remains open. |
| Presentation callback carries item ID instead of occurrence | Closed within EXP-173 deterministic mounted evidence: captured occurrence tokens reject old callbacks; accepted Binding reads preserve current content rematerialization. Native77/77 and337 tests pass. Genuine physical callback ordering remains H08/H09/H13. |
| Old Resource completion mutates a new-session action | Reproduced and repaired in [EXP-175](Results/EXP-175-resource-completion.json); original Resource owner and foreign continuous-action counts are discriminated. Full T03 acceptance is [EXP-176](Results/EXP-176-resource-start.json). |
| Multi-observer nested transition delivery | Resolved by [EXP-174](Results/EXP-174-observer-delivery.json): initial/commit nested generation and observer add/remove controls use every live host. The bounded R05 review is complete. |
| Queued A→B Resource start, sendEvent return signature, profiling identity | Do not reopen rejected/pre-existing concerns or invent a repair from this review. Existing exact-source and process-fallback contracts remain in force. |

## Disposition rules

Reject a finding only with a concrete counterexample/reproduction showing why the
reported path cannot violate the contract. Preserve that reasoning, failed attempts
and frozen baseline limits. A bounded repair does not close hardware or final
release obligations. [PLAN](PLAN.md) owns priority/dependency rules and
[.continue-here.md](../../.continue-here.md) owns the sole restart action.
