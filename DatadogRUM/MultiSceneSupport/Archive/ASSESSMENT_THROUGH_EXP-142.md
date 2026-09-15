# RUM multi-scene assessment and evidence

Read this document when you need the detailed support verdict, source-level
baseline, causal-attribution boundaries, or the evidence status for each SDK
surface. Start at the [canonical overview](../MULTI_SCENE_SUPPORT.md) for the
current checkpoint and next action.

Evidence references use the stable `EXP-*` identifiers from
[EXPERIMENTS.md](EXPERIMENTS.md), which owns exact run and session identifiers.

Last updated: 2026-09-15

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
The structural UIKit split fix adds two regressions and that complete RUM
plan passed 1,153/1,153. The SwiftUI authority slice adds four regressions and its
checkpoint RUM plan passed 1,157/1,157; Trace remains 151/151, including 4/4 focused OpenTelemetry
handoff tests. Repository lint passes all 713 source and 699 test files. The
structured probe recorder, mapper reducer, semantic oracle, exact main-actor
scene registry, and observable stack/split/UIKit/lifecycle/coexistence driver now
pass 135/135 tests (`EXP-108` through `EXP-142`). The exact-scene manual-authority
regression set passes 8/8, and the focused presentation plus approved manual
contract set passes 6/6. The first complete RUM run passed 1,164/1,165; its
only failure was an unrelated timeseries timing assertion that passed immediately
in isolation. A clean complete rerun then passed 1,165/1,165. Three clean iPadOS
27 Home → Detail → Home runs each
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
`EXP-115` then enables automatic discovery at the same time as the explicit
route-owned tracker. An active, attached explicit reader suppresses only a
containing automatic controller hierarchy; unrelated siblings stay eligible and
UIKit acceptance is unchanged. The clean 7/7 run and backend intake contain
exactly ApplicationLaunch, Home H1, Detail D1, and Home H2, with distinct Home
UUIDs and no hosting-controller duplicate. This validates the internal authority
mechanics, not the once-per-container customer API or transparent automatic
navigation semantics.
`EXP-116` supplies the missing integration-shape experiment without adding public
API. One probe wrapper consumes the bound `NavigationStack` path and centralized
route resolver, then applies the proven route-owned boundary at the root and each
materialized destination. Clean return, aborted-push, and same-type-replacement
runs pass locally and in backend intake. Home H1/H2 and same-named Detail 1/2 use
distinct UUIDs, the abort creates no Detail, and final action/Resource work uses
the committed occurrence. `EXP-117` separately proves that the in-app clean flag
does not provide host isolation: two back-to-back Xcode launches created correct
local timelines but view documents retained the prior run's global probe
attribute. Those runs are local-only evidence and were superseded by explicit
uninstall reruns.
`EXP-118` adds a scene-selective coexistence discriminator: automatic SwiftUI
tracking remains enabled application-wide while the semantic container boundary
is present only in scene A. Two explicitly uninstalled simulator runs kept A's
marker pair on semantic Home H1 and independently created automatic fallback and
navigation-host views in scene B after B opened, proving that A's authority does
not suppress automatic discovery globally. Both runs ended in a simulator
`backboardd` Metal/CoreAnimation abort before the decisive B marker and terminal
oracle result. The prefix is positive scope evidence, but the full scenario is
hardware-inconclusive and still requires an exact physical-device run plus
backend confirmation.
`EXP-119` then covers an exceptional explicit Sheet over an otherwise automatic
hierarchy. Mapper output and backend intake contain automatic Home H1, explicit
Sheet S1, and fresh automatic Home H2 without an automatic Sheet duplicate. The
run fails at the return boundary: Home-source work in SwiftUI's immediate
`onDismiss` callback still owns S1 because H2 starts afterward; settled work owns
H2. This confirms coexistence and exposes a real semantic-attribution gap.
`EXP-120` then tests the existing direct keyed manual API over automatic Home H1.
It fails more fundamentally: manual Compose M1 stops 31–48 ms after starting,
automatic discovery installs a fallback while the manual authority interval is
still open, and all decisive Compose action/Resource work belongs to that
fallback. Stopping M1 eventually leads to fresh automatic Home H2, which owns
only the settled pair. Local mapper and backend data agree. The raw final run
also exposed an oracle-only issue: deferred H1 stop arrived after M1 stop, and the
matcher initially rejected the unrelated stop rather than scanning onward. The
fixed matcher finds the exact later H1 stop; the product failure remains the
fallback that preempts M1. The native SwiftUI host's startup fallback owns no
probe work in `EXP-119`, but its later fallback is the wrong owner in `EXP-120`.
Native gesture synthesis remains unavailable, but it no longer blocks exact
programmatic scenario driving.
`EXP-121` switches only the probe call site to the new internal exact-scene
manual-stack path. That run proves authority fixed: M1 remains current and owns
its active action/Resource. It still fails because a generic automatic hosting
fallback is staged below M1 and revealed for immediate post-stop work before the
real H2 owns settled work. Commit `b1a0fb6b8` retains the last semantic
destination through that structural churn and rejects known generic SwiftUI
hosting/navigation-stack fallbacks while manual authority is active. The clean
`EXP-122` successor passes 16/16 with exactly H1 → M1 → fresh H2, no intervening
fallback, active work on M1, and immediate plus settled return work on the same
H2. Backend intake agrees across 28 exact-run documents and reports zero errors
or crashes. This closes the internal authority/reveal mechanism; the public
Swift/Objective-C scene overloads and two-live-scene same-key proof remain open.
`EXP-123` applies that exact handler path to a semantic Sheet and proves it is
only half of presentation coexistence: automatic discovery still emits a
redundant `ProbeSheetView` presentation host and structural navigation-host
churn. Commit `f452e9e3f` adds a suppression-only authority state mounted in the
presented subtree while the router remains the sole publisher of its semantic
RUM lifecycle. `EXP-124` then produces the correct H1/M1/fresh-H2 view set and
owners but exposes a harness error: M1's final aggregate snapshot is delayed by
a pending Resource and therefore cannot delimit semantic authority. Commit
`fad83f58f` separates router authority from native subtree lifetime. The clean
`EXP-125` successor passes 14/14 with no automatic Sheet, active work on M1, and
immediate plus settled dismiss work on the same fresh H2. Backend intake agrees
across 29 events and reports zero errors or crashes. The complete RUM suite now
passes 1,169/1,169. Commit `c70920c94` adds an independent `fullScreenCover`
discriminator. Its clean `EXP-126` successor also passes 14/14 with H1 → semantic
Cover M1 → fresh H2, no automatic `ProbeFullScreenCoverView`, active work on M1,
and immediate plus settled work on H2. Exact backend intake contains 28 events—
five views, ten actions, ten Resources, one long task, one vital, and one session—
with zero errors or crashes. At that checkpoint the probe passed 69/69. This closes the internal
complete-destination presentation slice for Sheet and full-screen cover, but not
the reviewed public semantic API.
`EXP-127` then mounts two independent `NavigationStack` controller branches under
one outer SwiftUI host. Its required ancestry witness proves that the left manual
authority boundary and the right automatic Home/Detail branch are siblings, not
one nested candidate. While manual M1 is current, the right-hand Detail commits
without emitting an intermediate current view; exact stop reveals only that
latest Detail as a fresh occurrence, and immediate plus settled work uses the new
Detail ID. The first pass is retained because the probe-only ancestry reader
became a late fifth automatic view. After filtering that exact measurement type
and making the topology assertion mandatory, two clean runs pass 19/19. The final
backend session contains exactly launch, Home H1, manual M1, and fresh Detail D1,
with 11 correctly attributed action/Resource pairs and zero errors or crashes.
At that checkpoint the probe passed 76/76. This closes internal
sibling-container isolation; the
public semantic API and broader scene/hardware matrix remain open.
`EXP-128` adds independent runtime proof for the remaining one-scene manual-stack
rules. The real SwiftUI hierarchy produces automatic Home H1 → Compose C1 →
Preview P1 → fresh Compose C2 → fresh automatic Home H2. The duplicate active
Compose start creates no restart or additional view, and its action/Resource pair
stays on C2. Immediate and settled work after each exact stop use the newly
revealed occurrence. The first attempt is retained as a harness failure: C1's
mapper snapshot preceded the driver's wait step. Exact immutable RUM-occurrence
waits now search already-recorded evidence, and the clean retry passes 29/29.
Backend intake confirms all five semantic IDs after the two startup views, 15
actions, 15 Resources, and no error or crash.
At that checkpoint the probe passed 83/83. This closes the one-scene nested/duplicate runtime
discriminator; same-key A/B isolation and public Swift/Objective-C review remain.
`EXP-129` prepares that same-key A/B discriminator without weakening its live
gate. It starts `compose` independently in A and B, stops B before A, and rejects
shared UUIDs, cross-scene work, B preemption of A, and reused returned-Home
occurrences. The hostless plan passes 91/91. Its explicitly uninstalled iPad
simulator attempt resolved distinct native A/B scenes and reached B readiness,
then lost the Xcode/device session amid CoreAnimation/BoardServices interruptions
before either manual start. No terminal result or backend document exists, so
same-key live isolation remains hardware-inconclusive rather than failed.
`EXP-130` then closes the single-scene Operation/navigation runtime row. The
driver invokes success across Home H1 → Detail D1, failure across Home H2 →
Detail D2, and a duplicate identity across Home H3 → Detail D3 before succeeding
the latest start. Its local scenario passes 27/27 and the full probe plan passes
93/93. Backend intake contains seven raw Operation steps and three reduced
Operations. Success and failure preserve
their different start/end view IDs. The duplicate reduces from D3 to D3 while
the earlier H3 raw start remains open, with the corrected four-hour-timeout
warning and no synthetic end, error event, or app/SDK crash. This proves
independent per-step navigation attribution and duplicate semantics; cross-scene
A-to-B completion plus the public target remain open.
`EXP-131` prepares that cross-scene runtime discriminator without weakening its
acceptance gate. It drives A→B success and failure, plus distinct-key parallel A/B
Operations completed B-before-A. The 100/100 hostless plan includes a passing
fixture and four adversarial ownership fixtures. The already documented simulator
topology expires during comparable simultaneous-window runs, so no live/backend
claim is made; the exact named scenario remains queued for capable hardware.
`EXP-132` closes the independent UIKit scroll/navigation discriminator with a
real `UITableView` gesture. The measured lift exceeds the SDK's swipe threshold,
deceleration begins on Secondary 2, and Secondary 3 appears before deceleration
ends. Exactly one `.scroll` action remains on the stopped origin occurrence; the
fresh destination owns its immediate action and Resource. The local oracle,
mapper, and backend agree on type, count, and ownership, with no RUM error or
app/SDK crash. The full probe plan passes 109/109. This same-scene result does not
replace the hardware-gated A/B different-representative discriminator.
`EXP-133` closes the separate Trace-only URLSession owner-freezing row. A held
first-party request starts on A/Home H1, B/Home B1 becomes representative, and B
releases the response. The clean run passes 8/8; local mapping and exact backend
predicates contain one `urlsession.request` span on A/H1 and the original
session, zero on B/H1, and no matching RUM Resource. The probe plan now passes
115/115. This proves preservation of trustworthy request-time context through
completion, not discovery of an otherwise unknown simultaneous-window source.
`EXP-134` closes the independent two-request reverse-completion row for the same
automatic Trace path. A and B each start one held request; B completes first
while A is representative, then A completes while B is representative. The
14/14 local oracle and backend queries find exactly one span per request on its
own start-scene Home view, zero opposite-view matches, both on the expected RUM
session, and zero matching RUM Resources. The probe plan now passes 120/120.
This still does not disambiguate a genuinely shared/coalesced request or discover
an otherwise missing source.
`EXP-135` closes the separate ordinary SwiftUI Button → structured `Task` row as
a negative causal-boundary result. A hierarchy-derived physical tap emits exactly
one automatic action on A/Home H1. The SwiftUI button closure begins with
`RUMContextHandoff.current == nil`, and its child task also starts with no
handoff. `UITraitCollection.current` identifies A at callback and task start but
changes to B after suspension and B takeover. The resumed manual Action and
Resource therefore follow the approved source-less representative fallback to
B/Home H1. The strict expected-A oracle terminates `FAIL` after four matched
expectations, and backend intake independently confirms the same owners. This is
not a regression from existing compatibility behavior, but it disproves both a
zero-code task-local inheritance claim for ordinary SwiftUI buttons and an
ambient-trait async fix. Exact origin needs an explicit target or scoped customer
integration after API review.
`EXP-136` then adds one shared-request consumer without a second URLSession task.
The hostless contract requires a single span on the trustworthy A/Home creator.
Two clean iOS 27 simulator attempts rendered B and crashed `backboardd` in the
same Metal validation path before response release. The retry reached B's join
assertion first, proving the intended shared topology, but emitted no completion,
trace, or terminal result. The app emitted no RUM error/crash signal and has no
crash report; this is a physical-hardware acceptance row, not an SDK verdict.
`EXP-137` through `EXP-140` then replace the internal manual handler calls with
the proposed customer-shaped iOS 27 Swift SPI. Manual H1/M1/H2, nested
H1/C1/P1/C2/H2, Sheet, and full-screen-cover runs all pass locally and in exact
backend intake, with fresh returned occurrences, exact action/Resource owners,
no automatic presentation duplicate, and zero errors/crashes. The first nested
attempt is rejected because simulator-restored `WindowGroup` state kept the prior
run ID despite uninstall; normalization plus exact-session view inspection close
that harness gap. `EXP-141` then replaces the probe-only navigation wrapper with
the actual customer-shaped complete-destination SPI. Its one clean run passes
38/38 with distinct H1/D1/H2/Sheet/H3/Cover/H4 IDs, no automatic duplicate, and
correct action/Resource ownership before, during, and after each transition. The
exact backend session contains those seven semantic views plus ApplicationLaunch,
25 actions, 25 Resources, and zero errors/crashes. The full RUM suite passes
1,177/1,177 and the full probe passes 134/134. `EXP-142` then exercises two
consecutive equal route values through real `NavigationLink(value:)` controls.
Its first stronger-oracle run proves returned lifecycle work remained on D2 until
fresh D3 started. Per-materialized-boundary occurrence claims fix that ordering
without changing the customer's route type; the accepted H1/D1/D2/D3/H2 run
passes 48/48 and backend intake with no duplicate, error, or crash. The full
probe now passes 135/135 and the full RUM suite passes 1,181/1,181. Objective-C selector smoke and
fallback tests pass, lint passes at the preceding manual-API checkpoint, and the
semantic SPI builds in Release under Xcode 27. This validates prototype
usefulness, not stable API approval.
Exact run, session, and view identifiers remain in [EXPERIMENTS.md](EXPERIMENTS.md).
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
`EXP-135` additionally proves that an ordinary SwiftUI Button closure is not
inside this handoff even though the automatic tap itself has an exact source.
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

The product contract now removes the earlier ambiguities. First, a scene has one
current destination: split sidebars, tab bars, and containers are structural, not
parallel RUM views. Second, scene-aware manual view start/stop is required so the
same customer key can exist in A and B and an exact stop closes only its targeted
scene; existing source-less methods keep their inferred/last-interacted behavior.
Targeted start and stop must be paired; a legacy source-less stop is not an escape
hatch for a targeted start, and no public UUID or returned handle is introduced.
`EXP-120` proves this cannot be implemented as a scene-targeted copy of the
existing direct commands. Targeted manual entries need per-scene stack ownership
and must remain authoritative over automatic candidates until exact removal.
That internal requirement is implemented by `29c8cec2c` and hardened by
`b1a0fb6b8`; `EXP-122` validates its one-scene H1/M1/H2 behavior. The scene-A/B
same-key behavior passes focused tests but still needs live capable-hardware
evidence before the support claim.

Navigation may commit beneath manual authority. Only the latest committed
underlying destination is eligible for reveal; intermediates that were never the
scene's current visible destination emit nothing. Exact stop starts the revealed
destination as a fresh occurrence. Different manual keys form a legitimate
suffix—Compose -> Attachment Preview -> fresh Compose—while a duplicate active
`(scene, key)` start is instrumentation misuse requiring crash safety rather than
new product semantics.

Third, the initial semantic SwiftUI integration is not stack-only. Its centralized
router/resolver describes the complete scene destination, including sheets and
full-screen covers. A presentation replaces the current destination, and dismissal
must create a fresh revealed occurrence before post-dismiss customer work while
preventing its automatic duplicate.
`EXP-125` now proves that contract internally for Sheet by combining exact router
start/stop with a suppression-only state attached to the native presentation
subtree. `EXP-126` independently proves the same contract for `fullScreenCover`,
and `EXP-127` proves the authority boundary remains local to its sibling
container. `EXP-141` exercises the first actual container SPI across stack,
Sheet, and full-screen-cover destinations. Its exact seven-occurrence semantic
chain and downstream owners pass locally and in backend intake without an
automatic duplicate. This validates one API shape experimentally; it does not
approve the public API. `EXP-142` validates sequential equal route occurrences
through native value links and proves fresh revealed D3/H2 ownership before
returned lifecycle callbacks. Direct restoration into an initial repeated path
remains unproven.
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
| Concurrent view creation and lifetime | UIKit and explicit SwiftUI windows coexist in one session; the iOS 27 early-mount candidate preserves exact A/B lifecycle work; route-owned controls publish semantic roots and destinations; `EXP-090` proves a RUM-only occurrence change preserves customer SwiftUI state, `EXP-098` reveals retained Home before immediate work, and `EXP-105` preserves that occurrence across a subtree remount. `EXP-115` keeps automatic tracking enabled while an active explicit subtree owns H1/D1/H2 without duplicates; `EXP-116` moves the path and resolver to one probe-container call site; both clean `EXP-118` prefixes keep A semantic while independently creating B automatic views. `EXP-122` proves the internal exact-scene stack preserves authoritative manual M1 and reveals one fresh H2. `EXP-125` and `EXP-126` prove the same exact lifecycle and target-scoped automatic dedup for semantic Sheet and full-screen-cover destinations. `EXP-127` proves a left manual boundary does not suppress an independently materialized right sibling and reveals only its latest staged Detail. `EXP-128` proves distinct-key nesting creates fresh revealed Compose and Home occurrences while a duplicate active key creates none. `EXP-137` through `EXP-140` validate the customer-shaped manual SPI, and `EXP-141` validates seven fresh semantic occurrences through the actual container SPI. `EXP-129` adds a strict same-key A/B oracle, but the simulator expired before its manual steps | Complete live same-key A/B and semantic-A/automatic-B isolation on capable hardware, then cover simultaneous visibility, construction, restoration, and iPhone Duo validation before API promotion |
| UIKit and SwiftUI navigation | UIKit push/pop/modal and explicit SwiftUI stack/modal flows preserve one UUID per committed path occurrence; signal-driven stack return, abort, same-/different-type replacement, split replacement, retained split return, and UIKit cancel/finish pass locally and in backend intake. `EXP-116` repeats return, abort, and same-type replacement through one centralized container resolver. `EXP-125` and `EXP-126` close the Sheet and full-screen-cover return boundaries with complete-destination routing, a fresh H2 before immediate dismiss work, and no automatic presentation duplicate. `EXP-127` proves that an independently materialized sibling controller can commit Home → Detail beneath manual authority without creating an intermediate current view, then become one fresh current Detail on reveal. `EXP-141` repeats stack return plus both presentation styles through the actual customer-shaped container and produces H1/D1/H2/Sheet/H3/Cover/H4 without duplicates. The matching automatic SwiftUI split control still fails with no semantic destination views. Stock regular-width UIKit splits no longer start or restart structural Primary/supplementary views; cancellation retains S2 and completion creates fresh S1 | Harden repeated equal routes, external router replacement, restoration, and presentation replacement; prove recognized native SwiftUI cancel/finish and exact activation on hardware; then cover startup/subclass containers, adaptive resize, simultaneous-visible A/B completion, and ordinary-app compatibility |
| Action attribution | Source-bearing UIKit/SwiftUI taps emit once; exact-view actions update the representative; execution-local manual action/error/view mutations and internal view work prefer exact handoff view/scene; `EXP-098` attributes immediate returned-Home work correctly and source-less work keeps last-interacted fallback. `EXP-122` attributes exact-scene M1 active work correctly and gives immediate plus settled post-stop work to one fresh H2. `EXP-125` and `EXP-126` repeat that ownership across Sheet and full-screen-cover dismissal. In `EXP-127`, right-Detail work remains on current M1 until exact stop and switches immediately to fresh Detail afterward. `EXP-128` assigns first Compose, Preview, resumed Compose, duplicate-start, and final Home work to their exact occurrence IDs. `EXP-141` backend-confirms 25 actions and 25 Resources across seven semantic occurrences, including immediate, settled, and delayed post-dismiss work on fresh H3/H4. `EXP-132` drives a threshold-qualified real UIKit fling through navigation and keeps exactly one `.scroll` action on its origin while the fresh destination owns follow-up work. `EXP-135` keeps the real automatic SwiftUI Button tap exactly once on A but classifies its later source-less child-task work on B. `EXP-129` encodes but does not yet complete the A/B live attribution row | Repeat manual-handoff precedence with B representative and A visibly interactive, then finish explicitly targeted downstream runtime rows; retain `EXP-132` as the UIKit deceleration regression |
| Scene lifecycle and sessions | Requested destruction/close preserves delayed ownership; exact A-to-B open and B close wait for B readiness/disconnect, and post-close A work keeps A's original Home UUID; exact activation and current-state lifecycle conditions are implemented in the probe; disconnect invalidation, retained-reader rearming, migration, and stale-observer isolation pass; explicit stop/expiry restore concurrent branches; the probe registry models exact logical/native identity without retaining windows or serializing its future Execution Context seam | Prove activation plus peer background and stable simultaneous-visible peer close on capable hardware, then genuine OS disconnect/reconnect, per-scene background/foreground, concurrent restoration, and the equivalent shipping ownership path ready for future Window Execution Context mapping; backend visualization is follow-up work |
| Resources, traces, and operations | Start provenance and Resource completion ownership are frozen; manual Resource starts, automatic URLSession completion, and native/OpenTelemetry span starts use scene handoff; Operations use application-wide typed identities and per-step resolution. `EXP-130` backend-confirms Home→Detail success/failure and duplicate latest-start semantics; `EXP-131` prepares exact Operation A→B and reverse-completion acceptance; `EXP-133` backend-confirms one Trace-only request across representative churn; `EXP-134` backend-confirms two independent A/B requests completed in reverse order without owner drift; `EXP-135` proves an ordinary SwiftUI button's child task begins outside the event handoff and becomes source-less; `EXP-136` prepares one A-created/B-joined request and reaches B join before a repeatable simulator-system crash | Run `EXP-136` unchanged on capable hardware; finish exact-source proof, experimental explicit target/scoped APIs and review, `EXP-131`, compatibility, and overhead gates |
| Errors, logs, WebView, vitals, fatal/exported context, and profiling | Scene-aware source or focused tests exist for each except profiling, whose process-level limitation is known | Targeted two-window runtime/backend evidence; profiling needs an explicit support statement, not guessed per-scene ownership |
| Normal-app compatibility | Exact manual-authority tests pass 8/8, six focused semantic occurrence/binding tests pass, and the current complete RUM rerun passes 1,181/1,181; Trace remains 151/151. Complete Internal/Logs/WebView suites at their stated checkpoints, probe builds, 135/135 native probe tests, package build, and repository lint at the prior checkpoint pass. Both customer-shaped manual and semantic-navigation SPIs compile in an Xcode 27 Release build | Live single-scene behavior, custom-handler integration, external-router/restoration hardening, and `sendEvent` overhead/recursion measurement |
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
row. `EXP-115` implements and backend-validates target-scoped authority for an
already explicit semantic subtree while automatic discovery remains enabled.
`EXP-116` then centralizes the path and resolver at one probe navigation
container while retaining route-owned placement at materialized builders. The
remaining API problem is choosing the reviewed public shape, not proving that
once-per-container configuration can preserve occurrence semantics. `EXP-118`
adds a separate automatic-only scene with a source/owner discriminator that
rejects stale pre-open automatic views. Two clean simulator prefixes created B's
own automatic views while A remained semantic, but simulator compositor aborts
prevented the final marker and terminal result. Complete that exact row on
physical hardware rather than treating the prefix as a pass. `EXP-117` keeps the
host-side clean-run isolation flaw visible until the reproducible runner owns
uninstall and artifact validation. `EXP-119` independently proves that one
exceptional explicit Sheet can suppress its own automatic duplicate while the
underlying automatic Home eventually returns with a fresh UUID. It also rejects
the current transition ordering because immediate Home work in `onDismiss`
retains S1; the reviewed navigation/manual-view design must close that gap rather
than treating later H2 attribution as sufficient.
`EXP-120` closes the next source question with negative runtime evidence: existing
keyed manual start/stop bypasses `RUMViewsHandler`, automatic discovery preempts
M1 during its authority interval, and the resulting fallback owns Compose work.
`EXP-121` proves the new handler-stack route keeps M1 authoritative but reveals a
generic fallback at exact stop. `EXP-122` proves the hardened route retains the
semantic base, rejects that structural fallback, and reveals one fresh H2 before
both immediate and settled work. The internal requirement is complete; public
scene-aware overload review and live same-key A/B proof remain. `EXP-123` applies
that route to the Sheet and rejects handler-only dedup after automatic discovery
creates the presentation host. `EXP-124` adds target-scoped suppression and gets
the right owners, while exposing aggregate-lifetime matching as a false oracle.
`EXP-125` separates router authority from native subtree lifetime and passes
14/14 plus exact backend intake. `EXP-126` then repeats the same strict oracle
and exact backend ownership for `fullScreenCover`, without inferring parity from
Sheet. Both required presentation styles are now internally correct; the
reviewed public complete-destination integration remains. `EXP-127` closes the
internal sibling-container question with a mandatory real-controller ancestry
witness, exact H1/M1/fresh-Detail ownership, and two clean 19/19 runs. Its first
run remains useful negative harness evidence because an unfiltered probe-only
ancestry reader became a late automatic view.
`EXP-128` closes the single-scene nested-manual and duplicate-start runtime row:
its clean 29/29 run and backend session contain H1/C1/P1/fresh-C2/fresh-H2,
retain duplicate-start work on C2 without a restart, and keep every paired
Resource on the same owner as its action. The earlier timeout is retained as a
harness ordering lesson and is fixed by accepting already-recorded exact-view
evidence.
`EXP-129` adds the exact two-scene same-key and reverse-stop scenario plus
adversarial ownership fixtures. Its clean simulator attempt reached both native
scenes but expired before manual authority began, so the row is preserved in the
physical-device queue without a semantic conclusion.
`EXP-130` closes the simulator-capable Operation navigation and duplicate-start
rows. Its backend raw steps prove each start/end owner independently, and its
reduced documents prove that only the latest duplicate start is completed. It
does not substitute for the still-pending cross-scene A-to-B run.
`EXP-131` turns that pending run into one named, fail-closed scenario with exact
A/B invocation order, distinct-key reverse completion, and four adversarial
ownership fixtures. Its 100/100 hostless result is readiness evidence only; live
raw/reduced intake remains hardware-gated.
`EXP-132` closes the simulator-capable UIKit scroll/deceleration row. A measured
above-threshold fling starts on Secondary 2, Secondary 3 is presented while
deceleration is still active, exactly one `.scroll` action stays on Secondary 2,
and immediate follow-up work uses fresh Secondary 3. Local and backend ownership
agree, and the probe plan passes 109/109.
`EXP-133` closes Trace-only URLSession completion owner freezing across a process
representative change. The held request starts with A/Home H1, completes after
B/Home B1 becomes representative, and emits exactly one backend span on A/H1 and
the original session. B/H1 and the matching RUM-Resource counts are zero. The
accepted oracle passes 8/8 and the full probe plan passes 115/115. The first
attempt ended with its Xcode interaction session and has no crash evidence or
acceptance claim.
`EXP-134` closes the two-independent-request reverse-completion variant. A and B
start in that order, complete B-before-A while the opposite scene is
representative, and still emit exactly one backend span each on B/Home and
A/Home respectively. Both spans keep session `a9d038c5…`; opposite-view and
matching RUM-Resource counts are zero. The accepted oracle passes 14/14 and the
full probe plan passes 120/120. The first exact backend query ran before APM
indexing and returned zero even though the Trace uploader had received 202; the
later URL/run queries and six exact aggregates are the accepted backend result.
Real-device and
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
| SwiftUI Button followed by structured `Task` | `EXP-135` physically taps A, then opens B before releasing the suspended child task. The automatic tap occurs exactly once on A/H1. SDK handoff is nil in the button callback, at task start, and at resume; UIKit's ambient trait changes from A to B across suspension. The resumed Action/Resource use B/H1 in mapper and backend intake | Backend-classified as source-less for an ordinary SwiftUI Button callback; exact origin requires an explicit target or scoped API, not ambient trait inference |
| SwiftUI `.task` and `onAppear` loading | Pre-trait explicit experiments `EXP-010` through `EXP-012` failed; trait experiments `EXP-013` through `EXP-015` achieved correct queued attribution; `EXP-030`/`EXP-031` proved modifier placement alone insufficient; the iOS 27 early-mount candidate then mapped every marker correctly in `EXP-032`/`EXP-033`. `EXP-056` maps route-owned on-appear/immediate work correctly but classifies an A delayed manual call after B activation as source-less representative fallback. Automatic UIKit-hosted and native work still uses preceding views, and `EXP-029` rules out a usable transparent hosting-controller boundary | Backend-pass for exercised iOS 27 explicit route creation; source-less delayed manual work is intentionally representative. Finish construction stress; automatic initial-root/destination attribution still needs reviewed semantic integration |
| Scene connection and UIKit `viewDidAppear` loading | `EXP-006` and `EXP-016` used the prior representative before the new view existed | Backend-classified as source-less |
| Pre-created URLSession task resumed from a UI action | `EXP-006` selected B Detail and the resume action at interception rather than object creation | Backend-pass |
| One shared/coalesced request used by both scenes | `EXP-136` creates one real task on A and lets B join without creating or resuming another. Its 132/132 hostless oracle requires exactly one A/Home span. Two clean simulator runs crashed `backboardd` before release; the retry first proved B joined the active request | Simulator-inconclusive; run unchanged on iPhone Duo or a physical multi-window iPad. A trustworthy creator should remain the owner; a consumer must not retarget or duplicate the span |
| Navigation and session rollover before actual request start | Navigation-at-resume passed in `EXP-006`; `EXP-007` exposed rollover loss and `EXP-008` verified the fix | Backend-pass |
| Reverse-order completion from two scenes | RUM and Trace focused tests pass with frozen A/B owners; `EXP-134` live- and backend-confirms two independent Trace-only URLSession requests completed B-before-A without owner drift; `EXP-131` adds the exact hostless Operation command/oracle sequence | Backend-pass for Trace; Operation runtime/backend remains pending on capable hardware |
| Source scene closes before completion | `EXP-019` preserved delayed resources and traces; `EXP-020` preserved the fixed operation | Backend-pass |
| Operation starts before navigation and ends after it | `EXP-130` backend-confirms success H1→D1 and failure H2→D2 with different start/end view UUIDs; `EXP-131` prepares A→B success/failure | Backend-pass for one scene; cross-scene live/backend acceptance remains pending on capable hardware |
| Concurrent operations with identical `(name, key)` | `EXP-130` emits the exact `[start H3, start D3, end D3]` raw sequence and the corrected warning; the reduced Operation uses D3→D3 | Backend-pass; the earlier H3 raw start has no synthetic end and remains open for its four-hour timeout |
| Trace-only URLSession span | `EXP-133` starts a held request on A/H1, makes B/H1 representative, and releases the response from B. `EXP-134` starts independent A/H1 and B/H1 requests and completes B-before-A while the opposite scene is representative. The 8/8 and 14/14 oracles plus backend predicates find exactly one span per request on its captured start view and session, none on the opposite view, and no matching RUM Resource. `EXP-136` adds the single-task shared-consumer contract but is hardware-gated before completion | Backend-pass for request-time owner freezing and independent reverse completion; run shared completion and simultaneous-visible exact-source discovery on capable hardware, then custom-handler compatibility |
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
  than the one that initiated the request. The branch snapshots request-time
  `RUMCoreContext`; `EXP-133` proves one completion-created span retains that
  owner after the representative changes, and `EXP-134` proves two independent
  requests retain distinct A/B owners through reverse completion. Trace parentage is more robust because
  active spans are execution-scoped. Unknown source discovery remains global
  fallback rather than invented provenance.
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
internal opaque scene token. A structured `Task {}` created while code is actually
executing inside that dynamic scope inherits the token through `TaskLocal`,
including across suspension. A real three-minute UIKit/control-path URLSession
probe validates that inheritance after another scene becomes representative.
Conceptual causation by a touch is insufficient: `EXP-135` proves that an ordinary
SwiftUI Button closure begins after the synchronous `sendEvent` handoff has ended,
so its child task inherits nothing. This also does not extend to schedulers that
discard task-local context.

`UITraitCollection.current` is an ambient UIKit execution-context value, not a
durable scene token. In `EXP-135` it reports A at the SwiftUI callback and child
task start, then reports B after suspension and B takeover. It may help synchronous
platform work but must not be captured or re-read as automatic async provenance.

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
or an ambient trait when exact provenance is required, and it must not duplicate
one operation into every active scene. The process-representative `RUMCoreContext`
remains the explicit compatibility fallback for source-less work, not an exact
source inference.

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
| Automatic SwiftUI view lifetime | Transparent hosting-controller discovery can select process-global history, run after lifecycle work, miss semantic route changes, or preempt explicit authority | Scene-keyed routing and keyed occurrence state pass. `EXP-115` adds weak target-scoped authority while keeping automatic tracking enabled elsewhere; `EXP-116` centralizes path/resolver ownership; `EXP-122` integrates targeted manual views with the scene stack; `EXP-125`/`EXP-126` mount suppression-only state in independent Sheet and full-screen-cover subtrees; `EXP-127` proves containment across two sibling controller branches under one outer host; `EXP-128` exercises a real nested manual suffix plus duplicate active-key misuse; `EXP-129` adds exact same-key A/B and reverse-stop expectations; `EXP-137` through `EXP-140` route those one-scene flows through the customer-shaped manual SPI; `EXP-141` routes the full stack/presentation stream through the customer-shaped semantic SPI | Automatic-only semantic stack/split baselines remain wrong. Explicit coexistence passes H1/D1/H2; customer-shaped manual coexistence passes H1/M1/H2. The semantic SPI passes 38/38 with H1/D1/H2/Sheet/H3/Cover/H4 and no automatic duplicate. Probe tests pass 134/134; six focused semantic-navigation tests pass; full RUM passes 1,177/1,177. `EXP-129` reached both simulator scenes but expired before manual starts | Backend distinguishes the wrong automatic baselines from correct semantic chains. `EXP-137` through `EXP-140` confirm the manual, nested, Sheet, and cover customer API paths. `EXP-141` confirms all seven semantic occurrences, 25 exact-view actions, 25 exact-view Resources, and zero errors/crashes. `EXP-118` and `EXP-129` remain hardware-inconclusive | Automatic discovery remains the zero-code default. Both API proposals are implemented and experimentally useful; stable review, repeated/external-router hardening, live same-key A/B proof, semantic-A/automatic-B isolation, physical scene coexistence, and normal-app validation remain |
| SwiftUI navigation | Hosting controllers from all windows share history, transparent discovery may report containers instead of customer destinations, and cancellation can publish an uncommitted path | A bound typed path drives RUM occurrence generations; retained routes use guarded scene proof; transition completion owns commit/cancel. The `EXP-141` SPI owns the typed `NavigationStack` materialization boundary and consumes centralized root, destination, and presentation resolvers. `EXP-142` adds per-materialized-boundary claims so equal route values retain distinct occurrences without changing the customer path type. Presentations start only after exact-scene mount, use manual authority for the semantic destination, and retain target-local automatic suppression through native disappearance | Route-owned return, abort, replacement, repeated equal values, split selection, retained return, Sheet, and full-screen-cover present/dismiss pass. `EXP-141` passes H1/D1/H2/Sheet/H3/Cover/H4 without an automatic presentation duplicate; `EXP-142` passes H1/D1/D2/fresh D3/fresh H2 through native value links, with the fresh reveal preceding lifecycle work. Navigation beneath a mounted presentation reveals only the latest underlying destination in focused tests. `EXP-129` remains hardware-inconclusive before manual steps. `EXP-100` gestures were ignored, so native interactive source delivery remains unproven | Backend confirms the exact seven-occurrence `EXP-141` stream and six-view `EXP-142` stream, including launch, with per-occurrence action/Resource ownership. Independent presentation, sibling, and nested-manual sessions also agree; `EXP-129` produced no backend event | The first once-per-container API shape, required presentations, and sequential equal routes pass experimentally. External router mutations, initial/repeated restoration, presentation replacement, reviewed API, human gestures, same-key hardware acceptance, adaptive navigation, and simultaneous-visible hardware remain |
| Tap actions | Touch window is available but baseline routing loses it | Branch retains touch/modifier scene; automatic actions no longer fan out; exact-view actions refresh the representative; manual calls inside event handoff prefer exact view then scene and preserve fallback outside it | UIKit and SwiftUI source-window taps and controls pass; `EXP-089` proves physical filtering/fallback but not a different representative. `EXP-135` physically taps a SwiftUI Button in A and observes exactly one automatic tap on A/H1 before B opens | Actions emit once on their originating view in exercised runs; `EXP-135` backend-confirms the exact A tap | Core and focused routing pass; the SwiftUI automatic tap is correct, while its later framework callback has no durable handoff. Exact precedence over a different visible representative remains a physical-device row |
| Scroll actions | Scroll callbacks have a view/window but no scene reaches the command | Branch retains source scene through drag and deceleration | SwiftUI scene D swipe emitted on D while another scene survived. `EXP-132` drives a threshold-qualified UIKit fling on Secondary 2, navigates to fresh Secondary 3 during deceleration, and observes exactly one origin action plus correctly owned follow-up work | SwiftUI D retained its view. `EXP-132` backend intake confirms one `.scroll` action on stopped Secondary 2 and immediate action/Resource ownership on fresh Secondary 3 | Same-scene UIKit navigation/deceleration and exercised SwiftUI runtime pass; simultaneous-visible A/B with a deliberately different representative remains hardware-gated |
| Resources and traces | A generic request/span has no intrinsic scene; representative fallback can be wrong | Branch has bounded UI-event/TaskLocal provenance, frozen owners, exact manual Resource start, owner-routed completion, automatic URLSession completion handoff, native/OpenTelemetry span-start parity, and request-time context for completion-created Trace-only URLSession spans; detached/shared work remains ambiguous. Only tasks actually created inside the dynamic handoff inherit it | Structured/UI-local work with a proven handoff retains ownership; delayed completion survives source-scene closure; source-less schedulers use representative fallback. `EXP-133` completes one held Trace-only request after A→B representative churn; `EXP-134` completes independent A/B requests B-before-A while the opposite scene is representative. `EXP-135` shows an ordinary SwiftUI Button callback starts outside the handoff and its resumed work follows B. `EXP-136` creates one shared request in A and proves B joins it, but simulator `backboardd` fails before release twice | Existing backend runs show RUM/APM agreement and teardown ownership. `EXP-133` finds one span on A/H1 and zero on B/H1. `EXP-134` finds one A span on A/H1 and one B span on B/H1, zero opposite matches, one shared session, and no matching RUM Resources. `EXP-135` finds the automatic tap on A/H1 and both resumed source-less events on B/H1. `EXP-136` has no span by design because neither simulator attempt reached release | Partial and bounded; Trace-only owner freezing and independent reverse completion are backend-pass, the SwiftUI Button/task row is classified source-less, and shared/coalesced completion plus simultaneous exact-source discovery are physical-device rows. Experimental explicit target/scoped APIs, compatibility, and overhead gates stay open |
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
