# RUM multi-scene support

This is the canonical entry point for concurrent `UIWindowScene` support in
Datadog RUM. It records the current contract, support status, decisions, and exact
resume point. Detailed evidence and chronology are split by ownership so future
work can start here without loading the frozen experiment history.
It remains separate from `RUM_FEATURE.md` until the behavior is implemented,
validated, and ready to become a supported contract.

Last updated: 2026-09-17

Current SDK checkpoint: signed `7619eb8a2` (EXP-173 accepted presentations and
exact occurrence callbacks). The finite [release checklist](MultiSceneSupport/PLAN.md)
has **29/66 gates closed**. All12 findings in the
[production safety review](MultiSceneSupport/PRODUCTION_SAFETY_REVIEW.md) have
bounded repair evidence. EXP-173 passes337 affected tests and77/77 mounted checks
versus55/77. Early dispatch/allocation/reentrancy and retained-scene budgets now
pass on27/26.5. R05 multi-observer nested commit/remove/add is the next executable
gate, followed by the finite remaining telemetry families. Minimum-runtime,
physical iPad/Duo, API review and final release acceptance remain open. Preserve
accepted experiment identities; do not rerun them merely to resume.
[Current evidence](MultiSceneSupport/Experiments/EXP-143-199.md).

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
| [Navigation API proposal](MultiSceneSupport/NAVIGATION_API.md) | You are reviewing the container-independent SwiftUI host/source/adapter model, optional native convenience, scene-aware manual views, coexistence rules, or Swift/Objective-C compatibility |
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
passes the native-convenience prototype through H1 → D1 → H2 → Sheet →
H3 → Cover → H4 with seven distinct view IDs and no automatic duplicate. This
is implementation and runtime evidence, not approval of a stable public API.
`EXP-142` additionally passes native repeated-value links through H1 → D1 → D2
→ fresh D3 → fresh H2. Per-materialized-boundary claims publish each revealed
occurrence before its lifecycle work without changing the customer's route type.
`EXP-143` and `EXP-144` close restoration, external-router acceptance, and
presentation-to-presentation replacement. `EXP-145` then reuses the proven
sibling-controller topology through the actual SPI: Detail commits beneath left
manual authority, emits no intermediate or automatic view, and starts once as a
fresh occurrence after authority ends. Its final run passes 19/19 locally and
matches a 30-event backend session with zero errors/crashes.

This proves the semantic mechanics, not a required customer navigation shape.
The current `RUMNavigationStack` may remain an optional native convenience, but
`EXP-146` extracts a scene-scoped engine and adds an arbitrary-view host, optional
type-erased capability, and explicit transition source. Its deterministic
explicit-source adapter wraps unchanged `NavigationStack`, `.sheet`, and
`.fullScreenCover` code, starts Home before initial lifecycle work, and passes
42/42 through H1/D1/H2/Sheet/H3/Cover/H4 with exact backend ownership and no
automatic duplicate. The identical harness container also passes 42/42 when a
stable optional capability supplies the source. Its opaque specialization passes
5/5 with automatic capture still active, no semantic view invented, and exact
Detail work on the automatic controller owner. This validates the engine and
adapter boundary only: the probe's `willNavigate`/`commit` calls are not an
accepted normal-customer integration.

The final integration must keep native, internal, third-party, UIKit-coordinator,
and custom navigation and presentation code. Correctness must use automatic
metadata by default, allow sparse optional naming overrides, and cost roughly one
integration per independent container or existing router. It must not require an
exhaustive RUM-only route/presentation resolver, edits to screen files, or RUM
calls in every navigate, pop, present, and dismiss method. `EXP-147` closes that
migration-cost gate for an existing observable router: one integration per
router/container, automatic metadata, sparse overrides, and no RUM-code growth
for an added route or presentation. `EXP-148` moves that policy into the SDK-owned
iOS 27 prototype and preserves the same 38/38 semantic/backend oracle. The next
deterministic gate, `EXP-149`, proves one real-host subscription across SwiftUI
reconstruction, exact A/B source isolation and posted-disconnect cleanup, and an
unrelated automatic subtree at 20/20. `EXP-150` then rejects a value-only
current-destination host as the native/local-state answer: the host sees both
sheet and cover dismissal one render too late, so synchronous post-dismiss
action/Resource pairs stay on the dismissed presentation. Frozen mapper and
backend evidence agree even though settled work is correct and the app remains
healthy. `EXP-151` accepts Xcode 27 one-shot Observation `.didSet` for an
existing `@Observable` router whose complete accepted destination is exposed as
one atomically updated property. Its post-review frozen run passes 38/38 locally
and in backend intake, including immediate and settled dismissal ownership on
fresh Home occurrences. Nested reentrancy, SwiftUI reconstruction, invalid
background mutation crash safety, the iOS Release build, and the visionOS
package build also pass. `EXP-152` then keeps that accepted boundary and records
SwiftUI's actual Sheet and cover `onDismiss` callbacks after proving each native
presentation appeared. Its clean frozen run passes 38/38 locally and in backend
intake: both callbacks observe accepted Home, emit once, create no extra Home,
and place immediate plus settled work on fresh H3/H4. Plain local `@State` and
opaque containers retain automatic tracking plus sparse manual exceptions.
`EXP-153` closes reliable callback-driven custom/third-party parity. A genuinely
custom visual container reports synchronous accepted snapshots to one boundary
adapter, which reuses the SDK publisher host and passes 42/42 locally and in
backend intake with one stable registration. It requires no screen or
navigation-method edits, retroactive conformance, or new SDK input primitive.
`EXP-154` then closes serial two-native-scene Observation parity: two real
native scenes independently complete H1 -> D1 -> fresh H2 and keep all six
action/Resource marker pairs on their exact scene-local occurrences. The clean
run passes 25/25 locally and in backend intake. Genuine simultaneous-window
parity and API review follow; interactive dismissal and OS disconnect remain
hardware-gated. `EXP-155` accepts explicit per-step Operation targeting, and
physical `EXP-157` accepts inferred A→B Operation ownership across two native
scenes. `EXP-158` generalizes the experimental target and accepts one-shot
action targeting while preserving source-less last-interacted fallback.

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
present. `EXP-142` then passes 48/48 locally and in backend intake for sequential
equal route values. `EXP-143` closes direct repeated restoration and external
router replacement/rejection/canonicalization. `EXP-144` closes direct Sheet →
Cover → Sheet replacement at 43/43 with exact H1/S1/F1/S2/fresh H2 backend
ownership, no intermediate Home, and zero errors/crashes. `EXP-145` closes
actual-SPI sibling isolation at 19/19 with exact Home/manual/Detail ownership and
no automatic duplicate. `EXP-146` validates container-independent engine/adapter
explicit-source and optional-capability paths at 42/42 with exact initial lifecycle and
H1/D1/H2/Sheet/H3/Cover/H4 ownership. Its opaque path passes 5/5 without
suppressing automatic capture or inventing a semantic view. Runtime explicit
precedence, stable reconstruction, and adversarial capability replacement each
pass 43/43 with the same exact backend owners and no decoy view. A real-reader
synchronous detach/reattach run passes 17/17 with one preserved Detail occurrence;
focused disconnect/lifetime tests pass 4/4 and the handler suite passes 84/84.
Two clean final-host-removal simulator attempts crashed `backboardd` before the
removal step and remain device-INCONCLUSIVE. The `EXP-146` checkpoint passed
150/150 probe tests; the EXP-158 checkpoint passed164/164 after the router-adapter,
serial two-native-scene, Operation-target, and action-target experiments. The
EXP-158 RUM checkpoint passed1,255/1,255 test cases with zero failures. Current
repository lint passes across 713 source and 699 test files.
API-surface
verification reports only the unapproved experimental symbols without baseline
changes, and the Xcode 27 iOS Release plus visionOS package builds pass.

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
are all observed. Cross-scene inferred completion and explicit targeting remained
separate gates at that point.

`EXP-131` defines the exact inferred cross-scene Operation discriminator. It
starts success and failure in A and completes them in B, then starts two
same-name Operations with distinct keys in A and B and completes B before A. The
hostless driver and adversarial oracle raise the probe plan to 100/100 while
rejecting shared view identity, wrong-scene B work, B completion on A, and A owner
drift after B completes. Its corrected physical execution is recorded as
`EXP-157`: the run passes 24/24 across two native scenes, and backend intake has
all eight raw steps plus four exact A→B/A→A/B→B reduced Operations. Both scenes
were full-screen rather than simultaneously visible, so only that topology
qualification remains for a human-arranged Stage Manager or split-window run.

`EXP-155` accepts the first explicit Operation target as an iOS 27 SPI proof.
Every start/end call uses `.current(in:)` for A or B while an opposite-scene
marker deliberately changes the process representative. After correcting a stale
non-navigation occurrence-source harness, the run passes 24/24. Backend intake
contains exactly eight raw steps and four reduced Operations: A→B success, A→B
failure, A→A alpha, and B→B beta with beta completing before alpha. The target
does not expose RUM UUIDs, retains no UIKit object, and preserves explicit →
inferred → last-proven → representative fallback. Stable Swift/Objective-C names,
availability, and later manual-key/controller target forms still require review.
The physical inferred call-site row now passes in `EXP-157`.

`EXP-158` generalizes that bounded experimental value to `RUMViewTarget` and
adds a one-shot `addAction(..., view:)` SPI. Its serial two-native-scene run
deliberately keeps B representative: explicit A owns A, explicit B owns B, and
a source-A legacy action plus Resource remain on B. The local oracle passes 9/9,
backend session `f67c75b2-e839-4701-a283-7e4355682b6a` confirms the same owners
across 30 events, Objective-C smoke passes 8/8, and custom/NOP conformers retain
exactly-once legacy fallback. EXP-159 subsequently accepts targeted long-running actions; D12 and stable API review remain.

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
scenarios through the `EXP-146` precedence/lifetime matrix passed 150/150 tests
at that checkpoint; the EXP-158 generated suite passed164/164 after
`EXP-147`-`158`. The prepared two-scene same-key and shared-request scenarios
remain hardware-gated; inferred Operations pass on two physical scenes in
`EXP-157`, and the single-scene Operation/navigation plus explicit Operation and
action target scenarios pass locally and in backend intake.
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
the [experiment index](MultiSceneSupport/EXPERIMENTS.md) locates exact runs, and
[REJECTED_APPROACHES.md](MultiSceneSupport/REJECTED_APPROACHES.md) owns paths not
to retry.

| Surface | Current branch status | Remaining release condition |
| --- | --- | --- |
| UIKit views and navigation | Independent stacks, push/pop, modal, duplicate names, and teardown pass experimentally. On iOS 27 in declared multi-scene apps, regular split Primary/supplementary columns are now structural rather than RUM views. Deterministic cancel keeps S2 and finish creates fresh S1; both have exact backend action/Resource ownership | Cover the application-subclassed container and startup-host fallback, then prove simultaneous visibility, adaptive/lifecycle/restoration, live normal-app compatibility, and iPhone Duo behavior |
| Explicit/semantic SwiftUI tracking | Experimental iOS 27 early-start, retained-return, modal, repeated push/pop, crash-safe teardown, restoration, synthetic reconnect, and customer-state-preserving keyed-occurrence controls pass; single- and two-window split replacement plus a retained split return preserve customer state and exact markers. `EXP-116` proves a builder-owned materialization boundary; `EXP-141`-`145` validate the native-convenience SPI across complete destinations, repeated/restored routes, router acceptance/canonicalization, atomic presentations, and sibling isolation. `EXP-146` validates the shared engine and arbitrary-host adapter boundary with stable explicit or optional-capability input around unchanged standard SwiftUI at 42/42; runtime precedence, repeated reconstruction, and adversarial source replacement pass 43/43 each. Its opaque specialization retains automatic capture at 5/5, and its synchronous real-reader bounce passes 17/17 without changing the active Detail UUID. `EXP-147` validates the route-count-independent migration budget; `EXP-148` moves observation, automatic metadata, sparse overrides, equal-route identity, delayed authority, and strict pending-source precedence into DatadogRUM. Its final frozen run passes 38/38 locally and in backend with eight exact views and 22 ownership buckets. `EXP-149` closes real-host subscription reconstruction, publisher replacement, two-scene observed-source isolation, posted-disconnect cleanup, and unrelated automatic-subtree coexistence at 20/20. `EXP-150` rejects render-time current-value observation; `EXP-151` accepts one-shot Observation of one atomic accepted-state property, with a post-review 38/38 mapper/backend pass plus nested, reconstruction, background-misuse, iOS Release, and visionOS build coverage. `EXP-152` closes actual programmatic Sheet/Cover `onDismiss` timing at 38/38 with fresh H3/H4 ownership and no callback-created Home. `EXP-153` closes callback-driven custom/third-party parity at 42/42 through one adapter boundary and the existing publisher host, with one stable registration and exact initial lifecycle ownership. `EXP-154` closes serial two-native-scene Observation parity at 25/25 with distinct A/B H1/D1/H2 IDs and six exact action/Resource owner pairs. The low-level publisher remains adapter-author SPI, not the normal customer path. `EXP-122` proves the internal exact-scene keyed manual stack stays authoritative and reveals a fresh underlying destination. `EXP-125`-`128` cover presentation boundaries, sibling isolation, nesting, and duplicate-start crash safety; `EXP-137`-`140` exercise the customer-shaped manual SPI. `EXP-129` adds the strict same-key A/B contract, but its live simulator run expired before manual authority began | Close interactive dismissal/cancellation, OS disconnect/final detach on hardware, and same-key A/B acceptance before adaptive navigation, simultaneous visibility, reconnect, and restoration; complete normal API review for the experimental semantic shape |
| Automatic native SwiftUI | Transparent discovery remains semantically late; route-owned controls prove initial creation, abort, different- and same-type stack/split replacement, and retained Home without resetting customer state, but only through an internal debug integration; automatic split has no semantic selection views. `EXP-115`/`EXP-116` prove target-scoped semantic authority, `EXP-122` prevents exact-scene manual preemption, `EXP-125`/`EXP-126` cover presentation subtrees, and `EXP-127` plus actual-SPI `EXP-145` leave an unrelated sibling controller eligible while manual authority is active. `EXP-141` keeps automatic discovery enabled around the actual semantic container without producing a duplicate. `EXP-146` proves an opaque arbitrary host does not suppress automatic capture, while also confirming that opaque input cannot repair automatic lifecycle or destination precision | Validate automatic behavior in a separate live scene and ordinary automatic-only applications, then take the container-independent shape through API review |
| Actions | Source-bearing UIKit/SwiftUI taps emit once on their scene; exact-view actions refresh the process representative; public manual errors, view mutations, and internal view work consume exact handoff view/scene when present; source-less work retains last-interacted fallback. `EXP-122` attributes active Compose work to exact-scene M1 and immediate plus settled return work to one fresh H2. `EXP-125` and `EXP-126` do the same across presentation dismissal. In `EXP-127`, work originating from underlying Detail stays on M1 until stop, then switches immediately to fresh Detail. `EXP-128` keeps first Compose, Preview, resumed Compose, duplicate-start, and final Home action/Resource pairs on their exact occurrence IDs. `EXP-132` proves a threshold-qualified real UIKit fling remains exactly once on its origin when navigation starts during deceleration. `EXP-135` proves one automatic SwiftUI Button tap stays on A, while source-less work resumed after B takes over follows B by compatibility. `EXP-158` accepts explicit one-shot A/B targets while proving that an unchanged source-A legacy action still follows representative B. `EXP-129` encodes the simultaneous A/B precedence oracle but has no completed runtime result | EXP-159 targeted long-running slice is accepted; repair D12 and finish named T03–T14 gates plus simultaneous A/B hardware ownership |
| Resources and traces | Trustworthy start provenance is frozen; manual Resource completions remain with their captured owner; automatic URLSession completion and OpenTelemetry spans use the same scene-handoff model. `EXP-133` backend-confirms one Trace-only request across A→B representative churn; `EXP-134` backend-confirms independent A/B requests completed in reverse order while each retains its own start-scene Home view. Neither scenario emits a matching RUM Resource. `EXP-135` proves an ordinary SwiftUI Button callback is outside the synchronous handoff and its resumed task is source-less. `EXP-136` proves the shared-consumer harness through B join, but the simulator compositor failed before completion twice | Finish the unchanged shared/coalesced completion and simultaneous-window exact-source rows on capable hardware, then normal-handler compatibility, explicit target/scoped API review, and overhead measurement |
| Operations | Internal per-step routing and exact application-wide identity pass focused tests. `EXP-130` proves live Home→Detail success/failure plus duplicate latest-instance reduction. `EXP-155` proves customer-shaped `.current(in:)` targeting with eight raw steps and four exact A/B reduced Operations. `EXP-157` proves the corresponding inferred A→B and distinct-key reverse-completion contract on two physical native scenes | Complete stable Swift/Objective-C target API review. Simultaneous visibility is still a human topology qualifier, but duplicate, explicit-target, and inferred cross-scene ownership are backend-confirmed |
| Lifecycle and sessions | Independent close, rollover, fresh/retained-reader remount, and cancellation rearming are covered; exact A-to-B open and B close are signal-driven, and A continues on its original Home occurrence after B disconnects; exact activation dispatch and current-state lifecycle waits are implemented in the harness; hidden detached readers retain only their last concrete scene proof, which disconnect clears before requiring a new mount. `EXP-146` adds a synchronous real-reader bounce plus focused final-detach and posted-disconnect fencing tests | Run final host removal and genuine OS disconnect/reconnect on capable hardware; then prove activation/background, stable simultaneous-visible peer continuity, live background/foreground, and concurrent restoration |
| Other signals | Focused ownership exists for logs, mirrored errors, WebView, vitals, fatal context, and profiling identity | Targeted two-window runtime proof and explicit process-wide limitations |
| Session Replay | Coexists in tested two-window runs without an SDK crash | No scene-correct replay work is required here |
| Normal applications | The exact manual-authority set passes 8/8, focused semantic replacement passes 3/3, and the complete DatadogRUM run passes 1,255/1,255. DatadogTrace remains 151/151; repository lint, expected-only prototype API-surface diff, and both probes build at their recorded checkpoints. The EXP-161 fresh native probe passes166/166. EXP-147's zero-screen/zero-method migration budget is preserved by the SDK-owned EXP-148 publisher and EXP-151 Observation candidates while standard SwiftUI stays unchanged; EXP-149 adds a 20/20 actual-host lifetime and scene-isolation matrix, EXP-152 validates actual native dismissal callbacks without changing customer code, EXP-153 validates one callback-driven custom-container boundary, EXP-154 validates independent serial native scenes, EXP-155 validates explicit Operation targeting, EXP-157 validates inferred physical Operation ownership, and EXP-158 validates shared target action routing plus custom/NOP fallback. The latest affected SwiftUI file selection passes 193/193 | EXP-160 closes early ordinary/custom/dispatch/reentrancy gates; fix P02/P03 and D01–D12; physical topology remains required |

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
   navigation is an optional integration installed once per independent
   container or router without replacing the customer's native, internal,
   third-party, UIKit-coordinator, or custom navigation. Integration cost scales
   with flow boundaries, not screens or presentations. Its exact API requires
   normal review.
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
17. The scene-scoped semantic engine treats stack navigation, sheets, full-screen
    covers, UIKit presentations, and custom overlays as changes to one current
    destination. Exact sources create a fresh underlying occurrence on dismissal;
    opaque containers retain automatic fallback. Customers do not replace
    `.sheet`, `.fullScreenCover`, or destination modifiers with Datadog APIs.
    Integration precedence is explicit source/adapter, optional stable capability,
    optional native convenience, scene-aware automatic discovery, then the
    representative fallback. Exact tracking requires a trustworthy signal; a
    fully opaque container remains crash-safe and best-effort rather than having
    semantics fabricated for it.
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
23. Semantic input precedence is explicit transition source/adapter, optional
    type-erased container capability, native convenience adapter, scene-aware
    automatic discovery, then process-representative fallback. The transition
    source must survive SwiftUI value reconstruction. An opaque container with no
    trustworthy signal remains crash-safe and best-effort; the SDK does not
    fabricate exact navigation state.
24. Exact semantic correctness must not require exhaustive custom metadata or
    per-navigation-method RUM calls. Metadata is automatic by default with sparse
    optional overrides. Integration cost scales with independent containers or
    existing routers, not routes, screens, sheets, covers, or destination count.
    The low-level EXP-146 transition publisher remains an engine/adapter-author
    primitive. `EXP-147` proves a low-cost existing-router candidate without
    making that primitive the normal customer integration; the SDK-owned API
    prototype must preserve the measured migration budget.

The complete Operation contract, proposed Swift and Objective-C escape hatch,
customer workflow, and required tests live only in
[OPERATIONS.md](MultiSceneSupport/OPERATIONS.md).

## Resume here

Read `.continue-here.md` and AGENTS first. Signed source remains `af63657f0`;
EXP-160/161 add tooling/evidence, with no SDK behavior change. See the active
[records](MultiSceneSupport/Experiments/EXP-143-199.md) for exact identities.
Superseded restart narratives moved to
[completed notes](MultiSceneSupport/Experiments/PLAN_COMPLETED_THROUGH_EXP-159.md).

- Follow [PLAN](MultiSceneSupport/PLAN.md) and the
  [assessed repair order](MultiSceneSupport/REVIEW_TRIAGE.md). The next SDK slice
  is D01/D02 supported-platform compatibility, defined before implementation.
- Keep the predeclared [baseline thresholds](MultiSceneSupport/BASELINES.md).
  P02 allocation and P03 retained-registry failures remain blockers; timing and
  exact nested context restoration pass in their simulator microbenchmarks.
- Use the [acceptance runbook](MultiSceneSupport/TOOLING_RUNBOOK.md). A01 is
  accepted for its single admitted scenario; unsupported families/topologies do
  not inherit the result. All prior failed attempts remain available.
- Hardware H01–H16 and minimum15 runtime remain required. Rediscover device/MCP
  identities and authenticated backend access; do not reuse temporary sessions.
- Preserve both dirty user paths and the independent safety-review file. Never
  read local xcconfig contents. Use explicit-path commits, signing when available
  and continuing unsigned locally if the agent is unavailable. Sign before any
  future authorized push; no push is authorized here.
- Deferred source extraction remains after multi-scene freeze.

## Open API-review questions

Product behavior is settled for this project. The concrete alternatives, call
sites, compatibility constraints, and required tests are consolidated in
[NAVIGATION_API.md](MultiSceneSupport/NAVIGATION_API.md). API review still needs
to choose:

- the stable arbitrary-view host, type-erased transition capabilities, explicit
  source/adapter entry points, descriptor, and availability surface. The host
  must preserve standard navigation/presentation code, and the source must remain
  stable across SwiftUI value reconstruction;
- the optional native `RUMNavigationStack` convenience breadth. `EXP-141`-`145`
  prove its builder-owning mechanics, repeated routes, presentations, and sibling
  isolation, but it is not the prerequisite for exact support and must not mirror
  Apple's full navigation/presentation surface;
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

[PLAN.md](MultiSceneSupport/PLAN.md#release-and-compatibility-gates) owns the exhaustive release
checklist. The support claim remains experimental until:

- automatic SwiftUI remains scene-isolated and zero-code by default without
  producing cross-scene attribution or duplicate views, while the optional
  reviewed host/source/adapter integration provides exact root/destination
  occurrence semantics in both native `WindowGroup` and UIKit-hosted
  applications without replacing customer navigation APIs;
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
- the optional semantic integration accepts native, customer-owned, and
  third-party-style navigation through a container-independent engine, creates
  one fresh UUID per committed occurrence, preserves unchanged presentation call
  sites, coexists with automatic tracking, and suppresses duplicates only in its
  authoritative container;
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
