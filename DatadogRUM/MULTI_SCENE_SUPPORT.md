# RUM multi-scene support

This is the canonical entry point for concurrent `UIWindowScene` support in
Datadog RUM. It records the current contract, support status, decisions, and exact
resume point. Detailed evidence and chronology are split by ownership so future
work can start here without loading the frozen experiment history.
It remains separate from `RUM_FEATURE.md` until the behavior is implemented,
validated, and ready to become a supported contract.

Last updated: 2026-09-15

## Goal

RUM must correctly represent applications that have two or more independently
navigable windows at the same time. Opening, foregrounding, backgrounding, or
closing one scene must not end or replace the view that remains visible in another
scene. Automatically and manually captured events must be attributed to the scene
that produced them whenever that identity is available.

The primary validation areas are:

1. UIKit and SwiftUI view creation and lifetime.
2. UIKit and SwiftUI navigation, including concurrent navigation stacks.
3. Tap and scroll action attribution.
4. Resource, error, long-task, vital, trace, feature-operation, crash, and
   exported RUM-context attribution; Session Replay crash-free coexistence only.
5. No behavior or performance regression for applications with one scene or no
   scene lifecycle.

The release target for this work is iPhone Duo on iOS 27.1. Correct multi-scene
behavior on earlier systems is welcome when the same implementation provides it
without compromise, but it is not a release requirement. The SDK must continue
to build and behave normally on its iOS 15 deployment target even where semantic
multi-scene support is not claimed.

## Document map

| Document | Read it when |
| --- | --- |
| [Assessment and evidence](MultiSceneSupport/ASSESSMENT.md) | You need the detailed verdict, source baseline, causal-attribution boundaries, or surface-by-surface evidence |
| [Implementation and validation plan](MultiSceneSupport/PLAN.md) | You are choosing the next implementation slice, extending a probe, or checking release gates |
| [Deferred single-scene extraction](MultiSceneSupport/DEFERRED_SINGLE_SCENE_EXTRACTION.md) | The multi-scene runtime is frozen and you are ready to separate generic reliability fixes before review |
| [Experiment index](MultiSceneSupport/EXPERIMENTS.md) | You need a named experiment's status and targeted detailed-record locator |
| [Rejected approaches](MultiSceneSupport/REJECTED_APPROACHES.md) | You are designing an experiment or revisiting a prior implementation or tooling path |
| [Tooling runbook](MultiSceneSupport/TOOLING_RUNBOOK.md) | You are preparing Xcode, selecting a simulator/device, running the probe, validating backend intake, or classifying tooling failures |
| [Navigation API proposal](MultiSceneSupport/NAVIGATION_API.md) | You are reviewing the optional SwiftUI container integration, scene-aware manual views, coexistence rules, or Swift/Objective-C compatibility |
| [Operations contract](MultiSceneSupport/OPERATIONS.md) | You are changing Operation identity, per-step attribution, duplicate-start behavior, public targeting, documentation, or tests |

Read this overview first, then open only the document that owns the question.
`EXPERIMENTS.md` uses stable `EXP-*` identifiers; append full new records to the
active numbered shard, add one index row, and never renumber them.

Evidence is labeled by source inspection, focused test, local runtime, emitted
payload, backend intake, or reducer result wherever that distinction changes the
strength of a support claim. The detailed matrix groups some of those labels for
readability; the experiment ledger owns the exact evidence boundary.

## Current support verdict

The released baseline is not semantically safe for concurrent scenes. This branch
has an experimental core model that keeps one active view branch per scene and
routes established UIKit or explicitly tracked SwiftUI views, navigation, actions,
lifecycle, delayed completions, and Operations without replacing another visible
window. Multiple two-window simulator runs and Datadog intake validate that model.

The branch is not ready for a support claim. Transparent native SwiftUI creates
views after early lifecycle work and can attribute a new window's work to the
previous scene (`EXP-028`); controller callbacks, navigation titles, and iOS 27
reflection do not supply an earlier trustworthy semantic destination (`EXP-029`).
Automatic tracking remains the zero-code default, while exact navigation will use
the approved optional container-level path/router integration.

The underlying occurrence mechanics now have strong experimental evidence. The
iOS 27 explicit path attributes early work correctly, committed
Home → Detail → Home produces distinct H1/D1/H2 UUIDs, cancellation produces no
speculative occurrence, and the debug route source preserves customer SwiftUI
state across same-type replacements and retained returns (`EXP-030` through
`EXP-105`). This is integration evidence, not a reviewed public API.

The first coexistence slice is now implemented internally. In iOS 27 declared
multi-scene applications, an active explicit SwiftUI boundary suppresses
automatic controller discovery only for its containing hierarchy. Automatic
tracking remains enabled elsewhere, detached or inactive explicit readers do not
suppress it, and UIKit predicate acceptance is unchanged. A clean signal-driven
Home → Detail → Home run with both trackers enabled produced exactly launch plus
H1/D1/H2 locally and in backend intake, with no automatic duplicate (`EXP-115`).
A probe-only once-per-container `NavigationStack` wrapper first proved that one
bound path and one centralized route-to-RUM resolver can preserve return,
aborted-push, and same-type-replacement semantics with no automatic duplicate
(`EXP-116`). That shape is now implemented as an iOS 27 experimental Swift SPI.
It owns root and destination materialization, consumes centralized path and
presentation state, and covers both Sheet and full-screen cover. `EXP-141`
passes the actual customer-shaped integration through H1 → D1 → H2 → Sheet →
H3 → Cover → H4 with seven distinct view IDs and no automatic duplicate. This
is implementation and runtime evidence, not approval of a stable public API.
`EXP-142` additionally passes native repeated-value links through H1 → D1 → D2
→ fresh D3 → fresh H2. Per-materialized-boundary claims publish each revealed
occurrence before its lifecycle work without changing the customer's route type.

The original exceptional SwiftUI Sheet discriminator (`EXP-119`) produced
automatic Home H1, explicit Sheet S1, and eventual H2 without an automatic Sheet
duplicate, but immediate `onDismiss` work still belonged to S1. The approved
complete-destination successor is now internally correct. `EXP-123` proves exact
handler authority alone still allows an automatic presentation host. A mounted
suppression-only boundary then keeps automatic discovery out of only that native
subtree while the router publishes the semantic Sheet. After correcting an
aggregate-lifetime oracle defect found in `EXP-124`, `EXP-125` passes 14/14 with
H1 → semantic Sheet M1 → fresh H2, no automatic Sheet, and both immediate and
settled dismiss work on H2. Backend intake agrees with zero errors or crashes.
The independent full-screen-cover discriminator now passes the same 14/14
contract in `EXP-126`: H1 → semantic Cover M1 → fresh H2, no automatic
`ProbeFullScreenCoverView`, and immediate plus settled dismissal work on H2.
Its exact backend session contains 28 events and zero errors or crashes. This
closes the internal complete-destination presentation slice for both required
SwiftUI presentation styles; the public API remains under review.

Sibling-container isolation now passes as well (`EXP-127`). The probe mounts two
independent `NavigationStack` branches beneath one outer SwiftUI host and records
their complete controller ancestries before accepting the result. A left-hand
suppression boundary and exact-scene manual M1 remain authoritative while the
right-hand stack commits Home → Detail underneath it. No automatic view becomes
current during M1; exact stop reveals only the right-hand Detail as a fresh
automatic occurrence, and immediate plus settled work use that same new ID. The
first pass exposed a probe-only ancestry reader as a fifth automatic view after
the assertions; an exact predicate exclusion removed that measurement artifact.
The two clean successors pass 19/19, and the final 31-event backend session has
exactly launch, Home, M1, and Detail with zero errors or crashes. This proves the
internal containment and reveal mechanics, not the public semantic API.

The existing direct keyed manual API has now been exercised over an automatic
Home view (`EXP-120`). It is not a coexistence solution: Compose M1 was stopped
31–48 ms after it started, an automatic hosting fallback took over while manual
authority was supposed to remain active, and the decisive Compose action and
Resource were attributed to that fallback. Stopping M1 eventually produced a
fresh automatic Home H2, but only the settled work belonged to H2. Local mapper
evidence and backend intake agree. Scene-aware manual APIs therefore need an
internal per-scene authority/stack integration, not just a scene target on the
existing direct commands.

That internal integration is now implemented and runtime-validated. The first
exact-scene run kept Compose authoritative but revealed a staged generic hosting
fallback before Home H2 (`EXP-121`). The hardened path retains the last semantic
destination during manual authority and ignores known generic SwiftUI hosting
fallbacks without suppressing a later trustworthy destination. Its clean
successor passes 16/16 with H1 → M1 → fresh H2: active work belongs to M1 and
both immediate and settled post-stop work belong to the same H2 (`EXP-122`).
Backend intake agrees and reports zero errors/crashes. Existing source-less APIs
remain unchanged. The scene-aware customer bridge is now implemented as an iOS
27 Swift SPI with Debug-only Objective-C counterparts. Stable exposure still
needs normal API review.

Nested manual authority and duplicate-start crash safety now have independent
runtime evidence (`EXP-128`). Automatic Home H1 gives way to Compose C1, then
Preview P1; stopping Preview creates a fresh Compose C2, and a duplicate active
Compose start creates no additional view or restart. C2 owns the resumed and
duplicate-start action/Resource pairs. Stopping C2 reveals fresh automatic Home
H2 before both post-stop pairs. The local oracle passes 29/29, and backend intake
contains the exact H1/C1/P1/C2/H2 occurrence chain after startup with distinct
Compose and Home IDs. This closes the one-scene approved manual-stack runtime
discriminator; same-key isolation across live scenes and public API review remain.

`EXP-137` through `EXP-140` validate the proposed scene-targeted manual-view call
sites rather than only internal handler entry points. The probe passes automatic
Home → manual Compose → fresh Home, nested Compose → Preview → fresh Compose,
and independent Sheet/full-screen-cover replacement and dismissal using the
Swift SPI. Mapper output and backend intake agree on every owner, all returned
destinations have fresh IDs, no automatic presentation duplicate appears, and all
four sessions contain zero errors/crashes. Swift fallback tests, Debug-only
Objective-C selector smoke, a 1,171-test RUM suite, a 133-test probe suite, lint,
and an Xcode 27 Release build pass. This establishes that the proposal is useful
and implementable; stable names, availability, Objective-C Release exposure, and
third-party-conformer semantics remain normal API-review decisions.

`EXP-141` validates the semantic-navigation proposal through the actual SDK SPI,
with automatic SwiftUI tracking still enabled. One clean iPadOS 27 run passes
38/38 locally and uploads exactly seven semantic views after launch: four fresh
Home occurrences plus Detail, Sheet, and full-screen Cover. Backend intake finds
25 actions and 25 Resources on their exact owning occurrences; immediate,
settled, and delayed post-dismiss work uses the fresh revealed Home H3/H4 views.
No automatic Sheet/cover or hosting-controller duplicate, RUM error, or crash is
present. The full probe plan now passes 134/134, the clean complete RUM suite
passes 1,177/1,177, and the SPI builds in Release with Xcode 27. `EXP-142` then
passes 48/48 locally and in backend intake for sequential equal route values.
The full probe is now 135/135 and the complete RUM suite is 1,181/1,181.

`EXP-129` now supplies the deterministic two-scene same-key contract. Its 91-test
plan rejects a shared A/B Compose UUID, cross-scene work, a B stop that preempts
A, and reuse of either returned Home. The explicitly uninstalled iPad simulator
run reached distinct native A/B scenes, then lost the Xcode/device session amid
CoreAnimation and BoardServices interruptions before the first manual start.
There was no terminal oracle or backend intake. This is a simulator-inconclusive
runtime row queued unchanged for iPhone Duo or a physical multi-window iPad, not
evidence for or against the SDK behavior.

`EXP-130` closes the simulator-capable Operation/navigation discriminator. One
clean run starts and completes a successful Operation across Home H1 → Detail D1,
starts and fails another across Home H2 → Detail D2, and starts the same identity
twice across Home H3 → Detail D3 before succeeding it. The local oracle passes
27/27 and the full probe plan passes 93/93. Backend intake contains seven raw
Operation steps and three reduced Operations: the first two preserve different
start/end view IDs, while the duplicate reduces from the latest D3 start and
leaves the earlier H3 start open without a synthetic end. The corrected warning,
failure reason, zero error/crash result, and exact six semantic view occurrences
are all observed. Cross-scene A-to-B completion and public targeting remain open.

`EXP-131` prepares the exact remaining cross-scene Operation discriminator. It
starts success and failure in A and completes them in B, then starts two
same-name Operations with distinct keys in A and B and completes B before A. The
hostless driver and adversarial oracle raise the probe plan to 100/100 while
rejecting shared view identity, wrong-scene B work, B completion on A, and A owner
drift after B completes. No simulator or backend claim is made: the named scenario
is queued intact for iPhone Duo or a physical multi-window iPad.

`EXP-132` closes the simulator-capable UIKit scroll/navigation discriminator
with a real gesture through the production `UITableView` delegate proxy. The
lift speed exceeded the SDK's swipe threshold, UIKit remained in deceleration
while a fresh destination appeared, and exactly one `.scroll` action stayed on
the originating occurrence. The new destination then owned its immediate action
and Resource. Mapper and backend evidence agree, with no duplicate action, RUM
error, or app/SDK crash. This does not replace the still-hardware-gated proof of
interacting in A while a simultaneously visible B is process representative.

`EXP-133` closes the Trace-only URLSession request-time owner-freezing row. One
real first-party request starts on A/Home H1, B/Home B1 then becomes the process
representative, and B releases the held response. The clean run passes 8/8 and
backend intake contains exactly one `urlsession.request` span on A/H1 and the
original session, zero on B/H1, and no matching RUM Resource. This proves that
completion does not re-resolve a later representative; exact source discovery
between simultaneously visible windows remains a separate hardware-gated row.

`EXP-134` closes the two-request reverse-completion row. Independent requests
start on A/Home H1 and B/Home B1. B completes first while A is representative;
A completes second while B is representative. The local oracle passes 14/14,
backend intake contains exactly two spans, and each request remains on its own
start-scene view and shared RUM session. The opposite-view predicates and both
Trace-only RUM Resource predicates return zero. Shared/coalesced work and exact
simultaneous-window source discovery remain separate.

`EXP-135` closes the ordinary SwiftUI Button → structured `Task` discriminator
as a negative causal boundary. A real automatic SwiftUI tap emits exactly once
on A/Home H1. The button callback and child-task start have no SDK handoff, while
the scene trait initially reports A; after the task suspends and B becomes the
representative, that ambient trait reports B. The resumed manual Action and
Resource therefore use the approved source-less fallback and land on B/Home H1.
Backend intake confirms the exact A tap and B resumed owners with zero errors or
crashes. Neither task-local handoff nor `UITraitCollection.current` can recover
durable origin for this ordinary SwiftUI callback; exact A ownership requires a
future explicit target or scoped customer integration.

`EXP-136` prepares the shared/coalesced-request discriminator with one real
underlying URLSession task created on A/Home and one B consumer that joins it
without creating or resuming another task. The strict oracle requires exactly
one span on the trustworthy creator and rejects B ownership, absence, or
duplication. Two clean iOS 27 simulator runs crashed `backboardd` in identical
Metal texture validation while rendering B. The retry proved B joined the active
request, but the system process failed before response release, trace mapping, or
the terminal oracle. This is hardware-gated with no app/SDK crash or attribution
verdict.

The experimental scene-targeted manual API slice adds one restored-window
isolation regression. The first nested API run
also exposed that simulator-restored `WindowGroup` values can outlive an app
uninstall; telemetry is now normalized to the current run without changing the
SwiftUI routed window identity (`EXP-138`).

UIKit split tracking now suppresses regular-width Primary and supplementary
columns for declared multi-scene applications on iOS 27 while preserving fresh
returned-Secondary occurrences. Signal-driven cancellation keeps the existing
Secondary UUID; completion creates a fresh returned-Secondary UUID, and backend
intake contains no Primary view (`EXP-112`). The native SwiftUI host still emits
a short startup fallback before the first UIKit destination, and the historical
application-subclassed split-container case remains open. Simultaneous visibility,
adaptive resize, genuine reconnect/restoration, and human native-gesture evidence
also remain open.

The structured probe records versioned JSONL, separates call-site source from
mapper-observed ownership, and evaluates fixture timelines with a pure oracle.
It also has an exact main-actor scene registry with weak window ownership,
readiness, activation, geometry, route, and disconnect generations. Its
signal-driven stack, split, UIKit-transition, scene-lifecycle,
automatic/manual-coexistence, semantic-navigation, action, Operation, and Trace
scenarios through `EXP-141` pass 134/134 tests. The prepared two-scene same-key, cross-scene
Operation, and shared-request scenarios
remain hardware-gated; the single-scene Operation/navigation scenario passes
locally and in backend intake.
Clean iPadOS 27 runs prove
distinct Home₁ → Detail → Home₂ occurrences, no speculative view for an aborted
push, and fresh occurrences for same- and different-type replacements. Each run
has exact final action/Resource ownership, one local terminal verdict, and
matching backend intake. Route-owned split selection and retained return also
pass with one exact action/Resource pair per occurrence, while the identically
driven automatic split baseline creates internal container views and fails at its
first semantic destination. Deterministic UIKit cancel/finish then pass 11/11 and
13/13 with exact resolved-view work and no Primary. Exact A-to-B open, B close,
and continuing A work pass 9/9 without changing A's original Home UUID
(`EXP-108` through `EXP-113`).
The container wrapper then passes Home₁ → Detail → Home₂, an aborted
same-turn push/revert, and same-named Detail₁ → Detail₂ in isolated local
and backend runs (`EXP-116`). Two earlier back-to-back launches remain recorded
as local-only evidence because the in-app `clean` flag cannot uninstall its own
bundle; their view events retained the preceding run ID until a host-side
uninstall (`EXP-117`).
Exact activation is now addressable and lifecycle-gated in the harness, but the
current fullscreen simulator cannot prove a focus handoff: both scenes may remain
foreground-active, and a rapid activation attempt crashed simulator `backboardd`
inside CoreAnimation/Metal before the harness timeout (`EXP-114`). A prior run
also confirmed that a plain source-labelled manual call is still source-less to
the SDK and correctly follows the last-interacted representative. This is a
compatibility result, not cross-scene attribution evidence.
Xcode's packaged device-interaction instructions now make measured UIKit gesture
synthesis available. `EXP-132` uses it for a conclusive real scroll/deceleration
run. Native SwiftUI edge-pop cancellation, simultaneous-window gestures, and
other device-only rows remain separate from deterministic programmatic proof.
Detailed conclusions live in [ASSESSMENT.md](MultiSceneSupport/ASSESSMENT.md);
exact runs and rejected paths live in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

| Surface | Current branch status | Remaining release condition |
| --- | --- | --- |
| UIKit views and navigation | Independent stacks, push/pop, modal, duplicate names, and teardown pass experimentally. On iOS 27 in declared multi-scene apps, regular split Primary/supplementary columns are now structural rather than RUM views. Deterministic cancel keeps S2 and finish creates fresh S1; both have exact backend action/Resource ownership | Cover the application-subclassed container and startup-host fallback, then prove simultaneous visibility, adaptive/lifecycle/restoration, live normal-app compatibility, and iPhone Duo behavior |
| Explicit/semantic SwiftUI tracking | Experimental iOS 27 early-start, retained-return, modal, repeated push/pop, crash-safe teardown, restoration, synthetic reconnect, and customer-state-preserving keyed-occurrence controls pass; single- and two-window split replacement plus a retained split return preserve customer state and exact markers. `EXP-116` proves the builder-owning shape, and `EXP-141` validates the actual Swift SPI with one typed path plus centralized root, destination, and presentation resolvers. Its clean H1/D1/H2/Sheet/H3/Cover/H4 run has seven distinct semantic IDs, exact downstream ownership, and no automatic duplicate. `EXP-122` proves the internal exact-scene keyed manual stack stays authoritative and reveals a fresh underlying destination. `EXP-125` and `EXP-126` cover complete-destination Sheet and full-screen-cover boundaries; `EXP-127` proves sibling isolation; `EXP-128` proves nesting and duplicate-start crash safety; `EXP-137` through `EXP-140` exercise the customer-shaped manual SPI. `EXP-129` adds the strict same-key A/B contract, but its live simulator run expired before manual authority began | Harden repeated equal routes, external router mutations, presentation replacement, and restoration, then take the validated manual and semantic shapes through API review; complete same-key A/B acceptance on capable hardware, then cover gestures, adaptive navigation, simultaneous visibility, reconnect, and restoration |
| Automatic native SwiftUI | Transparent discovery remains semantically late; route-owned controls prove initial creation, abort, different- and same-type stack/split replacement, and retained Home without resetting customer state, but only through an internal debug integration; automatic split has no semantic selection views. `EXP-115`/`EXP-116` prove target-scoped semantic authority, `EXP-122` prevents exact-scene manual preemption, `EXP-125`/`EXP-126` cover presentation subtrees, and `EXP-127` leaves an unrelated sibling controller eligible while manual authority is active. `EXP-141` keeps automatic discovery enabled around the actual semantic container without producing a duplicate | Validate automatic behavior in a separate live scene and ordinary automatic-only applications, then take the semantic-container shape through API review |
| Actions | Source-bearing UIKit/SwiftUI taps emit once on their scene; exact-view actions refresh the process representative; public manual errors, view mutations, and internal view work consume exact handoff view/scene when present; source-less work retains last-interacted fallback. `EXP-122` attributes active Compose work to exact-scene M1 and immediate plus settled return work to one fresh H2. `EXP-125` and `EXP-126` do the same across presentation dismissal. In `EXP-127`, work originating from underlying Detail stays on M1 until stop, then switches immediately to fresh Detail. `EXP-128` keeps first Compose, Preview, resumed Compose, duplicate-start, and final Home action/Resource pairs on their exact occurrence IDs. `EXP-132` proves a threshold-qualified real UIKit fling remains exactly once on its origin when navigation starts during deceleration. `EXP-135` proves one automatic SwiftUI Button tap stays on A, while source-less work resumed after B takes over follows B by compatibility. `EXP-129` encodes the A/B precedence oracle but has no completed runtime result | Complete exact precedence with simultaneously visible A/B and a different representative, then finish explicitly targeted downstream runtime rows |
| Resources and traces | Trustworthy start provenance is frozen; manual Resource completions remain with their captured owner; automatic URLSession completion and OpenTelemetry spans use the same scene-handoff model. `EXP-133` backend-confirms one Trace-only request across A→B representative churn; `EXP-134` backend-confirms independent A/B requests completed in reverse order while each retains its own start-scene Home view. Neither scenario emits a matching RUM Resource. `EXP-135` proves an ordinary SwiftUI Button callback is outside the synchronous handoff and its resumed task is source-less. `EXP-136` proves the shared-consumer harness through B join, but the simulator compositor failed before completion twice | Finish the unchanged shared/coalesced completion and simultaneous-window exact-source rows on capable hardware, then normal-handler compatibility, explicit target/scoped API review, and overhead measurement |
| Operations | Internal per-step routing and exact application-wide identity pass focused tests. `EXP-130` proves live Home→Detail success/failure plus duplicate latest-instance reduction. `EXP-131` adds the exact hostless A→B and distinct-key reverse-completion contract | Run `EXP-131` on capable multi-window hardware and complete public target API review; duplicate behavior itself is backend-confirmed |
| Lifecycle and sessions | Independent close, rollover, fresh/retained-reader remount, and cancellation rearming are covered; exact A-to-B open and B close are signal-driven, and A continues on its original Home occurrence after B disconnects; exact activation dispatch and current-state lifecycle waits are implemented in the harness; hidden detached readers retain only their last concrete scene proof, which disconnect clears before requiring a new mount | Prove the activation/background sequence and stable simultaneous-visible peer continuity on capable hardware, then genuine OS disconnect/reconnect, live background/foreground, and concurrent restoration |
| Other signals | Focused ownership exists for logs, mirrored errors, WebView, vitals, fatal context, and profiling identity | Targeted two-window runtime proof and explicit process-wide limitations |
| Session Replay | Coexists in tested two-window runs without an SDK crash | No scene-correct replay work is required here |
| Normal applications | The exact manual-authority set passes 8/8, the focused presentation/manual contract set passes 6/6, six focused semantic-navigation tests pass, and the clean full DatadogRUM rerun passes 1,177/1,177. DatadogTrace remains 151/151; repository lint and both probes build, with the native probe at 134/134 and both customer-shaped SPIs building in Release under Xcode 27 | Live single-scene and custom-handler behavior plus `sendEvent` overhead/reentrancy |

Generic work with no trustworthy source still emits once on the process
representative, intended to be the last-interacted view. This preserves existing
instrumentation but is not exact attribution. Resource/Trace work is limited to
preserving provenance that actually exists; request rewrites across capture or
first-party boundaries are developer misuse and outside this project.

The detailed basis is in [ASSESSMENT.md](MultiSceneSupport/ASSESSMENT.md); exact
payload and backend proof is indexed in [EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

## Confirmed product decisions

Status: approved for multi-window iPad and iPhone applications.

1. Generic work with no trustworthy source uses the process representative,
   intended to be the last-interacted view. It emits once and is never broadcast.
   This compatibility fallback can be inaccurate and must not be presented as
   exact ownership.
2. Entering the background ends only that scene's visible view; foregrounding
   restarts it. Merely losing focus while remaining visible does not end a view.
3. Concurrent scene views overlap within one application RUM session. Scene
   ownership remains reliable internal state and is not serialized as a temporary
   window attribute, separate session, or other new wire concept.
4. Process-wide long tasks, hangs, memory warnings, and crashes emit once on the
   process representative. Shared process/render-loop vitals are not duplicated
   as independent per-window measurements.
5. Session Replay needs crash-free coexistence only. Scene-correct recording,
   touch routing, and replay context are out of scope for this project.
6. iPhone Duo on iOS 27.1 is the release target. Semantic multi-scene support
   before iOS 27 is not required, while normal apps on every supported deployment
   target must remain compatible.
7. Automatic SwiftUI view tracking remains the zero-code default. Exact semantic
   navigation is an optional integration installed once per independent SwiftUI
   navigation container, such as a `NavigationStack`, consuming the application's
   existing path/router and a centralized route-to-RUM resolver. Its exact API
   requires normal review.
8. A semantic integration is authoritative only in its exact navigation
   container; exceptional manual instrumentation is authoritative only for its
   explicitly tracked view. Each must suppress its own duplicate automatic view,
   while automatic tracking continues elsewhere in the scene and application.
9. On the OS range where multi-scene semantics are claimed, SwiftUI lifecycle
   work must belong to the intended RUM view. This is a semantic-attribution
   contract, not a promise about observable callback/command ordering, and it
   cannot depend on unsupported SwiftUI internals.
10. A RUM view represents one committed navigation-path occurrence, not the
   lifetime or identity of a SwiftUI value, `UIView`, or view controller. Returning
   to the same Home platform item after Detail starts a new Home view ID; a
   cancelled transition starts no occurrence.
11. Each scene has one current RUM destination. Sidebars, split panes, tab bars,
    and other simultaneously visible structural regions do not become concurrent
    RUM views. True multi-pane/tab modeling is a separate follow-up project.
12. Backend Execution Context support will eventually represent each window
    branch. The SDK must keep scene ownership suitable for a future Window
    Execution Context ID, but current attribution fixes do not wait for backend
    visualization or invent an interim wire format.
13. Scene-aware manual view start/stop APIs are required. The same customer key may
    exist independently in A and B; an explicit scene wins over inferred process
    context; existing APIs retain their current inferred behavior; and Swift and
    Objective-C surfaces require normal API review without exposing RUM UUIDs.
14. Automatic navigation may continue beneath a scene-targeted manual view, but
    only the latest committed underlying destination is retained. Intermediate
    destinations that were never current and visible emit no RUM view. Exact stop
    reveals the latest destination as a fresh occurrence with a new view ID.
15. Different manual keys may nest. Stopping Attachment Preview above Compose
    creates a fresh Compose occurrence. Re-starting the same `(scene, key)` while
    it is active is instrumentation misuse: remain crash-safe, but add no elaborate
    lifecycle semantics for it.
16. A scene-targeted start pairs only with a scene-targeted stop for the same
    scene and key. Mixing it with a legacy source-less stop is unsupported. The
    existing source-less API continues to use inferred/last-interacted behavior;
    this design adds neither public RUM UUIDs nor returned view handles.
17. The first optional SwiftUI semantic integration covers the router's complete
    current destination, including `NavigationStack` paths, sheets, and full-screen
    covers. A presentation replaces the scene's destination. Dismissal reveals a
    fresh underlying occurrence before post-dismiss customer work, without a
    duplicate automatic view.
18. Resource and Trace work is limited to preserving trustworthy provenance and a
    shared frozen owner. The SDK does not guess after causality is lost and does
    not defend developer-written handlers that rewrite a request across automatic
    capture or first-party header-injection boundaries.
19. Operations use exact application-wide `(name, operationKey)` identity; scenes
   never namespace it. Every step resolves its view independently. A last-proven
   snapshot is a fallback, not permanent ownership by the start scene.
20. Starting the same Operation identity twice tracks only the latest start in
    the client. A later success or failure ends only that instance; the earlier
    backend operation remains open until its four-hour timeout. The SDK emits no
    synthetic end. Customers must use a unique key for every concurrent instance.
21. The Operation view-target escape hatch requires normal Swift, Objective-C,
    protocol-compatibility, and RFC review. Existing APIs retain inferred behavior,
    and no internal RUM view UUID becomes public.
22. Delivery priority is view occurrence/lifecycle and navigation; scene-aware
    manual views; downstream ownership; normal-app compatibility; then Session
    Replay crash safety. Multi-pane modeling and Execution Context serialization
    remain follow-up work.

The complete Operation contract, proposed Swift and Objective-C escape hatch,
customer workflow, and required tests live only in
[OPERATIONS.md](MultiSceneSupport/OPERATIONS.md).

## Resume here

### Checkpoint

The branch is `valpertui/multiple-windows-scenes`. The latest production SDK
checkpoint is signed commit `eb89a4f24` (`Prototype SwiftUI semantic navigation
integration`), followed by signed probe commit `3af24003c` (`Exercise semantic
navigation API in native probe`). Together they implement and validate the iOS
27 builder-owning semantic-navigation SPI through `EXP-141`. The scene-targeted
manual-view prototype is signed commit `01e5d1ffb`, followed by signed
documentation commit `3b26da106`; it adds the Swift SPI, Debug-only Objective-C
selectors, compatibility fallback, customer-call-site probe migration, and
restored-window normalization validated by `EXP-137` through `EXP-140`.
The preceding production SDK checkpoint is `f452e9e3f` (`Preserve semantic
presentation authority through dismissal`), following the exact-scene manual
stack in `29c8cec2c` and `b1a0fb6b8`. The latest signed documentation checkpoint
is `d2a5b9491` (`Document shared request validation boundary`), following signed
probe commit `e804d3bd6` (`Exercise shared URLSession ownership across scenes`),
SwiftUI-task documentation checkpoint `75becb324`, and probe checkpoint
`2972d3de1`. Earlier probe checkpoints are signed documentation commit
`0dca626df` (`Document trace-only reverse completion evidence`), signed probe
commit `353679bb5` (`Exercise trace-only reverse completion across scenes`), `130ba7646`
(`Exercise trace-only URLSession attribution across scenes`), `3c9730805`
(`Exercise UIKit scroll attribution across navigation`), `a653e29f2` (`Prepare
cross-scene operation attribution probe`), `5d536e0bd` (`Exercise operation
attribution across navigation`), `9fa58e3c0` (`Exercise same-key manual views
across scenes`), and `af2a2666d` (`Exercise nested manual view authority`). Their
frozen trees from newest to oldest are
`232715c3d7ff67f719508d9d37b2ba5161b27f15`,
`163604e679db1021a16fd6a11959d7ba069afe5f`,
`05f9db5089a769acbb1fe5df79645641cc83464e`,
`614e83f2d1bdad6ba166f152b9bc90c5a2bc30a9`,
`efe7f2a754c0191ebfacd1952eb422a41fafa315`,
`942f1207f6e6dad9cfab6c897894f2e1ea5f7a15`,
`3f1edaf17f4d7dd4fe654c8738ca6cb9c09440f7`,
`67eb64a23f985494992ef53db36130557414fd1d`,
`22ddf1f9b4ab1193cc1bb635b6ebae83f97e0f20`,
`0b41cbbb34cd5ff138a9b792a0c8e528505e17a8`, and
`082310e18ecfbdb9fc18a4f9d1914c7660a6edfd`. The approved product decision
checkpoint is
`b61e783a6`; the public-navigation proposal starts at `b5494adb0`.
All branch commits through `e804d3bd6` are verified signed local commits and must
not be pushed. Earlier signer outages and the exact rewritten commit
mapping remain preserved in the experiment ledger. The
chronological checkpoint table in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md) is authoritative.

Resume local implementation with the builder-owning complete-destination SwiftUI
SPI described in [NAVIGATION_API.md](MultiSceneSupport/NAVIGATION_API.md). Its
first customer-shaped run must cover H1 → D1 → H2, Sheet dismissal to fresh H3,
and full-screen-cover dismissal to fresh H4 while automatic tracking remains on.
Then prototype the opaque Operation `view: .current(in:)` SPI described in
[OPERATIONS.md](MultiSceneSupport/OPERATIONS.md). Public review blocks stable
promotion, not either experiment. Keep same-key A/B manual views, semantic-A plus
automatic-B, cross-scene Operations, activation, shared-request completion, and
adaptive/restoration rows in the physical-device queue.

`EXP-090` through `EXP-105` establish the debug SwiftUI occurrence mechanics,
including abort, replacement, retained return, state preservation, and remount.
`EXP-106` through `EXP-113` make stack, split, UIKit transition, and exact
open/close results signal-driven, locally self-validating, and backend-confirmed.
`EXP-114` adds exact activation dispatch, latched scene-state conditions, durable
terminal-result logging, and explicit `INCONCLUSIVE` classification when the
topology does not transition. The current simulator did not produce a qualifying
activation sequence and crashed its own compositor during one retry. Native
gesture, adaptive topology, and genuine lifecycle rows remain separate.
`EXP-115` then enables automatic and explicit SwiftUI tracking together and
proves target-scoped authority with an exact backend H1/D1/H2 sequence and no
duplicate automatic view. `EXP-116` installs that route-owned boundary once at a
probe navigation container, with one bound path and centralized resolver, and
passes return, abort, and same-type replacement locally and in backend intake.
`EXP-117` records why host-side uninstall remains mandatory for an isolated clean
run. `EXP-118` adds the exact separate-scene automatic/semantic discriminator.
Two clean simulator attempts proved that A's authority does not suppress B's
automatic controller views, but `backboardd` crashed before the decisive B marker
and terminal oracle. That row remains explicitly simulator-inconclusive and is
queued for physical multi-window hardware. `EXP-119` proves exceptional explicit
Sheet dedup and eventual automatic Home restoration, while conclusively exposing
incorrect immediate `onDismiss` ownership. `EXP-120` then proves that direct
keyed manual start/stop is also not authoritative: automatic discovery displaces
M1 during its authority interval and takes its action/Resource work. `EXP-121`
proves the first internal stack route fixes that preemption but still reveals a
generic fallback. `EXP-122` closes the narrower defect: the clean 16/16 run and
backend intake contain H1 → authoritative M1 → fresh H2, with no intervening
fallback and exact active/immediate/settled ownership. `EXP-123` then proves
handler authority alone does not suppress the automatic controller representing
a semantic Sheet. `EXP-124` produces the correct five-view chain but exposes an
oracle error: a pending Resource can delay an outgoing aggregate snapshot beyond
semantic stop. The corrected `EXP-125` run passes 14/14 locally and in backend
intake with exact H1 → semantic Sheet M1 → fresh H2, no automatic Sheet, and
immediate plus settled dismissal work on H2. `EXP-126` independently repeats the
complete-destination contract for `fullScreenCover`: its clean 14/14 run and 28
backend events contain H1 → semantic Cover M1 → fresh H2, no automatic
`ProbeFullScreenCoverView`, exact pre/active/dismiss ownership, and zero errors or
crashes. `EXP-127` then proves sibling containment on real iOS 27 controller
topology: the left manual boundary stays authoritative while right Detail stages,
and exact stop reveals a fresh right Detail occurrence. The accepted hardened
run passes 19/19 and its 31-event backend session contains four views, 11 actions,
11 Resources, three long tasks, one session, and one vital with no error or crash.
`EXP-128` then exercises the approved nested manual suffix in a real SwiftUI
destination hierarchy. The first attempt exposed a driver race because the exact
Compose mapper snapshot arrived before its wait step; exact occurrence waits now
accept already-recorded immutable evidence. The clean retry passes 29/29 with
H1 → C1 → P1 → fresh C2 → fresh H2. A duplicate active Compose start creates no
new view; its action and Resource remain on C2. The seven-view backend session
adds only ApplicationLaunch and the expected startup fallback, and reports no
error or crash.
`EXP-129` then adds the exact two-scene same-key and reverse-stop contract. Its
hostless plan passes 91/91, but the clean simulator run reached only the A/B
automatic prefix before the Xcode/device session expired. It has no terminal or
backend result and is queued for capable hardware.
`EXP-130` adds an independently driven single-scene Operation/navigation
scenario. Its 27/27 local oracle and 93/93 full plan agree with backend intake:
successful and failed Operations retain different start/end views across
navigation, while a duplicate identity emits `[start, start, end]`, reduces from
the latest start, and leaves the earlier raw start open without a synthetic end.
`EXP-131` prepares A→B success/failure and two distinct same-name Operations
completed B-before-A. The full hostless plan passes 100/100 with four adversarial
cross-scene ownership fixtures; live execution remains in the hardware queue.
`EXP-132` then drives a real threshold-qualified UIKit fling on Secondary 2,
presents Secondary 3 while UIKit is still decelerating, and proves one `.scroll`
action remains on the stopped origin occurrence. The fresh destination owns its
post-navigation action and Resource. At that checkpoint the full probe plan
passes 109/109; mapper and backend intake agree on exact ownership and count.
`EXP-133` then starts a Trace-only URLSession request on A/Home H1, makes B/Home
B1 representative, and releases the response from B. The 8/8 run and exact
backend predicates find one span on A/H1, none on B/H1, the original session,
and no RUM Resource for the Trace-only URL. The full probe plan now passes
115/115.
`EXP-134` then starts independent requests on A/Home H1 and B/Home B1 and
completes them B-before-A while deliberately making the opposite scene
representative. The 14/14 run and backend predicates find exactly one span for
each request on its own start view, zero on the opposite view, the same RUM
session for both, and zero matching RUM Resources. The full probe plan now
passes 120/120.
`EXP-135` then drives a real SwiftUI Button in A, creates a child task, suspends
it, opens B, and resumes from B. The automatic button tap emits once on A/H1.
Diagnostic evidence shows the SDK handoff is already nil in the SwiftUI closure
and at task creation; UIKit's ambient scene trait begins as A but changes to B
after suspension. The resumed manual Action and Resource consequently use the
approved source-less fallback and land on B/H1. The strict expected-A oracle
terminates `FAIL` after matching four of six expectations, intentionally preserving
the unsupported exact-origin contract, while backend intake confirms the same
boundary and reports zero errors or crashes. `EXP-136` then adds the shared
A-created/B-joined URLSession task contract and raises the plan to 132/132; two
simulator attempts crash `backboardd` before response release, so exact span
ownership remains a physical-device row. `EXP-137` through `EXP-140` replace the
probe's internal manual-view calls with the customer-shaped Swift SPI and pass
manual, nested, Sheet, and full-screen-cover semantics locally and in backend
intake. The rejected first nested run exposes restored `WindowGroup` metadata
surviving uninstall; run normalization plus exact-session view inspection close
that harness defect. `EXP-141` then replaces the probe-only navigation wrapper
with the actual iOS 27 semantic-navigation SPI. Its combined stack, Sheet, and
full-screen-cover run passes 38/38 locally and matches backend intake across seven
fresh semantic occurrences, including four distinct Home IDs. The full probe plan
now passes 134/134. `EXP-142` closes sequential repeated equal routes through
native value links and raises the probe plan to 135/135; initial restoration
directly into repeated equal values remains open.
The complete chronology and every failed attempt live in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

### Exact next work

The deterministic harness is complete through `EXP-142`; [PLAN.md](MultiSceneSupport/PLAN.md)
owns the finished phases and full release matrix. The scene-aware manual-view and
builder-owning semantic-navigation proposals are both implemented behind iOS 27
experimental boundaries and validated through customer-shaped calls. Continue in
this order:

1. Harden the semantic-navigation SPI against external router mutation,
   presentation replacement, and restoration, including initial restoration into
   repeated equal values. Keep automatic
   tracking enabled and require committed navigation-path occurrences only. Add a
   presentation-free convenience shape if it remains implementable without
   weakening the centralized complete-destination model. Do not promote symbols
   before normal API review.
2. Rerun `swiftui.coexistence.sibling-container-authority` through the actual
   semantic SPI, then add a bounded semantic-A/automatic-B isolation run if the
   simulator remains stable. Preserve the existing probe-only paths as controls.
3. Finish `swiftui.coexistence.same-key-manual-two-scenes` on iPhone Duo or a
   physical multi-window iPad. The simulator prefix reached both native scenes
   but expired before manual starts. Stop B before A and prove each exact
   scene/key closes only its own Compose occurrence while automatic tracking
   remains active.
4. Finish `swiftui.coexistence.semantic-a-automatic-b` on physical multi-window
   hardware. The simulator prefix already proves B automatic discovery remains
   eligible; require the final B marker and backend owner before closing it.
5. Run `traces.urlsession-shared-request` unchanged on iPhone Duo or a physical
   multi-window iPad. The simulator retry proves A creation and B join but twice
   lost `backboardd` before release. Require one A/Home span, zero B-owned or
   duplicate spans, and no matching RUM Resource.
6. Close the remaining action-attribution hardware row: keep A and B
   simultaneously visible, make B representative, interact in A without a
   focus-driven fallback, and prove exact A ownership. `EXP-132` already closes
   UIKit drag/deceleration across same-scene navigation and should remain a
   regression gate rather than be repeated as a prerequisite.
7. Run `operations.cross-scene.lifecycle` on capable hardware. Require A→B
   success/failure, distinct A/B Home owners, and distinct-key reverse completion
   with eight raw steps and four reduced Operations.
8. Run `windows.activation-sequence` on iPhone Duo or a physical multi-window
   iPad. Require the activated scene to become foreground-active and the peer to
   become background before asserting fresh view occurrences or marker ownership.
9. Take the experimentally validated manual-view and semantic-navigation shapes
   through normal API review. Reconsider using automatic-predicate `RUMView` as
   the semantic descriptor, the required presentation generic for stack-only
   customers, stable availability, and Objective-C Release exposure for manual
   APIs.
10. Route recognized native gestures, adaptive resize, and stable simultaneous A/B
   topology through the real-device/human queue; ignored simulator input is not
   evidence.
11. Run genuine disconnect/reconnect, per-scene background/foreground, and
   concurrent restoration.
12. Prototype and then review the Operations public target. Keep application-wide
   `(name, operationKey)` identity; `EXP-130` already closes duplicate-start
   backend behavior, while A-to-B execution remains item 7.
13. Finish explicitly targeted downstream-signal runtime rows. `EXP-133` closes
   one-request Trace-only owner freezing across A→B representative churn;
   `EXP-134` closes independent two-request reverse completion; `EXP-135`
   classifies an ordinary SwiftUI Button child task as source-less after the
   framework callback escapes the synchronous handoff.
   Then prove live single-scene/custom-handler compatibility and measure
   event-handoff recursion and overhead. Repeat the release matrix on iOS 27.1
   and iPhone Duo.
14. Only after the multi-scene runtime is frozen and every experiment is closed or
   explicitly deferred, execute the
    [single-scene reliability extraction](MultiSceneSupport/DEFERRED_SINGLE_SCENE_EXTRACTION.md).
    Preserve the completed branch, prove every extracted fix as a source-less
    defect on `develop`, rebuild the multi-scene branch on the generic stack, and
    stop before any push.

### Proven and implemented

- Scene identifiers and routing targets are internal and are never serialized.
- Core UIKit and explicit SwiftUI view stacks, sessions, navigation, actions,
  scrolls, INV, lifecycle, rollover, delayed completions, WebView containers,
  Operations, and representative fatal context accept scene-aware routing.
- The hidden SwiftUI scene reader and UI-event causal handoff activate only when
  the app declares `UIApplicationSupportsMultipleScenes = true`. Ordinary apps
  retain the original direct SwiftUI modifier path.
- On iOS 17+, a scene-level custom UIKit trait bridges each real scene identity
  into SwiftUI. It improves attribution but does not guarantee internal tracking
  occurs before customer outer lifecycle callbacks.
- On iOS 27, explicitly tracked multi-scene SwiftUI views use that inherited
  trait at hidden-reader creation to enqueue the semantic view before early
  customer work. iOS 15-26, visionOS, and single-scene applications retain their
  prior lifecycle path. Three clean final-code A/B runs and focused stress pass,
  while the construction/visibility matrix remains incomplete.
- The internal keyed-occurrence seam can replace a RUM occurrence without
  replacing customer SwiftUI content. Its debug per-window source now reveals a
  retained returned route before immediate post-pop work and preserves the same
  customer state token. The same key/generation model independently replaces
  retained split Detail occurrences in two windows. A source-started returned
  split occurrence can also transfer to a replacement SwiftUI tracking state
  without a duplicate start. This is integration evidence, not a shipped API.
- On the iOS 27 declared multi-scene path, active explicit SwiftUI boundaries are
  registered weakly and suppress automatic controller discovery only for a
  containing hierarchy. Inactive, detached, and unrelated sibling boundaries do
  not suppress discovery, and UIKit tracking keeps precedence. `EXP-115` proves
  exact H1/D1/H2 occurrence output with both SwiftUI tracking modes enabled.
- `EXP-127` proves that containment remains scoped between two sibling
  `NavigationStack` controller branches under one SwiftUI host. A left authority
  boundary does not suppress right-hand automatic materialization, and the latest
  right destination becomes one fresh current occurrence when manual authority
  ends. The topology assertion is mandatory and times out as `INCONCLUSIVE`.
- `EXP-128` proves the approved distinct-key manual suffix with real probe
  destinations: Compose C1 → Preview P1 → fresh Compose C2. Duplicate active
  Compose start remains crash-safe, creates no view, and leaves action/Resource
  ownership on C2; final exact stop reveals fresh automatic Home H2.
- The probe-only container prototype accepts one binding to the application path
  and one centralized route resolver, and owns root/destination materialization
  so the route-owned boundary is early enough. `EXP-116` preserves return,
  cancellation, and same-type replacement semantics without putting RUM metadata
  into each destination view. This is design evidence only; no public API was
  added.
- Operations resolve every step independently. Trustworthy new context replaces
  the last-proven snapshot; the snapshot and then process representative are
  fallbacks. Identity is the exact application-wide `(name, operationKey)` tuple.
- Profiling uses the same typed Operation identity and distinguishes omitted from
  empty keys.
- Session Replay is required only to coexist without an SDK crash.
- The standalone probe now resolves 50 named scenarios from command-line input,
  preserves exact known legacy environment profiles, and fails closed before SDK
  initialization. It records ordered versioned JSONL signals, keeps call-site
  source separate from mapper-observed RUM ownership, derives view start/stop from
  snapshots, and evaluates ordered/negative expectations using only `PASS`,
  `FAIL`, `SKIPPED`, and `INCONCLUSIVE`. Its observable driver waits for exact
  scene, path/selection, destination, and RUM-occurrence signals. Home return,
  abort, same-/different-type replacement, split replacement, and retained split
  return plus deterministic UIKit cancel/finish, exact scene open/close, and
  lifecycle-gated activation passed 45/45 at the `EXP-113` harness checkpoint.
  Clean semantic runs through `EXP-113` have one final verdict per run. `EXP-114` deliberately emits
  `INCONCLUSIVE` when the simulator cannot prove the requested scene-state
  transition, and writes the terminal result to OSLog so it survives an Xcode
  console-session expiry. The automatic SwiftUI split control
  produces the intended semantic `FAIL`.
  This improves evidence quality but does not change the RUM support verdict.
- UIKit split scenario manifests forbid Primary as a RUM view. On iOS 27 in a
  declared multi-scene app, the shipping handler now ignores regular-width
  Primary/supplementary columns while retaining their probe lifecycle as
  structural diagnostic evidence. Cancellation keeps S2's UUID and completion
  creates a fresh returned S1 UUID. The startup SwiftUI hosting fallback and
  application-subclassed split-container case remain separate gaps.

### Validation snapshot

As of 2026-09-15:

- The current RUM plan passes 1,177/1,177. Earlier complete suites pass:
  Internal 477/477, Logs 95/95,
  Trace 151/151, WebView 31/31, and Profiling 233/233.
- Focused retained-route, occurrence-isolation, transition-arbiter, Operations,
  UIKit-scroll, and OpenTelemetry ownership regressions pass. Native SwiftUI
  edge gestures remain unproven because `EXP-100` produced no navigation signal.
- The named runner validates fail-closed startup (`EXP-106`), and its recorder,
  oracle, scene registry, and observable driver pass 134/134. Clean runs prove
  Home₁/Detail/Home₂, aborted and replacement stacks, split replacement/retained
  return, and exact per-occurrence action/Resource ownership (`EXP-109` through
  `EXP-111`). The fully driven automatic SwiftUI split control fails locally as
  expected because it has no semantic selection boundary.
- Clean UIKit cancellation and completion pass 11/11 and 13/13. Cancellation
  retains S2; completion creates a fresh returned S1. Backend intake has exact
  marker pairs, no Primary, no errors, and no work on the startup hosting fallback
  (`EXP-112`).
- A clean exact-lifecycle run passes 9/9: A opens B through A's registered
  executor, B emits and uploads `before-close`, B disconnects, then A emits and
  uploads `after-peer-close` on A's unchanged Home UUID (`EXP-113`). The
  fullscreen simulator topology does not close simultaneous-visible continuity.
- The exact activation scenario dispatches through each registered
  `UIWindowScene`, acknowledges target foreground state, and treats the peer's
  background state as a latched condition so notification ordering cannot create
  a false timeout. The completed source-less control reached backend intake; the
  lifecycle-gated retries remained inconclusive, including one interrupted by a
  simulator `backboardd` SIGABRT rather than an app/SDK crash (`EXP-114`).
- With automatic SwiftUI discovery and explicit route-owned tracking enabled
  together, `swiftui.stack.return` passes 7/7. Mapper and backend intake contain
  exactly ApplicationLaunch, Home H1, Detail D1, and Home H2; H1/H2 are distinct
  and no hosting-controller duplicate exists (`EXP-115`).
- The once-per-container probe wrapper repeats that exact return result, rejects
  an aborted Detail occurrence, and gives same-named Detail₁/Detail₂ distinct
  UUIDs with exact final action/Resource ownership. All three isolated runs agree
  locally and in backend intake (`EXP-116`).
- The exceptional-manual-Sheet scenario builds. Its
  corrected local and backend run has exact H1/S1/H2 occurrence and dedup
  evidence, but fails because immediate `onDismiss` action/Resource work remains
  on S1 before H2 starts (`EXP-119`).
- The direct keyed-manual scenario and hardened oracle bring the probe plan to
  65/65 tests. Clean simulator/backend runs prove M1 is displaced by an automatic
  fallback during its authority interval and that Compose work follows that
  fallback; fresh H2 eventually receives only settled work (`EXP-120`).
- The internal exact-scene manual path routes through the target scene's handler
  stack. `EXP-121` proves M1 authority and isolates a generic-fallback reveal;
  `EXP-122` rejects that structural candidate and passes 16/16 with exact
  H1/M1/fresh-H2 mapper and backend ownership. Existing source-less APIs are
  unchanged, and no public API has been added.
- The exact-scene semantic Sheet successor passes 14/14 (`EXP-125`). A
  suppression-only state follows the native presentation subtree without
  publishing its own RUM view, so automatic discovery remains enabled outside
  that subtree. Mapper and backend contain exactly H1, semantic Sheet M1, and
  fresh H2 after startup; active work uses M1 and immediate plus settled dismiss
  work uses H2. The backend session has 29 events and zero errors or crashes.
  `EXP-123` preserves the failure without that boundary, and `EXP-124` preserves
  the corrected lesson that delayed aggregate snapshots are not authority clocks.
- The independent full-screen-cover successor passes the same 14/14 contract
  (`EXP-126`). Its mapper and 28-event backend session contain only the expected
  startup views plus H1, semantic Cover M1, and fresh H2. No automatic
  `ProbeFullScreenCoverView` starts; active work owns M1, both dismiss pairs own
  H2, and zero errors or crashes appear. This closes internal presentation-style
  parity without approving the public semantic API.
- The sibling-container scenario passes 19/19 twice after the controller topology
  was proven. Final backend intake contains exactly four views and 11
  action/Resource pairs: Home work uses H1,
  underlying Detail work stays on M1, and immediate plus settled post-stop work
  uses one fresh Detail. The first pass is retained because its probe-only
  ancestry reader became a late fifth view; the accepted predicate filters only
  that measurement type.
- The nested keyed-manual scenario passes 29/29. Backend intake contains distinct
  automatic Home H1, Compose C1, Preview P1, Compose C2, and automatic Home H2
  after startup. The duplicate
  Compose marker and Resource remain on C2, and the final immediate return pair
  uses H2. The first attempt is retained as a harness failure because the C1
  snapshot arrived before its wait step. The driver now searches
  already-recorded evidence for exact immutable RUM occurrence waits.
- The two-scene same-key scenario raises the local probe plan to 91/91 and rejects
  shared Compose identity, cross-scene work, wrong-scene stop effects, and reused
  returned Home occurrences. Its clean iPad simulator run reached distinct A/B
  native scenes, then lost its Xcode/device session before manual authority
  began. It produced no backend documents or terminal verdict; `EXP-129`
  therefore remains hardware-inconclusive.
- The Operation/navigation scenario `operations.navigation.lifecycle` passes
  27/27 locally; the full probe plan is 93/93. Backend intake contains six fresh
  semantic Home/Detail occurrences, seven raw Operation steps, and three reduced
  Operations. Success
  preserves H1→D1, failure preserves H2→D2 and its reason, and the duplicate case
  reduces from D3→D3 while its earlier H3 start remains unclosed. The corrected
  four-hour-timeout warning appeared, with no synthetic end, error event, or
  app/SDK crash (`EXP-130`). Exact identifiers and artifacts for these runs stay
  in [EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).
- The exact cross-scene Operation scenario raises the probe plan to 100/100. Its
  driver proves the eight A/B invocations and reverse-completion order. The
  semantic oracle passes its valid fixture and rejects four ownership failures.
  Because the same two-scene simulator topology already expired in `EXP-129`, no
  redundant runtime claim is made; `EXP-131` is queued for capable hardware.
- The real UIKit scroll/navigation scenario raises the probe plan to 109/109.
  A measured lift above the SDK's swipe threshold entered deceleration, then
  Secondary 3 appeared before deceleration ended. Exactly one `.scroll` action
  stayed on the stopped Secondary 2 occurrence; a fresh Secondary 3 owned the
  immediate action and Resource. The terminal oracle, mapper output, backend
  count and ownership, and zero-error/crash checks all pass (`EXP-132`).
- The Trace-only URLSession scenario raises the probe plan to 115/115 and passes
  8/8 live assertions. After B/Home B1 became representative, one held request
  completed with its original A/Home H1 and session correlation. Backend counts
  are exactly one for A/H1, zero for B/H1, and zero matching RUM Resources
  (`EXP-133`). The first attempt ended with the Xcode interaction session and no
  crash evidence; only the clean retry is acceptance evidence.
- The two-request Trace-only scenario raises the probe plan to 120/120 and
  passes 14/14 live assertions. B completed before A while the opposite scene
  was representative for each completion. Backend intake contains exactly one
  A span on A/Home H1 and one B span on B/Home B1, zero opposite-view matches,
  both on the expected RUM session, and zero matching RUM Resources
  (`EXP-134`). The initial backend query returned zero before indexing caught
  up; the accepted 202 upload and later raw plus aggregate results are retained
  as the complete evidence chain.
- The real SwiftUI Button → structured-task scenario raises the probe plan to
  126/126 (`EXP-135`). Its accepted run emits exactly one automatic tap on A/H1,
  then intentionally fails the expected-A semantic oracle after matching four
  expectations because resumed source-less Action/Resource work lands on the
  later B/H1 representative. SDK handoff is nil at callback, task start, and
  resume; the ambient UIKit scene trait changes from A to B across suspension.
  Backend intake confirms those owners, one tap, and zero errors/crashes. Four
  earlier timeout/tooling attempts and the pre-diagnostic failure remain recorded
  separately and make no support claim.
- The shared-request scenario adds six focused tests (`EXP-136`). Two clean
  simulator runs reached A creation and B rendering; the retry also passed the B
  join assertion without creating another task. Both then crashed simulator
  `backboardd` in the same Metal validation path before response release. No span,
  terminal result, app crash report, or RUM error/crash signal exists. The
  unchanged 132/132 contract is queued for capable physical hardware.
- The customer-shaped scene-targeted manual API runs pass in `EXP-137` through
  `EXP-140`: H1/Compose/H2, nested Compose/Preview/Compose/Home, Sheet, and
  full-screen cover all preserve fresh occurrence and action/Resource ownership.
  Four backend sessions contain zero errors/crashes. Swift/custom/NOP forwarding,
  Debug-only Objective-C selectors, lint, and an Xcode 27 Debug plus Release build
  pass. The API-surface verifier reports only the expected experimental additions;
  no baseline changed.
- The actual semantic-navigation SPI passes `EXP-141`: automatic tracking stays
  enabled while one customer-shaped container produces H1/D1/H2/Sheet/H3/Cover/H4
  with distinct IDs and no automatic duplicate. All 38 local expectations pass;
  backend intake contains 25 actions and 25 Resources on the seven exact semantic
  owners, plus zero error/crash events. Six focused SDK tests, the full 1,177-test
  RUM suite, the 134-test probe suite, and an Xcode 27 Release build pass.
- Both probes build through Xcode 27; package build, recorded repository lint, and
  focused changed-source lint pass at their stated checkpoints.

These are regression and implementation checks, not substitutes for the missing
runtime rows. Detailed run evidence remains in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

### Blockers and workspace safety

Stable SwiftUI and Operation APIs require normal RFC/API review; experimental
iOS 27 SPI implementation and validation are not blocked by that review. The
branch tail through `3af24003c` is signed, and a raw commit-object audit finds a
signature block on all 105 commits after the `develop` merge base. The earlier
signer outages, replaced hashes, and exact frozen trees remain documented in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).
The iOS 27 integration-runner half-and-half layout repeatedly respawned
`backboardd`, although the standalone native `WindowGroup` probe opens two windows.
The standalone probe also reproduced a `backboardd` CoreAnimation/Metal SIGABRT
while rapidly requesting exact A/B activation; no probe crash or backend event was
recorded for that interrupted run. Do not repeat that activation loop on this
simulator.
The current iPad simulator also rejects `devicectl appResize` because it lacks
Resizable App Management; adaptive width proof needs a capable destination.
Xcode's packaged device-interaction skill can be exported before opening its
short-lived session. `EXP-132` used the documented measured-coordinate command
and now supplies real UIKit gesture evidence. Earlier sessions expired before
input and remain tooling-only attempts. Other native gesture and visual claims
still require a live interaction key or human/device evidence; programmatic runs
do not become native-gesture proof.
Ignored native edge drags, fullscreen-only peer-window layouts, partial scene
restoration, and unsupported resize are tracked in the dedicated
[physical-device and human-driven queue](MultiSceneSupport/PLAN.md#physical-device-and-human-driven-queue).
Those rows require observable path/coordinator/lifecycle evidence, not more
unverified simulator touches.

`--probe-run-mode clean` is an in-app manifest value, not a host teardown action.
Back-to-back Xcode install/run calls can leave semantic view documents carrying
the previous run's global probe attribute even when later actions and Resources
use the new run ID (`EXP-117`). `EXP-138` additionally proves that the simulator
window system can restore an old `WindowGroup` value after successful uninstall
and absent-container proof. The probe now normalizes restored telemetry while
preserving routed window identity. Continue explicit host teardown and reject any
backend set whose view documents do not all carry the requested
`@context.probe.run_id`.

Do not stage, commit, revert, or expose
`Datadog/Datadog.xcodeproj/project.pbxproj` or
`xcconfigs/Datadog.local.xcconfig`. Both predate this work and the latter contains
local credentials. An exact `git add` is insufficient while the xcconfig is
pre-staged; use `git commit --only -- <exact paths>` or an isolated index, then
verify the commit tree and restore/preserve its exact `AM` state.

Rejected experiments and do-not-repeat guidance are authoritative in
[REJECTED_APPROACHES.md](MultiSceneSupport/REJECTED_APPROACHES.md).

## Open API-review questions

Product behavior is settled for this project. The concrete alternatives, call
sites, compatibility constraints, and required tests are consolidated in
[NAVIGATION_API.md](MultiSceneSupport/NAVIGATION_API.md). API review still needs
to choose:

- the stable container-level SwiftUI wrapper/modifier, path abstraction, root
  descriptor, route-resolver shape, destination-builder integration, and
  availability surface. `EXP-141` proves the experimental builder-owning SPI; a
  passive root-only modifier remains known-too-late. Review should also decide
  whether stack-only customers need a presentation-free overload and whether a
  semantic descriptor should avoid `RUMView.isUntrackedModal`;
- the public representation and lifecycle ownership of the experimentally proven
  target-scoped authority boundary between semantic integration, automatic
  discovery, and exceptional manual views;
- the Swift and Objective-C signatures and naming for scene-aware manual view
  start/stop; and
- the shared view-target abstraction used by Operations, including how UIKit
  objects are synchronously erased without retaining them or exposing RUM UUIDs.

One current destination per scene, scene-aware manual view targeting, automatic
SwiftUI as the default, and future Window Execution Context representation are
approved direction rather than open questions. Execution Context serialization
and true multi-pane/tab modeling remain explicitly separate follow-up projects.

## Completion gates

[PLAN.md](MultiSceneSupport/PLAN.md#completion-gates) owns the exhaustive release
checklist. The support claim remains experimental until:

- automatic SwiftUI remains scene-isolated and zero-code by default without
  producing cross-scene attribution or duplicate views, while the optional
  reviewed container integration provides exact root/destination occurrence
  semantics in both native `WindowGroup` and UIKit-hosted applications;
- the explicit iOS 27 early-start path passes aborted/preloaded containers,
  live simultaneous transitions, split navigation, visible-peer close continuity,
  surviving-reader reconnect, and restoration without
  inventing a view for construction alone; modal occurrence navigation and
  crash-safe close ownership already pass;
- UIKit and SwiftUI navigation, including cancelled interactive transitions,
  actions, lifecycle, disconnect, and restoration pass the concurrent-scene
  matrix;
- each scene exposes only its current destination as a RUM view; structural
  split/sidebar/tab containers do not create competing active views;
- the optional container-level SwiftUI semantic integration consumes an existing
  path/router, creates one fresh UUID per committed navigation occurrence,
  coexists with automatic tracking, and suppresses duplicate automatic views only
  in its authoritative container;
- scene-aware manual start/stop lets the same customer key coexist in A and B,
  stops only the explicitly targeted scene, preserves old inferred APIs, and has
  reviewed Swift and Objective-C surfaces;
- Operations pass live cross-window and duplicate-start validation and ship only
  with the reviewed explicit target API;
- bounded Resource/Trace provenance and source-less fallback behavior pass the
  remaining runtime cases without adding request-rewrite scope;
- downstream signals have explicit runtime-backed support levels and Session
  Replay continues to coexist without an SDK crash;
- live ordinary-app regression, custom-handler, and event-dispatch performance
  checks pass; and
- internal scene ownership is stable and naturally ready to map to a future
  Window Execution Context ID without any temporary serialized scene concept; and
- the complete matrix passes on iPhone Duo with iOS 27.1.
