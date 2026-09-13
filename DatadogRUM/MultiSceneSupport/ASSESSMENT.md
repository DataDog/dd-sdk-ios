# RUM multi-scene assessment and evidence

Read this document when you need the detailed support verdict, source-level
baseline, causal-attribution boundaries, or the evidence status for each SDK
surface. Start at the [canonical overview](../MULTI_SCENE_SUPPORT.md) for the
current checkpoint and next action.

Evidence references use the stable `EXP-*` identifiers from
[EXPERIMENTS.md](EXPERIMENTS.md), which owns exact run and session identifiers.

Last updated: 2026-09-13

## Detailed current verdict

**The released baseline is not semantically multi-scene-safe. This branch now has
an experimental core-RUM implementation that fixes the reproduced ownership
failures once a UIKit or explicitly tracked SwiftUI view is established, including
navigation, actions, lifecycle, delayed Resource/Trace completion, and Operations.
An iOS 27-only candidate now starts explicitly tracked SwiftUI views from their
inherited scene trait while the hidden platform reader is created, fixing the
reproduced early root/destination attribution in the tested matrix. Transparent
automatic native SwiftUI creation still fails before those views exist, so the
branch is not ready for a general support claim.** Multiple
real two-window iPad runs and their ingested backend sessions validate the core
model; the remaining matrix and normal-app regressions still gate release. The
pre-trait RUM suite passed 1,018/1,018 after the SwiftUI
attachment and normal-app gating changes. After adding the iOS 17+ trait bridge,
the complete RUM suite passed 1,020/1,020. Logs passed 95/95, Internal 477/477,
Trace 147/147, and WebView 31/31. After the superseding per-step Operations change,
the complete RUM suite passed 1,033/1,033 and the focused manager/session-scope set
passed 98/98. Five explicit early-mount state tests and the navigation-occurrence
model test brought the earlier clean RUM run to 1,039/1,039. After the
interactive-transition isolation hardening in `EXP-045`, the complete RUM suite
passed 1,058/1,058 at that checkpoint. The later dormant occurrence slice in
`EXP-062` builds cleanly; its expanded state set passes 25/25, its arbiter set
passes 27/27, and its targeted handler-publisher descriptor regression passes
(53/53 total). `EXP-063` expands this to 27/27 state and 29/29 arbiter tests plus
two targeted handler regressions (58/58), and the complete current RUM plan passes
1,092/1,092 with no failures, skips, or not-run tests. `EXP-064`/`EXP-065` add the
retained-reader reconnect and cross-scene hardening: state passes 34/34, the
arbiter passes 38/38, two handler regressions pass, and the complete current RUM
plan passed 1,108/1,108 at that checkpoint. After UIKit split-column hardening
and execution-local manual action/Resource targeting, the next complete RUM plan
passed 1,122/1,122. The retained-route source and later exact-view routing
hardening brought the complete RUM plan to 1,147/1,147. The retained split-return
remount fix and its four added regressions brought the RUM plan to 1,151/1,151.
The structural UIKit split fix adds two regressions and the current complete RUM
plan passes 1,153/1,153; Trace remains 151/151, including 4/4 focused OpenTelemetry
handoff tests. Repository lint passes all 713 source and 699 test files. The
structured probe recorder, mapper reducer, semantic oracle, exact main-actor
scene registry, and observable stack/split/UIKit/lifecycle driver now pass 45/45
tests (`EXP-108` through `EXP-114`). Three clean iPadOS 27 Home → Detail → Home runs each
emitted one 7/7 local `PASS`, distinct Home₁/Detail/Home₂ UUIDs, and post-return
action/Resource ownership on Home₂. Backend intake independently agrees for all
three sessions and reports no errors. Clean abort and same-/different-type
replacement reruns passed 5/5, 6/6, and 6/6; backend intake confirms no
speculative aborted view, fresh replacement UUIDs, exact final action/Resource
owners, and no errors. Route-owned split replacement and retained return pass
10/10 and 13/13 with exact per-occurrence action/Resource ownership. The same
steps in automatic mode fail 0/9 because semantic work uses launch/internal host
views. Signal-driven UIKit cancellation passes 11/11 while retaining S2's UUID;
completion passes 13/13 with a fresh returned S1 UUID. Backend intake has exact
resolved-view action/Resource pairs, no Primary view, and no error in either run.
Exact scene lifecycle run `EXP-113` then passes 9/9: source A opens target B,
B disconnects after its own marker pair, and A's post-close pair remains on A's
unchanged Home UUID. Backend intake agrees; fullscreen simulator topology still
cannot establish simultaneous-visible peer continuity. `EXP-114` adds exact
activation dispatch and scene-state gating. Its completed control kept
source-less A-labelled work on representative B, which is the approved
compatibility behavior because the SDK had no trustworthy call-site source. The
simulator kept both scenes foreground-active instead of producing the peer
background transition required for an exact occurrence assertion. A later retry
ended when simulator `backboardd` aborted in CoreAnimation/Metal; the probe did
not crash and no events from that interrupted run reached backend intake. Exact
activation semantics therefore remain device-inconclusive rather than failed.
The native SwiftUI host still contributes a short fallback view before S1, but it
owns no probe work. Native gesture synthesis remains unavailable, but it no
longer blocks exact programmatic scenario driving.
The prior `EXP-062` full attempt's sole unchanged timeseries timing failure passed
in isolation and in its clean rerun.

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

The stricter explicit candidate addresses the remaining queue order directly on
iOS 27. The inherited scene trait is passed into the hidden platform reader, and
its creation starts the semantic `.trackRUMView` occurrence before customer
outer `.onAppear` and the synchronous prefix of `.task`. Three clean runs of the
final availability-gated code preserved all 72 lifecycle actions/resources on
exact Home/Detail UUIDs; across all five behavior-equivalent A/B runs, all 120
were exact. A single-window run preserved all 12. Dormant destination, unselected tab, and
three-cycle push/pop stress emitted no extra view outside the completed navigation
path. The candidate is intentionally disabled on iOS 15-26, visionOS, and apps
that do not declare multiple scenes. It changes explicit tracking only;
`DefaultSwiftUIRUMViewsPredicate` remains the P0 gap.

This result is runtime-backed, not a new Apple lifecycle guarantee.
`UIViewRepresentable.makeUIView` denotes platform-view construction rather than
documented semantic visibility. The passing dormant and unselected-container
cases did not preconstruct their readers, so aborted construction, immediate
scene close, restoration, split navigation, and a genuinely preloaded
offscreen container remain required before a release claim.
`EXP-039` tried to sharpen that distinction with a rejected `ViewThatFits`
candidate, but SwiftUI never constructed its diagnostic platform reader. Its
clean backend result is therefore an inconclusive container experiment, not an
additional visibility guarantee.

Completed modal navigation does satisfy the occurrence contract. `EXP-040`
emitted exact `Home₁ → Sheet → Home₂` client and backend ordering, including two
different Home UUIDs around the Sheet UUID. Sheet lifecycle work used Sheet and a
post-dismiss marker used Home₂, with no fallback or extra semantic view.

Immediate B teardown is safe in the exercised path. In `EXP-041`, B started and
stopped once and all six B lifecycle action/resource markers retained B ownership,
including delayed completions after dismissal. The fullscreen simulator returned
to SpringBoard when its frontmost B window closed, so A really became inactive
and its later foregrounding created a new occurrence. This does not prove or
disprove continuity when another window remains visibly active.

Restoration has a partial native pass. `EXP-042` relaunched without uninstalling
and restored B with its original native scene-session ID. A new RUM session and
Home occurrence correctly received every restored-B marker with no fallback.
iPadOS did not reconnect A, so concurrent restoration remains unproven.

Interactive cancellation is a separate explicit-tracking defect. A cancelled
back gesture left Detail visible but emitted a roughly half-second Home occurrence
and restarted Detail. The same false sequence with a comparable duration
reproduced with the early candidate disabled, so the candidate neither causes
nor repairs it. `EXP-043` then resolved the retained Home's public UIKit
transition coordinator during the speculative callback. It was initially
interactive, cancellation became known only in coordinator completion, and the
later SwiftUI reversal callback had already lost the coordinator. The scene-local
completion gate now passes focused state tests and native/backend `EXP-044`: the
cancelled gesture emitted nothing, the completed interactive pop produced a fresh
Home UUID, and post-pop action/resource work used that occurrence. RUM views
represent completed navigation occurrences—not platform-object lifetimes. A
completed `Home → Detail → Home` path therefore has three RUM view IDs,
including two distinct Home occurrences even when SwiftUI retains the same value.
Speculative transitions that are cancelled must not create an occurrence.

The post-run audit in `EXP-045` found that the first gate draft relied too heavily
on retained observers and grouped all pending work by scene. The corrected gate
first uses the tracked view's own hosting-controller chain, falls back to only the
matching `UIWindowScene` hierarchy while a recreated reader is unattached, and
keys deferral by scene plus UIKit coordinator identity. Provisional membership is
rechecked when the reader really attaches, so an unrelated sheet or split subtree
escapes the pop transaction instead of being discarded with it. A trustworthy
attachment to another scene similarly overrides the earlier trait. Focused tests
cover these cases, same-scene independent coordinators, stale completion,
disconnect, and cancellation. Live simultaneous-window transition proof remains
open. A provisional reader that never attaches during a successful transition,
and disconnect/reconnect of one surviving representable, remain part of the
aborted-container and restoration gates rather than claimed support.

The typed-path experiments now isolate two separate requirements. `EXP-046`
proved that the bound route changes only at completion for the exercised
interactive pop: a cancelled pop emitted nothing, while a completed pop created
a new Home occurrence despite retained Home state. `EXP-047` through `EXP-049`
then proved that the path signal alone is insufficient when its tracker is a
detached root sibling or wrapper;
B's initial Home work still used A Detail, and the whole-stack wrapper replayed
lifecycle. `EXP-050` passed only when existing explicit tracking was installed at
the Home and typed-destination builders. `EXP-051` retained that placement and
confirmed exactly `Home₁ → Detail → Home₂` around cancel/complete gestures.
`EXP-052` then wrote Detail and Home in the same task turn: both binding mutations
were observed, but no destination materialized and RUM correctly kept the
original Home UUID. `EXP-054` then passed a materialized Detail-to-Alternate
replacement with no intermediate Home. `EXP-056` repeated that flow in A and B:
each scene produced exactly Home, Detail, and Alternate once. One delayed manual
marker from A used B Home after B became process representative; that call had no
trustworthy SDK source and is the approved source-less fallback, not a view
creation defect. This does not make automatic SwiftUI supported: no SDK
integration API exists. `EXP-057` then replaced Detail(1) with Detail(2) through
the same destination type and RUM name. SwiftUI reused the destination reader,
the UI committed Detail 2, and RUM incorrectly kept Detail₁ active. A future
integration therefore needs customer-supplied route state, route-owned view
creation, and an occurrence identity independent of platform lifetime.
`EXP-058` proves that diagnosis: applying a probe-only `.id(route)` produced
distinct same-named Detail₁ and Detail₂ UUIDs with exact markers. The production
integration must use the same semantic input to restart only RUM tracking; asking
customers to apply `.id` would also reset their content state and is not the API.
`EXP-059` repeats the control in A/B with independent Detail₁/Detail₂ UUIDs and no
intermediate Home. Its one A-delayed/B-Home pair is the already-decided source-less
fallback, separate from occurrence correctness.
`EXP-060` adds the internal atomic stack replacement required by that design.
Focused tests prove visible, covered, inactive, missing, and cross-scene cases,
including no intermediate Home and no peer-scene mutation. The reader, tracking
state, and interactive arbiter do not yet supply an occurrence key, so the
runtime support verdict is unchanged.
`EXP-061` fixes a second-order scope bug that a three-UUID assertion alone did
not reveal. When Home₁ remained alive for a pending Resource, Home₂'s later
start reused the same platform lifecycle identifier and could mutate the inactive
Home₁ scope. Inactive occurrences now ignore later same-identity view start/stop
commands but still process exact pending-work completions. A focused regression
proves the old Resource remains on Home₁, post-pop work uses Home₂, and the two
occurrences keep independent attributes. Restored scopes now also establish their
synthetic start boundary, preventing a later same-identity start from leaving two
active occurrences. Focused regressions pass 3/3, all 75 session-scope tests pass,
and all 27 application-scope tests pass.
`EXP-062` adds the dormant internal occurrence model needed to connect that
runtime evidence safely. Keyed configurations create fresh command identities,
replace an active same-scene stack slot atomically, migrate with stop/start, and
reject stale binding generations. The interactive arbiter retains the final
accepted configuration/emission closure, preserves state on cancellation, and
guards coordinator completion with the concrete deferred transaction rather than
scene/coordinator identity alone. The committed occurrence owns its immutable
descriptor, and keyed state rejects stale or unversioned lifecycle input. State
tests pass 25/25, arbiter tests pass 27/27, and the targeted publisher regression
passes. The public modifier does not yet supply a key, so this changes no
customer-facing or same-type runtime verdict. At that checkpoint, reader
disconnect/reconnect still blocked runtime wiring.
`EXP-063` closes the handler/state teardown divergence for a fresh platform
remount. When A disconnects, the handler emits the sole stop and deletes A's
stack; the arbiter silently clears only A-owned state, advances its revision, and
retains its keyed generation fence. Stale callbacks cannot recreate generation N,
while an explicit N+1 remount emits a fresh start rather than a replacement. B
continues independently, including when a speculative B-to-A migration is
discarded. State tests now pass 27/27, arbiter tests 29/29, and two handler tests
prove descriptor/scene propagation and exact one-stop/one-restart behavior.

`EXP-064` adds the missing retained-reader path: `updateUIView` rebinds and
re-registers its observer, an actual mount is reported independently of ordinary
updates, and an unchanged attachment is not treated as a new navigation
occurrence. Its first green revision passed 61/61 focused cases and 1,096/1,096
RUM tests, but review found that deferred reconnect could lose remount
authorization and that repeated unchanged updates could restart a normally
disappeared retained view. That revision is evidence for the integration seam,
not the final correctness claim.

`EXP-065` hardens the seam. Initial-trait input is now accepted only for the
first clean mount, an inactive view waits for a real semantic appearance after
reconnect, cancelled reconnects rearm the retained reader, and source-scene
disconnect cannot discard a pending migration to another scene. Observer
registration retains its last proven scene across detachment so an old A reader
cannot contaminate B's coordinator selection. A reader mount merged with a
disappear retains its authorization until success or cancellation resolves it.
Focused coverage is 34/34 state, 38/38 arbiter, and two handler tests (74/74);
the full RUM plan is 1,108/1,108 and final review found no P0/P1 issue. This closes
the source/focused-test gap.

`EXP-066` exercises the retained-reader integration through explicit fault
injection while both native scenes and the same B representable remain alive.
The old B Detail occurrence stops once, a fresh B Detail occurrence starts once,
its action/resource use the new UUID, A is untouched, and backend intake agrees.
This is runtime/payload/backend evidence for the handler, arbiter, and retained
update seam; it is not a genuine OS disconnect/reconnect or restoration result.

`EXP-090` through `EXP-099` close the next experimental runtime question without
changing customer SwiftUI identity. A debug-only keyed binding creates distinct
same-named Detail₁/Detail₂ RUM UUIDs while preserving one customer state token;
a same-turn push/revert creates no destination occurrence. A normal pop initially
created returned Home too late for its immediate marker. Hidden-reader `.id`,
observer rebinding, and stale-callback hypotheses all failed. Diagnostics in
`EXP-097` established the actual state: SwiftUI retains Home but reports its
platform reader as detached while Detail covers it. The corrected per-window
source may therefore reuse only Home's last concrete scene proof, only for a
previously started and currently inactive matching occurrence. Scene disconnect
clears that proof and fences reuse until a newer concrete mount.

`EXP-098`/`EXP-099` backend-prove the result. Returned Home receives a fresh UUID
before `onAppear`, its immediate action/resource use that Home₂ UUID, and the same
customer state token survives. Source delivery goes through the existing
interactive arbiter. At that checkpoint, focused source coverage passed 13/13,
including cancellation,
completion, ordinary detach, explicit unresolved attachment rejection,
disconnect/remount, scene migration, stale/duplicate generations, and same-key
A/B isolation. `EXP-100` is deliberately not native interactive evidence: both
synthetic edge drags were ignored before any path, coordinator, source, or
lifecycle signal. A human-driven physical-device run remains required. The source
is internal debug integration evidence, not a supported automatic tracker or
public API. `EXP-104` extends this to a retained split route whose platform subtree
is rebuilt. It caught a real handoff bug: the old state stopped the source-started
returned Detail occurrence and the replacement state started a duplicate.
`EXP-105` passes after the replacement adopts the already-published identity and
owns its eventual stop. Focused source coverage is now 17/17 and also proves that
only the newest eligible registration reveals a route and a superseding reveal
cannot leave the prior state's disappearance suppressed.

`EXP-067` finds that `NavigationSplitView` and `UISplitViewController` still have
no committed route-occurrence or destination-selection model. The approved model
has one current RUM destination per scene: Primary/sidebar/container panes are
structural context and must not become concurrent or transitional RUM views.
SwiftUI same-type selection can be invisible when it retains the hosting item.
UIKit lifecycle ordering can restart a still-visible Primary between two
Secondary occurrences, and an application split-controller subclass can become
an extra RUM view. `EXP-068` confirms the
SwiftUI half in regular width: Detail(1) → Detail(2) retained the same adjacent
platform witness, reused one RUM UUID, and attributed Detail(2)'s action/resource
to Detail(1); different-type Placeholder started correctly without an invented
Sidebar/Home interval. `EXP-069` confirms automatic split tracking emits no
semantic Detail(1), Detail(2), or Placeholder views and attributes their markers
to launch or hosting-controller views. `EXP-070` restores the exact semantic
chain and marker ownership with `.id(selection)`, but replaces the adjacent
content witness and therefore cannot be the customer solution. `EXP-102` removes
that content-identity compromise in the route-owned probe: one retained Detail
witness advances through Detail₁, Detail₂, and Placeholder while keyed RUM
generations create three exact occurrences and marker pairs. `EXP-103` repeats
the result independently in A and B, yielding six exact semantic occurrences plus
launch. Its telemetry was accepted before final hierarchy capture crashed the
simulator's `backboardd` Metal process; the probe app produced no crash report.
This is a split occurrence and attribution pass, but not stable simultaneous-
visible or SDK crash evidence. `EXP-104`/`EXP-105` then exercise
Detail₁ → Detail₂ → Placeholder → Detail₂(returned). The failure run exposed a
short ghost returned occurrence; the fixed run emits one fresh returned-Detail
UUID and attributes its immediate action/resource to it while preserving customer
content identity. Adaptive collapse/expand remains open. `EXP-071`
backend-proves the UIKit ordering failure: removing Secondary₁ immediately
restarts the same continuously visible Primary before Secondary₂ appears.
`EXP-072` additionally proves that an application-subclassed split container is
tracked as a short-lived view under the default bundle-based predicate. The
ordering and predicate issues require separate compatibility decisions.
`EXP-073` proves the ordering failure is not limited to replacing a split column
root: push and pop inside one stable secondary navigation controller each restart
the continuously visible Primary. The returned controller already receives a
fresh RUM UUID, so the fix must remove only those false sibling-column intervals
and retain occurrence-per-path semantics.
`EXP-074`/`EXP-075` validate the resulting iOS 27 multi-scene-only coalescing
candidate in both native controls. Stock root replacement emits launch → Primary
→ Secondary₁ → Secondary₂. Nested push/pop emits launch → Primary →
Secondary₁(first) → Secondary₂ → Secondary₁(returned); the same returned
controller receives a fresh RUM UUID. Marker attribution is exact and neither run
restarts Primary during navigation. These runs fix the lifecycle-ordering defect,
but at that checkpoint the initial Primary remained a known semantic gap under
the approved one-destination model. `EXP-112` later closes the stock regular-width
case; the subclass-container predicate issue from `EXP-072` remains separate.
Post-run review found two adjacent lifecycle flaws rather than invalidating that
core handoff: an unrelated same-scene appearance could consume the pending item,
and background flush could briefly start Primary before suspension. `EXP-077`
closes both plus disconnect timing in 57/57 handler tests. The authoritative
`EXP-079`/`EXP-080` reruns preserve the same exact backend paths and returned-view
UUID semantics on the hardened revision, with no errors or crashes.
`EXP-082` adds a physical edge-swipe commit and `EXP-083`/`EXP-084` add a
deterministic public-UIKit cancel/finish pair. UIKit emitted speculative lifecycle
on cancellation, but RUM retained the original S2 UUID; each committed pop gave
the reused S1 controller a fresh RUM UUID, with no restarted Primary during the
transition. Their initial Primary remains historical evidence, not accepted final
semantics.
`EXP-112` turns that deterministic pair into exact signal-driven acceptance and
closes the stock regular-width Primary gap for the target runtime. For declared
multi-scene applications on iOS 27, the handler classifies concurrently displayed
Primary and supplementary split columns as structural and does not start RUM
views for them. It keeps legacy behavior for ordinary apps, compact layouts, and
older systems. The final clean cancellation run retained one S2 UUID and passed
11/11; the final completion run emitted S1(first) → S2 → fresh S1(returned) and
passed 13/13. Every required action and Resource used the resolved destination,
backend intake reported no errors, and no Primary view appeared. The native
SwiftUI host's short automatic fallback still precedes S1 but owns no probe work;
the application-subclassed split container from `EXP-072` also remains open.
`EXP-086` then overlapped A and B transitions. B completed its exact path while
A stalled after B became fullscreen; the capture lacks activation-state callbacks,
so this is a topology limitation rather than an SDK defect. Its A marker used B
because the public manual calls had no SDK source after B became representative,
which is the approved fallback. `EXP-087` proves an empty split selection creates
no Detail occurrence. Adaptive collapse remains unrun because CoreDevice reports
that this simulator lacks Resizable App Management.
Restoration, type-erased paths, unbound destination links, and mixing rules also
remain unresolved. A binding mutation is not a RUM occurrence by itself, but
each materialized committed path step is—including a newly revealed Home after a
pop when the platform object is reused.

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

The `EXP-085` Xcode 27 interface/source audit confirms that the remaining public
SwiftUI surface narrows the viable automatic design.
`NavigationStack` exposes a bound homogeneous route collection or
`NavigationPath`, but no API reports the currently visible semantic destination
before customer lifecycle work. A typed `[Route]` can be mapped by an explicit
route-to-RUM-view resolver; heterogeneous `NavigationPath` exposes mutation,
count, and codable representation but no public last-element iteration.
`NavigationLink(destination:)` supplies no authoritative bound path at all. The
credible boundary is therefore an opt-in scene-root navigation integration that
observes or owns semantic route mutation before SwiftUI constructs the next
screen. A root modifier alone cannot cover destinations, inferred destination
types cannot prove committed visibility, and late reconciliation cannot invent
the missing Home identity. The exact customer API and coexistence rules with the
automatic predicate require RFC review. Internally it must keep route frames
separate from occurrences so a completed return starts Home₂, while equal/no-op
path updates and cancelled transitions create nothing.

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
`EXP-088` closes one bounded omission: manual actions and all manual Resource-start
overloads now consume the same execution-local exact view or scene when invoked
inside that handoff. Resource completion stays routed by its frozen start owner.
Source-less calls outside the handoff remain representative. `EXP-089` exercises
the physical filtered-control path through backend intake, but switching from
fullscreen B to A created a fresh A occurrence before the tap. It therefore
confirms live capture and representative fallback, not exact-handoff precedence
over a different representative.

Important limits remain explicit. Generic source-less manual APIs and feature-
flag messages use the process representative, which normally follows the most
recently tracked interaction. Operation steps first use their last-proven view
snapshot when one exists. Early scene
connection and `viewDidAppear` requests can also reach the previous representative
before the new scene's first RUM view exists; this matches the approved fallback
but is not exact attribution. UI-triggered manual action and Resource-start APIs
now consume the bounded handoff when it exists; focused tests prove precedence,
while the first live run did not keep a different representative. Callers outside
that path remain inherently ambiguous. Main-run-loop long tasks, hangs, and other process-wide
signals also use one representative rather than being duplicated. Correcting
automatic SwiftUI view discovery, split-view navigation, restoration, profiling
correlation, external-display refresh rate, and iPhone Duo validation remain open.
Session Replay scene-correctness is out of scope; repeated two-window runs uploaded
replay data without an SDK crash, which is the required contract here.

The product contract now removes two earlier ambiguities. First, a scene has one
current destination: split sidebars, tab bars, and containers are structural, not
parallel RUM views. Second, scene-aware manual view start/stop is required so the
same customer key can exist in A and B and an exact stop closes only its targeted
scene; existing source-less methods keep their inferred/last-interacted behavior.
Both the manual Swift/Objective-C surface and the optional container-level SwiftUI
semantic integration require normal API review. Internal scene ownership must
also remain suitable for a future Window Execution Context ID, but this project
adds no temporary attribute, session boundary, or wire-format concept and does
not wait for backend visualization.

## Objective progress review

This review measures the branch against the initial support objective rather than
against the amount of implementation completed:

| Objective | Current evidence | Remaining release work |
| --- | --- | --- |
| Concurrent view creation and lifetime | UIKit and explicit SwiftUI windows coexist in one session; the iOS 27 early-mount candidate preserves exact A/B lifecycle work; route-owned controls publish semantic roots and destinations; `EXP-090` proves a RUM-only occurrence change preserves customer SwiftUI state, `EXP-098` reveals retained Home before immediate work, and `EXP-105` preserves that occurrence across a subtree remount | Automatic native `WindowGroup` still lacks the approved optional container-level semantic integration and authority/dedup rules. Finish that review plus simultaneous visibility, construction, restoration, and iPhone Duo validation |
| UIKit and SwiftUI navigation | UIKit push/pop/modal and explicit SwiftUI stack/modal flows preserve one UUID per committed path occurrence; signal-driven stack return, abort, same-/different-type replacement, split replacement, retained split return, and UIKit cancel/finish pass locally and in backend intake. The matching automatic SwiftUI split control fails with no semantic destination views. Stock regular-width UIKit splits no longer start or restart structural Primary/supplementary views; cancellation retains S2 and completion creates fresh S1 | Turn the debug route source into the reviewed optional semantic container integration, prove recognized native SwiftUI cancel/finish and exact activation on hardware, then cover startup/subclass containers, adaptive resize, simultaneous-visible A/B completion, restoration, and ordinary-app compatibility |
| Action attribution | Source-bearing UIKit/SwiftUI taps emit once; exact-view actions update the representative; execution-local manual action/error/view mutations and internal view work prefer exact handoff view/scene; `EXP-098` attributes immediate returned-Home work correctly and source-less work keeps last-interacted fallback | Repeat manual-handoff precedence with B representative and A visibly interactive; finish UIKit scroll/deceleration and targeted downstream runtime rows |
| Scene lifecycle and sessions | Requested destruction/close preserves delayed ownership; exact A-to-B open and B close wait for B readiness/disconnect, and post-close A work keeps A's original Home UUID; exact activation and current-state lifecycle conditions are implemented in the probe; disconnect invalidation, retained-reader rearming, migration, and stale-observer isolation pass; explicit stop/expiry restore concurrent branches; the probe registry models exact logical/native identity without retaining windows or serializing its future Execution Context seam | Prove activation plus peer background and stable simultaneous-visible peer close on capable hardware, then genuine OS disconnect/reconnect, per-scene background/foreground, concurrent restoration, and the equivalent shipping ownership path ready for future Window Execution Context mapping; backend visualization is follow-up work |
| Resources, traces, and operations | Start provenance and Resource completion ownership are frozen; manual Resource starts, automatic URLSession completion, and native/OpenTelemetry span starts use scene handoff; Operations use application-wide typed identities and per-step resolution with focused cross-window tests | Finish bounded live causal/reverse-completion rows, exact different-representative proof, live Operation A-to-B/duplicate-start proof, and public Operation target review |
| Errors, logs, WebView, vitals, fatal/exported context, and profiling | Scene-aware source or focused tests exist for each except profiling, whose process-level limitation is known | Targeted two-window runtime/backend evidence; profiling needs an explicit support statement, not guessed per-scene ownership |
| Normal-app compatibility | RUM 1,153/1,153 and Trace 151/151 pass; complete Internal/Logs/WebView suites, probe builds, package build, and repository lint pass | Live single-scene behavior, custom-handler integration, and `sendEvent` overhead/recursion measurement |
| Session Replay | Multiple UIKit/SwiftUI two-window and teardown runs uploaded replay data without an SDK crash | No scene-correctness work required for this objective |

The probe registry and observable-driver portions of `EXP-108` through `EXP-114`
are evidence-harness improvements. `EXP-112` separately includes the shipping
structural UIKit split-column fix. The initial Home mapper
snapshot can still precede native scene resolution;
the stable logical scene label can be joined to the exact native session once the
scene becomes ready, while release support still requires the production RUM
scope to preserve its own reliable scene ownership.

The core model is no longer the largest unknown. `EXP-079`/`EXP-080` pass the
UIKit split ordering controls that failed in `EXP-071`/`EXP-073` on the
post-review `EXP-077` revision, while retaining their historical initial Primary.
`EXP-082` through `EXP-084` pass physical commit and deterministic cancel/finish
without restarting it. `EXP-112` suppresses the structural Primary in the stock
iOS 27 multi-scene path and reruns cancel/finish through exact observed signals
and backend intake. `EXP-086` proves overlap but not simultaneous
visibility or A completion, and `EXP-087` passes only the empty-selection half of
adaptive preflight. Subclass compatibility, capable-destination resize, live
lifecycle, and ordinary-app behavior remain.
`EXP-068`/`EXP-069` reproduce route-owned and automatic SwiftUI split failures;
`EXP-090`, `EXP-098`/`EXP-099`, and `EXP-102` through `EXP-105` now prove the
RUM-only identity, retained return, same-type split replacement, and retained
split-remount mechanics without customer-state reset. The named recorder,
fixture-backed oracle, registry, and driver now have three-run mapper/backend
agreement for a complete Home₁ → Detail → Home₂ timeline (`EXP-109`) plus stack
abort and same-/different-type replacement (`EXP-110`). Signal-driven split
replacement and retained return also pass, while the exact automatic control
fails on launch/internal host ownership (`EXP-111`). The same driver proves UIKit
cancellation and fresh return semantics in `EXP-112`; `EXP-113` then drives exact
A-to-B open, exact B close, and post-close A work through readiness/disconnect
acknowledgements. `EXP-114` prepares exact activation and rejects missing peer
lifecycle as inconclusive; its simulator runs do not close the hardware evidence
row. The debug source moves
toward the approved optional container-level semantic SwiftUI integration,
which must coexist with automatic discovery and suppress duplicates only in its
target. Real-device and
human-driven gaps are explicitly queued in `EXPERIMENTS.md`; ignored synthetic
gestures are not counted as cancellation evidence, and a simulator system-process
crash after accepted telemetry is not counted as an SDK crash.
`EXP-066` closes only the synthetic retained-reader integration row; genuine OS
reconnect/restoration remains in the lifecycle matrix. The remaining
navigation/lifecycle/action rows and proof that ordinary apps do not pay a
behavioral or performance cost follow. No additional distributed-tracing or
header-repair work is justified unless one of the pending causal experiments
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
| SwiftUI `.task` and `onAppear` loading | Pre-trait explicit experiments `EXP-010` through `EXP-012` failed; trait experiments `EXP-013` through `EXP-015` achieved correct queued attribution; `EXP-030`/`EXP-031` proved modifier placement alone insufficient; the iOS 27 early-mount candidate then mapped every marker correctly in `EXP-032`/`EXP-033`. `EXP-056` maps route-owned on-appear/immediate work correctly but classifies an A delayed manual call after B activation as source-less representative fallback. Automatic UIKit-hosted and native work still uses preceding views, and `EXP-029` rules out a usable transparent hosting-controller boundary | Backend-pass for exercised iOS 27 explicit route creation; source-less delayed manual work is intentionally representative. Finish construction stress; automatic initial-root/destination attribution still needs reviewed semantic integration |
| Scene connection and UIKit `viewDidAppear` loading | `EXP-006` and `EXP-016` used the prior representative before the new view existed | Backend-classified as source-less |
| Pre-created URLSession task resumed from a UI action | `EXP-006` selected B Detail and the resume action at interception rather than object creation | Backend-pass |
| One shared/coalesced request used by both scenes | Probe control exists; no conclusive two-window run | Pending; expected to remain ambiguous |
| Navigation and session rollover before actual request start | Navigation-at-resume passed in `EXP-006`; `EXP-007` exposed rollover loss and `EXP-008` verified the fix | Backend-pass |
| Reverse-order completion from two scenes | RUM and Trace focused tests pass with frozen A/B owners | Runtime/backend pending |
| Source scene closes before completion | `EXP-019` preserved delayed resources and traces; `EXP-020` preserved the fixed operation | Backend-pass |
| Concurrent operations with identical `(name, key)` | Contract decided and focused test passes: the second start emits normally and replaces only local tracking; one later end closes the latest start, with no synthetic client-side end | Live warning/raw-vital proof pending; the earlier backend operation is expected to remain open until its four-hour timeout |
| Trace-only URLSession span | Probe control and four Trace ownership regressions exist | Runtime/backend pending |
| Action accepted, rejected, already active, and expired | `EXP-006`, `EXP-002`, `EXP-003`, and `EXP-007` cover accepted/filtered, fan-out failure/fix, and expiry; `EXP-088` routes manual actions and Resource starts through an available event handoff; `EXP-089` physically exercises the filtered control | Backend-pass for automatic cases; exact manual-handoff precedence needs simultaneous A/B visibility; the post-scope source-less pair correctly used last-interacted A |
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

## Released baseline assessment

Everything in this section describes commit
`92f021ba7e4a866f84a52da93ed8b63f3dc75882`, before this branch's changes. It is
kept as the causal baseline and must not be read as the current worktree state.

### View instrumentation and navigation

`RUMViewsHandler` owned one process-wide `stack`. When a view appeared, it stopped the
last view in that stack before starting the new one. When a view disappears, it can
restart only the previous item in that same stack. There is no scene identity in
the stored view or in `RUMStartViewCommand` / `RUMStopViewCommand`.

Consequences for two visible windows A and B:

1. A starts view A1.
2. B starts view B1 and the SDK stops A1 even though A1 remains visible.
3. Navigation in A starts A2 and stops B1 even though B1 remains visible.
4. A disappearance can reveal or restart a view from B because the histories are
   interleaved in one stack.

UIKit callbacks retained a `UIViewController`, from which a `UIWindowScene` could
usually be determined. Automatic actions received a `UIEvent` and touch view,
which also normally retained window/scene identity. That information was
discarded at the baseline.

SwiftUI modifier callbacks carried only a string view identity or action name. The
same modifier identity used in separate windows can therefore collide, and there
is no scene identity at the command boundary. Automatic SwiftUI navigation is
ultimately observed through hosting view controllers and has the same global-stack
problem. `NavigationSplitView` coverage must be validated separately.

### Session model and downstream attribution

`RUMSessionScope` could keep several view scopes, but exposed one `activeView`
chosen from the most recently active scope. Starting a new view deactivated the
previously active view. Commands without their own view identity were processed
against that single active view.

This affects at least automatic actions, manual actions, scrolls, resources,
errors, long tasks, vitals, feature operations, interaction-to-next-view metrics,
Session Replay context, tracing correlation, crash/fatal context, and the public or
internal RUM context exported to other SDK features. Some event types have their
own asynchronous context capture and may behave better than this baseline implies;
each must be tested rather than assumed.

### Lifecycle

Baseline view instrumentation observed process-level application background and
foreground notifications. A scene becoming inactive, entering the background, or
disconnecting is not equivalent to the whole application doing so. Conversely,
closing one scene must not stop unrelated scenes or end the process session.

The baseline integration runner had a `UISceneDelegate`, but its Info.plist set
`UIApplicationSupportsMultipleScenes` to `false`. It could exercise scene
lifecycle plumbing but not two concurrent windows. The baseline Example target
had no scene manifest and created one app-delegate-owned window.

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
- **Feature operations and feature flags:** commands and message-bus payloads did
  not carry a scene or view target, so operation steps could inherit the wrong
  process-representative view. Operation identity was process-global by design:
  the same `(name, operationKey)` in two scenes denotes one logical identity, not
  scene-disambiguated instances. A separate delimiter-concatenation collision for
  distinct tuples existed in profiling bookkeeping.
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
| UIKit navigation | Navigation histories from all scenes interleave; default controller discovery can model structural split panes as destinations | Baseline global stack; branch isolates navigation per scene, coalesces outgoing/incoming split-column transitions, and on iOS 27 ignores regular structural Primary/supplementary columns only for declared multi-scene apps | Pushes, duplicate-name views, modal presentation/dismissal, and scene closure affected only the source window. `EXP-112` signal-drives cancel/finish: cancellation retains S2 and completion creates fresh returned S1, with no Primary | Independent A/B histories and fresh return IDs persisted. Final `EXP-112` sessions have exact destination action/Resource pairs and no errors; historical sessions preserve the prior Primary failure | Stock regular-width isolation and structural filtering pass. Startup-host fallback, application-subclassed container, compact/adaptive, simultaneous-visible A/B, lifecycle/restoration, and live ordinary-app compatibility remain |
| Explicit SwiftUI view lifetime | Modifier identities can collide, detach can retain stale scene state, synchronous lifecycle work can precede the RUM start, and cancelled interactive navigation can publish speculative occurrences | Branch resolves the hosting scene only for declared multi-scene apps, keeps stable lifecycle identity, ignores transient detach, and bridges a scene custom trait into SwiftUI. On iOS 27 only, the explicit modifier uses that inherited trait at hidden-reader creation; older iOS, visionOS, and single-scene paths keep prior behavior. A scene/coordinator-keyed UIKit gate defers initially interactive lifecycle changes, validates recreated-view ownership after attachment, isolates unrelated same-scene work, and commits final state only on success | Three clean final-code A/B runs preserved all 72 lifecycle markers; five behavior-equivalent runs preserved all 120. Single-window, dormant destination, unselected tab, three-cycle push/pop, modal occurrence navigation, and one-scene restoration also passed. Immediate B close retained B ownership but the fullscreen topology backgrounded A. The rejected `ViewThatFits` child was never constructed, so that stress was inconclusive. `EXP-043` positively resolved the coordinator during the false cancelled-pop callback; `EXP-044` produced no false cancelled occurrence and a fresh Home on completed pop; `EXP-045` passes 19/19 state/provider isolation tests | Backend IDs confirm exact early candidate attribution, the baseline cancellation defect, and the corrected four-view `ApplicationLaunch → Home₁ → Detail → Home₂` result with exact marker attribution; `EXP-045` is focused-test evidence only | Experimental iOS 27 explicit path passes the exercised matrix; live concurrent-transition isolation, visible-peer close continuity, concurrent restoration/surviving-reader reconnect, and remaining construction containers stay open; no general SwiftUI ordering guarantee is claimed |
| Automatic SwiftUI view lifetime | Transparent hosting-controller discovery can select process-global history, run after lifecycle work, or miss semantic route changes | Core scene routing accepts discovered controllers; the route-owned prototype adds keyed state, atomic replacement, disconnect fencing, retained-reader handling, and a weak per-window committed-occurrence source without changing customer content identity | Automatic baselines remain wrong. Route-owned placement passes initial roots/destinations; `EXP-090` passes same-type replacement with one customer state token; `EXP-091` rejects an unmaterialized abort; `EXP-098`/`EXP-099` reveal retained Home before immediate work; `EXP-102`/`EXP-103` pass same-type split replacement in one and two windows; `EXP-105` preserves a source-started returned split occurrence across remount; `EXP-111` deterministically reruns split replacement under both modes and the automatic control fails 0/9. Source tests pass 17/17 | Backend distinguishes wrong transparent baselines from correct debug-source stack and split chains, including exact immediate markers. In `EXP-111`, automatic Detail₁ uses ApplicationLaunch and Detail₂/Placeholder share one internal hosting UUID | Automatic discovery remains the zero-code default, but exact semantics require the approved optional path/router integration; its reviewed API, container-scoped authority, and duplicate suppression are not implemented |
| SwiftUI navigation | Hosting controllers from all windows share history, transparent discovery may report containers instead of customer screens, and cancellation can publish an uncommitted path | Scene-keyed scope plus a bound typed path drives RUM-only occurrence generations; retained routes use last concrete scene proof only as guarded fallback; arbiter completion owns commit/cancel; a replacement tracking state can adopt a source-published occurrence | Explicit repeated push/pop and native/backend cancellation controls pass; debug source passes different-type, same-type, abort, retained Home, same-type split replacement, and retained split return without `.id`. `EXP-111` drives the split cases through observed selection/destination signals and passes 10/10 and 13/13. `EXP-100` gestures were ignored, so native interactive source delivery is still unproven; `EXP-103` ended with a simulator `backboardd` crash after telemetry acceptance | `EXP-090` emits distinct Detail UUIDs without customer-state reset; `EXP-098` emits Home₁ → Detail → Home₂ with exact immediate work; `EXP-102`/`EXP-103` emit exact split Detail₁ → Detail₂ → Placeholder chains; `EXP-105` adds one exact returned-Detail occurrence; `EXP-111` independently repeats those split chains with local oracle and backend agreement | Occurrence mechanics pass experimentally; implement/review one integration per navigation container using the customer's path/router and centralized resolver, then cover human-driven gestures, adaptive navigation, simultaneous-visible hardware, and restoration |
| Tap actions | Touch window is available but baseline routing loses it | Branch retains touch/modifier scene; automatic actions no longer fan out; exact-view actions refresh the representative; manual calls inside event handoff prefer exact view then scene and preserve fallback outside it | UIKit and SwiftUI source-window taps and controls pass; `EXP-089` proves physical filtering/fallback but not a different representative | Actions emit once on their originating view in exercised runs | Core and focused routing pass; exact precedence over a different visible representative remains a physical-device row |
| Scroll actions | Scroll callbacks have a view/window but no scene reaches the command | Branch retains source scene through drag and deceleration | SwiftUI scene D swipe emitted on D while another scene survived; UIKit scroll/deceleration remains to be repeated | SwiftUI D action retained D view | SwiftUI runtime passes; UIKit matrix remains open; focused tests pass |
| Resources and traces | A generic request/span has no intrinsic scene; representative fallback can be wrong | Branch has bounded UI-event/TaskLocal provenance, frozen owners, exact manual Resource start, owner-routed completion, automatic URLSession completion handoff, and native/OpenTelemetry span-start parity; detached/shared work remains ambiguous | Structured/UI-local work retains ownership; delayed completion survives source-scene closure; source-less schedulers use representative fallback | Existing backend runs show RUM/APM agreement and teardown ownership; different-representative and reverse-completion rows remain | Partial and bounded; focused ownership is broad, but remaining live discriminators and compatibility/overhead gates stay open |
| Manual errors and process-wide long tasks | Source-less APIs/signals have no unique scene | Manual errors consume exact event handoff when present; process-wide and source-less signals use one representative with no broadcast | Pending targeted manual-error rerun | Pending | Explicit exact-when-proven/fallback-otherwise policy; long tasks remain process-representative |
| Logs and mirrored errors | A log and its later RUM error can resolve different global views | Branch snapshots request-local RUM context and preserves exact or same-scene routing for the mirrored error; legacy no-scene work retains representative fallback | Pending fixed-runtime rerun | Pending fixed-runtime rerun | Captured-view mirroring fixed and unit-validated; targeted two-window runtime proof remains open |
| Vitals, TNS, and INV | Process vitals overlap; navigation edges could cross scenes | Branch has one INV tracker per scene; TNS follows resource owner; vitals remain process-derived per view | Pending | Pending | INV/TNS fixed; vitals policy and external displays remain partial |
| Feature operations and flags | Delayed steps receive the global active view; string-concatenated identities can collide in both RUM and Profiling; permanently pinning later steps to the start scene would misrepresent cross-window work; closing the last proven view can drop an end step | Branch uses typed `(name, key)` identity in RUM and Profiling, independently resolves each step, refreshes a last-proven view snapshot only from trustworthy context, and uses that snapshot before representative fallback | Focused tests cover A-to-B success/failure, A1-to-A2 navigation, parallel keys, reverse completion, explicit/inferred override, duplicate starts, teardown, and profiler key collisions; `EXP-020` emitted both steps after the source scene closed | The reducer produced the successful closed-scene operation in `EXP-020`; live A-to-B backend proof is pending | Internal lifecycle, attribution, and Profiling identity contract implemented; public target API and live cross-window/duplicate proof pending; flags remain open |
| Session rollover | A process-wide stop/expiry can lose still-visible views or revive the view being replaced | Branch snapshots every active foreground scene and now restores only branches unaffected by a scene-targeted start/stop | Explicit stop followed by B Home -> Detail initially dropped A; fixed rerun emits new A Home and B Detail views | New explicit-stop session contains both raw view documents and the delayed B request remains on B Detail; reducer converged to `view.count:2` | Fixed for explicit stop, inactivity, and max duration; product UI rendering of overlap remains unchecked |
| Session Replay | Recorder/context mapping may follow an arbitrary scene's key window | First key window across an unordered scene set; one coordinator | Repeated two-window UIKit/SwiftUI runs, navigation, and scene teardown completed without an SDK crash | Replay was available on the broad and post-fix sessions | Out of scope except crash safety; coexistence requirement passes for the exercised matrix |
| WebView correlation | Browser events can be stitched to another scene's native container | Branch carries private source-scene metadata and queries scene-keyed view history | Pending fixed-runtime rerun | Pending | Fixed in branch; three focused tests pass |
| Profiling | Profile-level RUM attributes are last-writer-wins across views | One mutable correlation snapshot | Pending | Pending | Confirmed by source |
| Crash/fatal context | Any view update can overwrite one process crash context | Branch restricts updates to the representative and restores another active scene when needed | Pending | Pending | Fixed to representative policy; focused tests pass |
| App/scene lifecycle | Per-scene transitions are invisible to baseline view ownership | Branch observes lifecycle per scene; teardown aligns handler and fresh/retained-reader state, clears last-proven scene proof, fences stale callbacks, rearms cancellation, preserves migration, and isolates observers. The probe dispatches activation through an exact registered scene and waits on the latest non-superseded lifecycle state | Requested destruction stopped only source views; `EXP-113` exact-opened B, exact-closed B, and continued A on its original Home UUID; `EXP-114` could not obtain the required peer-background transition before a simulator compositor crash; synthetic retained-reader remount passes; real reconnect is still unrun | B's marker pair uses B Home, A's post-close pair uses unchanged A Home, and destroyed-scene views become inactive without replacing the survivor. `EXP-114`'s completed source-less control reached backend intake but is not exact activation evidence | Exact open/close passes; human/device queue owns activation, live reconnect, restoration, simultaneous-visible peer continuity, and per-scene background/foreground |
