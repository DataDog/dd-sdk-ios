# RUM multi-scene assessment and evidence

Read this document when you need the detailed support verdict, source-level
baseline, causal-attribution boundaries, or the evidence status for each SDK
surface. Start at the [canonical overview](../MULTI_SCENE_SUPPORT.md) for the
current checkpoint and next action.

Evidence references use the stable `EXP-*` identifiers from
[EXPERIMENTS.md](EXPERIMENTS.md), which owns exact run and session identifiers.

Last updated: 2026-09-12

## Detailed current verdict

**The released baseline is not semantically multi-scene-safe. This branch now has
an experimental core-RUM implementation that fixes the reproduced ownership
failures once a UIKit or explicitly tracked SwiftUI view is established, including
navigation, actions, lifecycle, delayed Resource/Trace completion, and Operations.
Transparent native SwiftUI root and destination creation still fails before those
views exist, so the branch is not ready for a general support claim.** Multiple
real two-window iPad runs and their ingested backend sessions validate the core
model; the remaining matrix and normal-app regressions still gate release. The
pre-trait RUM suite passed 1,018/1,018 after the SwiftUI
attachment and normal-app gating changes. After adding the iOS 17+ trait bridge,
the complete RUM suite passed 1,020/1,020. Logs passed 95/95, Internal 477/477,
Trace 147/147, and WebView 31/31. After the superseding per-step Operations change,
the complete RUM suite passes 1,033/1,033 and the focused manager/session-scope set
passes 98/98.

The iOS 17+ custom-trait experiment now works as an early scene-identity bridge,
but it does not change SwiftUI's outer-to-inner lifecycle modifier ordering. In
two iOS 27 runs, trait-backed tracking made all six Home/Detail lifecycle resources
land on the correct views and `onChange(initial:)` reduced the first-view delay
from about 35 ms to about 3 ms. Customer outer `.onAppear` and the synchronous
prefix of `.task` still ran first. This is a useful attribution improvement, not
a supported view-before-callback guarantee. A stricter follow-up invoked four
synchronous custom RUM actions in those customer callbacks. The view commands
were processed first, all four actions were emitted on the intended new
Home/Detail view, and backend intake agreed. The residual timing gap has therefore
not produced a semantic attribution failure in the tested iOS 27 command/resource
paths.

The probe now has separate manual and automatic SwiftUI tracking modes while it
continues to host SwiftUI inside the integration runner's UIKit `UISceneDelegate`.
Automatic experiment `EXP-021` kept navigation actions and
view activation isolated between scenes A and B, so the branch's scene routing is
effective for hosting-controller discovery. It also reproduced a separate
semantic failure in transparent view creation: Home and Detail `.onAppear` and
immediate `.task` resources completed on the preceding view, after which the
tracker emitted a short-lived `RUMMultiSceneProbeSwiftUIRoot` view and only then
the final navigation-host or destination view. The backend session confirms the
same ordering and attribution. Automatic UIKit-hosted SwiftUI is therefore a
reproduced P0 gap rather than an untested one. Single-window iPadOS 27 experiment
`EXP-022` independently reproduced the same Home and
Detail sequence in console and backend intake, so it is not specific to the 26.5
runtime used for stable two-window testing.

The native SwiftUI lifecycle is now tested and fails more directly. A standalone
iOS 27 `WindowGroup` probe avoids the Runner's UIKit scene delegate and drives a
bound `NavigationStack` plus `openWindow`. Single-window experiment `EXP-027`
kept Home `.onAppear` and immediate
`.task` on `ApplicationLaunch`; delayed Home work and all three Detail lifecycle
markers used the preceding `NavigationStackHostingController<AnyView>`.
`ProbeHomeView` was never emitted, and `ProbeDetailView` appeared only after all
Detail callbacks. Two-window experiment `EXP-028` then proved the multi-scene
consequence:
scene B Home `.onAppear` and immediate `.task` actions and resources were attached
to scene A's final `ProbeDetailView`. Console mapper output and backend aggregates
agree exactly. The branch therefore routes established automatic views by scene,
but transparent native SwiftUI discovery is neither early enough nor semantically
safe while a new window is being created.

An iOS 27-only `UIViewController.viewIsAppearing` experiment was then implemented,
unit-tested, and run against the same probe. It did not move automatic discovery
ahead of SwiftUI lifecycle work: Detail's final automatic view still started about
515 ms after `.onAppear`, all three lifecycle resources stayed on the source view,
and the transient root remained. The extra swizzle and its tests were removed rather
than imposing new controller interception with no semantic gain. `EXP-023`
preserves the rejected experiment.

A separate base-`UIViewController.viewWillAppear` experiment was also rejected.
LLDB on iPadOS 27 proved that both the outer hosting controller and inner
navigation hosting controller already carry the correct scene trait at the base
interception, even before their own views have a window. Calling the tracker
before the base implementation did not make the initial Home view early enough,
and backend view-ID comparison showed that all three Detail lifecycle resources
still reused the Home navigation-host view rather than a new destination view.
Calling it after the base implementation produced the same semantic result. The
candidate hook and tests were removed. Experiments `EXP-024` and `EXP-025`
preserve both orderings.

A follow-up LLDB inspection completed the native Home and Detail timing analysis.
At launch, the generic root `UIHostingController` reached the base
`viewWillAppear` implementation with a nil navigation title and no child
controllers. `ProbeHomeView.onAppear` ran next. Only afterward did
`UIKitNavigationController.viewWillAppear` run, followed by
`NavigationStackHostingController.viewWillAppear` with the correct
`scene-A: Home` title. On navigation, `ProbeDetailView.onAppear` likewise ran
before both `UIHostingController.viewWillAppear` and the base UIKit
implementation. The destination controller and `scene-A: Detail` title already
existed at the callback, but no public controller lifecycle notification had fired
for the SDK to observe. A navigation-title fallback is therefore too late for
Home/Detail lifecycle work even when its eventual value is correct.

The same inspection found iOS 27 private-reflection drift. The existing
`content.list.item.type` path no longer exists. The apparent replacement,
`elements.body.viewType`, exposes the registered destination type and reports
`ProbeDetailView` while Home is still visible. It describes a destination
registration, not the current screen, and must not replace the old path. These
are local runtime/LLDB findings; they do not add a payload or backend result.

The baseline verdict is supported by source inspection and a reproduced iPad
simulator failure: opening scene B emitted a final inactive update for scene A's
still-visible Home view before starting scene B's Home view. In the fixed iPadOS
26.5 probe, opening scene B created a second active RUM view without stopping A;
navigating, presenting, dismissing, scrolling, and closing B affected only B.
UIKit and manually tracked SwiftUI duplicate-name views retained distinct IDs,
and actions plus delayed work stayed on their source windows. Datadog intake
preserved all scene view IDs in one session. The branch keeps one active view
branch per scene and has focused coverage for UIKit and explicit SwiftUI view
lifetimes, duplicate identities, navigation, taps, scrolls, scene lifecycle,
session rollover, and interaction-to-next-view attribution. Mirrored log errors,
WebView native-container correlation, and the representative fatal context have
focused ownership tests.

A teardown-specific experiment found one additional failure after the first core
fix: a scene-owned feature operation emitted its start vital on the correct view,
but closing that scene before the end left no active matching view, so the end
vital was not retained by intake and no reduced operation was created. The manager
now stores the last trustworthy view ID, name, and path proven by any operation
step. Each start, update, retry, success, or failure resolves its call-site view
independently; a trustworthy scene-B step replaces the stored scene-A snapshot.
Only a later source-less or unresolved step falls back to that snapshot, without
resurrecting or updating a stopped `RUMViewScope`. Focused tests cover A-to-B
success and failure, A1-to-A2 navigation, snapshot refresh, teardown fallback,
parallel keys, reverse completion, and process-representative compatibility.
`EXP-020` remains the backend proof for the closed-
scene fallback; a live A-to-B operation run is still pending.

The Operations review also found that Profiling still correlated operation
messages with the delimiter-concatenated string `name-operationKey`. Distinct
tuples such as (`a-b`, `c`) and (`a`, `b-c`) therefore collided outside the RUM
manager. Commit `ac90b5865` replaces that dictionary key in both continuous and
app-launch profiling with a typed `(name, operationKey)` value, including a
distinct representation for an omitted versus empty key. The complete Profiling
scheme passes 233/233 after this change.

Generic automatic Resource and Trace attribution is **not solved**. An arbitrary
`URLSession` request has no intrinsic `UIWindowScene` identity. The current
`UIApplication.sendEvent` experiment can carry provenance only for synchronous
customer code dispatched by a scene-owned UI event, plus structured child tasks
that actually inherit its `TaskLocal` value. It does not establish ownership for
detached tasks, GCD, timers, repositories, background work, framework-created work,
or other requests that have lost their causal origin. Focused tests and one
button-local resource/span probe show that ownership can be preserved when a
source is known; they do not justify a general automatic-attribution claim.

Important limits remain explicit. Generic source-less manual APIs and feature-
flag messages use the process representative, which normally follows the most
recently tracked interaction. Operation steps first use their last-proven view
snapshot when one exists. Early scene
connection and `viewDidAppear` requests can also reach the previous representative
before the new scene's first RUM view exists; this matches the approved fallback
but is not exact attribution. UI-triggered manual APIs can participate in the
bounded event handoff only when the relevant instrumentation is enabled and the
runtime experiment proves inheritance; callers outside that path remain
inherently ambiguous. Main-run-loop long tasks, hangs, and other process-wide
signals also use one representative rather than being duplicated. Correcting
automatic SwiftUI view discovery, split-view navigation, restoration, profiling
correlation, external-display refresh rate, and iPhone Duo validation remain open.
Session Replay scene-correctness is out of scope; repeated two-window runs uploaded
replay data without an SDK crash, which is the required contract here.

## Objective progress review

This review measures the branch against the initial support objective rather than
against the amount of implementation completed:

| Objective | Current evidence | Remaining release work |
| --- | --- | --- |
| Concurrent view creation and lifetime | UIKit and explicit SwiftUI `.trackRUMView` windows coexist in one RUM session; established automatic hosting-controller stacks retain scene isolation | Native `WindowGroup` proves B startup work can inherit A's view before B discovery. LLDB rules out title, current reflection paths, and controller appearance callbacks as early transparent sources. Review an explicit iOS 27 integration before restoration and iPhone Duo validation |
| UIKit and SwiftUI navigation | UIKit push/pop/modal and manually tracked SwiftUI `NavigationStack`/modal flows have independent backend view chains, including duplicate names; automatic navigation remains scene-local once its host exists | Correct native automatic root/destination creation and attribution through a reviewed integration, plus `NavigationSplitView`, UIKit split/adaptive collapse, and restoration |
| Action attribution | UIKit/SwiftUI taps emit once on the source view; SwiftUI scroll, action rejection, action expiry, and overlapping-action fixes have backend or focused-test proof | UIKit scroll through deceleration and the filtered-physical-interaction representative edge |
| Scene lifecycle and sessions | Requested scene destruction/close affects only its scene; focused tests cover disconnect; explicit stop and expiry restore concurrent branches; overlapping views reached raw intake and the reducer | Temporary disconnect/reconnect, per-scene background/foreground, restoration, and product UI presentation of overlapping views |
| Resources, traces, and operations | Known Resource/Trace provenance is frozen through completion. Operations use application-wide typed identities and independently resolve each step; focused A-to-B, parallel-key, reverse-completion, navigation, teardown, and compatibility tests pass | Four unrun Resource/Trace causal rows, live A-to-B/duplicate-start Operation proof, public Operation target API review, and generic source-less representative fallback |
| Errors, logs, WebView, vitals, fatal/exported context, and profiling | Scene-aware source or focused tests exist for each except profiling, whose process-level limitation is known | Targeted two-window runtime/backend evidence; profiling needs an explicit support statement, not guessed per-scene ownership |
| Normal-app compatibility | Full RUM/Internal/Logs/Trace/WebView suites, gating regressions, probe build, lint, and generic iOS package build pass | Live single-scene behavior, custom-handler integration, and `sendEvent` overhead/recursion measurement |
| Session Replay | Multiple UIKit/SwiftUI two-window and teardown runs uploaded replay data without an SDK crash | No scene-correctness work required for this objective |

The core model is no longer the largest unknown. The release-critical work now
starts with the reproduced automatic SwiftUI view-creation/navigation failure,
then the remaining navigation/lifecycle/action rows and proof that ordinary apps
do not pay a behavioral or performance cost. No additional distributed-tracing
or header-repair work is justified unless one of the pending causal experiments
reproduces a RUM/APM ownership disagreement.

### Required causal-boundary experiment status

This table records every case requested by the product clarification. “Classified”
means the observed representative fallback is the intended compatibility result,
not exact source attribution.

| Required case | Evidence | Status / next action |
| --- | --- | --- |
| Synchronous URLSession request in a UIKit tap | `EXP-006` kept RUM Resource, APM span, source view, and accepted action together | Backend-pass |
| Structured `Task` created in a tap, including suspension | `EXP-007` proved 20/200 ms action validity; `EXP-009` retained scene B across three minutes and a representative switch | Backend-pass |
| `Task.detached`, GCD, and timer | `EXP-009` put all three on representative A rather than source B | Backend-classified as source-less |
| SwiftUI Button followed by structured `Task` | The control exists, but no isolated two-window backend result distinguishes it from the broader SwiftUI delayed-work runs | Pending |
| SwiftUI `.task` and `onAppear` loading | Pre-trait explicit experiments `EXP-010`, `EXP-011`, and `EXP-012` failed; trait experiments `EXP-013`, `EXP-014`, and `EXP-015` achieved correct explicit attribution. Automatic UIKit-hosted and native experiments put lifecycle work on preceding views. `EXP-029` then proved Home/Detail `.onAppear` precede the usable navigation-host appearance boundary | Backend-pass for explicit tracking on iOS 27; automatic initial-root and destination attribution fail; explicit integration review next |
| Scene connection and UIKit `viewDidAppear` loading | `EXP-006` and `EXP-016` used the prior representative before the new view existed | Backend-classified as source-less |
| Pre-created URLSession task resumed from a UI action | `EXP-006` selected B Detail and the resume action at interception rather than object creation | Backend-pass |
| One shared/coalesced request used by both scenes | Probe control exists; no conclusive two-window run | Pending; expected to remain ambiguous |
| Navigation and session rollover before actual request start | Navigation-at-resume passed in `EXP-006`; `EXP-007` exposed rollover loss and `EXP-008` verified the fix | Backend-pass |
| Reverse-order completion from two scenes | RUM and Trace focused tests pass with frozen A/B owners | Runtime/backend pending |
| Source scene closes before completion | `EXP-019` preserved delayed resources and traces; `EXP-020` preserved the fixed operation | Backend-pass |
| Concurrent operations with identical `(name, key)` | Contract decided and focused test passes: the second start emits normally and replaces only local tracking; one later end closes the latest start, with no synthetic client-side end | Live warning/raw-vital proof pending; the earlier backend operation is expected to remain open until its four-hour timeout |
| Trace-only URLSession span | Probe control and four Trace ownership regressions exist | Runtime/backend pending |
| Action accepted, rejected, already active, and expired | `EXP-006`, `EXP-002`, `EXP-003`, and `EXP-007` cover accepted/filtered, fan-out failure/fix, and expiry | Backend-pass; filtered-tap representative persistence remains separate |
| Single-scene and custom URLSession-handler compatibility | Complete module suites and 43 resource-handler tests pass; the rejected request-rewrite experiment was removed | Live single-scene, custom-handler integration, and performance pending |

## Baseline environment

| Item | Baseline |
| --- | --- |
| Branch | `valpertui/multiple-windows-scenes` |
| Baseline commit | `92f021ba7e4a866f84a52da93ed8b63f3dc75882` |
| SDK deployment target | iOS 15.0 |
| Xcode | 27.0 (27A266a) |
| Simulator | iPad Pro 13-inch (M5), iOS 27.0 |
| Backend access | Datadog RUM search and aggregation tools available |
| Local credentials | Read from `xcconfigs/Datadog.local.xcconfig`; values must never be copied here |

Pre-existing working-tree changes at the start of this assessment:

- `Datadog/Datadog.xcodeproj/project.pbxproj` was modified.
- `xcconfigs/Datadog.local.xcconfig` was staged as a new file and also modified.

Both are treated as user-owned and must not be reverted or exposed. Any project
file edits made by this work must be distinguished from that baseline.

## Existing support assessment

### View instrumentation and navigation

`RUMViewsHandler` owns one process-wide `stack`. When a view appears, it stops the
last view in that stack before starting the new one. When a view disappears, it can
restart only the previous item in that same stack. There is no scene identity in
the stored view or in `RUMStartViewCommand` / `RUMStopViewCommand`.

Consequences for two visible windows A and B:

1. A starts view A1.
2. B starts view B1 and the SDK stops A1 even though A1 remains visible.
3. Navigation in A starts A2 and stops B1 even though B1 remains visible.
4. A disappearance can reveal or restart a view from B because the histories are
   interleaved in one stack.

UIKit callbacks retain a `UIViewController`, from which a `UIWindowScene` can
usually be determined. Automatic actions receive a `UIEvent` and touch view, which
also normally retain window/scene identity. Today that information is discarded.

SwiftUI modifier callbacks carry only a string view identity or action name. The
same modifier identity used in separate windows can therefore collide, and there
is no scene identity at the command boundary. Automatic SwiftUI navigation is
ultimately observed through hosting view controllers and has the same global-stack
problem. `NavigationSplitView` coverage must be validated separately.

### Session model and downstream attribution

`RUMSessionScope` can keep several view scopes, but exposes one `activeView` chosen
from the most recently active scope. Starting a new view deactivates the previously
active view. Commands without their own view identity are processed against that
single active view.

This affects at least automatic actions, manual actions, scrolls, resources,
errors, long tasks, vitals, feature operations, interaction-to-next-view metrics,
Session Replay context, tracing correlation, crash/fatal context, and the public or
internal RUM context exported to other SDK features. Some event types have their
own asynchronous context capture and may behave better than this baseline implies;
each must be tested rather than assumed.

### Lifecycle

View instrumentation currently observes process-level application background and
foreground notifications. A scene becoming inactive, entering the background, or
disconnecting is not equivalent to the whole application doing so. Conversely,
closing one scene must not stop unrelated scenes or end the process session.

The integration runner has a `UISceneDelegate`, but its Info.plist explicitly sets
`UIApplicationSupportsMultipleScenes` to `false`. It can exercise scene lifecycle
plumbing but cannot validate two concurrent windows. The Example target has no
scene manifest and creates one app-delegate-owned window.

### Downstream correlation surfaces

The global active-view assumption is reused well beyond view instrumentation:

- **Resources and network tracing:** `URLSessionRUMResourcesHandler` and
  `URLSessionTaskInterception` preserve request and trace state but no originating
  RUM view or scene. An automatic or manual resource start therefore resolves
  against the process-wide active view. Simply allowing several scopes to remain
  active would duplicate one resource into every active view unless routing is
  made explicit.
- **Logs and mirrored RUM errors:** `RemoteLogger` snapshots one exported RUM
  view/action context. When an error log is mirrored into RUM, the message does
  not carry that captured view, so `ErrorMessageReceiver` resolves the view again
  later. The log and corresponding RUM error can disagree after a scene switch.
- **Traces:** spans snapshot the singular exported RUM context. Trace-only
  URLSession spans are constructed at completion with a historical start time,
  which means their RUM view can come from the scene active at completion rather
  than the one that initiated the request. Trace parentage is more robust because
  active spans are execution-scoped, but the RUM correlation remains global.
- **Feature operations and feature flags:** commands and message-bus payloads do
  not carry a scene or view target. Feature-operation lifecycle keys are also
  process-global, so equal operation keys used concurrently by two scenes can
  collide.
- **Session Replay:** `KeyWindowObserver` flattens all connected scenes and picks
  the first key window. Multiple scenes can each have a key window and set order
  is not stable. A single recording coordinator then combines that arbitrary
  window with one global RUM context, while the recorder can drop overlapping
  requests. Captures, touches, and RUM view IDs can therefore refer to different
  windows.
- **Web views:** the bridge receives the exact `WKWebView` but retains only its
  hash. Native-container selection later uses a global timestamp-only
  `ViewCache`, so browser events from one scene can be stitched to another
  scene's native view.
- **Vitals and interaction-to-next-view:** each concurrent view would sample the
  same process readers; refresh-rate collection uses `UIScreen.main`, which is
  additionally wrong for external displays. `INVMetric` keeps one current view,
  making a navigation in scene B the successor of an interaction in scene A.
- **Crashes, fatal hangs, watchdog termination, nonfatal hangs, long tasks, and
  memory warnings:** these signals are process-wide and often have no unique
  scene. Current persistence and fatal context retain only one view. They need a
  deliberate representative or de-duplicated multi-view policy; broadcasting
  would inflate event counts.
- **Profiling:** one profiler per process remains appropriate, but its mutable
  RUM attributes are last-writer-wins while event identifiers can span several
  views. Correlation should aggregate active view IDs or retain ownership per
  event rather than multiply profilers.

Application sessions, sampling decisions, timeseries collection, upload, and the
aggregate application lifecycle should remain process-wide. Scene support must
not multiply these facilities.

### Compatibility constraints

- Keep one application-level RUM session unless experiments reveal an unavoidable
  backend contract problem. Concurrent windows should normally be concurrent view
  branches inside that session, not separate SDK instances.
- Scene identity should remain internal metadata unless a separate public/backend
  contract is approved.
- Commands that have no scene identity must retain today's behavior until a safe
  attribution rule is specified.
- The no-scene/single-scene path must remain behaviorally identical and avoid
  meaningful extra work.
- Scene disconnect must not be treated as application termination.

## Causal attribution boundary for asynchronous work

A scene can be selected automatically only while trustworthy provenance still
exists. A `UIView` reached from a `UIEvent` can identify its `UIWindowScene`.
Customer work invoked synchronously during that event can therefore receive an
internal opaque scene token. A structured `Task {}` created inside that dynamic
scope inherits the token through `TaskLocal`, including across suspension. A real
three-minute URLSession probe now validates that inheritance after another scene
becomes representative. This does not extend to schedulers that discard task-local
context.

The following paths have no generally reliable automatic scene owner and must be
documented as ambiguous unless an application supplies one:

- `Task.detached`, `DispatchQueue.async`, timers, and pre-created tasks resumed
  later;
- shared repositories, caches, background workers, global prefetching, push, and
  background refresh;
- framework-created tasks and observers whose execution context is not inherited;
- scene connection or `viewDidAppear` work without a scoped callback;
- a request shared or coalesced by multiple scenes.

SwiftUI outer `.onAppear` and the synchronous prefix of `.task` are not UI-event
handoff contexts and still invoke before the inner RUM modifier's appearance
callback. Attachment-only, `willMove(toWindow:)`, and child-controller experiments
therefore misattributed them to the preceding view. On iOS 17+, the later
trait-backed explicit-tracking path gave the RUM queue enough scene-aware state to
attribute all tested lifecycle actions and resources to the destination view.
That is backend-validated semantic behavior, not TaskLocal inheritance or a
guarantee about observable callback/view-command ordering. Transparent automatic
SwiftUI tracking is now backend-proven to fail in the native lifecycle as well as
the UIKit-hosted probe.

Thread-local storage is only a synchronous bridge around event dispatch. Thread
identity must never be interpreted as asynchronous scene ownership. The SDK must
not infer an owner from `keyWindow`, the foreground scene, the last active scene,
or the process-representative `RUMCoreContext`, and it must not duplicate one
operation into every active scene.

When provenance does exist, the intended internal Resource/Trace contract is:

1. Propagate an opaque scene token, not a permanently frozen global RUM context.
2. Resolve that scene's fresh session, view, and valid action at the actual
   request or span start.
3. Freeze that one selection for metrics, completion, errors, RUM Resource, and
   Trace writing, even if navigation, session rollover, or scene closure follows.
4. Make RUM Resource and Trace consume the same start-time selection so their
   correlation cannot disagree.
5. Fail closed when an explicit source scene has no valid context; never resurrect
   another scene's representative context.

For work with no provenance, the process-representative fallback is the chosen
compatibility behavior, not exact attribution. It preserves existing event volume
and avoids introducing a resolver requirement, while accepting that source-less
work may be attributed to the wrong concurrent scene.

## Gap and evidence matrix

| Area | Baseline risk | Source evidence | Simulator evidence | Backend evidence | Status |
| --- | --- | --- | --- | --- | --- |
| UIKit view lifetime | A view in one scene stops a still-visible view in another | Baseline global stack; branch scene-keyed stacks/scopes | Fixed run opened B without stopping A | Both scene view IDs coexist in one session | Fixed in branch; tests and runtime pass |
| UIKit navigation | Navigation histories from all scenes interleave | Baseline global stack; branch isolates navigation per scene | Pushes, duplicate-name views, modal presentation/dismissal, and scene closure affected only the source window | Independent A/B view chains and IDs persisted | Fixed in branch; tests and runtime pass |
| Explicit SwiftUI view lifetime | Modifier identities can collide, detach can retain stale scene state, and synchronous lifecycle work can precede the RUM start | Branch resolves the hosting scene only for declared multi-scene apps, keeps stable lifecycle identity, ignores transient detach, and on iOS 17+ bridges a scene custom trait into SwiftUI; `willMove(toWindow:)`, child-controller, and trait lifecycle hooks were all tested | Trait-backed `onChange(initial:)` reduced the outer-callback gap from 35 ms to 2-3 ms without duplicate views; four synchronous lifecycle actions and six resources all resolved to their intended new views despite earlier invocation | Backend view/action/resource IDs confirm the earlier misattribution, the removed duplicate, and correct semantic attribution in both trait runs plus the synchronous-action run | Explicit `.trackRUMView` semantic attribution passes; view-before-callback ordering is not guaranteed |
| Automatic SwiftUI view lifetime | Transparent hosting-controller discovery can select a process-global history, run after lifecycle work, or miss native scene transitions | Core routing accepts a discovered controller's scene identity; both probes use `DefaultSwiftUIRUMViewsPredicate` without explicit modifiers. iOS 27 no longer matches `content.list.item.type`; `elements.body.viewType` is a destination registration rather than current-screen identity | UIKit-hosted and native runs put lifecycle work on preceding views. LLDB shows root/base and hosting-controller appearance boundaries do not expose a usable semantic view before Home/Detail `.onAppear`; native scene B initially reused scene A Detail | `EXP-021`, `EXP-027`, `EXP-028`, and `EXP-029` confirm wrong exact IDs, late destinations, and the B-to-A mapping | P0 semantic failure reproduced; transparent title/reflection/lifecycle candidates are rejected, and a reviewed explicit integration is next |
| SwiftUI navigation | Hosting controllers from all windows share one active history, and transparent discovery may report container transitions instead of customer screens | Scene-keyed scope support resolves explicit modifiers and automatic hosting controllers by scene; the native harness uses a bound typed `NavigationStack` | Manually tracked concurrent stacks, duplicate-name destinations, and modals pass. Native automatic Home is absent and every Detail lifecycle phase stays on the source navigation host before the final destination appears | Manual source-scene chains remain independent; native single/two-window sessions retain all lifecycle events on the wrong preceding views | Manual core path passes; automatic root/destination creation fails; `NavigationSplitView` and restoration pending |
| Tap actions | Touch window is available but not propagated to RUM scope routing | Branch retains the touch/modifier scene; new actions no longer fan out to older scene action scopes | UIKit and SwiftUI source-window taps, navigation links, duplicate-name controls, fixed-toolbar activation, and close actions passed | Actions emitted once on their originating view; the pre-fix manual B fan-out did not recur | Core path passes; filtered physical interaction followed by a later source-less API remains open |
| Scroll actions | Scroll callbacks have a view/window but no scene reaches the command | Branch retains source scene through drag and deceleration | SwiftUI scene D swipe emitted on D while another scene survived; UIKit scroll/deceleration remains to be repeated | SwiftUI D action retained D view | SwiftUI runtime passes; UIKit matrix remains open; focused tests pass |
| Resources and traces | A generic request/span has no intrinsic scene; representative fallback can be wrong | Branch has an experimental `sendEvent`/TaskLocal causal bridge, synchronous owner capture, and frozen completion routing; GCD, detached, timer, repository, lifecycle, and shared work remain ambiguous | Structured tasks and UI-local work retain source ownership; detached/GCD/timer and early scene lifecycle use the representative. Delayed UIKit/SwiftUI resources and traces survive source-scene closure | `EXP-006`, `EXP-009`, and `EXP-019` show that RUM and APM agree on the supported boundary and retain teardown ownership | Partial and bounded; known provenance and completion routing pass, while generic source discovery remains impossible |
| Manual errors and process-wide long tasks | Source-less APIs/signals have no unique scene | Branch uses one process representative; no broadcast | Pending | Pending | Explicit fallback policy; not source-attributed |
| Logs and mirrored errors | A log and its later RUM error can resolve different global views | Branch snapshots request-local RUM context and preserves exact or same-scene routing for the mirrored error; legacy no-scene work retains representative fallback | Pending fixed-runtime rerun | Pending fixed-runtime rerun | Captured-view mirroring fixed and unit-validated; targeted two-window runtime proof remains open |
| Vitals, TNS, and INV | Process vitals overlap; navigation edges could cross scenes | Branch has one INV tracker per scene; TNS follows resource owner; vitals remain process-derived per view | Pending | Pending | INV/TNS fixed; vitals policy and external displays remain partial |
| Feature operations and flags | Delayed steps receive the global active view; string-concatenated identities can collide in both RUM and Profiling; permanently pinning later steps to the start scene would misrepresent cross-window work; closing the last proven view can drop an end step | Branch uses typed `(name, key)` identity in RUM and Profiling, independently resolves each step, refreshes a last-proven view snapshot only from trustworthy context, and uses that snapshot before representative fallback | Focused tests cover A-to-B success/failure, A1-to-A2 navigation, parallel keys, reverse completion, explicit/inferred override, duplicate starts, teardown, and profiler key collisions; `EXP-020` emitted both steps after the source scene closed | The reducer produced the successful closed-scene operation in `EXP-020`; live A-to-B backend proof is pending | Internal lifecycle, attribution, and Profiling identity contract implemented; public target API and live cross-window/duplicate proof pending; flags remain open |
| Session rollover | A process-wide stop/expiry can lose still-visible views or revive the view being replaced | Branch snapshots every active foreground scene and now restores only branches unaffected by a scene-targeted start/stop | Explicit stop followed by B Home -> Detail initially dropped A; fixed rerun emits new A Home and B Detail views | New explicit-stop session contains both raw view documents and the delayed B request remains on B Detail; reducer converged to `view.count:2` | Fixed for explicit stop, inactivity, and max duration; product UI rendering of overlap remains unchecked |
| Session Replay | Recorder/context mapping may follow an arbitrary scene's key window | First key window across an unordered scene set; one coordinator | Repeated two-window UIKit/SwiftUI runs, navigation, and scene teardown completed without an SDK crash | Replay was available on the broad and post-fix sessions | Out of scope except crash safety; coexistence requirement passes for the exercised matrix |
| WebView correlation | Browser events can be stitched to another scene's native container | Branch carries private source-scene metadata and queries scene-keyed view history | Pending fixed-runtime rerun | Pending | Fixed in branch; three focused tests pass |
| Profiling | Profile-level RUM attributes are last-writer-wins across views | One mutable correlation snapshot | Pending | Pending | Confirmed by source |
| Crash/fatal context | Any view update can overwrite one process crash context | Branch restricts updates to the representative and restores another active scene when needed | Pending | Pending | Fixed to representative policy; focused tests pass |
| App/scene lifecycle | Per-scene transitions are invisible to view ownership | Branch observes background, foreground, and disconnect per scene | Requesting UIKit and SwiftUI scene destruction stopped only the source views and surviving scenes continued | Destroyed-scene views became inactive without replacing the survivor | Scene close/destruction passes; temporary disconnect, reconnect/restoration, and per-scene background/foreground remain open |
