# Production safety review assessment and repair order

Assessed 2026-09-17 at `af63657f08dbecb66e7c3ae97ed53fc8f7b065b9` against
`92f021ba7e4a866f84a52da93ed8b63f3dc75882`. The [production safety review](PRODUCTION_SAFETY_REVIEW.md) now carries a live
disposition table while retaining its original findings and evidence.
Review finding Rxx maps to repair gate Dxx; these must not be confused with the
responsibility-review gates R01–R06 in the release checklist.

All 12 findings are relevant to this branch's stability, compatibility or ownership
contract. None is dismissed because the current iOS suite passed. Their evidence
levels differ: two compiler expressions were reproduced here; several ownership
failures follow directly from source; the reported extracted-state/ARC probes do
not establish mounted SwiftUI or physical lifecycle ordering. The initial
assessment claimed no repair. EXP-162 closes D01/D02 with complete platform
builds and focused iOS checks; EXP-163 closes D12 with 212 affected tests.
EXP-164 closes D09 with 31 tests and mounted Main Thread Checker evidence.
EXP-165 closes D11 with 102 tests and 19/19 mounted WebView/Replay checks.
EXP-166 closes D04/P02 with 282 affected tests and full Release ABBA allocation,
latency and reentrancy acceptance on27/26.5. EXP-167 closes D05/D06 with 198
affected tests and two native simulator scenes (47/47 versus control 20/47).
EXP-168 closes D03 with 303 tests and mounted 27/26.5 weak-release/teardown
acceptance, 37/37 each. EXP-169 closes D07 with four failing controls, 119 tests
and mounted29/29 acceptance. Two findings remain open. Existing
accepted experiment slices remain valid within their recorded boundaries.

## Finding decisions

| Review / gate | Assessment and source evidence | Fix boundary and decisive regression | When |
| --- | --- | --- | --- |
| R01 / D01, P1 | Confirmed platform compile defect. Resource `modify` references `RUMUIEventNetworkContext` at line 135 while its declaration is excluded on watchOS. Package supports watchOS 9. Isolated conditional/reference probe reproduces missing symbol. | Move the accessor to platform-neutral Internal ownership or guard the UIKit-only extraction while preserving absent-context behavior. Full DatadogRUM watchOS compile, not just the expression, must pass. Keep its interface compatible with D04's core-scoped contract. | CLOSED in EXP-162, signed `e420528f7`; full Debug/Release watchOS builds and 70 iOS tests. |
| R02 / D02, P1 | Confirmed platform compile defect. `DDScriptMessageHandler` is available under WebKit on macOS, but unconditionally follows `NSWindow.windowScene`. Narrowed compiler probe fails; normal NSWindow access control passes. | Guard UIKit scene extraction and use absent metadata on macOS. Build DatadogWebViewTracking on macOS and retain iOS message/ownership tests. | CLOSED in EXP-162, signed `af8864528`; full Debug/Release macOS builds and 28 iOS tests. |
| R03 / D03, P1 | Source confirms the strong closure/State cycle at SwiftUI modifier lines 4456/4698 and registration lines 2621/2644. The original review's ARC-shape probe supports it; no mounted SDK teardown result exists yet. | Replace bound-modifier captures with a small cancellable context and weak handler/state/arbiter ownership. Mount/remove a real keyed host, release the core and prove weak registration/instrumentation release and teardown. | CLOSED in EXP-168, signed `7b77f60eb`; 25 retained registrations/states become zero on27/26.5, instrumentation releases and three real method implementations restore. P03 registry retirement stays open. |
| R04 / D04, P1 | Confirmed isolation gap. `RUMContextHandoff` has one process-wide TaskLocal/thread slot; Monitor/subscriber, Logs, Trace and network consumers have no core identity check. A foreign authoritative nil is wrong too. | Shared internal core-instance/generation key, nested per-owner entries and lookup only by the consuming core. Cover different cores, identical application IDs/different sessions, no-RUM cores, nested dispatch, inherited work after stop/reinitialize. | CLOSED in EXP-166, signed `5eb3c1aac`; 282 tests, core lifetime and every consumer covered, allocation1/64 and latency/reentrancy budgets pass on27/26.5. |
| R05 / D05, P1 | Source-confirmed target-resolution defect. `startNewSession` excludes the old last representative, then the unchanged process target resolves against restored peers. Existing restart coverage supplies an explicit scene and misses this path. | Resolve the old owner once before restoration; carry that exact decision through new-session dispatch. Test A/B, representative B, stopSession, source-less start C; also identity-stop A with B preserved. | CLOSED in EXP-167, signed `0aaafa7bd`; six failing scope controls, 198 tests and two-native-scene 47/47 acceptance. |
| R06 / D06, P1 | Source-confirmed lazy-expiration divergence. Lifecycle-triggered expiration postpones creation; the next start/stop has restart=false and resumes no peers. Immediate refresh has the concurrent-view rule that the lazy path lacks. | Reuse D05's resolution/restoration policy for explicit stop, immediate refresh and lazy timeout/max-duration paths. Controlled-clock lifecycle-then-navigation tests must preserve eligible B in the new session and respect background policy. | CLOSED in EXP-167 with D05; 44 new matrix cases distinguish timeout/max duration, immediate/delayed creation, background policy and legacy shape. |
| R07 / D07, P1 | Confirmed explicit/capability pending-authority gap. Host line 5272 calls suppression appear before an empty source delivers a snapshot. Observed input's nil-until-ready path is different; its passing test is not a control for empty explicit sources. | Separate subscribing from acquiring effective authority. Real registry tests before/after first accepted state; absent instrumentation must remain harmless. | CLOSED in EXP-169, local unsigned `a9aaf25a7`; four failing controls, 119 tests and mounted explicit/capability29/29 versus19/29. D08 remains separate. |
| R08 / D08, P1 | Relevant conditional state defect. Host line 5369 records a generation after a void handler call even when handler line 361 rejects the disconnected scene; trait line 6063 can supply the stale attachment. Exact framework ordering still requires a live test. | Connection/remount epoch plus accepted-publication bookkeeping. Deterministic stale-trait → reconnect → reader-mount regression first; H09 retains genuine OS ordering and immediate-telemetry verification. | CLOSED in EXP-170, signed `66d1ccb02`; actual handler controls,314 tests and mounted51/51 versus39/51, including fresh Resource/Log owners. H09 physical ordering remains open. |
| R09 / D09, P1 | Confirmed newly reachable unsafe hierarchy read. Existing nonisolated public controller APIs have no main-thread requirement; stop previously used identity only. `sceneTarget` now reads viewIfLoaded/window/windowScene synchronously on the caller. No crash is reproduced here. | Main-thread-only extraction; off-main immutable identity lookup or legacy inferred fallback. No sync-to-main wait or source-breaking actor annotation. Background getter-spy and Main Thread Checker regression plus main-thread exact targeting. | CLOSED in EXP-164 at local `a9abc092b`; 31 tests and 19/19 mounted checks, zero background reads/Main Thread Checker diagnostics. |
| R10 / D10, P2 | Confirmed accepted-state mismatch. Presentation line 6445 reconciles the proposal before customer Binding write; path line 5589 forwards then reads accepted state. A rejecting/canonicalizing setter is legal. | Accepted-state boundary for presentations, preserving transaction and immediate callback ownership. Reject nil/canonicalize item, emit work in setter, and verify exactly-once dismissal. Cover same-ID style replacement as a separate ordering discriminator. | Native adapter repair before R06/F01 and presentation hardware H13. |
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
| Disconnected scene dictionaries grow without retirement | Confirmed independently by EXP-160: 220 entries after 20 warm-up plus 200 unique disconnect cycles. P03 already owns the finite repair. Retire connection generations without removing the fence while stale callbacks can still arrive; repeat ownership and retained-heap checks. |
| Final detach uses one queue turn | R04 closes in EXP-171 after two failing no-body controls and native retained-reader57/57 versus43/57. First mount precedes body/source rebind and owns fresh telemetry. H08/H09 genuine OS lifetime ordering remains open. |
| Presentation callback carries item ID instead of occurrence | Relevant unproven ordering risk. Add sheet/cover same-ID and A→B→A mount/disappear tests to D10/R06; carry an occurrence token if actual callback ordering proves stale callbacks can stop the replacement. |
| Old Resource completion mutates a new-session action | Treat as a pre-existing routing risk, not one of the 12 introduced defects. T03 must exercise a live continuous action plus late failed Resource completion and reject false counts; the existing immediately finished custom action does not discriminate. Fix if the required ownership oracle reproduces it. |
| Multi-observer nested transition delivery | Incremental review added this explicit R05 gap: one-observer nested tests do not establish monotonic delivery to every host. Test nested commit plus observer add/remove before closing R05; no unsupported runtime-failure claim. |
| Queued A→B Resource start, sendEvent return signature, profiling identity | Do not reopen rejected/pre-existing concerns or invent a repair from this review. Existing exact-source and process-fallback contracts remain in force. |

## Execution order and stopping rules

0. EXP-160/161 baselines and automation are recorded; D01/D02 platform repairs
   pass EXP-162. Preserve failed attempts and frozen evidence identities.
1. Early compatibility repairs D12, D09 and D11 pass EXP-163/164/165. Preserve
   their bounded evidence and invalid attempts; do not repeat them merely to resume.
2. D04/P02 passes EXP-166 with one core-lifetime identity across every consumer.
   D05/D06 passes EXP-167 with old navigation ownership resolved before
   restoration across explicit stop, immediate and lazy expiration. The first
   native readiness attempt is INVALID and preserved separately.
3. D03 mounted lifetime passes EXP-168 and bounded R02 review is complete.
   D07 pending authority, D08 reconnect and R04 retained-reader remount pass
   EXP-169/170/171. Next define P03 registry retirement, then D10.
   Keep the remaining R05/R06 discriminators in those slices. Each fix is a small
   component commit with explicit paths. Sign when available; if unavailable,
   continue unsigned locally and sign before any future authorized push.
   Deferred extraction still starts only after release freeze.
4. Resume T03–T14 only after the relevant repair dependencies and early baseline
   gates pass. Physical H08/H09/H13 follow their repair gates when capable hardware
   is available; a posted lifecycle test never closes them. Finish API review,
   supported-platform CI and Duo release acceptance after these gates.

Every repair experiment must name its gate, pinned source, environment and
predeclared decisive test. A finding may be rejected only with a concrete
counterexample/reproduction result showing the reported path cannot violate the
contract. Keep that disposition; do not silently delete its gate or raise a failed
performance threshold. Unsupported environments remain visible blockers.
