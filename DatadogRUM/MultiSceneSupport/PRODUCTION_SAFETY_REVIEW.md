**Production safety review of multi-scene SDK instrumentation**

Updated 2026-09-17 during plan execution. **Release remains on hold: 4 of the
12 review findings are closed, 8 remain open.** The finite checklist has 16/66
release gates closed. [PLAN.md](PLAN.md) owns the release contract and
[REVIEW_TRIAGE.md](REVIEW_TRIAGE.md) owns assessed repair order and evidence limits.
Review IDs R01–R12 below map to repair gates D01–D12, not PLAN's responsibility
review gates R01–R06.

| Finding / gate | Current disposition | Evidence or next decisive check |
| --- | --- | --- |
| R01 / D01 | CLOSED | EXP-162, signed `e420528f7`: full watchOS RUM Debug/Release builds and 70 iOS Resource/action tests |
| R02 / D02 | CLOSED | EXP-162, signed `af8864528`: full macOS WebView Debug/Release builds and 28 iOS bridge tests |
| R03 / D03 | OPEN | Mounted keyed host teardown and repeated lifetime checks, paired with P03 |
| R04 / D04 | OPEN | Core/generation isolation across every handoff consumer, paired with P02 allocation budget |
| R05 / D05 | OPEN | Resolve old session ownership once before restoring peers |
| R06 / D06 | OPEN | Controlled lazy-expiration restoration after lifecycle boundaries |
| R07 / D07 | OPEN | Empty explicit/capability source must retain automatic tracking until accepted state |
| R08 / D08 | OPEN | Stale trait, real reconnect and accepted-publication regression; hardware ordering stays separate |
| R09 / D09 | CLOSED | EXP-164 at local `a9abc092b`: 31 tests and actual mounted fixture 19/19; zero background reads/MTC diagnostics versus control 5 reads/4 diagnostics |
| R10 / D10 | OPEN | Reject/canonicalize Binding writes and verify accepted-state callbacks/occurrences |
| R11 / D11 | OPEN | Replay-enabled legacy native/WebView correlation plus cross-scene negative control |
| R12 / D12 | CLOSED | EXP-163, signed `084dff4c1`: three failing recipient controls, 212 affected tests pass; own overdue-stop attributes retained without peer leakage |

EXP-162's [durable result](Results/EXP-162-platform-compatibility.json) includes
both failing full-target controls and passing builds. R01's platform-neutral
adapter is now outside the watchOS guard; core scoping remains a separate R04
repair. R02 forwards absent scene metadata on macOS. These compile results do not
close runtime, restoration, lifetime, minimum-iOS or hardware gates. Early
EXP-160 measurements independently fail allocation and retained-scene budgets;
thresholds remain frozen. EXP-163's [durable result](Results/EXP-163-action-stop-attributes.json)
closes D12 and restores T02 using retained EXP-159 backend evidence; no hardware
or new backend acceptance is inferred. EXP-164's
[controller-thread result](Results/EXP-164-controller-threads.json) closes D09
using an actual native scene with a logical peer; it does not prove physical
window concurrency. D11 correlation remains next. Keep this review and its open
findings until their corresponding gates close; preserve historical evidence below.

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

**Safer implementation direction and repair order**

1. **Restore compatibility first:** fix R01/R02, then R09/R11/R12. Add the missing supported-platform builds and focused legacy regressions. These changes can be small and reviewed independently.
2. **Give execution context an owner:** address R04 with one internal core/generation-aware handoff contract shared by Logs, Trace, RUM resources, and network instrumentation. Preserve the existing distinction between absent context and a known scene with no valid view.
3. **Resolve routing before changing state:** fix R05/R06 with a single internal resolution/restoration policy. Reusing an unresolved process representative after mutating the tree is intrinsically fragile. Keep resource completion tied to operation ownership, not a newly chosen representative.
4. **Make SwiftUI lifetime and authority explicit:** fix R03/R07/R08 with cancellable registrations, disconnected-scene epochs, and authority acquired only after an accepted destination can be published. Use transient detach, suspended scene, and final owner destruction as distinct states. Remove bound-modifier callbacks rather than relying solely on disappearance cleanup.
5. **Unify accepted-state handling:** fix R10 and presentation occurrence identity. Path, presentation, and router adapters should all feed accepted transitions to the same small state machine. After behavior is covered, split the 6,613-line modifier file by responsibility: attachment, registration lifetime, authority, transition state, and public adapters. Splitting alone will not fix the ownership problems; avoid a broad rewrite before the regression cases exist.

**Validation needed to close this review**

Turn the reproductions into failing regression tests before changing behavior, then run the relevant RUM, Internal/network, Logs, Trace, WebView, and Objective-C suites. Add compile coverage for watchOS, macOS, tvOS, visionOS, and the repository's supported iOS/toolchain compatibility paths. Newer semantic APIs must remain availability-gated while iOS 15+ legacy behavior stays valid.

Use a mounted SwiftUI host for retain/release, rejected presentation writes, delayed detach/remount, stale trait after disconnect, and same-ID presentation transitions. Exercise at least two live scenes with session stop/expiration and asynchronous completion. Capture actual emitted ownership and action/resource counts. Run Main Thread Checker for the existing controller APIs and memory growth checks over repeated navigation/window creation; retain the planned physical iPad/Duo and release-performance gates.

The review's compiler probes used `swiftc -typecheck -` with the installed SDK and `/tmp/dd-multiscene-review-module-cache`. SwiftUI executable probes used the installed Xcode Swift interpreter in Swift 5 mode, macOS SDK 26.5, and `/tmp/multiscene-review-swift-cache`; source snippets were read from the current checkout, with dependency/handler stubs where stated. Probe scripts were supplied on stdin, not committed as tests. No new complete SDK build or device result is claimed.

Reviewed concerns that did not become findings: the preliminary queued A→B resource-start concern was rejected because existing same-scene fallback and resource ownership handle that sequence; the UIApplication sendEvent return-signature concern is pre-existing; no additional independently provable defect was found in the changed profiling identity or watchdog-clear code. These exclusions should not be interpreted as exhaustive proof of those components' production safety.

The original review changed no SDK source and created no commit. Subsequent
repairs and validation are tracked in the current-disposition table above.
