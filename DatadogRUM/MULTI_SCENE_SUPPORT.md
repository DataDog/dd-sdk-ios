# RUM multi-scene support

This is the canonical entry point for concurrent `UIWindowScene` support in
Datadog RUM. It records the current contract, support status, decisions, and exact
resume point. Detailed evidence and chronology are split by ownership so future
work can start here without reading the complete experiment history.
It remains separate from `RUM_FEATURE.md` until the behavior is implemented,
validated, and ready to become a supported contract.

Last updated: 2026-09-14

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
| [Experiment history](MultiSceneSupport/EXPERIMENTS.md) | You need exact run/session IDs, chronological observations, rejected attempts, or checkpoint history |
| [Navigation API proposal](MultiSceneSupport/NAVIGATION_API.md) | You are reviewing the optional SwiftUI container integration, scene-aware manual views, coexistence rules, or Swift/Objective-C compatibility |
| [Operations contract](MultiSceneSupport/OPERATIONS.md) | You are changing Operation identity, per-step attribution, duplicate-start behavior, public targeting, documentation, or tests |

Read this overview first, then open only the document that owns the question.
`EXPERIMENTS.md` uses stable `EXP-*` identifiers; append new experiments and never
renumber them.

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
A probe-only once-per-container `NavigationStack` wrapper now consumes one bound
path and one centralized route-to-RUM resolver, then installs the existing
route-owned tracking boundary at the root and each materialized destination.
Clean return, aborted-push, and same-type-replacement runs preserve exact
occurrence and downstream ownership semantics with no automatic duplicate
(`EXP-116`). This proves an integration shape, not a reviewed public API. The
customer-facing signature remains unimplemented and requires API review.

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
remain unchanged; public scene-aware Swift and Objective-C overloads still need
normal API review.

Nested manual authority and duplicate-start crash safety now have independent
runtime evidence (`EXP-128`). Automatic Home H1 gives way to Compose C1, then
Preview P1; stopping Preview creates a fresh Compose C2, and a duplicate active
Compose start creates no additional view or restart. C2 owns the resumed and
duplicate-start action/Resource pairs. Stopping C2 reveals fresh automatic Home
H2 before both post-stop pairs. The local oracle passes 29/29, and backend intake
contains the exact H1/C1/P1/C2/H2 occurrence chain after startup with distinct
Compose and Home IDs. This closes the one-scene approved manual-stack runtime
discriminator; same-key isolation across live scenes and public API review remain.

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
automatic/manual-coexistence, and Operation/navigation scenarios through
`EXP-130` pass 93/93 tests. The prepared two-scene same-key scenario remains
hardware-gated; the single-scene Operation/navigation scenario passes locally and
in backend intake.
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
Native gesture synthesis remains unavailable and is kept separate from this
deterministic programmatic proof.
Detailed conclusions live in [ASSESSMENT.md](MultiSceneSupport/ASSESSMENT.md);
exact runs and rejected paths live in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

| Surface | Current branch status | Remaining release condition |
| --- | --- | --- |
| UIKit views and navigation | Independent stacks, push/pop, modal, duplicate names, and teardown pass experimentally. On iOS 27 in declared multi-scene apps, regular split Primary/supplementary columns are now structural rather than RUM views. Deterministic cancel keeps S2 and finish creates fresh S1; both have exact backend action/Resource ownership | Cover the application-subclassed container and startup-host fallback, then prove simultaneous visibility, adaptive/lifecycle/restoration, live normal-app compatibility, and iPhone Duo behavior |
| Explicit/semantic SwiftUI tracking | Experimental iOS 27 early-start, retained-return, modal, repeated push/pop, crash-safe teardown, restoration, synthetic reconnect, and customer-state-preserving keyed-occurrence controls pass; single- and two-window split replacement plus a retained split return preserve customer state and exact markers. `EXP-116` proves that a probe-only integration can consume one container path and centralized resolver without moving instrumentation into every destination view. `EXP-122` proves the internal exact-scene keyed manual stack stays authoritative and reveals a fresh underlying destination. `EXP-125` and `EXP-126` extend that mechanism to complete-destination Sheet and full-screen-cover boundaries. `EXP-127` proves a boundary in one sibling container does not suppress an independently materialized controller branch and reveals only its latest staged destination. `EXP-128` proves Compose → Preview → fresh Compose nesting and duplicate-active-key crash safety without restart. `EXP-129` adds the strict same-key A/B contract, but its live simulator run expired before manual authority began | Convert the proven wrapper/builder, presentation-boundary, and manual-overload shapes into API-reviewed integrations; complete same-key A/B acceptance on capable hardware, then cover gestures, adaptive navigation, simultaneous visibility, reconnect, and restoration |
| Automatic native SwiftUI | Transparent discovery remains semantically late; route-owned controls prove initial creation, abort, different- and same-type stack/split replacement, and retained Home without resetting customer state, but only through an internal debug integration; automatic split has no semantic selection views. `EXP-115`/`EXP-116` prove target-scoped semantic authority, `EXP-122` prevents exact-scene manual preemption, `EXP-125`/`EXP-126` cover presentation subtrees, and `EXP-127` leaves an unrelated sibling controller eligible while manual authority is active | Validate automatic behavior in a separate live scene and ordinary automatic-only applications, then take the semantic-container shape through API review |
| Actions | Source-bearing UIKit/SwiftUI taps emit once on their scene; exact-view actions refresh the process representative; public manual errors, view mutations, and internal view work consume exact handoff view/scene when present; source-less work retains last-interacted fallback. `EXP-122` attributes active Compose work to exact-scene M1 and immediate plus settled return work to one fresh H2. `EXP-125` and `EXP-126` do the same across presentation dismissal. In `EXP-127`, work originating from underlying Detail stays on M1 until stop, then switches immediately to fresh Detail. `EXP-128` keeps first Compose, Preview, resumed Compose, duplicate-start, and final Home action/Resource pairs on their exact occurrence IDs. `EXP-129` encodes the A/B precedence oracle but has no completed runtime result | Complete exact precedence with simultaneously visible A/B and a different representative; finish UIKit deceleration and targeted downstream runtime rows |
| Resources and traces | Trustworthy start provenance is frozen; manual Resource completions remain with their captured owner; automatic URLSession completion and OpenTelemetry spans now use the same scene-handoff model | Finish the bounded causal matrix, simultaneous-window/reverse-completion proof, normal-handler compatibility, and overhead measurement |
| Operations | Internal per-step routing and exact application-wide identity pass focused tests. `EXP-130` proves live Home→Detail success and failure attribution, plus duplicate-start latest-instance reduction and an orphaned earlier raw start, with seven raw steps and three reduced Operations | Public target API review and live A-to-B cross-scene completion; duplicate behavior itself is backend-confirmed |
| Lifecycle and sessions | Independent close, rollover, fresh/retained-reader remount, and cancellation rearming are covered; exact A-to-B open and B close are signal-driven, and A continues on its original Home occurrence after B disconnects; exact activation dispatch and current-state lifecycle waits are implemented in the harness; hidden detached readers retain only their last concrete scene proof, which disconnect clears before requiring a new mount | Prove the activation/background sequence and stable simultaneous-visible peer continuity on capable hardware, then genuine OS disconnect/reconnect, live background/foreground, and concurrent restoration |
| Other signals | Focused ownership exists for logs, mirrored errors, WebView, vitals, fatal context, and profiling identity | Targeted two-window runtime proof and explicit process-wide limitations |
| Session Replay | Coexists in tested two-window runs without an SDK crash | No scene-correct replay work is required here |
| Normal applications | The exact manual-authority set passes 8/8, the focused presentation/manual contract set passes 6/6, and the clean full DatadogRUM rerun passes 1,169/1,169. DatadogTrace remains 151/151; repository lint and both probes build, with the native probe at 93/93 | Live single-scene and custom-handler behavior plus `sendEvent` overhead/reentrancy |

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
checkpoint is `f452e9e3f` (`Preserve semantic presentation authority through
dismissal`), following the exact-scene manual stack in `29c8cec2c` and
`b1a0fb6b8`. The latest probe checkpoint is `5d536e0bd` (`Exercise operation
attribution across navigation`), following `9fa58e3c0` (`Exercise same-key manual
views across scenes`) and `af2a2666d` (`Exercise nested manual view authority`).
Their exact code-only trees are respectively
`22ddf1f9b4ab1193cc1bb635b6ebae83f97e0f20`,
`0b41cbbb34cd5ff138a9b792a0c8e528505e17a8`, and
`082310e18ecfbdb9fc18a4f9d1914c7660a6edfd`. The approved product decision
checkpoint is
`b61e783a6`; the public-navigation proposal starts at `b5494adb0`.
All existing branch commits through `5d536e0bd` are verified signed local commits
and must not be pushed. The
chronological checkpoint table in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md) is authoritative.

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
The complete chronology and every failed attempt live in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

### Exact next work

The deterministic harness is complete through `EXP-130`; [PLAN.md](MultiSceneSupport/PLAN.md)
owns the finished phases and full release matrix. Continue in this order:

1. Finish `swiftui.coexistence.same-key-manual-two-scenes` on iPhone Duo or a
   physical multi-window iPad. The simulator prefix reached both native scenes
   but expired before manual starts. Stop B before A and prove each exact
   scene/key closes only its own Compose occurrence while automatic tracking
   remains active.
2. Finish `swiftui.coexistence.semantic-a-automatic-b` on physical multi-window
   hardware. The simulator prefix already proves B automatic discovery remains
   eligible; require the final B marker and backend owner before closing it.
3. Take the scene-aware Swift/Objective-C
   overloads through API review. The same key must coexist independently in A
   and B; existing overloads keep inferred/last-interacted behavior.
4. Close the primary action-attribution hardware row: keep A and B simultaneously
   visible, make B representative, interact in A without a focus-driven fallback,
   and prove exact A ownership. Repeat UIKit drag plus deceleration and require one
   action on the originating occurrence.
5. Extend the Operation driver to start in A and complete in B using one exact
   application-wide identity. Preserve each step's actual view and exercise
   reverse-order completion for distinct keys; execute it on capable hardware if
   the simulator again loses its two-scene session.
6. Run `windows.activation-sequence` on iPhone Duo or a physical multi-window
   iPad. Require the activated scene to become foreground-active and the peer to
   become background before asserting fresh view occurrences or marker ownership.
7. After API approval, land the optional container-level SwiftUI semantic
   integration. It must consume a customer path/router's complete current
   destination—including sheets and full-screen covers—and a centralized resolver,
   coexist with automatic tracking, preserve customer state, and suppress
   duplicate automatic views only within its target container.
8. Route recognized native gestures, adaptive resize, and stable simultaneous A/B
   topology through the real-device/human queue; ignored simulator input is not
   evidence.
9. Run genuine disconnect/reconnect, per-scene background/foreground, and
   concurrent restoration.
10. Complete Operations public-target API review. Keep application-wide
   `(name, operationKey)` identity; `EXP-130` already closes duplicate-start
   backend behavior, while A-to-B execution remains item 5.
11. Finish the bounded Resource/Trace and downstream-signal runtime rows, then prove
   live single-scene/custom-handler compatibility and measure event-handoff
   recursion and overhead. Repeat the release matrix on iOS 27.1 and iPhone Duo.

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
- The standalone probe now resolves 45 named scenarios from command-line input,
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

As of 2026-09-14:

- The current RUM plan passes 1,169/1,169. Earlier complete suites pass:
  Internal 477/477, Logs 95/95,
  Trace 151/151, WebView 31/31, and Profiling 233/233.
- Focused retained-route, occurrence-isolation, transition-arbiter, Operations,
  and OpenTelemetry ownership regressions pass. Native SwiftUI gestures remain
  unproven because `EXP-100` produced no navigation signal.
- The named runner validates fail-closed startup (`EXP-106`), and its recorder,
  oracle, scene registry, and observable driver pass 93/93. Clean runs prove
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
- Both probes build through Xcode 27; package build, recorded repository lint, and
  focused changed-source lint pass at their stated checkpoints.

These are regression and implementation checks, not substitutes for the missing
runtime rows. Detailed run evidence remains in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

### Blockers and workspace safety

Public SwiftUI and Operation API work requires normal RFC/API review. The branch
history through `5d536e0bd` has been re-signed or created with verified SSH
signatures. The earlier signer outages remain documented, together with the exact
frozen trees for `EXP-128` through `EXP-130`; no unsigned fallback was used.
The iOS 27 integration-runner half-and-half layout repeatedly respawned
`backboardd`, although the standalone native `WindowGroup` probe opens two windows.
The standalone probe also reproduced a `backboardd` CoreAnimation/Metal SIGABRT
while rapidly requesting exact A/B activation; no probe crash or backend event was
recorded for that interrupted run. Do not repeat that activation loop on this
simulator.
The current iPad simulator also rejects `devicectl appResize` because it lacks
Resizable App Management; adaptive width proof needs a capable destination.
Xcode device-interaction guidance is now available, but the auto-driven
`EXP-115` launch session had expired before its opaque interaction key could be
reused for visual inspection. Read-only OSLog and backend verification remained
available. Native gesture and visual claims still require a live interaction key
or human/device evidence; programmatic runs do not become native-gesture proof.
Ignored native edge drags, fullscreen-only peer-window layouts, partial scene
restoration, and unsupported resize are tracked in the dedicated
[real-device and human-driven rerun queue](MultiSceneSupport/EXPERIMENTS.md#real-device-and-human-driven-rerun-queue).
Those rows require observable path/coordinator/lifecycle evidence, not more
unverified simulator touches.

`--probe-run-mode clean` is an in-app manifest value, not a host teardown action.
Back-to-back Xcode install/run calls can leave semantic view documents carrying
the previous run's global probe attribute even when later actions and Resources
use the new run ID (`EXP-117`). Until the reproducible host runner exists,
explicitly uninstall the probe before every clean run and reject any backend set
whose view documents do not carry the requested `@context.probe.run_id`.

Do not stage, commit, revert, or expose
`Datadog/Datadog.xcodeproj/project.pbxproj` or
`xcconfigs/Datadog.local.xcconfig`. Both predate this work and the latter contains
local credentials. An exact `git add` is insufficient while the xcconfig is
pre-staged; use `git commit --only -- <exact paths>` or an isolated index, then
verify the commit tree and restore/preserve its exact `AM` state.

Rejected experiments and do-not-repeat guidance are authoritative in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md#attempts-not-to-repeat).

## Open API-review questions

Product behavior is settled for this project. The concrete alternatives, call
sites, compatibility constraints, and required tests are consolidated in
[NAVIGATION_API.md](MultiSceneSupport/NAVIGATION_API.md). API review still needs
to choose:

- the concrete container-level SwiftUI wrapper/modifier, path abstraction, root
  descriptor, route-resolver shape, destination-builder integration, and iOS 27
  availability surface. `EXP-116` proves the builder-owning shape; a passive
  root-only modifier remains known-too-late;
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
