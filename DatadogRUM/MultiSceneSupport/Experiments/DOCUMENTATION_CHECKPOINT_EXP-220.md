# Documentation checkpoint after EXP-220 preparation

This is non-frozen historical reference, not restart reading or execution authority.
It preserves original review evidence and observations removed from active documents
during the authorized consolidation at `8d62fe01f92b8582eca9613bfef15e9708d296fd`.
Earlier deadlines, permissions, status claims, temporary paths and instructions in
quoted excerpts describe that time only. The current cursor, register and procedures
supersede them; no experiment was run or gate changed by this consolidation.

The [section map](../Results/documentation-migration-exp220.json) records original
hashes and line ranges, current owners and exact excerpt provenance. Detailed
experiment shards, results, thresholds and frozen archive remain unchanged.

Current reading: [runbook](../TOOLING_RUNBOOK.md), [assessment](../ASSESSMENT.md),
[safety dispositions](../PRODUCTION_SAFETY_REVIEW.md), [triage](../REVIEW_TRIAGE.md),
[component review](../COMPONENT_REVIEW.md). Use [the experiment index](../EXPERIMENTS.md)
for exact attempts rather than treating the following historical prose as live status.

## Original safety review

Original `PRODUCTION_SAFETY_REVIEW.md`, lines 236–375. Quoted without changes.

~~~~text
**Original review at the source revision below**

Reviewed on 2026-09-17. Branch: `valpertui/multiple-windows-scenes`. Reviewed head: `af63657f08dbecb66e7c3ae97ed53fc8f7b065b9`; comparison base: `92f021ba7e4a866f84a52da93ed8b63f3dc75882` (merge base with `origin/develop`). The production-source delta spans 41 files, with 11,191 added and 456 removed lines. There were no uncommitted production-source changes during the review. Existing local configuration and concurrent planning edits were preserved.

**Original verdict: hold this branch from production release.** The design has useful foundations: scene-keyed view branches, explicit command targets, origin capture for asynchronous work, and a semantic navigation source. However, this review found 12 actionable defects: nine P1 findings and three P2 findings. They include supported-platform compile failures, retained instrumentation, incorrect attribution across SDK instances, lost scene branches, and single-scene compatibility regressions. Passing the current iOS tests does not cover these cases.

This is a source and focused-probe review, not a production certification. Two compile failures were reproduced with isolated expressions against installed SDKs. Additional probes exercised extracted production state/context implementations or the relevant ARC ownership shape. The complete SDK suites, mounted SwiftUI teardown, physical-device lifecycle ordering, and release performance measurements were not rerun for this review. Each finding below states its evidence boundary.

**R01 — P1: Resource instrumentation does not compile for watchOS**

Location: [URLSessionRUMResourcesHandler.swift:135](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Resources/URLSessionRUMResourcesHandler.swift:135). The new resource path unconditionally references `RUMUIEventNetworkContext`, whose declaration is entirely inside `#if !os(watchOS)` in [RUMActionsHandler.swift:248](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Actions/RUMActionsHandler.swift:248). The package supports watchOS 9.

Evidence: a focused compiler probe containing the actual conditional declaration and exact reference, targeting `arm64_32-apple-watchos9.0`, reports `cannot find 'RUMUIEventNetworkContext' in scope`. This was not a complete watchOS SDK build.

Required change: use a platform-independent, core-scoped handoff accessor in DatadogInternal. A UIKit action helper must not be a dependency of cross-platform Resource code. Regression: compile DatadogRUM for watchOS, including the no-handoff path.

**R02 — P1: WebView instrumentation does not compile for macOS**

Location: [DDScriptMessageHandler.swift:32](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogWebViewTracking/Sources/DDScriptMessageHandler.swift:32). The file is guarded by `canImport(WebKit)`, but the new expression follows `WKWebView.window.windowScene`. On macOS, that window is an `NSWindow`.

Evidence: typechecking the exact expression against the installed macOS SDK reports `value of type 'NSWindow' has no member 'windowScene'`. macOS is an advertised package target.

Required change: isolate UIKit scene extraction behind a platform guard such as `canImport(UIKit)`; use absent routing metadata on platforms without UIWindowScene. Regression: compile DatadogWebViewTracking for macOS independently of the iOS suite.

**R03 — P1: Keyed SwiftUI registrations form a retain cycle and prevent instrumentation teardown**

Locations: callback capture in [SwiftUIViewModifier.swift:4456](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Views/SwiftUI/SwiftUIViewModifier.swift:4456), repeated at line 4698; callback storage at lines 2621 and 2644.

`RUMSwiftUINavigationOccurrenceRegistration` owns an escaping `process` closure. The closure accesses the modifier's `transitionArbiter` and bound `apply` method, retaining the modifier. The modifier in turn retains its `@State` registration and its instrumentation. No invalidation clears the closure. Removing the destination therefore does not break this ownership cycle. The retained instrumentation matters beyond memory: [RUMInstrumentation.swift:340](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/RUMInstrumentation.swift:340) performs unswizzling and stops hang, long-task, watchdog, and memory-warning monitors in `deinit`.

Evidence: an executable probe using the real SwiftUI.State wrapper and identical escaping instance-method capture shape retained both a weak registration and an instrumentation token after releasing the modifier; clearing the callback released both. This establishes the ARC cycle, but was not a mounted iOS memory-graph test.

Required change: make the callback operate on a small context with immutable metadata and weak handler/state/arbiter references; do not capture a modifier or its bound method. Add explicit cancellation to registration lifetime. Regression: mount a real keyed destination, remove its host, release the SDK core, and assert that the registration/instrumentation deallocate and teardown runs. Repeat the cycle to detect growth.

**R04 — P1: UI-event context leaks across named SDK cores**

Location: [NetworkContext.swift:34](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogInternal/Sources/NetworkInstrumentation/NetworkContext.swift:34). The TaskLocal value and thread dictionary override have no owning core identity. [RemoteLogger.swift:154](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogLogs/Sources/RemoteLogger.swift:154), [DatadogTracer.swift:150](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogTrace/Sources/DatadogTracer.swift:150), and [NetworkInstrumentationFeature.swift:435](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogInternal/Sources/NetworkInstrumentation/NetworkInstrumentationFeature.swift:435) consume that global value.

Trigger: core A establishes a UI-event handoff, then customer code logs or starts a span through named core B. B receives A's application/session/view context, including when B has no RUM feature. Named cores are supported by [Datadog.swift:222](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogCore/Sources/Datadog.swift:222). Avoiding one core per scene does not remove the SDK's obligation to isolate independently configured cores.

Evidence: executing the unchanged RUMContextHandoff and LazySpanWriteContext implementations with stubbed core scheduling produced `destination_core_context=B` and `actual_span_rum_application=A`.

Required change: index handoffs by opaque core-instance identity and lifecycle generation; preserve separate entries through nested instrumentation. Each consumer looks up only its own entry. Ignore foreign values, including a foreign authoritative nil snapshot. Checking application ID alone is insufficient when two cores use the same application. Regressions: different cores, same application/different sessions, a core without RUM, nested dispatch, and inherited work after stop/reinitialization.

**R05 — P1: A source-less navigation after stopSession replaces the wrong scene**

Location: [RUMApplicationScope.swift:332](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/RUMMonitor/Scopes/RUMApplicationScope.swift:332), with representative exclusion at line 418 and subsequent target resolution in [RUMSessionScope.swift:322](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/RUMMonitor/Scopes/RUMSessionScope.swift:322).

Trigger: A and B both have active views, B is representative, `stopSession()` ends the session, then an ordinary `startView(key: "C")` occurs outside a handoff. Restoration excludes B because the incoming target is processRepresentative. It restores only A, then resolves the still-unresolved command against the new representative A. C replaces A and B disappears. Expected: preserve A and replace B with C. A source-less stop using nonrepresentative A's identity can also discard B before stopping A.

Evidence: traced command mutation and restoration against the baseline. The existing restart test at [RUMApplicationScopeTests.swift:480](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Tests/RUMMonitor/Scopes/RUMApplicationScopeTests.swift:480) supplies an explicit scene target and misses this path; no new runtime test was run.

Required change: resolve ownership against the old session before choosing peers to restore, and carry that same resolved target through creation and dispatch. Resolve a stop's matching identity before representative fallback. Regressions: the source-less start and nonrepresentative identity-stop sequences above.

**R06 — P1: Lazy session expiration drops unaffected scene branches**

Location: [RUMApplicationScope.swift:339](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/RUMMonitor/Scopes/RUMApplicationScope.swift:339).

Trigger: a lifecycle command observes inactivity or maximum-duration expiration, ending the active session without immediately creating a new one. The next navigation command targets A while another tracked branch B should survive. Start/stop view commands set `shouldRestartLastViewAfterSessionExpiration` to false, so the lazy path restores neither branch and loses B. Immediate refresh already considers concurrent views at lines 281–287; the lazy path omits that rule.

Evidence: source-traced divergence between the immediate refresh, explicit-stop, and lazy expiration paths. The existing timeout test directly triggers expiration with a navigation command and does not cover a preceding lifecycle command.

Required change: share one restoration policy across these transition paths, using the owner resolved before mutation in R05. Regressions: expiring lifecycle command followed by start and stop in A, with B's new-session view and subsequent attribution preserved when foreground policy allows it.

**R07 — P1: Empty semantic sources disable automatic tracking before they can replace it**

Location: [SwiftUIViewModifier.swift:5272](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Views/SwiftUI/SwiftUIViewModifier.swift:5272).

`RUMNavigationTransitions()` can initially be empty. Selecting it immediately activates `suppressionState`, although no snapshot exists to establish a semantic destination. Once attached, the authority registry suppresses automatic discovery while no semantic view can start. The observed-publisher path uses nil before its first state and avoids the bug; explicit and capability-provided empty sources do not. This contradicts the pending-source rule in [NAVIGATION_API.md:568](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/MultiSceneSupport/NAVIGATION_API.md:568).

Evidence: extracted production source/host state produced `suppressed=true events=[]` for an empty source.

Required change: separate subscribing from acquiring tracking authority. Acquire suppression only when a trustworthy accepted snapshot can establish an occurrence in the attached scene. Regressions: empty explicit and capability sources with the real authority registry, before and after `setInitialDestination`; nil instrumentation must not leave an authoritative but nonfunctional host.

**R08 — P1: A rejected appearance can consume the reconnect generation**

Locations: trait-based attachment in [SwiftUIViewModifier.swift:6063](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Views/SwiftUI/SwiftUIViewModifier.swift:6063), unconditional active-occurrence assignment at line 5369, and generation deduplication at line 5344.

Trigger: disconnect A; release the semantic host's source/attachment; reevaluate the retained host while its inherited scene trait still says A. It resubscribes and treats that trait as an attachment. The handler correctly rejects the appearance because A is disconnected, but the host nevertheless marks its generation active. A real connection and reader mount then arrive; the host deduplicates the generation and does not restore the view until another navigation transition.

Evidence: a deterministic probe ran the actual host/source state with a handler stub implementing the real disconnected-scene rejection in [RUMViewsHandler.swift:361](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Views/RUMViewsHandler.swift:361). No start was delivered after reconnect. The particular SwiftUI post-disconnect rendering order has not been reproduced on a device.

Required change: fence attachment by scene connection epoch and distinguish an inherited trait hint from a live reader attachment after disconnect. Record an active occurrence only after the consumer accepts it. Regression: put stale-trait body reconciliation between disconnect and real reconnect, then verify exactly one fresh occurrence and correct immediate resource/log attribution.

**R09 — P1: Existing controller APIs now access UIKit on arbitrary caller threads**

Location: [Monitor.swift:963](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/RUMMonitor/Monitor.swift:963).

The existing nonisolated `startView(viewController:)` and `stopView(viewController:)` APIs now synchronously read `viewIfLoaded`, `window`, `windowScene`, and `session` before enqueueing. Previously, the stop path needed only controller identity. A worker-queue caller now traverses mutable UIKit state with no main-thread boundary. Apple's [UIKit documentation](https://developer.apple.com/documentation/uikit?changes=_2_2) requires main-thread use except where documented otherwise.

Evidence: reachable source path and comparison with the old implementation. No customer-app crash or Main Thread Checker run was reproduced.

Required change: inspect UIKit only when on the main thread. For other callers, use a thread-safe immutable identity-to-scene association captured earlier on main, or retain the legacy inferred fallback. Avoid synchronous dispatch to main and avoid imposing a new actor requirement on the existing public protocol. Regression: worker-queue start/stop with a getter spy proving no background UIKit hierarchy read, plus main-thread scene extraction.

**R10 — P2: Presentation tracking commits rejected Binding writes**

Location: [SwiftUIViewModifier.swift:6445](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Views/SwiftUI/SwiftUIViewModifier.swift:6445).

The presentation setter reconciles `newItem` before forwarding it to the customer's Binding. A setter that rejects dismissal or canonicalizes the proposed value leaves the SDK describing an unaccepted destination. The path adapter already forwards first and reconciles the accepted getter at lines 5589–5595.

Evidence: actual presentation-state methods with a SwiftUI.Binding rejecting nil produced `accepted=document`, `events=[start:sheet,stop]`, and `hasDismissal=true`. The application retained the sheet while tracking stopped it and recorded dismissal.

Required change: forward the transaction, then reconcile accepted state. For exact attribution of work emitted inside a custom setter, use an accepted-state callback or observation boundary instead of guessing from the proposal. Regressions: rejected and canonicalized presentation changes, emitted work, and dismissal callback delivery.

**R11 — P2: Legacy single-window manual views lose native WebView correlation**

Location: [WebViewEventReceiver.swift:106](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Integrations/WebViewEventReceiver.swift:106); filtering at [ViewCache.swift:143](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/RUMMonitor/Scopes/Utils/ViewCache.swift:143).

Trigger: an ordinary single-window app uses `startView(key:)` outside UI dispatch, keeping its native view in the legacy scene-less branch. The new message handler supplies a real scene ID for its mounted WKWebView. The receiver then requires an exact scene match and rejects the legacy native view, losing `container.view.id`. This is a compatibility regression in existing native/browser replay association, independent of the deferred full multi-scene replay design.

Evidence: the unchanged ViewCache implementation returned `legacy-manual-view` for the old lookup and nil for the new scene-specific lookup with the same single legacy view.

Required change: preserve legacy lookup for the known single-scene compatibility mode, or introduce a narrowly defined fallback when ownership is unambiguous. Never fall back indiscriminately to another scene. Regression: replay-enabled string-key native view and scene-backed WKWebView must retain their container association.

**R12 — P2: Advancing peer action timeouts also discards the source action's stop attributes**

Location: [RUMViewScope.swift:248](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/RUMMonitor/Scopes/RUMViewScope.swift:248), invoked for every branch by [RUMSessionScope.swift:373](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/RUMMonitor/Scopes/RUMSessionScope.swift:373).

Trigger: in a single-scene app, start a continuous action at t=0 and stop it at t=11 with `attributes: ["result": "ok"]`, without intervening commands or pending resources. The baseline expired the action at its existing deadline while merging stop-command attributes. The new code first expires it with a synthetic keepalive containing empty attributes; by the time its own stop arrives the action slot is gone. The timeout stays the same, but metadata is lost.

Evidence: baseline/source comparison through `RUMUserActionScope.sendActionEvent`. The existing peer-isolation test checks that B's attributes do not contaminate expired A and misses A's own stop.

Required change: resolve actual recipients first. Recipients process the original command, including its expiration semantics; only other branches receive time-only advancement. Regression: retain the peer-isolation case and add the source action's expired stop with attributes.

**Additional risks and existing behavior, kept separate from the 12 introduced findings**

- **Detach lifetime depends on one queue turn.** [SwiftUIViewModifier.swift:5940](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Views/SwiftUI/SwiftUIViewModifier.swift:5940) treats a continued detach as final and clears the semantic source. A later reader mount only restores attachment; it cannot reselect the source without a body reevaluation. An extracted state probe loses updates after detach → grace period → remount. Validate actual retained-container/presentation/hosting-controller reattachment. Prefer separate suspended and destroyed states, resynchronizing a retained source on concrete remount and tying unsubscribe to owner destruction.
- **Presentation callbacks identify an item rather than its occurrence.** [SwiftUIViewModifier.swift:5702](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Views/SwiftUI/SwiftUIViewModifier.swift:5702) matches disappearance by Presentation.id. An old sheet disappearing after a same-ID cover mounts could stop the cover. State methods allow the failure; platform ordering remains unverified. Carry an occurrence token through mount/disappear and test same-ID style replacement and A → B → A.
- **Disconnected scene history is unbounded.** [RUMViewsHandler.swift:1017](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Sources/Instrumentation/Views/RUMViewsHandler.swift:1017) keeps every unique disconnected ID; `sceneActivityByIdentifier` also never removes keys. Reconnecting the same session clears its tombstone, but permanently discarded sessions accumulate, and app backgrounding scans the history. Measure repeated create/discard cycles and reconcile retired session generations. Do not simply expire tombstones while stale callbacks can still exist.
- **Late resource completion can affect a new session's action; this predates the branch.** Old and new sessions independently process a late completion. The old session owns the resource, while fallback in the new session can feed that completion to a different active action. The new test at [RUMApplicationScopeTests.swift:647](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/Tests/RUMMonitor/Scopes/RUMApplicationScopeTests.swift:647) uses an immediately completed custom action and cannot expose false resource/error counts. Track this separately and test a continuous action plus late failed resource. Actual resource ownership should control completion routing across sessions.

Historical repair-order recommendations and the original closure checklist are preserved in the [documentation checkpoint](Experiments/DOCUMENTATION_CHECKPOINT_EXP-178.md). The disposition table above records their resolution; release obligations remain in the gate register.

The review's compiler probes used `swiftc -typecheck -` with the installed SDK and `/tmp/dd-multiscene-review-module-cache`. SwiftUI executable probes used the installed Xcode Swift interpreter in Swift 5 mode, macOS SDK 26.5, and `/tmp/multiscene-review-swift-cache`; source snippets were read from the current checkout, with dependency/handler stubs where stated. Probe scripts were supplied on stdin, not committed as tests. No new complete SDK build or device result is claimed.

Reviewed concerns that did not become findings: the preliminary queued A→B resource-start concern was rejected because existing same-scene fallback and resource ownership handle that sequence; the UIApplication sendEvent return-signature concern is pre-existing; no additional independently provable defect was found in the changed profiling identity or watchdog-clear code. These exclusions should not be interpreted as exhaustive proof of those components' production safety.

The original review changed no SDK source and created no commit. Subsequent
repairs and validation are tracked in the current-disposition table above.
~~~~

## Component repair history

Original `COMPONENT_REVIEW.md`, lines 42–149. Quoted without changes.

~~~~text
## Historical findings and repair evidence

**D03 / R02, registration lifetime — closed in EXP-168.** Mounted controls on
27/26.5 retain one registration and tracking state per cycle, reaching 25, while
readers/controllers release. Instrumentation remains alive and methods remain
swizzled after SDK stop. The repair stores a bound callback on an independent
context with weak state/handler/arbiter references; neither modifier is captured.
Cancellation removes the source entry, clears metadata/callback and advances the
epoch. Rebinding cancels the old source; hidden routes keep their registrations.
Both runtime candidates pass 37/37 with zero weak survivors and three original
method implementations restored. The 303-test selection covers exact fresh
reveals, current descriptor, stale generations/epochs, peer-local suppression,
released collaborators and interactive cancel/commit. This closes R02's bounded
review; P03 disconnected-registry retirement closes separately in EXP-172. R04's later D08 and
no-body retained-host remount evidence is recorded in EXP-170/171. No extraction or final independent review is claimed.

**D07, pending semantic authority — closed in EXP-169.** Source selection and
subscription no longer activate suppression. Four real-registry controls fail on
the unchanged SDK for empty explicit/capability input, absent handler and absent
attachment; all pass when authority waits for publication prerequisites. The119
affected tests pass. Mounted explicit/capability hosts pass29/29 versus19/29,
including automatic owners before input and an action submitted immediately at
the first accepted input. Two previous tests that assumed authority without a
handler now distinguish source pinning from actual publication. D08 still owns
rejected disconnected publication; R05 reentrant fan-out is resolved separately by EXP-174 below.

**D08, disconnected host — closed in EXP-170.**
The handler now reports accepted insertion/replacement; rejected cross-scene
replacement preserves the old owner. The host distinguishes first inherited
traits from reader mounts after teardown, and uses a new attachment generation.
Its source remains pinned within each live lifetime. Three failing controls and
314 affected tests cover early rejected reader callbacks, stale traits before/after
connection, latest input, repeated reconnects, nil prerequisites, inactive staging,
manual precedence and exact peer stop behavior. Mounted actual explicit/capability
hosts pass51/51 versus39/51; the old SDK sends immediate reconnect Resource/Log
work to Peer, while the candidate uses the fresh Home. The same retained hosting
controller is detached for200ms, then remounted after assigning a new root value;
a third unique Home occurrence and exact Resource/Log owners prove that delayed
boundary. It does not prove a retained reader callback without body reevaluation:
releaseSource clears selectedTransitions/latestSnapshot, while the reader only
reconciles attachment. That remaining R04 path is repaired and tested in EXP-171
below. EXP-168's zero-survivor/swizzle restoration evidence stays
valid. No new availability
requirement or public API was introduced; the split trait callback is within the
existing iOS27/visionOS27 host. This is not independent final review or genuine OS
ordering; H08/H09 remain open.

**R04, retained reader without body rebind — closed in EXP-171.** Two controls
reproduce loss of the latest source after final detach and scene reconnect. The
host remembers configuration weakly while detached, with no subscription or
authority. Only an accepted reader mount reobserves the latest input; a new body
with no source withdraws it. Released source/handler weak references become nil.
All318 affected tests pass, retaining D03/D08 and ordinary/keyed/arbiter coverage.
In both mounted explicit/capability variants the same controller is removed for
200ms, input changes while detached, and the captured reader callback runs with
zero source observers. It forwards SDK delivery, then submits Resource/Log work
before the framework can render. The root value is never replaced. Candidate57/57
uses a fresh Latest UUID/session; control43/57 loses it and misattributes markers.
Exact peer continuity, duplicate mount and final unsubscription checks pass.
This closes the bounded modifier/attachment review, with EXP-168 teardown and
EXP-170 trait fencing retained. H08/H09 physical ordering and final independent
release review are not inferred from it.

**D10/R06, accepted presentations — closed in EXP-173.** The actual native
Binding factory now forwards its transaction once and reads accepted state before
returning. Rejection preserves the current owner; canonicalization does not commit
the proposal. Mount/disappear closures capture an internal occurrence UUID, so
same-ID sheet→cover and A→B→A cannot revive/stop a later occurrence. Only accepted
handler publication sets started state and acquires suppression; rejected migration
preserves the old owner. Container detach and disconnect still cancel independently.
No callback is retained by the state, so boundary captures add no reverse ARC edge.
Standard container call sites, availability and metadata/default precedence remain.

The first native candidate still churned SheetAgain before old-callback injection:
SwiftUI rematerialized accepted content. The disappearance callback now reads the
current accepted Binding; unchanged accepted content keeps its occurrence, while
accepted nil balances once. A new failing unit control and the native
pre-injection stability check preserve this discriminator. All337 affected tests
pass. Native77/77 versus55/77 validates exact presentation/Home counts, peer
continuity and Resource/Log view/session IDs inside rejecting setters, immediately
after return and at actual native onDismiss. All invalid/failed attempts remain.
Opaque setter interiors still require an observed/explicit transition boundary;
no speculative proposal ownership, public API, extraction or physical ordering
claim was added. This closes the bounded R06 responsibility review.

**R05, reentrant observer fan-out — closed in EXP-174.** Three deterministic
controls reproduce `[0, 2, 1]` on nested commit, `[1, 0]` on nested initial
publication, and three callbacks after the first callback removes all observers.
Whichever observer receives the outer value first triggers the test; no dictionary
ordering assumption is involved. The single new `publish` helper snapshots IDs,
looks up live membership before each callback and stops an outer generation once
a nested commit supersedes it. The initial and ordinary publication paths share
this helper. Nested commit stays synchronous; every live observer has the newest
generation before it returns. Added observers receive current state once through
observe, and removals cancel pending delivery.

The observed adapter updates identity and rearms Observation before delivering;
actual multi-observer publisher and Observation tests preserve the latest value.
Source pinning, weak host captures, source unsubscribe and background FIFO remain
covered. Two actual host states emit distinct scene-local Latest occurrences,
keep their independent peer untouched and stop exactly those occurrences; removal
during nested delivery cannot revive a detached host. All346 affected tests and
strict source/test lint pass at signed `368c62a72`. This closes the bounded R05
review without deferring callbacks, adding API or changing event dispatch.
[Durable result](Results/EXP-174-observer-delivery.json) retains three failed
controls, all selectors and source identities. No physical/backend/final review
claim follows from this synchronous in-memory contract.
~~~~

## Retired release progress narratives

Original `ASSESSMENT.md`, lines 9–182. Quoted without changes.

~~~~text
## Release evidence boundaries

S1 extracts independently proven existing-customer reliability fixes. S2 targets
single-scene SDK27 Duo readiness by October 16, 2026. S3 retains full multi-scene
APIs, ownership/lifecycle and hardware acceptance. The reference results below
remain valid within their original source/environment limits; they do not certify
a newly extracted candidate. F07 must prove deferred behavior absent from each
S1/S2 shipped artifact, then F03/F06 qualify that exact candidate.

The [S1 delivery queue](S1_DELIVERY_PLAN.md) now separates seven PR units:
H00, E01–E05 and DL01. E01's 15/16 score describes its own qualification, not
completion of S1. Signed [H00/E01 local packets](Results/S1-H00-E01-packets.json)
preserve qualified production/test/build inputs; E01 now also has reachable feature-doc metadata. Seven drafts are now [published and verified](Results/S1-publication.json) with signed histories and the user-confirmed ticket waiver. Current required CI and human review remain; E03 now has a qualified current-develop reconciliation in [EXP-219](Results/EXP-219-upstream-resource-integration.json): RUM920/956, metrics9/9, native9/9 and strict ownership/lint/API/docs/review checks pass at signed1b2bff3e. Only H00 → E01 is an established
merge dependency. [EXP-214](Results/EXP-214-resource-action-design.json) records E03's signed repair and qualified owner contract before more S2 expansion.
[DL01/E02/E04/E05 local packets](Results/S1-independent-packets.json) preserve independent, source-matched qualification. Their completed hostless, Integration and platform checks retain exact counts and original skips/QoS warnings. E05 adds two qualified registered ownership cases and the reviewed request-session Core expectation. Automatic backend acceptance and the separately reviewed composed registered evidence pass. Each mode retains three native requests/client spans with exact nil/A/B ownership, reverse completion, complete service/session inventories and successful cleanup. The original registered run remains FAIL for a stale reducer snapshot; the session-only continuation remains FAIL under its original opaque-ID oracle. Offline stable-identity correction closes the backend qualification without a new native run or query. The [E05 admission record](Results/S1-E05-release-admission.json) owns the exact artifacts and independent review. H00 now passes its two standalone hitch cases with zero skips/runtime warnings and strict repository lint with zero violations; no accepted SDK check is due for repetition.

Replay captured-content correctness is outside the release scope. Host-app crash safety and non-disruption to other SDK features remain required; no full Replay suite, content repair or inherited-fixture waiver is needed. The [scope disposition](Results/S1-replay-scope-disposition.json) removes the content-fixture blocker without adding a test pass. Signed [feature-document corrections](Results/S1-documentation-checkpoint.json) qualify E03/DL01/E02/E04 docs without SDK changes. Current CI, human review and separately authorized merges remain; publication adds no release-gate or broader P03 closure.

S2 selects E01 + DL01 + E04, production `c9faed81` on develop `62f64d7b`,
documented in signed `7604da24` after test-only `1aa71d7f`. The independent
[composition review](Results/EXP-216-s2-composition-promotion.json) proves the
six-file boundary and closes object-lifetime safety for the exact candidate.
Ordinary compatibility and reentrancy retain narrow source-matched evidence;
new semantic SwiftUI and multi-scene code remain absent, making the scoped
application-performance comparison non-applicable without a numerical claim.
[Composed documentation](Results/S2-F02-composition-documentation.json) and
[composed compatibility](Results/EXP-217-s2-compatibility.json) now qualify F02/F03
for this exact source. The finite matrix includes 3,152 selected cases / 3,224 executions,
five public clients, twelve new platform builds, strict lint and unchanged
Swift/Objective-C APIs, with source-matched macOS/documentation reuse. Five OS skips,
eight Integration QoS warnings and the original pre-assertion stops remain recorded.
All ten Replay-only cases were excluded before assertions. No SDK/test change or
numerical performance claim follows.
Current-candidate Duo, native-input, app and final release gates remain open.
Historical EXP-195 source differs and cannot certify this candidate.

The [current-source comparison](Results/EXP-210-s2-automatic-coverage.json) is
checkpointed with unresolved native-input variability. The original SDK-on UIKit
switch fails through XCTest and direct Device Hub input; both the SDK-disabled
control and a later SDK/action-enabled control pass the unchanged native journey.
These mixed outcomes do not isolate an SDK, fixture or input cause. Independent
review stops further equivalent attempts; no candidate launches or gate credit.
Preserve all raw outcomes and use a concrete new discriminator before expansion.

[EXP-218](Results/EXP-218-native-input-observation.json) adds one valid SDK-on
input observation, not a completed comparison. Its native test passes, but the
unchanged diagnostic oracle rejects the switch's missing ended-touch ancestry and
state change after `sendEvent` returns. The original callback and value transition
occur before the frozen boundary. SDK-off remains unrun; all input variability,
command failure and observer limits remain recorded. No SDK cause, coverage pass
or gate closure follows. A different callback-side witness requires fresh admission.

The [Resource PR review](Results/S1-resource-completion-review.json) keeps the qualified SDK implementation after comparing smaller ownership designs. Handler-only or view-local filtering loses retained-session ownership or unknown-manual compatibility. Three test files now use behavior-based names and readable fixture steps; exact renamed-token comparison preserves all 388 XCT call sites and timing, with strict lint and syntax checks passing. Signed cleanup046719c3 is published in PR3218; new-head CI and maintainer review remain. No native rerun, SDK change or release-gate closure follows.

The [hitch review follow-up](Results/S1-hitch-review.json) qualifies and publishes signed0deff4750: three selected tests pass on iOS17.5, with zero skips/runtime warnings, full41-source compilation and guarded cleanup. Full documents replace reconstruction state; disabled tracking omits hitch data in every document. SDK production is unchanged. [Current CI investigations](Results/S1-ci-followup.json) remain separate and confer no release-gate closure. The [E01 forwarding test repair](Results/S1-resume-witness-review.json) is qualified and published at signed 0eaba3e3: 20 macOS passes in one process and full watchOS test compilation. Current-head CI remains. Original harness stops and 59 inherited test-dependency diagnostics are retained; no SDK change or warning-free claim follows. User scope now limits further CI repairs to failures clearly linked to our changed surface or associated tests. The upload-fixture and retained-core failures have no established link and remain preserved without further repair. PR3196 owns the timeseries correction; the completed local20/20 checks and negative control do not qualify its different source or authorize duplicate publication. Regular S2 plan work resumes. [EXP220](Results/EXP-220-native-input-callback.json) is paused for the requested laptop restart after callback source/oracle review and4positive/25negative controls. No SDK archive, build, simulator or native run exists; host-runner preparation and separate execution admission remain.

The [controlled app builds](Results/S2-F08-app-preparation.json) remain source-bound and reusable. The first logged-out journey stopped before assertions; its original cleanup failure remains alongside later absence proof. A separately admitted [environment-only Duo check](Results/S2-Duo-environment-readiness.json) again ends in terminal `Data Migration Failed`, before any app installation, launch or AXe probe. Source guards and complete cleanup pass. The cause remains unresolved; no SDK defect, app acceptance or equivalent retry follows. [Finite app journeys](Results/S2-F08-app-journeys.json) remain open, and TestFlight requires separate authorization.

The selected candidate's lifetime evidence covers task success/failure/cancellation,
core/display-link teardown, bounded value-cache expiry and native UIKit/SwiftUI
host/content release while Resources remain pending. Terminal completion releases
the old Resource/view with its original event owner and live restoration peer
preserved. [The source-bound disposition](Results/EXP-216-s2-composition-promotion.json)
combines the accepted component and [native host evidence](Results/EXP-215-native-view-lifetime.json).
Original synchronous fixture failures and configuration-delivery ownership remain
recorded; these results imply neither a blanket leak guarantee nor a performance pass.

Physical Duo hardware is unavailable until after release. S2 may use qualified
simulator and relevant physical iPhone/iPad evidence, disclosing that uncertainty;
F09 provides later targeted confirmation, while full F04 remains S3. Unchanged
automatic SwiftUI naming/control limitations are outside new S2 scope. Exact API
review F01 remains attributable and pending for S3; assessment assumptions are not
approval. [Stage views](PLAN.md) own readiness.

The ordinary iOS15 scene/target-call amendment is now mapped to existing S3
F01/C06/F03/A02 obligations in the [availability plan](Results/S3-api-availability-plan.json).
It adds no gate or pass. Approval, implementation, unguarded Swift/Objective-C
client builds,17.5 fallback and27 exact same-key ownership remain required. The
semantic host stays iOS27 with its compiler6.4 Observation guard; optional older
exact routing must be qualified before it is enabled.

The isolated E01 candidate1bdc9286 fixes repeated URLSession request mutation and
strong terminal-preparation retention. Its deterministic and native automatic/
registered controls preserve header, body, metrics and cleanup semantics. Debug
and optimized reentrancy checks pass. Concurrent duplicate resumes may forward
later on the preparation thread; arbitrary original-thread timing is not promised.
[Repair/ownership evidence](Results/EXP-199-terminal-task-ownership.json) and
[optimized controls](Results/EXP-203-optimized-reentrancy.json) define that scope.

Ordinary/legacy17.5 and26.5 compatibility and custom/NOP17.5/26.5/27.0 comparisons
pass on the candidate. Platform builds, compiled public clients, unchanged API
surface, feature documentation and full integration coverage qualify S1:F02/F03.
[Compatibility](Results/EXP-200-compatibility.json) and
[final matrix](Results/EXP-201-final-compatibility.json) retain exact inventories,
the corrected inherited hitch assertion and diagnostic limits.

E01 has15 of16 required gates qualified. Its signed delivery candidate also passes
the five previously missing hostless suites: 544 tests and one predefined
watchOS-only skip. [The packet](Results/S1-H00-E01-packets.json) preserves the
zero-test SPM-artifact failure and checksum-verified correction. Replay capture-suite qualification is excluded by the approved scope. The focused object-lifetime audit closes
S1:P03: native success/error/cancellation and feature teardown release their weak
witnesses in automatic and registered modes; the8-test follow-up passes with no
runtime warnings. Backend A01/T03/T08 now close after the independent four-cell
audit. F06 retains separate upstream hitch delivery and verified-source rebase,
with signed outgoing history required before any authorized push. The user removed detailed network performance and any
replacement standalone network campaign from release prerequisites. The
[optional benchmark](NETWORK_BENCHMARK_FOLLOWUP.md) preserves22 valid cells, its
prelaunch host failure and unfinished continuation without a numeric verdict.
Required performance work for S2/S3 concerns application-visible frame rate,
hitches/hangs, CPU and memory impact of included semantic SwiftUI/multi-scene
changes; source exclusion can qualify non-applicability. Correctness and ownership
requirements remain unchanged.
[Backend acceptance](Results/EXP-202-backend-qualification.json) qualifies both
candidate modes and preserves the predefined baseline terminal-view observations.
Each of the four cells has12 RUM rows,10 spans in each independent session/service
query, exact ownership/value checks,64 native receipts and complete cleanup. The
registered oracle rounding defect was corrected with exact ±1ns controls before
fresh execution; accepted automatic artifacts retain their original identities.
All collection bounds and earlier failed outcomes remain unchanged. Exact synthetic
evidence and helpers are preserved outside temporary storage with byte hashes.
This closes the E01 backend gates, not broader multi-scene or performance acceptance.

Test-only duplicate classes are excluded from inspected shipping graphs. The
[QoS comparison](Results/EXP-204-network-qos.json) now finalizes both unchanged
arms: one test each passes and reproduces the same warning and15 shown frames.
The displayed TSan/CFNetwork/libdispatch/pthread stack has no SDK frame and remains
incomplete. This establishes recurrence without E01, not harmlessness, root cause
or sanitizer/performance clearance. The original600second timeout is retained.
Controlled Datadog app evaluation is authorized; configuration preparation and
query access alone do not establish a run.

The independent E02 candidate prevents a retained old view from absorbing a later
same-key occurrence's start or stop attributes. The narrow repair preserves
Resource/action owners and one active restored occurrence. [EXP-205](Results/EXP-205-view-occurrence-isolation.json)
qualifies eligibility with failing current-develop controls, the complete affected
RUM suite and paired public-monitor full/delta writer-JSON tests. Its own release
qualification remains open; these results neither certify backend delivery nor
change E01's selected-candidate gates.

The separate E03 investigation reproduces an existing-customer action attribution
defect on current develop: late Resource success/error changes a newer view or
session's live action counters and error_tap, despite correct Resource/error parent
IDs. [EXP-206](Results/EXP-206-resource-action-ownership.json) has four exact
baseline failures and five preservation passes. Its earlier stateless repair was rejected under the retired automatic dual-terminal
premise. EXP214 now qualifies signed repair562cf74dd through full RUM925/961 and nine native XCTest passes with exact owner/count evidence. The inherited stopped-session precondition diagnostic remains explicitly classified, and source review confirms metrics preserve fixed action expiry and counters. All twelve affected-platform Debug/Release builds now pass on the signed candidate with complete source/module/product identities and cleanup. Eleven iOS schemes were exercised under the prior broader scope. Ten non-Replay scheme dispositions qualify; the inherited Replay content failure and unresolved paired raw topology remain recorded without a PASS. No capture repair, further topology test or waiver is required. Integration287/287 retains nine QoS warnings matching prior evidence. All five feature docs now pass; current CI, ticketing and human review remain.

The independent E04 candidate preserves delayed WebView correlation after a long
native visit. It retains A for the full inactivity window after navigation to B,
then expires A while retaining active B. [EXP-207](Results/EXP-207-active-view-cache.json)
qualifies the two-file repair using exact develop failures, 910 RUM cases / 946
executions and an identical three-test native bridge comparison. Session lifetime,
restoration, capacity and Replay controls pass. This is injected-message writer-JSON
evidence; backend, real browser timing, physical Duo and numerical performance are
not qualified. Lookup now takes a write lock for expiry. E04's release qualification
remains separate from the selected E01 candidate. The [changed-path lifetime disposition](Results/S1-E04-lifetime-disposition.json) reuses exact EXP207 cache/session teardown and restoration controls; E04 adds no host or pending Resource retention edge. Ordinary host lifetime remains a separate S2:P03 obligation.

E05 now preserves ordinary automatic Trace request ownership through delayed or
reverse completion. [EXP-208](Results/EXP-208-trace-ownership.json) qualifies the
three-file candidate with eight exact unit failures on develop,154/154 full Trace
tests and a matched native pair: two baseline ownership failures versus3/3 passing
controls. A request started without RUM retains absent ownership after later RUM
activation. Sampling, parent propagation, caller headers and non-RUM context controls
pass. Completion consumes value-only captures before guards; this bounds lifetime
relative to existing interceptions, without immediate-unbind or measured-footprint
claims. Two registered-mode cases also pass within full Integration282/282 and independently verified callback receipts; the [delivery admission](Results/S1-E05-release-admission.json) owns that result. Automatic and composed registered backend ownership now qualify under the reviewed stable-identity oracle; original failures remain preserved. Current CI, human release review and numerical performance are separate.

The first E05 candidate exposed a baggage-only write falsely claiming an SDK
TraceContext; its one-condition correction preserves emitted headers and passes the
unchanged existing assertion. Failed attempts remain recorded. Both native arms
retain the networking QoS warning, with no harmlessness or sanitizer clearance.
The [PR2683 review](Results/PR-2683-header-ownership-review.json) remains a source
review of the unmerged proposal. Its merge/fallback policy was not adopted; T08's
bounded partial/mixed-carrier follow-up remains separate.
~~~~

## Retired environment and physical chronology

Original `ASSESSMENT.md`, lines 297–344. Quoted without changes.

~~~~text
The Duo27.1 simulator assessment is complete within its finite boundaries.
[EXP-192](DUO_SIMULATOR_ASSESSMENT.md) records actual display/trait and OS lifecycle
observations, plus concrete limits for concurrent visibility, disconnect and
interactive gestures. The unchanged H01 native22/22 remains inconclusive without
overlap; two pairing and two outer gesture attempts do not qualify those inputs.

[EXP-193](Results/EXP-193-adaptive-split.json) now accepts both adaptive slices:
resize5 phases/16 exact work/3 backend views and pose10 phases/42 exact work/7
backend views, zero errors and each guarded XCTest1/1. Exact semantic ownership
survives measured geometry and actual open/close; accepted selections and returns
produce distinct occurrences. Source/installed identities and full cleanup pass.
This is strong SDK ownership evidence for the observed simulator callbacks, not
physical hinge or scheduling parity. Original fixture, input, hit-target and
projection failures remain attributable. Physical/human obligations stay open.

C06's corrected17.x qualification checks all five stable versions in Apple's
historical catalog through27.1; all downloads are unavailable, as is17.0 through
26.6. The user subsequently supplied17.5(21F79), now verified installed/available with
a booted iPad simulator. No candidate matrix cell is claimed yet. The S1/S2 runtime
exception has not been used; actual tests and deployment15/availability checks
remain required.

EXP-196 closes physical F05 Replay coexistence, H05 settled semantic/automatic
coexistence and H07 shared-request captured ownership with complete native/backend
inventories and installed-code/cleanup proof. H05 retains the approved early
source-less representative fallback. H07 start precision is limited to the observed
MCP millisecond projection; exact native timing and raw backend duration remain.
No simultaneous-visibility conclusion follows from these serial cases.

H01 closes with actual tiled A/B windows visible through the original same-key
critical interval, native22/22 and all61 backend events matching11 views/46 work
IDs. Continuous physical XCTest video and90 reviewed boundary frames bind the
precritical receipt to unchanged native scene identities. H11's corrected visible-edge
finish touch still produces no native interactive callback; its13-event partial
join is exact, but neither finish nor cancel is qualified. Stop equivalent retries.
H04's independent process-lifetime witness also receives no disconnect; the latest
29-event partial inventory matches. Stop equivalent close retries; the view-local
observer alone does not explain the missing notification and no SDK defect is established. H14 now closes with measured regular–compact–regular physical resizing, unchanged
accepted selection/path/owner and a complete22-event backend match. The [owning result](Results/EXP-196-physical-ipad-suite.json)
preserves every rejection and scope limit. The SDK candidate is unchanged.

The physical EXP-196 suite is checkpointed after H01 acceptance. Full Screen Apps
is restored, both task apps/processes are absent, and the owned keep-awake process
is stopped. Remaining scene combinations move to S3; no deferred case is accepted.
The Datadog app uses manual SwiftUI views, allowlisted automatic UIKit and native/
WebView tracking in one scene. Existing XCTest paths skip RUM bootstrap, so F08
requires normal-mode app journeys alongside separate automatic fixtures; see
[the source audit](Results/Datadog-app-source-audit.json).
~~~~

## Retired restart chronology

Original `.continue-here.md`, lines 8–159. Quoted without changes.

~~~~text
## Current priority and next action

Verify branch valpertui/multiple-windows-scenes, actual HEAD/signature and status.
Production reference04201edc7 is unchanged. The Resource PR3218 follow-up is
complete at signed046719c3: descriptive test names,388XCT call sites/timings
preserved, no safe smaller production design found. Accepted EXP219 remains.
The [hitch follow-up](DatadogRUM/MultiSceneSupport/Results/S1-hitch-review.json)
is now qualified and published at signed0deff4750 in PR3214: three cases/three
passes,zero skips/runtime warnings,41-source compilation and cleanup. One test
file changed; original preparation/transport stops remain. The owned simulator
is deleted. Do not rerun accepted checks. No native/build lane is active.

PAUSED at the user's request before a laptop restart. The sole native/build lane is idle and the existing reviewer is complete. Task-owned caffeinate PID22041 was stopped; do not restart it without a new request.

Next work is the reviewed [S2 callback-side input witness](DatadogRUM/MultiSceneSupport/Results/S2-native-input-callback-plan.json). [EXP220](DatadogRUM/MultiSceneSupport/Results/EXP-220-native-input-callback.json) is paused in source preparation at exp220-callback-input-d092fui4: three fixture files, one UI test, oracle/controls and a preparation helper exist. UIKitApp/control behavior is unchanged. Source/oracle review and4positive/25negative controls pass; no host runner, SDK archive, build, simulator or native launch exists. Verify preparation-checkpoint.json hashes before continuing. Preserve EXP218's rejected contract and skipped arm.

The original EXP220 preparation deadline21:20:35UTC is closed by this pause. Do not extend or silently reopen it. After fresh environment discovery, finish the host runner and its guard controls, then define a separate bounded execution admission and obtain the existing reviewer's source/runner approval before build/native work. Bind exactly one super call in sendAction/sendEvent, unchanged UIAction/button path, exact source/compiler/binary/runtime identities and complete cleanup. Use the regular iPhone27.0 diagnostic only; no Duo retry is admitted.

User scope2026-09-21: do not spend time fixing flaky CI unless clear evidence implicates our changed surface or associated tests. The [finite S1 CI record](DatadogRUM/MultiSceneSupport/Results/S1-ci-followup.json) preserves every failure. E03's upload fixture and H00's retained-core failure match inspected develop and have no established changed-surface cause; further investigation/repair is out of scope. Required CI and maintainer acceptance remain unwaived.

The timeseries pause correction is already owned by [PR3196](https://github.com/DataDog/dd-sdk-ios/pull/3196), observed open at5d5058e9. Do not commit/publish the duplicate local candidate in s1-timeseries-pause-olnmq8w2. Its completed20/20 positive executions and deliberate1-failure control remain local evidence, with full80-source membership,59 inherited diagnostics and successful cleanup. The upstream source is not byte-identical and was not tested. Preserve the original exit64 invocation stop and reviewed correction.

E01's test-only forwarding repair is published at signed0eaba3e3 in PR3215. Its [witness](DatadogRUM/MultiSceneSupport/Results/S1-resume-witness-review.json) passes20 macOS executions in one process and full watchOS test-target compilation for arm64/x86_64. No local watchOS runtime is installed; new-head CI remains decisive. Preserve source-membership/process-sampler stops and their static reconciliations; no rerun. DL01/E04 checks passed at the last observation; E05 smoke jobs and aggregate reconciliation remained pending. All seven PRs were ready by external action; preserve that state.

Seven PRs are published. Only H00 → E01 is an established merge dependency; no merge, retarget, new PR or TestFlight is authorized. Outgoing histories must be signed. Command-scoped exact HTTPS mapping avoids the inherited SSH URL rewrite.

The [fresh environment-only Duo check](DatadogRUM/MultiSceneSupport/Results/S2-Duo-environment-readiness.json)
at s2-duo-readiness-_kd586qn stopped at terminal Data Migration Failed despite
exit 0; zero app installs/launches and zero AXe probes. Source and full cleanup guards
pass by 18:21:42 UTC. Logs do not establish the cause; host unified-log access is
denied. Do not repeat this cell or the original J01 journey. Another boot requires
a materially changed environment and separate admission. Reuse accepted app builds
in s2-app-build-execution-xcie51kb. Callback witness design/source work can proceed
independently, but native Duo acceptance is unqualified. Preserve all eight dirty API documents.

User scope2026-09-21: stop testing or repairing Session Replay captured content.
Only host-app crash safety and non-disruption to other SDK features remain relevant.
No full Replay suite, scroll-pocket/topology diagnostic, content-fixture correction
or waiver is a release prerequisite. Original failures remain historical evidence,
not PASS. Read [scope disposition](DatadogRUM/MultiSceneSupport/Results/S1-replay-scope-disposition.json).

1. S1 local preparation is complete within the packet scopes. Read the
   [E05 admission](DatadogRUM/MultiSceneSupport/Results/S1-E05-release-admission.json)
   and [H00/E01 packets](DatadogRUM/MultiSceneSupport/Results/S1-H00-E01-packets.json).
   E05 exact productionf270c375 remains unchanged at delivery399b01ea. Registered
   Integration282/282, hostless2701cases/2773runs (2768pass/five predefined skips),
   twelve platform builds/144 source lists, automatic backend and independently
   reviewed composed registered backend evidence pass. Original registered stale-
   reducer FAIL and session-only opaque-ID FAIL remain unchanged. Offline stable-
   identity review resultc6bd2f03/review783b30c6 retains all native/source/owner/count/
   completeness predicates; it adds no native launch, backend query or SDK edit.

   H00 standalone qualification is PASS: two unchanged hitch cases, zero skips/
   runtime warnings, full41-source compilation and cleanup; strict lint734 source/
   709 test files has zero violations. Summary2184b287 owns the follow-up; preserve
   original zero-test discovery rejection and reviewed selector corrections.
   Do not rerun accepted S1 checks. Current CI/human review and final delivery
   review remain; all16 outgoing commits were verified signed before publication. No native/build lane is active. [EXP-215](DatadogRUM/MultiSceneSupport/Results/EXP-215-native-view-lifetime.json)
   now passes three SDK-on native cases/six cycles; test-only1aa71d7f follows a
   recorded signing timeout. [EXP-216](DatadogRUM/MultiSceneSupport/Results/EXP-216-s2-composition-promotion.json)
   selects exact productionc9faed81 E01+DL01+E04 and closes source-bound P03.
   No native/build lane is active. [S2:F02 documentation](DatadogRUM/MultiSceneSupport/Results/S2-F02-composition-documentation.json)
   now closes at signed7604da24: six docs only, five feature checks and registry
   pass; all source/test/build inputs unchanged. [EXP-217](DatadogRUM/MultiSceneSupport/Results/EXP-217-s2-compatibility.json)
   closes S2:F03 at unchanged 7604da24 after independent review: 3,152 selected
   cases / 3,224 executions, with 3,219 successes and five predefined OS skips;
   five public clients, twelve platform builds, strict lint and unchanged
   nine-module Swift/Objective-C APIs. Ten Replay-only cases were excluded before
   assertions. Eight Integration QoS warnings and all pre-assertion stops remain.
   Six source-identical macOS products / twelve cells and F02 were reused. All
   guard/cleanup checks passed before the original 12:17:52 UTC deadline.
   No native/build lane is active. The initial local documentation commit used the
   authorized fallback after a 25-second signing timeout; the requested retry
   succeeded at signed 3d6d2e699 with an identical tree.
   Do not repeat these accepted checks. Local S1 descriptions are now shortened.
   A side-task relay was originally rejected by automatic approval review. The
   user has now confirmed publication directly in this task; that confirmation
   supersedes the pending question and permits the seven drafts without tickets.
   [Local packet preparation](DatadogRUM/MultiSceneSupport/Results/S1-local-preparation.json)
   now verifies all seven signed histories and reconciled exact path inventories.
   E05 uses signed 44478840 in a separate checkout; its qualified original remains
   unchanged. [EXP-218](DatadogRUM/MultiSceneSupport/Results/EXP-218-native-input-observation.json)
   is now checkpointed: one native SDK-on test passes, but the frozen dispatch
   oracle rejects missing ended-touch ancestry and callback after sendEvent return.
   SDK-off remains unrun; no SDK cause, comparison or gate credit. A zero-test
   command rejection and its reviewed host-only correction remain preserved.
   Both task simulators/apps are removed and all source/protected guards pass.
   Do not loosen the oracle, run the skipped arm or repeat the pair. No native lane
   is active. [S2 app preparation](DatadogRUM/MultiSceneSupport/Results/S2-F08-app-preparation.json)
   retains all original stopped attempts and now records the successful pair of
   separately admitted builds. Read its current_status/build_execution and the
   finite journey plan; no runtime or gate credit follows from compilation.
   Preserve all eight dirty
   API-proposal documents. [Their plan alignment](DatadogRUM/MultiSceneSupport/Results/S3-api-availability-plan.json)
   now defines unguarded deployment15 clients,17.5 fallback and27 same-key proof.
   F01 stays REVIEW BLOCKED; no API implementation or S1/S2 expansion follows.
   Seven PRs are published; no merge or TestFlight is authorized.


2. Signed documentation updates now qualify all five feature docs and registry
   for E03f43d812d, DL0129c28a01, E024dec888b and E04171a2409.
   Read [documentation checkpoint](DatadogRUM/MultiSceneSupport/Results/S1-documentation-checkpoint.json).
   Trace timing prose and two invalid privacy-enum examples were corrected;
   SDK/test/build bytes are unchanged. Source-matched accepted runtime evidence
   stands. Recheck metadata after final ticketed history rewrites.

3. [E03 packet](DatadogRUM/MultiSceneSupport/Results/S1-E03-packet.json) owns signed
   repair562cf74dd, RUM925/961, nine native owner cases, twelve platform builds and
   ten qualified non-Replay iOS scheme dispositions, including Integration287/287.
   Retain the narrow stopped-session diagnostic and nine inherited QoS warnings.
   Metrics preserve actionStartTime expiry and counters; no extra repair/run is due.
   Its original two-file develop reproducer, nine bodies and100ms limits stay intact.
   Original Replay FAIL and paired raw topology remain unresolved but out of scope.
   No new full-Replay or normalized-pass claim follows.

4. [H00/E01 packets](DatadogRUM/MultiSceneSupport/Results/S1-H00-E01-packets.json)
   retain signed H008d7e429b/E01ab71c3a6. E01's15/16 gates describe E01 only;
   EXP202's four backend cells, ordinary/legacy/custom/NOP, lifetime/reentrancy,
   affected suites, platform/client/API and five additional hostless suites are
   accepted. Preserve the exact-checksum SPM artifact recovery and original failure.
   [Independent packets](DatadogRUM/MultiSceneSupport/Results/S1-independent-packets.json)
   own DL01/E02/E04's complete hostless, Integration and platform checks, all
   original skips/warnings and source-matched lifetime dispositions. No extra E04
   host/Resource lifetime slice is required. No accepted tests rerun merely to resume.

The seven draft publications omit tickets with direct user confirmation. Current
CI, human review and separately authorized merges remain. Do not invent tickets.
H00 must actually merge before E01 retarget/rebase; verify upstream content then.
[The delivery plan](DatadogRUM/MultiSceneSupport/S1_DELIVERY_PLAN.md) and
[queue](DatadogRUM/MultiSceneSupport/Results/S1-delivery-queue.json) own the packets.

## Selected S2 and other boundaries

The selected source is now E01+DL01+E04 productionc9faed81, documentation head7604da24
in the isolated s2-rum-lifetime checkout (test-only parent1aa71d7f). EXP216 preserves the former E01-only
freeze as history. P03 and F07 qualify this exact composition; C01–C06/P01/P04/A01
retain narrow accepted invariants. F02 documentation and F03 combined-source
compatibility now close on signed7604. Their finite owners/tests/environments are in the register.
No unrelated Duo, app, backend or S3 gate closes. Original failures remain preserved.

EXP210 native-input variability remains unresolved. EXP218 identifies a passive
observer boundary limitation. The reviewed [callback-side design](DatadogRUM/MultiSceneSupport/Results/S2-native-input-callback-plan.json) uses sendAction only
for the selector-based switch; it still needs a new definition and source/oracle
admission after the app build lane is free.
An equivalent retry or the skipped SDK-off arm is forbidden. Physical Duo is unavailable; S3 API/hardware remain later.

Optional EXP198 network benchmarks stay deferred. Required performance concerns
application-visible frame rate, hitches/hangs, CPU and memory from included new
semantic SwiftUI/multi-scene code, or source-proven exclusion; no replacement
network/per-dispatch campaign. FBC is Flutter-only. Controlled Datadog-app runs may
use the probe app ID and a separate service; no live customer-session claim.
~~~~

## Historical observations from the former runbook

The current procedures retain reusable discriminators. These exact observations
retain provenance, original counts/limits and stopped attempts. Commands and
permissions quoted here are historical, not instructions for another run.

## Runbook observation 01

Original `TOOLING_RUNBOOK.md`, lines 101–105. Quoted without changes.

~~~~text
EXP-202 owns the ordinary E01 Resource/Trace fixture and strict oracle. Freeze
all helper/oracle hashes as well as the complete source-member dictionary and
source archive; check the exact archived file set before and after execution.
An observed helper hash alone is insufficient: require the approved manifest
fingerprint before native actions and every backend projection/assembly.
~~~~

## Runbook observation 02

Original `TOOLING_RUNBOOK.md`, lines 259–259. Quoted without changes.

~~~~text
[Platform-build evidence](Experiments/EXP-143-199.md#exp-162--restore-watchos-resource-and-macos-webview-compilation) records the isolated full-target procedure. Exclude protected project/configuration; the repository SPM helper temporarily renames the workspace, so use an isolated package where that would violate workspace safety. Compile proof does not replace runtime proof.
~~~~

## Runbook observation 03

Original `TOOLING_RUNBOOK.md`, lines 300–305. Quoted without changes.

~~~~text
EXP-207 adds reusable fixture checks. Verify mock factories and access levels against
actual declarations; use the repository test lint configuration. Complete asynchronous
feature-context reads before asserting readiness or advancing a fake clock. The core
interceptor returns cumulative event inventories: separate incidental launch records
from the exact workload, assert each phase's count, and use raw JSON matching for
intentionally sparse browser payloads. Do not decode them as complete native models.
~~~~

## Runbook observation 04

Original `TOOLING_RUNBOOK.md`, lines 755–765. Quoted without changes.

~~~~text
For an exact semantic-engine or adapter-author probe, create its stable transition
source with the initial committed destination before the host evaluates. This is
the low-level EXP-146 harness recipe, not the recommended normal-customer
integration. Do not wait for a descendant
`.task`, probe scene reader, or diagnostic native-scene attribute before calling
`setInitialDestination`: `EXP-146` attempt A showed that this makes root
`onAppear` and immediate-task work precede the semantic view. The host resolves
the actual scene from the SDK's inherited scene trait; customer destination
metadata does not need an internal RUM UUID or native scene identifier. Add root
`onAppear` and immediate-task action/Resource ownership to the oracle so a normal
navigation-only timeline cannot conceal this ordering regression.
~~~~

## Runbook observation 05

Original `TOOLING_RUNBOOK.md`, lines 852–862. Quoted without changes.

~~~~text
`EXP-152` records the deterministic native-callback recipe. Use a separate
scenario so the accepted synchronous oracle is not rewritten. Wait for an
`onAppear` signal from the actual Sheet or cover content before programmatic
dismissal; accepted router state alone does not prove that SwiftUI mounted the
presentation, and dismissing earlier can make a missing `onDismiss` a harness
race. At callback entry, record the accepted presentation, current destination,
and mutation generation, then emit uniquely named immediate and settled
action/Resource pairs. Require exactly one appearance and callback per style,
fresh revealed-view ownership, and no extra underlying occurrence caused by the
callback. Direct presentation replacement may omit outgoing `onDismiss`
(`EXP-144`), so never use callback count as the adapter's commit signal.
~~~~

## Runbook observation 06

Original `TOOLING_RUNBOOK.md`, lines 949–954. Quoted without changes.

~~~~text
`open-window` is an acknowledged harness step: it waits for and consumes the
target scene's `scene-ready` signal before completing. Do not immediately follow
it with `wait-for-scene-ready` for the same target unless the scenario explicitly
expects a second lifecycle readiness event. `EXP-154` attempt 1 proved that the
duplicate wait starts after the first signal's acknowledgement and deterministically
times out; this is a harness failure, not evidence about the SDK or simulator.
~~~~

## Runbook observation 07

Original `TOOLING_RUNBOOK.md`, lines 993–998. Quoted without changes.

~~~~text
A clean uninstall and missing container can still leave simulator window-server
identity outside the app container. If a scenario requiring initial logical scene
A instead restores only B, the attempt is `INVALID`: do not reinterpret B as A or
attribute the missing readiness signal to the SDK. Use a fresh simulator target
or an explicit, proven window cleanup and a new run ID. EXP-155 attempt 1 records
this boundary.
~~~~

## Runbook observation 08

Original `TOOLING_RUNBOOK.md`, lines 1075–1083. Quoted without changes.

~~~~text
CoreDevice error 4000 (`device disconnected immediately after connecting`),
`Network.NWError 60` (`Operation timed out`), or a paired-but-disconnected state
fails this preflight. Stop before mutation, record an infrastructure-
inconclusive attempt, and preserve the named SDK scenario unchanged. The first
two `EXP-156` preflights record this boundary: one reached lock state before
app/process inventory failed, and the next found only a disconnected paired
record. Neither produced a clean boundary, install, launch, run ID, RUM session,
or SDK verdict. The later wired retry closed this connection gate before exposing
the separate signing prerequisite below.
~~~~

## Runbook observation 09

Original `TOOLING_RUNBOOK.md`, lines 1211–1218. Quoted without changes.

~~~~text
`waitForSignal` proves that a matching signal exists after the driver's current
observation cursor; it does not by itself prove that a new semantic occurrence
started after an earlier navigation boundary. A previously emitted occurrence
can satisfy a later wait when the cursor predates it. For returned destinations,
pair the wait with the ordered semantic oracle's after-index rule, or wait for an
occurrence number that cannot exist before the boundary. `EXP-143` caught a
hidden initial Home this way: the step wait reused H1, while the ordered oracle
correctly rejected the missing post-pop Home occurrence.
~~~~

## Runbook observation 10

Original `TOOLING_RUNBOOK.md`, lines 1227–1233. Quoted without changes.

~~~~text
Do not add a later `waitForSignal` for a short marker when the terminal completion
conditions already require the marker's action/Resource evidence. The marker may
arrive while the driver is evaluating an earlier step; subscribing afterward
creates a false timeout even though the SDK result is complete. The first
post-fix canonicalization attempt in `EXP-143` and `EXP-145` attempt A exposed
this race. If an explicit wait is necessary, choose a discriminator that cannot
exist before the current observation cursor.
~~~~

## Runbook observation 11

Original `TOOLING_RUNBOOK.md`, lines 1235–1240. Quoted without changes.

~~~~text
Do not use an ordinary delayed task as the clock for an exact authority stop.
Scheduling may place it before or after the stop; either owner can be correct for
the call site's actual execution time. `EXP-145` attempt B was invalid for fixing
that callback to the manual side. Use an explicit marker before stop and another
after the newly revealed occurrence starts. Treat the unsynchronized delayed
callback as diagnostic evidence unless the driver gates its execution side.
~~~~

## Runbook observation 12

Original `TOOLING_RUNBOOK.md`, lines 1749–1753. Quoted without changes.

~~~~text
Detailed RUM search puts source in attributes.source, outside attributes.custom.
Preserve that envelope field before projecting the custom payload. If both shapes
provide conflicting source values, reject them. Missing source cannot be derived
from expected phase/name/container. EXP-183 attempt A retains the original failed
projection; revised projection controls pass41 tests and require a fresh run.
~~~~

## Runbook observation 13

Original `TOOLING_RUNBOOK.md`, lines 1851–1857. Quoted without changes.

~~~~text
A complete count of indexed view IDs can precede their final counter updates.
For the process fixture, query view rows after individual events and allow at most
three fresh reads with10s between reads for lower integer counters to converge.
Keep exact identity/source/run checks and reject counter regression, overshoot,
malformed types or extra rows immediately. Final values must match the mapper.
Persist backend-exchanges.json before bridge and semantic validation so rejected
responses survive in the durable summary. See EXP-185 attempt B for the witness.
~~~~

## Runbook observation 14

Original `TOOLING_RUNBOOK.md`, lines 1888–1892. Quoted without changes.

~~~~text
EXP-186 attempt A establishes one narrow backend representation exception:
an empty mapper slowFrames array may appear as an absent backend field.
Record field presence separately; never treat explicit null or a missing
nonempty array as equivalent. Preserve the original projected values and the
failed run, and rerun from a newly frozen source/tooling identity.
~~~~

## Runbook observation 15

Original `TOOLING_RUNBOOK.md`, lines 1916–1921. Quoted without changes.

~~~~text
The first frozen native attempt showed that BenchmarkTests can build with empty
client-token/application-ID substitutions. Build and clean-install success do not
prove telemetry configuration. Require the fixture's configuration check before
SDK initialization; inspect only presence/format booleans if diagnosing the built
app, and never read the protected local xcconfig. Repair existing build-setting
wiring, freeze it and use a new full attempt; preserve the original INVALID receipt.
~~~~

## Runbook observation 16

Original `TOOLING_RUNBOOK.md`, lines 2104–2108. Quoted without changes.

~~~~text
An unrelated historical performance fixture can stop a compatibility-only build
after the SDK compiles if internal API shapes have changed. Preserve that failed
attempt. Exclude only the unused workload in both arms before comparing the new
source identities; do not patch the current SDK to satisfy an out-of-scope fixture.
EXP-189 records this preparation failure and the justified common-fixture rebuild.
~~~~

## Runbook observation 17

Original `TOOLING_RUNBOOK.md`, lines 2118–2123. Quoted without changes.

~~~~text
EXP-190's official exact15.0 requests return70 for both universal and arm64, with
no file exported. A support-table entry does not establish present catalog access.
Record that specific limit without claiming permanent runtime incompatibility.
Use older Xcode's xcdevice inventory as well as CoreDevice for older iOS devices;
exclude virtual CoreDevice entries by their reality field. Resume only when the
required runtime/device/host or catalog availability changes.
~~~~

## Runbook observation 18

Original `TOOLING_RUNBOOK.md`, lines 2153–2159. Quoted without changes.

~~~~text
Fresh post-restart MCP now reports SDK27.1 and eligible Duo destinations, matching
CLI27.1. Check that agreement on each new connection. Use Device Hub's observed
pose controls for opening/closing/folding; neither device type nor a click alone
proves the display transition. Capture devicectl display readback and app geometry.
Apple restricts new Duo windows to the inner display; qualify it before an
overlap scenario. EXP-192's finite routing preserves each original native and
backend discriminator and records unexpressible simulator boundaries explicitly.
~~~~

## Runbook observation 19

Original `TOOLING_RUNBOOK.md`, lines 2191–2196. Quoted without changes.

~~~~text
EXP-193 uses adaptive_split_contract.py with a fixed14-phase sequence. Record
the request sequence before each pose/resize, wait for matching fresh native
geometry, then deliver the visible marker. Preserve the geometry receipt and
post-resource sequence in phases.json; stale or post-marker geometry is rejected.
The selected-state model commit must precede immediate work. Acceptance joins
all50 work event IDs to exact backend owners plus the complete view inventory.
~~~~

## Runbook observation 20

Original `TOOLING_RUNBOOK.md`, lines 2212–2216. Quoted without changes.

~~~~text
EXP-190’s corrected17.x qualification records all five stable historical Apple
catalog versions as unavailable through27.1 downloadPlatform;26.6 also rejects
17.0. Direct catalog presence/HTML response is not a usable runtime. Do not
repeat unchanged requests or patch metadata. Resume from accessible official
content or an eligible test host/device.
~~~~

## Runbook observation 21

Original `TOOLING_RUNBOOK.md`, lines 2270–2276. Quoted without changes.

~~~~text
EXP-194 uses the existing acceptance runner's finite Replay scenario. Baseline and
growth observations carry actual core counters, exact representative/scene RUM
identity and live native scene geometry. Run before opening B, after B creation and
navigation, and after acknowledged OS disconnect plus A navigation. The native
UIView stimulus creates recorder input under default privacy; do not inject
records or use a browser bridge. The serial oracle requires complete six-view inventory,
zero errors/crashes and clean removal. Physical F05 remains a separate requirement.
~~~~

## Runbook observation 22

Original `TOOLING_RUNBOOK.md`, lines 2298–2302. Quoted without changes.

~~~~text
EXP-194 now accepts the serial iPad27.0 slice with four native recording boundaries,
complete six-view backend identity, zero stray work/errors/crashes and full cleanup.
Reuse those results within their source/oracle boundary. Physical F05 still needs
an actual multi-window device; ordinary single-window hardware and Duo simulator
geometry cannot substitute for it.
~~~~

## Runbook observation 23

Original `TOOLING_RUNBOOK.md`, lines 2312–2320. Quoted without changes.

~~~~text
EXP-193 pose input uses testAdaptivePoseSequence with a fresh runner UUID and
unique run-bound marker/selection command files. Admit every marker after native
geometry, accepted route and completed materialization evidence. A sidebar
overlay can leave detail text discoverable while Clear selection is not hittable;
dismiss the observed overlay through native input and require the button hittable.
Do not treat element existence as input readiness. Preserve the original failed
run, then rebuild the changed UI fixture and use a fresh run. Keep the app alive
through exact42-work/seven-view backend verification before releasing finish.
Direct active-display captures remain necessary when Device Hub shows black.
~~~~

## Runbook observation 24

Original `TOOLING_RUNBOOK.md`, lines 2330–2338. Quoted without changes.

~~~~text
EXP-195 keeps UIKit views/actions and SwiftUI views/actions separate. Default
public predicates and unchanged app sources are the subject; semantic hosts,
manual RUM calls and custom marker actions cannot substitute for automatic
coverage. Qualify actual native input and geometry independently of RUM output.
Use genuine old/new build SDKs, record installed binary identities and retain
existing limitations when comparing names, counts, occurrences and owners.
A Duo27.1 versus regular27.0 delta retains an OS-patch confound; same-device
old/new build pairs isolate rebuild changes. No mapper-only result is a backend
claim. The fixed matrix and failure classifications live in the owning result.
~~~~

## Runbook observation 25

Original `TOOLING_RUNBOOK.md`, lines 2340–2344. Quoted without changes.

~~~~text
The EXP-195 calibration exposed two important discriminators: terminate-only
collection may lose an otherwise pending final automatic action, so end with
a qualified real background boundary; a SwiftUI switch element can be found
and tapped without changing value, so require both its native callback and
value change. Preserve either failure as collector/input evidence, not SDK loss.
~~~~

## Runbook observation 26

Original `TOOLING_RUNBOOK.md`, lines 2364–2369. Quoted without changes.

~~~~text
The first automatic-only Duo XCTest Home attempt loses app/runner finalization
and emits no native background receipt. Preserve its XPC log and incomplete
result; successful preceding folds do not qualify the full cell. The Duo collector
now waits for actual Device Hub Home, then `pose.py home-ack` admits only the
fresh native background event before completing.49 oracle controls cover both
fold geometry/display and external Home chronology.
~~~~

## Runbook observation 27

Original `TOOLING_RUNBOOK.md`, lines 2371–2378. Quoted without changes.

~~~~text
For this user-authorized UI session, `caffeinate -d -i -u -t 3600` keeps display
and system awake with a bounded user-active assertion. Verify the owned PID in
`pmset -g assertions`, record its deadline and terminate only that process at
completion. It does not change persistent lock settings or replace manual unlock.
Independent regular/Duo runs require separate manifests to avoid update races;
all comparisons retain per-run source and installed identities. Freeze/check the
archived source and runner binary, rather than requiring the working tree to stay
at an older collector version while another slice is prepared.
~~~~

## Runbook observation 28

Original `TOOLING_RUNBOOK.md`, lines 2435–2448. Quoted without changes.

~~~~text
The first current-develop regular UIKit switch failure retains synthesized event,
native JSONL, installed identities and video. The AX element spans372points, but
XCTest selected a point inside the visible switch; do not infer a center miss from
AX bounds alone. Check exported video duration against the event time: this capture
does not cover the later failed switch interval. A successful preceding button
and absent switch callback do not establish an SDK regression. Define any new input
diagnostic before execution, preserve the failed cell and keep diagnostic/native
input success distinct from semantic acceptance.
A passing SDK-disabled control alone is not SDK-causality proof: EXP-210
later also passes with SDK/actions enabled. When the planned red arm passes, stop
the differential pair before its disabled arm, retain mixed outcomes and move to
independent work. A matching source inventory or selected object-code section is
not whole-binary identity. Archive raw controls/products before cleaning owned
simulators; restored evidence paths do not restore live destination identities.
~~~~

## Runbook observation 29

Original `TOOLING_RUNBOOK.md`, lines 2530–2530. Quoted without changes.

~~~~text
The first physical F05 run observed A Home/foreground during B close before explicit reactivation. Preserve that original strict rejection. The separately defined `validate_physical_local` requires that exact close-triggered interval; the existing simulator oracle retains its earlier explicit-reactivation contract. Six focused oracle tests pass, including fourteen new boundary/identity controls. No native test rerun is needed for an oracle-only repair when every frozen native input and signed/installed Mach-O still matches.
~~~~

## Runbook observation 30

Original `TOOLING_RUNBOOK.md`, lines 2581–2586. Quoted without changes.

~~~~text
EXP-196 is safely checkpointed. The original Full Screen Apps preference is
restored and screenshot-verified, test app/runner and process are absent, and the
exact task-owned caffeinate assertion was stopped. Its durable cleanup receipt
belongs to the EXP-196 result. Future device work requires fresh preflight and
new control/run identities; do not reuse its old PID or temporary outputs as a
new run. Remaining physical combinations are S3, not the next automatic task.
~~~~

## Runbook observation 31

Original `TOOLING_RUNBOOK.md`, lines 2639–2643. Quoted without changes.

~~~~text
EXP-198 is defined in its own protocol before fixture implementation. Its real
URLSession workload uses the unchanged performance budgets. The old allocation
collector observes only its installation thread; asynchronous coverage needs
independent all-thread calibration before measurement can qualify. Keep timing
and allocation processes separate and hold competing host workloads during ABBA.
~~~~

## Runbook observation 32

Original `TOOLING_RUNBOOK.md`, lines 2645–2653. Quoted without changes.

~~~~text
The admitted fourth correction uses one schema-v5 contract across native fixture,
host and evaluator. Freeze source/helpers before either build; freeze a separate
execution manifest afterward with actual binary hashes. Preserve native result
bytes before parsing even failed results, and keep capture status separate from
semantic verdicts. Qualification must validate only its own controls; timing must
never install the allocation observer. Enforce the absolute qualification and
matrix deadlines, including cleanup, and reserve each launch once. The owning
result records the finite correction admission and acceptance review; offline
negative-control passes never count as native or numeric evidence.
~~~~

## Runbook observation 33

Original `TOOLING_RUNBOOK.md`, lines 2692–2699. Quoted without changes.

~~~~text
The current API verifier hard-codes an iPhone17Pro latest destination. If absent,
preserve the failure and freeze a temporary destination-only adaptation; keep its
full declared Tests/Fixtures graph, parser/comparator and API baseline bytes.
Feature-doc verification needs reachable prior source objects. Use authenticated
HTTPS fetch with per-command rewrite/credential settings if the SSH agent is
unavailable; never change persistent Git configuration or emit credentials.
Verification headers now identify1bdc9286c; if later rebased/amended/squashed, rerun
the feature-doc skill before any separately authorized push so the SHA is reachable.
~~~~

## Runbook observation 34

Original `TOOLING_RUNBOOK.md`, lines 2914–2921. Quoted without changes.

~~~~text
Derive changed suite inventories from named upstream additions/removals before
discovery. Require every architecture's exact compiler membership before assertions,
and bind native attachments to the current device, invocation and critical boundary.
Compare public APIs against the new upstream reference, then bind feature-document
metadata to the new signed source commit. Update only the authorized draft with an
exact remote lease and read back its head, base, commits, files and concise body.
[EXP-219](Results/EXP-219-upstream-resource-integration.json) records this procedure;
its affected checks do not replace current CI or broaden older platform evidence.
~~~~
