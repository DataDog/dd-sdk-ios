# Historical documentation checkpoint at EXP-178

Source checkpoint: cdc9a6e528ae2027b5e6011e8eb5a0f3bb958318.
SDK checkpoint: signed1c6104cacb95751137c700e1812bcb1c0f05a359.

These quoted excerpts preserve historical information removed from active
documents during one bounded consolidation. They include stale status and
instructions **as historical evidence only**; none may direct execution.
[The handoff](../../../.continue-here.md) is the sole restart cursor;
[the register](../release-gates.json) owns current gate status.

The [active experiment shard](EXP-143-199.md), all durable result/attempt files,
frozen archive, baseline thresholds and rejected-approach lessons are retained.
Use [the index](../EXPERIMENTS.md) for exact owning experiment links.
Relative links inside quoted source excerpts retain their original meaning and
are not active navigation. Source path and checkpoint identify their origin.
The [preservation manifest](../Results/documentation-consolidation-EXP-178.json)
records source/excerpt hashes and invariant checks.

## Excerpt lookup

| Original document | Historical excerpt |
| --- | --- |
| DatadogRUM/MULTI_SCENE_SUPPORT.md | [Superseded overview and support narratives](#moved-01) |
| DatadogRUM/MultiSceneSupport/PLAN.md | [Superseded execution priorities and review staging](#moved-02) |
| DatadogRUM/MultiSceneSupport/ASSESSMENT.md | [Historical support conclusions and routing audit](#moved-03) |
| .continue-here.md | [Superseded restart history](#moved-04) |
| DatadogRUM/MultiSceneSupport/EXPERIMENTS.md | [Previous experiment index and checkpoint narratives](#moved-05) |
| DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md | [Earlier runbook experiment-specific appendices](#moved-06) |
| DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md | [Superseded documentation update workflow](#moved-07) |
| DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md | [Historical procedure example](#moved-08) |
| DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md | [Historical procedure example](#moved-09) |
| DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md | [Historical procedure example](#moved-10) |
| DatadogRUM/MultiSceneSupport/PRODUCTION_SAFETY_REVIEW.md | [Earlier review progress preface and repair order](#moved-11) |
| DatadogRUM/MultiSceneSupport/REVIEW_TRIAGE.md | [Original triage chronology and repair ordering](#moved-12) |
| DatadogRUM/MultiSceneSupport/COMPONENT_REVIEW.md | [Superseded component-review framing](#moved-13) |

## Moved 01

Superseded overview and support narratives

Source: DatadogRUM/MULTI_SCENE_SUPPORT.md. Original excerpt SHA-256: c40096e9afeb03b11fe4f1d1b713b906788f25e8a16962026ee232d016645211.

~~~~markdown
# RUM multi-scene support

This is the canonical entry point for concurrent `UIWindowScene` support in
Datadog RUM. It records the current contract, support status, decisions, and exact
resume point. Detailed evidence and chronology are split by ownership so future
work can start here without loading the frozen experiment history.
It remains separate from `RUM_FEATURE.md` until the behavior is implemented,
validated, and ready to become a supported contract.

Last updated: 2026-09-17

Current SDK checkpoint: signed `1e9c4788d` (EXP-177 current-view errors accepted;
EXP-176 accepted Resource starts at `5e41d0b11`,
restoration representative and response-plus-error completion). The finite [release checklist](MultiSceneSupport/PLAN.md)
has **32/66 gates closed**. All12 findings in the
[production safety review](MultiSceneSupport/PRODUCTION_SAFETY_REVIEW.md) have
bounded repair evidence. EXP-173 passes337 affected tests and77/77 mounted checks
versus55/77. Early dispatch/allocation/reentrancy and retained-scene budgets now
pass on27/26.5. EXP-174 passes346 affected tests, closing all six bounded
component reviews. EXP-175 passes379 affected tests for late Resource completion;
EXP-176 closes T03 with397 affected/8 Objective-C checks, iOS/watchOS Release,
167 probe tests and22/22 native expectations/77 signals. Exact backend5 Resources/
4 errors/5 views across2 sessions preserve captured owners and fresh peer counts0/0.
EXP-177 closes T04:376 SDK tests,24/24 native expectations and exact backend
9 errors/3 views/2 actions,1 callback and0 Resources/crashes. T05 view attributes
and removal is next. Minimum-runtime,
physical iPad/Duo, API review and final release acceptance remain open. Preserve
accepted experiment identities; do not rerun them merely to resume.
[Current evidence](MultiSceneSupport/Experiments/EXP-143-199.md).

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
~~~~

## Moved 02

Superseded execution priorities and review staging

Source: DatadogRUM/MultiSceneSupport/PLAN.md. Original excerpt SHA-256: e161784947c871af1b766380c6ef46d54ede47c87474e1e26e0c1ba0f7b438b8.

~~~~markdown
# RUM multi-scene release checklist

Last updated: 2026-09-17. This file owns the finite remaining release contract.
[release-gates.json](release-gates.json) is the machine-readable register.
Progress is gates closed, not experiment count. Completed planning narratives
were moved to [completed notes](Experiments/PLAN_COMPLETED_THROUGH_EXP-159.md);
attempt details remain in the experiment ledger.

## Current objective and scope

Deliver correct RUM attribution for concurrent iPad and iPhone windows, with
iPhone Duo on iOS 27.1 as the release target. The branch must preserve ordinary
single-scene behavior and the iOS 15 deployment target.

The approved model is:

- one current RUM destination per scene;
- RUM views represent navigation-path occurrences, not platform object identity;
- returning to the same destination creates a fresh view ID;
- automatic tracking remains the zero-code default;
- exact SwiftUI navigation is an optional once-per-container or once-per-router
  enhancement around the application's existing navigation system; standard
  `NavigationStack`, `.sheet`, `.fullScreenCover`, and custom-container call
  sites must not be replaced throughout the screen hierarchy;
- semantic correctness must not require per-destination metadata, an exhaustive
  RUM-only route/presentation resolver, or RUM calls in every navigation method;
  default metadata is automatic and customer overrides are sparse;
- a scene-scoped semantic engine is independent of any visual container and can
  accept native-adapter, optional-capability, explicit-source, coordinator, or
  automatic-discovery input;
- the explicit transition source is an engine and adapter-author primitive, not
  the representative normal-app integration;
- exact manual authority is scene-targeted, nestable by distinct key, and paired
  with an exact targeted stop;
- source-less work keeps the last-interacted/process-representative fallback;
- Operations remain application-wide by `(name, operationKey)` and resolve every
  step's view independently;
- scene ownership must be ready to map to a future Window Execution Context, but
  this work introduces no temporary attribute, session split, or wire format; and
- Session Replay only needs to remain crash-safe.

No product question blocks the next internal experiment. Stable API names and
Objective-C Release exposure still require normal API review.

## Execution and experiment admission

0. D01/D02 platform compatibility is closed by EXP-162; evidence is in the
   register and detailed record. Accepted experiment identities remain unchanged.
1. D12/T02, D09, D11 and D04/P02 repairs are accepted within their recorded
   boundaries. Preserve their controls and frozen acceptance identities.
2. D05/D06 restoration, D03/R02 keyed lifetime, D07 pending authority and D08
   reconnect acceptance are closed within their recorded boundaries.
   R04 retained-reader remount and P03 disconnected-registry retirement pass
   EXP-171/172 within their recorded boundaries.
3. D10/R06 accepted presentations and R05 observer reentrancy pass EXP-173/174.
   T03 Resource ownership closes with EXP-175/176; T04 closes with EXP-177.
   Execute defined EXP-178 for T05 view attributes/removal, then T06 timing/loading.
   Keep their distinct completion contracts and the accepted Resource owner rule.
   All six responsibility reviews have bounded evidence.
4. Close the early compatibility/performance gates in available environments;
   C06 remains blocked without a minimum-OS runtime. Resume T03–T14 only after
   relevant repair dependencies pass. A documented fallback remains a deliverable.
5. Resume hardware at H01 when capable iPad/Duo hardware is available, respecting
   H08/H09/H13 repair dependencies. Finish API/docs/CI, final Duo acceptance and
   release freeze. Deferred extraction remains after freeze.

A new EXP record must name one or more existing gate IDs, a frozen candidate,
predeclared decisive oracle and environment, and which result closes each gate.
It may instead investigate a concrete regression with a reproduction. New scope
requires an explicit checklist change with rationale; it cannot enter as an
unnamed “remaining signal.” A failed or inconclusive attempt does not create
another deliverable. Do not repeat accepted experiments merely to resume.

Owners below are responsible roles: the current implementer owns SDK/harness
work; reviewers own sign-off; the device operator owns physical/human evidence.
No external reviewer sign-off is implied. `CLOSED` is bounded by cited evidence;
`ENVIRONMENT BLOCKED` is still a required gate. EXP-039's unbuilt automatic
reflection candidate is not admitted: opaque/automatic limits are the approved
fallback covered by F02, not an exact-navigation release claim. UIKit-hosted
SwiftUI remains required as H16; the former conditional row is resolved.

A concurrent production safety review introduced these finite obligations on
2026-09-17. [REVIEW_TRIAGE.md](REVIEW_TRIAGE.md) assesses all 12 findings and repair timing.
Source-traced or extracted-probe findings still need their stated regression tests; a gate closes after repair or evidence-backed rejection.
SwiftUI findings are also triaged in COMPONENT_REVIEW.md. Existing accepted
experiment slices remain evidence, not a substitute for these missing cases.

~~~~

## Moved 03

Historical support conclusions and routing audit

Source: DatadogRUM/MultiSceneSupport/ASSESSMENT.md. Original excerpt SHA-256: 02d6e6307489075df71406d4dd3b09d12951b67d9f1b2a31a8e41cead0bd6383.

~~~~markdown
# RUM multi-scene support assessment

This document owns the current support verdict and remaining product gaps. Use
[PLAN.md](PLAN.md) for ordered work and hardware routing, and
[EXPERIMENTS.md](EXPERIMENTS.md) for exact evidence locators. The complete
assessment through `EXP-142` is frozen in
[Archive/ASSESSMENT_THROUGH_EXP-142.md](Archive/ASSESSMENT_THROUGH_EXP-142.md).

Last updated: 2026-09-17

## Current verdict

Current release accounting is **32/66 gates closed**. EXP-160 establishes early
ordinary automatic/manual/custom/NOP and26.5 compatibility, dispatch and exact
reentrancy baselines. EXP-166 repairs the enabled-handoff allocation failure:
complete Release ABBA runs measure 1 allocation/64 bytes per event on27/26.5,
within the original budget; ordinary dispatch remains0/0. EXP-172 repairs retained scene
registries: zero entries after20+100+100 lifetimes on27/26.5, within the frozen
64KiB/16KiB heap limits. Legacy27 remains
inconclusive; minimum15 runtime is unavailable. EXP-161 closes the repeatable
acceptance workflow with15/15 local assertions and exact7-action/3-view backend
ownership. These measurements precede further API expansion.

The [production-review assessment](REVIEW_TRIAGE.md) keeps all12 findings as
relevant repair gates D01–D12, distinguishing isolated compiler reproduction,
source-confirmed behavior and unproven framework ordering. Compatibility repairs
come first, then shared ownership/restoration and SwiftUI lifetime/authority.
The branch remains held from release; passing an earlier bounded experiment does
not close these missing cases. [PLAN.md](PLAN.md) and its machine register own
all remaining deliverables and dependencies; completed narratives are separate.
EXP-162 closes D01/D02: complete watchOS RUM and macOS WebView targets pass
Debug/Release builds after failing controls, and 70 Resource/action plus 28
WebView iOS tests pass. Signed platform fixes end at `af8864528`. EXP-163 closes
D12 and restores T02: overdue stops retain their own attributes,
while peers expire without foreign metadata; 212 affected tests pass at signed
`084dff4c1`. EXP-164 closes D09 at local `a9abc092b`: 31 affected tests and a
19/19 mounted-controller fixture pass with Main Thread Checker loaded, zero
background hierarchy reads and zero diagnostics. EXP-165 closes D11 at signed
`9a1ee83a5`: 102 affected tests, four collector controls and 19/19 mounted
WebView/Replay checks preserve the legacy container while excluding peers.
The original collector attempt is INVALID and preserved. EXP-166 closes D04/P02
at signed `5eb3c1aac`: core-lifetime ownership isolates every handoff consumer,
282 affected tests pass, complete watchOS RUM/macOS Core builds pass, and the
frozen allocation, latency and full-context reentrancy budgets pass. EXP-167
closes D05/D06 at signed `0aaafa7bd`: six failing scope controls, 198 affected
tests including 44 new matrix cases, and 47/47 checks in two native iPad simulator
scenes versus control 20/47. Navigation resolves its old owner before peer
restoration; immediate and delayed boundaries preserve the same eligible peers.
EXP-168 closes D03 and bounded R02 review at signed `7b77f60eb`: 303 affected
tests and 37/37 mounted checks on each of 27/26.5. The control retains 25 keyed
registrations/states; the candidate releases all weak objects and restores three
method implementations after SDK stop. P03 disconnected-registry
retirement is accepted separately in EXP-172. EXP-169 closes D07 at local unsigned `a9aaf25a7`: four failing
authority controls, 119 tests and mounted hosts29/29 versus control19/29.
Automatic eligibility persists before input, and the first semantic destination
owns immediate work. EXP-170 closes D08 at signed `66d1ccb02`: three failing controls,
314 affected tests and mounted51/51 versus39/51. Stale traits and rejected reader
callbacks cannot consume a generation. Immediate reconnect Resource/Log events
belong to the fresh Home; the control sends them to Peer. A retained host remounts
fresh after delayed detach with body reconstruction. EXP-171 closes R04 at signed
`4ba7179c6`: two failing no-body controls,318 affected tests and mounted57/57 versus
43/57. Its first retained-reader callback proves zero observers before SDK delivery,
then fresh Latest Resource/Log ownership. EXP-172 closes P03 at signed `4653e0a72`: three failing controls,326 affected
tests, complete Release ABBA on27/26.5 with zero retired entries/weak survivors,
eight ordinary automatic/manual passes and watchOS Release compile. Candidate
heap increases are512–832 bytes for the first100 and512–1,152 for the second100.
EXP-173 closes D10/R06 at signed `7619eb8a2`:337 affected tests and native77/77
versus55/77. Rejected/canonicalized writes follow the accepted Binding, and exact
occurrence callbacks preserve a rematerialized presentation. Resource/Log markers
keep their exact view/session at setter return and native onDismiss. All12 safety
findings are repaired within their evidence boundaries. EXP-174 closes R05 at
signed `368c62a72`: three failing controls and346 tests prove monotonic nested
publication, live observer membership and exact two-host teardown. All six bounded
component reviews now pass. EXP-175 repairs T03's existing late-completion
regression at signed `aefe337b6`: four failing controls and379 affected tests.
Resource metrics/completion keep their original scope while new-session and peer
actions retain zero foreign counts. EXP-176 closes T03 at signed SDK `5e41d0b11`
and fixture `797ab135c`:397 affected tests across396+1,8 Objective-C API checks,
iOS/watchOS Release and strict lint. Native167 tests and22/22 expectations/77
signals agree with Datadog on5 Resources,4 expected errors,5 views across2 sessions,
a fresh peer action with0/0 counts and0 crashes. All6 Swift/Objective-C starts and
both automatic task outcomes retain captured owners through actual A background,
B manual-view navigation and session renewal.53 Python controls reject invalid
owners, metrics, identifiers and timing. All failed fixture attempts are retained.
Physical scene, minimum-runtime, stable API and final release gates remain open.
Next implement T04 current-view errors under its separate explicit-target contract.

The released SDK baseline is not semantically safe for applications with
concurrent scenes. Process-representative view state and process-global SwiftUI
controller discovery can make one window replace or own telemetry from another,
especially during early scene creation and automatic SwiftUI navigation.

This branch has a credible iOS 27 multi-scene model, but it is not release-ready.
It keeps independent scene view branches, one current destination per scene, and
fresh RUM occurrences for committed navigation. UIKit, explicit SwiftUI,
scene-targeted manual authority, Operations across navigation, actions,
Resources, and Traces have substantial mapper/backend evidence. The experimental
manual-view APIs are useful and pass their one-scene scenarios. The SwiftUI
transition source and host prove the engine and adapter boundary. The SDK-owned
publisher and one-shot Observation router paths pass their low-cost migration
and runtime gates. EXP-150 proves that a plain current-destination value read
during SwiftUI reconstruction is too late; EXP-151 proves that an existing iOS
27 `@Observable` router can instead deliver the accepted destination before its
setter returns and preserve exact post-dismiss attribution. EXP-152 confirms
that SwiftUI's actual Sheet and full-screen-cover `onDismiss` callbacks then run
against those fresh revealed occurrences and do not create another Home.
EXP-153 closes reliable callback-driven third-party parity: one adapter around a
custom library-owned container reuses the SDK publisher host, preserves the
zero-screen/zero-navigation-method budget, and passes the complete occurrence
and downstream ownership oracle without a new SDK primitive. EXP-154 then proves
two native Observation scenes serially, and EXP-155 accepts the first explicit
Operation `.current(in:)` target with exact A→B raw and reduced backend evidence.
EXP-157 accepts inferred cross-scene Operations on a physical iPad. EXP-158 then
generalizes the experimental view target and accepts explicit one-shot action
routing: A and B own their requested actions while an unchanged source-less
action still uses the last-interacted representative.

The remaining risk is concentrated in automatic SwiftUI limitations, selecting
the reviewed public shape for trustworthy low-cost adapters and downstream
targets, proving genuine concurrently visible/interactive windows, completing genuine
scene disconnect/remount and final-host-removal runtime evidence, simultaneously
usable window hardware, remaining explicit
target APIs for work without reliable source context, downstream-surface runtime
coverage, lifecycle/restoration, API review, and ordinary-app
compatibility/performance.
No product decision blocks the next internal experiment.

EXP-177 closes T04 at signed SDK `1e9c4788d`:376 affected/11 new tests,8 ObjC,
strict lint and iOS/watchOS Release pass. Live targets preserve independent fallback
and Resource owners; two reproduced dropped-callback paths are repaired.168 probe
and67 Python/3 connector checks pass. Frozen run
`exp177-20260917T173444Z-28b735bf7f34` passes24/24 local expectations/61 signals,
one callback and exact backend9 errors/3 views/2 actions with7/2 error counts and
0 Resources/crashes. T05 view attributes/removal is next.

EXP-178 is defined for T05 single/batch view attributes and removal. Its oracle
requires exact target-only changes and unchanged process-wide global precedence
in SDK tests and a20-marker/3-view native/backend contract; no new gate closes yet.

## Support matrix

| SDK surface | Current branch support | Strongest evidence | Confirmed gap or remaining gate |
| --- | --- | --- | --- |
| View creation and lifecycle | Independent UIKit and explicitly tracked SwiftUI scene branches coexist in one RUM session. Navigation creates occurrences rather than reusing platform identity. One scene teardown does not resurrect or stop another branch. | Two-window backend runs beginning with `EXP-002`; occurrence/reconnect state tests `EXP-060`-`066`; signal-driven chains `EXP-109`-`113` | Released baseline remains process-representative. Simultaneous visibility, activation, peer close, reconnect, and two-scene restoration still need capable hardware. |
| SwiftUI navigation | The iOS 27 semantic engine is independent of a visual container. The native convenience SPI and arbitrary-content host prove committed fresh occurrences, unchanged standard `NavigationStack`/sheet/cover rendering, target-local authority, exact input precedence, and stable source lifetime. Opaque content retains automatic capture without guessed semantic views. EXP-148 adds an SDK-owned accepted-state publisher observer with automatic metadata, sparse overrides, equal-route occurrence identity, delayed authority, and route-count-independent integration. EXP-149 closes actual host reconstruction/subscription pinning, publisher replacement, two-scene observed-source isolation, posted-disconnect cleanup, and unrelated automatic-subtree coexistence. EXP-150 rejects render-time current-value observation. EXP-151 accepts one-shot Observation `.didSet` for an existing iOS 27 `@Observable` router whose complete accepted destination is stored in one atomic property, and restores exact synchronous dismissal attribution. EXP-152 confirms actual native Sheet/Cover `onDismiss` callbacks run after accepted Home state and use the fresh occurrences without creating another Home. EXP-153 proves a custom library-owned container can use one synchronous accepted-state callback adapter and the existing SDK publisher host without retroactive conformance or per-screen/per-method RUM code. EXP-154 proves two real native scenes independently mount the Observation boundary and retain distinct H1/D1/H2 occurrences plus exact downstream owners. The low-level EXP-146 publisher remains adapter-author evidence, not the normal customer path. | `EXP-141` 38/38; `EXP-142` 48/48; `EXP-143` restoration 20/20 and canonicalization 19/19; `EXP-144` 43/43; `EXP-145` 19/19; `EXP-146` explicit/capability 42/42 and precedence/lifetime matrix; `EXP-147` migration audit; `EXP-148` 9/9 focused, 153/153 probe, Release build, and final 38/38 local/backend; `EXP-149` 20/20 focused lifetime/scene matrix; `EXP-150` frozen runtime FAIL 17/38; `EXP-151` 8/8 focused, 193/193 broadened, 154/154 probe, Xcode 27 iOS Release plus visionOS package builds, and post-review 38/38 mapper/backend; `EXP-152` 155/155 probe plus clean 38/38 mapper/backend with exact native-callback owners; `EXP-153` 7/7 focused, 161/161 probe, lint and Release PASS, plus clean 42/42 mapper/backend and one stable registration; `EXP-154` 2/2 focused, 162/162 probe, lint and Release PASS, plus clean 25/25 mapper/backend with seven views and six exact marker pairs | Automatic discovery is still semantically late and automatic split lacks destination views. A plain current destination is not a trustworthy early signal. Interactive dismissal/cancellation, real OS disconnect/remount/final removal, API review, and simultaneous hardware coexistence remain. Plain local `@State` and opaque navigation retain automatic/manual fallback rather than an exact claim. |
| UIKit navigation | Push/pop/modal and stock regular-width split transitions create fresh committed occurrences. Interactive cancel retains the current UUID; finish creates a fresh returned UUID. Structural Primary/sidebar columns are not current RUM destinations. | `EXP-079`/`080`, deterministic `EXP-112`, mapper/backend action and Resource ownership | Human edge gestures, subclass containers, adaptive collapse/expand, simultaneous-window completion, and ordinary-app compatibility remain. |
| Manual views | Internal scene stacks and the iOS 27 Swift SPI support exact scene/key start-stop pairing, nested distinct keys, navigation beneath authority, latest-destination reveal, fresh returned occurrences, and crash-safe duplicate-key misuse. Automatic tracking continues outside the target. | `EXP-122`, `EXP-125`-`128`, customer-shaped `EXP-137`-`140` | Same key in A/B with reverse stop is tested hostlessly but live `EXP-129` is simulator-inconclusive. Stable Swift and Objective-C surfaces require review. Legacy source-less start/stop intentionally does not pair with targeted calls. |
| Actions | Source-bearing UIKit/SwiftUI taps emit once; exact-view actions advance the compatibility representative. Manual work inside trustworthy event handoff uses the exact view. A threshold-qualified UIKit scroll remains on its origin across navigation. The experimental one-shot `RUMViewTarget.current(in:)` overrides a wrong process representative, and an unavailable explicit target preserves independently inferred fallback. | `EXP-089`, `EXP-132`; `EXP-158` focused/custom/NOP tests, 9/9 mapper oracle, and exact backend A/B owners | EXP-159 accepts targeted start/stop at15/15; stable review, D12 expired-stop metadata and sustained concurrent topology remain. The decisive simultaneously visible A/B inferred discriminator remains hardware work. Ordinary SwiftUI Button child tasks begin outside the handoff in `EXP-135` and correctly use the approved last-interacted fallback unless explicitly targeted. |
| Resources | Start ownership is captured and completion remains on that scope after navigation or teardown. Manual starts use exact handoff view/scene when available. | `EXP-006`-`009`, `EXP-023`, focused completion tests | Explicit scene targeting and remaining two-window runtime rows are incomplete. Shared/coalesced `EXP-136` is hardware-gated after repeatable simulator-system crashes before completion. |
| Traces and log correlation | Manual/native/OpenTelemetry and URLSession spans share start-context selection. One request survives representative churn; independent A/B requests completed in reverse order keep their start owners. Log correlation and mirrored-error routing have focused scene tests. | Trace-only `EXP-133`/`134` backend spans; latest affected DatadogTrace suite 151/151 | Shared request hardware run, exact-source escape hatch, live two-window log/mirrored-error evidence, and compatibility remain. |
| Errors and view mutations | Manual errors, view attributes, timings, loading-time mutations, and internal view commands prefer exact handoff view then scene then representative. | Focused regressions grouped in `EXP-101` | Targeted public surface and comprehensive two-window mapper/backend runs remain. Raw customer `Error` values must still use sanitized telemetry paths. |
| Operations | Identity is application-wide `(name, operationKey)`. Every step resolves its view independently; navigation or an explicit scene target can change start/end view. Duplicate starts keep only the latest client start, produce no synthetic end, and leave the earlier backend operation to four-hour timeout. The iOS 27 `.current(in:)` SPI preserves explicit > inferred > last-proven > representative fallback. | `EXP-130` raw/reduced navigation Operations; `EXP-155` 24/24 plus eight raw steps and four reduced explicit-target Operations; physical `EXP-157` 24/24 with the same exact inferred A→B/A→A/B→B reduction | Explicit and inferred cross-scene behavior is accepted, but stable Swift/Objective-C API review remains. Simultaneous on-screen topology is still a human-arranged qualifier; manual-key/controller target forms and other downstream target APIs remain. |
| Scene lifecycle and restoration | Exact registry, disconnect fencing, retained-reader rearming, migration, explicit session stop, and origin-scene teardown preserve proven ownership in deterministic tests. EXP-146 additionally releases only the exact semantic host and rejects stale post-disconnect starts until fresh lifecycle. | `EXP-008`, `EXP-041`/`042`, `EXP-063`-`066`, `EXP-113`, `EXP-143`; EXP-146 focused disconnect/lifetime tests and synchronous real-reader bounce | Posted notifications and synchronous reader callbacks do not prove genuine OS disconnect or representable remount timing. Final two-window host removal hit the same simulator-system crash twice before removal. Real focus handoff, peer lifecycle, reconnect, isolated background/foreground, and concurrent A/B restoration remain hardware gates. |
| WebView, vitals, fatal/exported context, profiling | WebView native container snapshots and several process/context surfaces have source or focused-test seams. Vitals remain view-based. Profiling operation identity is exact. | Focused module checkpoints and source inspection in the archive | Named runtime/backend scenarios are missing for WebView, vitals, mirrored logs, fatal/exported context, and profiling support statements. Profiling is process-level, not a per-scene view model. |
| Session Replay | Exercised UIKit/SwiftUI two-window and teardown runs uploaded replay data without an SDK-caused crash. | Repeated runtime sessions including `EXP-004` and `EXP-019` | Scene-correct replay representation is explicitly out of scope. Only crash safety is a release requirement here. |
| Single-scene compatibility | Ordinary automatic/manual and custom/NOP early baselines pass on27/26.5 in EXP-160; broader compatibility is not yet established. D01/D02/D09/D11/D12 identify required repairs. | DatadogRUM 1,260/1,260 at EXP-159; EXP-151 broadened SDK selection 193/193; native probe166/166 at EXP-161; RUM view-handler regressions 84/84 at their recorded checkpoint; Operation focused/broadened selections 7/7 and 33/33; Objective-C action/target smoke 8/8; custom/NOP action fallback regressions; live opaque, capability, precedence, source-lifetime, reader-bounce, publisher-observed, Observation-observed, native-callback, custom callback-adapter, serial two-native-scene, explicit Operation, inferred physical Operation, and explicit action target runs; explicit Xcode 27 iOS Release and visionOS package builds PASS | API-surface verification correctly rejects only the unapproved experimental navigation, manual-view, shared-target, Operation, and action symbols; baselines remain unchanged. EXP-160 closes bounded ordinary/custom/NOP/older26.5/dispatch/reentrancy gates; P02 allocation and P03 retained-state failures are repaired in EXP-166/172. Legacy27, minimum15 runtime, reported regressions and final matrix remain. |

## Confirmed capabilities

- Per-scene view ownership survives concurrent creation, navigation, session
  rollover, delayed completion, and originating-scene teardown in exercised paths.
- Returning to the same destination is a new RUM occurrence. The SDK can rotate
  RUM identity without resetting customer SwiftUI state.
- The semantic SwiftUI prototype starts root/destination/presentation occurrences
  at owned materialization boundaries and coexists with automatic tracking without
  duplicate views in the target container.
- The container-independent host can wrap unchanged standard SwiftUI and consume
  a stable adapter source while starting its root before descendant `onAppear`
  and immediate task work. The deterministic probe provides neither a RUM UUID
  nor a native scene identifier. It still manually publishes low-level
  transitions, so this proves the adapter boundary rather than customer effort
  (`EXP-146`).
- The same customer-owned container can expose a stable type-erased capability
  instead of passing the source explicitly and retain the exact 42-event result.
  Without that capability, the host leaves automatic capture active, emits no
  synthetic semantic view, and remains crash-safe; it cannot infer exact
  destination semantics from opaque content (`EXP-146`).
- An explicit source overrides a contradictory capability at runtime. Repeated
  capability resolution during SwiftUI reconstruction does not replay state, and
  a later resolution that returns an adversarial source cannot replace the first
  source selected by the host. All three discriminators preserve the complete
  semantic timeline and exact backend ownership (`EXP-146`).
- One-shot Observation `.didSet` over a single atomic accepted-destination
  property can notify the semantic adapter and rearm before the router setter
  returns. Sequential and nested mutations, SwiftUI reconstruction, teardown,
  and invalid off-main mutation remain crash-safe in focused coverage; the
  post-review runtime assigns immediate and settled sheet/cover dismissal work
  to fresh revealed occurrences (`EXP-151`).
- After a standard Sheet or full-screen cover has actually appeared, its native
  SwiftUI `onDismiss` callback runs after the accepted Home mutation. Each
  programmatic callback fires once, creates no extra Home, and its immediate and
  settled action/Resource pairs use the fresh revealed occurrence (`EXP-152`).
- A callback-driven custom navigation library can keep ownership of rendering
  and transition methods while one boundary adapter observes its synchronous
  accepted snapshot. The existing publisher host produces the full
  H1/D1/H2/Sheet/H3/Cover/H4 sequence, initial lifecycle ownership, and one
  stable registration without retroactive conformance or a new SDK primitive
  (`EXP-153`).
- Two real `WindowGroup` scene sessions can independently mount that accepted
  Observation boundary. Serial A and B navigation each creates distinct H1,
  D1, and fresh H2 occurrences, and all six marker action/Resource pairs remain
  on their exact scene-local owner (`EXP-154`).
- The first customer-shaped Operation target can resolve `.current(in:)` for
  every step independently. With the opposite scene intentionally made process
  representative, backend raw steps and reduced Operations still expose A→B
  success/failure, A→A alpha, and B→B beta with reverse completion (`EXP-155`).
- The same generalized target can route a one-shot action to A or B while the
  opposite scene is representative. A legacy action emitted from source A still
  follows representative B, and an unresolved explicit target falls back to the
  independently inferred candidate instead of dropping the event (`EXP-158`).
- Sequential repeated equal route values retain distinct materialized occurrence
  claims while preserving ordinary `NavigationLink(value: Route)` matching.
- A directly restored repeated-equal path materializes only its top on iOS 27;
  removing that position rebases the boundary to a fresh surviving occurrence,
  without publishing hidden root or lower-route views. The accepted top starts
  before hidden-root lifecycle work, and reliable replacement readers can adopt
  or recover ownership across descriptor lag, disconnect, reuse, and scene move.
- External router replacement emits only accepted same-type and different-type
  destinations. A rejected proposal emits no view. If a binding canonicalizes a
  proposed value, only its getter result becomes current and starts before the
  accepted destination's `onAppear` and immediate task work.
- Direct semantic presentation replacement is atomic in both exercised
  directions: H1 → Sheet S1 → Cover F1 → Sheet S2 → fresh H2. The underlying
  stack destination is never briefly current between presentations.
- The actual semantic SPI preserves sibling-controller containment. Right-side
  Detail commits beneath left manual authority without becoming current, then
  starts once as a fresh semantic occurrence after authority stops (`EXP-145`).
- A manual authority suffix can hide underlying navigation, reveal only its latest
  committed destination fresh, and nest Compose → Preview → fresh Compose.
- UIKit interactive cancellation and completion are committed-transition
  semantics, and regular split Primary/sidebar surfaces are structural context.
- Source-bearing actions and captured Resource/Trace starts retain exact ownership;
  source-less work keeps the existing last-interacted representative behavior.
- Operation start/end views may differ, identities are not scene-namespaced, and
  duplicate-start behavior matches the approved backend timeout contract.
- Scene state is internal and suitable for future Execution Context mapping
  without changing today's wire format.

## Confirmed gaps and failure modes

1. Automatic native SwiftUI discovery can start after `onAppear`/immediate
   `.task` work, identify framework containers instead of semantic routes, and
   leak the prior scene into a newly opened window (`EXP-021`, `022`, `028`,
   `069`, automatic control in `EXP-111`).
2. `EXP-143` through `EXP-146` close direct repeated restoration, external router
   replacement/rejection/canonicalization, presentation-to-presentation
   replacement, actual-SPI sibling isolation, the container-independent engine,
   arbitrary-content host, stable explicit source, optional capability, and
   opaque automatic fallback, runtime precedence, repeated reconstruction, and
   adversarial source replacement at the engine/adapter boundary. EXP-146 also
   passes a synchronous real-reader bounce and focused disconnect fence, while
   its final-removal runtime is simulator-inconclusive before removal. `EXP-147`
   closes the migration-cost discriminator for an application with existing
   observable routers: 25 routes, seven presentations, three exact router
   boundaries, two automatic-fallback boundaries, zero screen edits, zero of
   twelve navigation-method edits, and zero RUM-code growth for one added route
   and presentation. `EXP-148` moves that policy into DatadogRUM and passes the
   same 38/38 semantic/backend oracle. It also fixes equal-route deduplication,
   pre-first-value authority, background-delivery ordering, and pending-source
   precedence. `EXP-149` closes actual host subscription reconstruction,
   publisher replacement, two-scene observed-source isolation, posted-disconnect
   fencing, and unrelated automatic-subtree coexistence at 20/20. `EXP-150`
   conclusively rejects a value sampled only during SwiftUI reconstruction: its
   frozen run fails 17/38 and backend intake keeps immediate dismissal work on
   the outgoing presentation. `EXP-151` accepts one-shot Observation of one
   atomic accepted-state property: 8/8 focused tests, 193/193 affected SwiftUI
   tests, 154/154 probe tests, iOS Release and visionOS builds, and a post-review
   38/38 runtime/backend run with exact immediate dismissal ownership. `EXP-152`
   separately waits for actual Sheet/Cover content appearance and then passes
   38/38 locally and in backend intake: both native callbacks see accepted Home,
   create no extra occurrence, and use fresh H3/H4. `EXP-153` then closes
   callback-driven custom/third-party parity at 42/42 through one boundary and
   the existing publisher host, with one stable registration and no per-screen
   or per-method RUM code. `EXP-154` then closes serial two-native-scene parity:
   both real scenes produce independent H1/D1/H2 chains and exact owners at
   25/25. Genuine concurrent visibility, interactive gesture dismissal, and
   genuine OS disconnect/remount remain hardware-gated.
3. Stable simultaneously visible/interactive windows cannot be proven by this
   simulator. Repeated Metal/`backboardd` failures are environment boundaries, not
   SDK crash evidence.
4. Ordinary SwiftUI Button child tasks are outside the `sendEvent` handoff in the
   measured path. Exact origin cannot be inferred after suspension; `EXP-135`
   intentionally preserves the approved B/last-interacted fallback.
5. Scene-targeted Operations and one-shot actions are accepted engine proofs.
   Stable API review and named T03–T14 families remain. EXP-159 closes its
   targeted long-running slice; D12 reopens T02 for expired-stop metadata.
6. Activation, peer backgrounding, reconnect, per-scene lifecycle, and concurrent
   restoration are incomplete.
7. Errors, logs, WebView, vitals, fatal/exported context, and profiling lack the
   same depth of live two-window/backend evidence as views, Resources, and Traces.
8. Full normal-app, custom-handler, Objective-C Release, supported-system, and
   performance/reentrancy validation has not run on the final code shape.

## Historical pre-implementation routing audit for EXP-159

Source inspection on 2026-09-17 uses `670843f9d` (the documentation-only
successor of accepted implementation `c2d1f1f9a`). No test or runtime was rerun
for this audit. The interrupted pre-pause audits are not evidence. This table
is the historical slice selection; the accepted EXP-159 update and finite T gates
below/in PLAN supersede its next-boundary column.

| Surface | Current committed routing and lifetime | Next boundary |
| --- | --- | --- |
| Long-running actions | `Monitor.startAction` and `stopAction` each capture `currentExecutionTarget`: exact handoff view, then handoff scene, then representative. `RUMSessionScope` already isolates these commands by view/scene, but only one-shot action commands carry a separate explicit candidate. `RUMViewScope` has one action slot per view; duplicate starts do not replace it. | Extend the accepted action target bridge to start/stop, preserving both candidates and exactly-once custom/NOP fallback. This is the selected EXP-159 slice. |
| Action completion | `RUMUserActionScope.process` stops the selected view's action; stop name/type are final event metadata, not an identity lookup. View navigation/stop already ends the outgoing action. Cross-scene activity advances timeouts with an attribute-free keep-alive command. | A live explicit view with no action must not fall through to another scene's action. The target selects current view at processing time; it is not a frozen action handle and does not extend actions across navigation. Preserve timeout and duplicate-start behavior. |
| Manual Resource starts | All three `startResource` forms capture the same inferred target. The owning `RUMViewScope` creates the Resource child. | A later slice should target starts; it must retain the captured owner and avoid adding a completion-time view lookup. |
| Resource metrics/success/error | Manual completion commands retain their resource key and default representative target. `RUMSessionScope.propagate` finds the existing Resource owner before removing completed scopes; `RUMResourceScope` emits success or network error through that original parent, including an inactive view retained for pending work. | Preserve resource-key ownership, late completion, metrics, and error paths. Concurrent duplicate resource keys require separate contract analysis; do not introduce scene namespacing in the action slice. |
| Current-view errors | Message, `Error`, completion-handler, and internal monitor entry points converge on `processCurrentViewError`, which captures inferred context. Resource failures and mirrored/fatal errors use distinct paths. | Explicit current-view errors can reuse separate candidate resolution later. Do not retarget Resource errors or alter captured log action correlation, fatal handling, or telemetry sanitization. |
| View mutations | Single/batch attribute add/remove, custom timings, loading time, feature flags, and cross-platform internal attributes/performance mutations capture inferred context. An obsolete exact view resolves to the current view in its known scene, not an unrelated representative. Global monitor attributes remain process-wide. | Add only reviewed experimental overloads in a later bounded slice; preserve same-scene stale-view fallback, internal-only attributes, and existing loading-time overwrite behavior. |

Primary implementation evidence: `RUMCommandSubscriber.currentExecutionTarget`,
`Monitor` action/Resource/error/view methods, `RUMSessionScope.process`,
`propagate`, `shouldPropagate`, and `routedView`, plus `RUMViewScope`,
`RUMUserActionScope`, and `RUMResourceScope`. Existing tests inspected include
manual handoff routing in `MonitorTests`, concurrent continuous-action isolation
and late Resource completion in `RUMSessionScopeTests`, and custom/NOP bridge
fallback in `RUMMonitorProtocolTests`. These are source/test-code evidence, not
new execution results. Cross-codebase usage inspection also covers automatic
scroll commands, both mock sets, Objective-C forwarding, and internal interfaces.
No Core protocol, encoder, generated model, project file, or wire change is
needed for the selected action overloads.

## Compatibility and regression risks

| Risk | Required protection |
| --- | --- |
| Global automatic suppression | Authority must be contained by exact scene/controller ancestry; detached or sibling trackers cannot suppress unrelated views. |
| Source-less behavior drift | Legacy APIs keep last-interacted/process representative behavior. An unresolved explicit target falls through safely rather than dropping work. |
| Route identity leaking into customer state | Never wrap or replace the customer's route element type. RUM occurrence identity stays private to materialized boundaries. |
| Datadog-specific navigation migration | Keep the semantic engine independent of visual containers. Standard SwiftUI/UIKit/custom navigation and presentation code remains owned by the customer. EXP-147 proves one boundary per existing router, zero screen and navigation-method edits, automatic metadata, sparse overrides, and no route/presentation-growth cost; EXP-148 preserves that budget in the SDK-owned prototype. Neither experiment approves stable API names. |
| Unstable optional capability | Use a stable type-erased transition source across SwiftUI value reconstruction. An explicit source wins over detected capability; an opaque container degrades to automatic tracking rather than fabricated semantics. |
| Uncommitted navigation | A path proposal, speculative callback, or cancelled transition cannot create a view. Reconcile against accepted path and transition completion. |
| Retained/stale scene state | Retain snapshots only as fallbacks; fence disconnected callbacks and never resurrect a live scope from stale UI objects. |
| Swizzle and event-handoff safety | Preserve repository swizzling rules, reentrancy, main-thread constraints, bounded work, and no customer-app crashes. |
| Custom conformers/NOP initialization | New capabilities must fall back exactly once and remain source-compatible when the core or specialized handler is unavailable. |
| Older systems | Gate iOS 27 APIs. Multi-scene semantics may be unavailable earlier, but existing iOS 15-26 apps must build and behave as before. |
| API/wire stability | No internal UUID exposure, returned view handle, temporary scene attribute, session split, generated-model edit, or endpoint change. |
| Replay coupling | Multi-scene RUM changes cannot crash Session Replay; replay correctness does not drive this design. |

## Evidence confidence and recorded validation through EXP-158

Evidence strength is intentionally separated:

| Tier | What it proves |
| --- | --- |
| Source | A path exists or a platform/API limitation is understood; it does not prove runtime attribution. |
| Focused test | State transitions, fallbacks, identity, and adversarial oracle behavior are deterministic. |
| Local/mapper | The intended UI path occurred and the SDK assigned concrete RUM UUID ownership. |
| Backend | Intake and, for Operations, reduction represented the emitted ownership. |
| Physical/human | The topology or analog gesture unavailable to deterministic simulator control actually occurred. |

Latest authoritative checkpoint. All `EXP-146` transition-source entries below
are engine/adapter proofs; none is evidence that normal customers should publish
every transition manually:

- Accepted `EXP-146` explicit-source run
  `semantic-host-explicit-20260916-b`: 42/42, exact ApplicationLaunch/H1/D1/H2/
  Sheet/H3/Cover/H4 inventory, 26 actions, 26 Resources, five long tasks, one
  session, one vital, and zero errors/crashes. ApplicationLaunch owns no action or
  Resource after the initial-lifecycle fix. All four Home occurrences have distinct
  IDs and standard SwiftUI navigation/presentation call sites are unchanged. Host
  implementation `a84061840`; probe/oracle `354422d88`.
- Accepted `EXP-146` optional-capability run
  `semantic-host-capability-20260916-a`: 42/42, the same eight-view semantic
  inventory, 26 actions, 26 Resources, no automatic duplicate, and zero
  errors/crashes. Accepted opaque run
  `semantic-host-automatic-fallback-20260916-b`: 5/5, four automatic-era views,
  six actions, six Resources, no semantic-origin view, and exact Detail delayed
  ownership on `NavigationStackHostingController<AnyView>`. Matrix commit
  `651b173c6`.
- Accepted `EXP-146` runtime precedence and source-lifetime runs:
  `semantic-host-explicit-precedence-20260916-a`,
  `semantic-host-capability-reconstruction-20260916-a`, and
  `semantic-host-capability-replacement-20260916-a` each pass 43/43. Their
  backend sessions `174b4c5c-a7dd-4cee-ab4f-dc0be8ca9c62`,
  `24dd4a46-4a6f-4caf-93e1-77685425e7dc`, and
  `4841bf45-25ac-4f63-ac2c-1de934ef9d3b` each contain launch plus seven unique
  semantic occurrences, 26 exact-view actions, 26 exact-view Resources, no
  decoy/automatic duplicate, and no error event. Probe commit `47bc08eca`.
- Accepted deterministic lifetime run
  `exp146-transient-reader-reattach-20260916T034534Z`: 17/17, session
  `fe33be6f-b953-4c9a-abce-aae37bdb2ef5`. One Detail UUID survives the
  synchronous detach/reattach delivered through the real SDK reader; a later
  source commit creates fresh Home H2, and backend action/Resource owners match.
  This proves generation cancellation, not actual representable remount timing.
- Focused scene-disconnect and lifetime handling passes all 84
  `RUMViewsHandlerTests`: stale A starts are fenced until fresh scene lifecycle,
  A's semantic source and suppression are released, and B remains usable. Posted
  lifecycle notifications are deterministic internal evidence, not a genuine OS
  disconnect run.
- Final-host-removal runs `exp146-final-host-removal-20260916T035341Z` and
  `exp146-final-host-removal-20260916T035545Z` are simulator-INCONCLUSIVE. Both
  clean attempts hit the same `backboardd` Metal/CoreAnimation SIGABRT after B
  became ready and before host removal; neither produced an app crash, terminal
  result, upload, or backend event. The unchanged row is now hardware-only.
- Closed `EXP-145` semantic sibling run
  `semantic-sibling-isolation-20260916-fix-c`: 19/19, exact
  ApplicationLaunch/H1/manual-authority/D1 inventory, 11 actions, 11 Resources,
  two long tasks, one session, one vital, and zero errors/crashes. No automatic
  destination starts, D1 begins only after manual authority, and all active/
  post-stop work uses the expected UUID. Probe/oracle commit `144d6e0e7`.

- Closed `EXP-144` bidirectional run
  `semantic-presentation-bidirectional-20260916-fix-b`: 43/43, exact
  ApplicationLaunch/H1/S1/F1/S2/H2 inventory, 19 actions, 19 Resources, two
  long tasks, one session, one vital, and zero errors/crashes. Every action and
  Resource is grouped on its exact occurrence. SDK implementation `698b1584d`;
  bidirectional probe `01a8466c5`. Exact session and event IDs are in the active
  `EXP-144` record.
- Closed `EXP-143` canonicalized-write and restored-path runs remain accepted at
  19/19 and 20/20 with exact backend ownership.
- `EXP-142` accepted run: 48/48, exact H1/D1/D2/fresh D3/fresh H2
  ownership, 55 backend events (24 actions, 22 Resources, six views including
  ApplicationLaunch, one long task, one session, one vital), zero error/crash,
  and six HTTP 202 uploads.
- Accepted `EXP-151` post-review run
  `exp151-observation-router-postreview-20260916T083131Z`: 38/38 with exact
  ApplicationLaunch/H1/D1/H2/Sheet/H3/Cover/H4 inventory. Backend session
  `ea9adc0e-5a00-4290-9580-fb4df6bc18e7` contains eight views, 11 actions,
  11 Resources, five long tasks, one session, one vital, and no error bucket or
  crash. Immediate and settled sheet dismissal work owns fresh H3; immediate
  and settled cover dismissal work owns fresh H4. The frozen source hashes are
  recorded in the active experiment record.
- Accepted `EXP-152` native-callback run
  `exp152-native-dismiss-callbacks-20260916T094300Z`: 38/38 with each Sheet and
  cover content-appearance and actual `onDismiss` assertion firing exactly once.
  Backend session `fee27d61-1eb7-4eb6-8525-7af74a53ed7e` contains eight views,
  11 actions, 11 Resources, seven long tasks, one session, one vital, and zero
  errors/crashes. Both immediate and settled Sheet callback pairs own fresh H3;
  both cover pairs own fresh H4; no callback creates another Home.
- Accepted `EXP-153` callback-driven third-party run
  `exp153-third-party-callback-20260916T103122Z`: 42/42 plus the
  `registrations=1 active=1` assertion. Backend session
  `f2d2fb24-02d6-4bd9-9df9-ee353b899e69` contains eight views, 13 actions,
  13 Resources, one long task, one session, one vital, and zero errors/crashes.
  All seven semantic occurrence IDs are distinct; initial `on-appear` and
  `task-immediate` work owns H1, and immediate/settled Sheet and cover dismissal
  pairs own fresh H3/H4.
- Accepted `EXP-154` serial two-native-scene run
  `exp154-observation-two-scenes-serial-fix-20260916T111921Z`: 25/25. Backend
  session `a6a5afd5-8089-4996-9805-ed62fb76927d` contains seven views, six
  actions, six Resources, five long tasks, one session, one vital, and zero
  errors/crashes. A and B each own distinct H1/D1/H2 UUIDs; every one of the
  six scene-context marker pairs uses its matching occurrence. The preceding
  attempt is retained as a harness failure because `open-window` had already
  consumed the readiness signal awaited again by the next step.
- Accepted `EXP-155` explicit Operation run
  `exp155-operation-explicit-target-serial-manual-boundaries-20260916T124918Z`:
  24/24 with eight raw steps and four exact reduced Operations in backend session
  `bcb168fd-b5df-42ed-b416-b505a42e6e76`.
- Accepted physical `EXP-157` inferred Operation run
  `exp131-physical-manual-20260916T160435Z`: 24/24 across two native scenes.
  Backend session `1dd8d491-19a4-4b67-bfa5-13df5b2a73a6` contains eight exact
  raw steps and four exact A→B/A→A/B→B reduced Operations. Both windows were
  full-screen rather than simultaneously visible, so that topology qualifier
  remains human-gated.
- Accepted `EXP-158` explicit one-shot action run
  `exp158-sim-66f922ee-19a3-4941-b8ca-c518216e6b0d`: 9/9. Backend session
  `f67c75b2-e839-4701-a283-7e4355682b6a` contains 30 events; explicit A and B
  actions use their requested Home, while the legacy source-A action and Resource
  retain representative B. There is no error or crash bucket.
- Signed SDK implementation/test checkpoint `24cf5078a`; signed migration
  fixture, harness, and probe-test checkpoint `7da52ae6d`; signed EXP-152
  harness checkpoint `0a67f3e36`; signed EXP-153 harness checkpoint
  `d6d813736`; signed EXP-154 scenario checkpoint `7fd6a891a`; accepted
  readiness correction `f92d72909`.
- EXP-151 focused Observation/adapter tests: 8/8. The complete affected SwiftUI
  test file passes 193/193, including nested reentrancy, `StateObject`
  reconstruction, independent-property semantics, deallocation, and invalid
  background-mutation crash safety.
- Native multi-scene probe: 164/164.
- Complete DatadogRUM suite: 1,255/1,255 test cases with zero failures; the
  result bundle records 1,291 expanded device/configuration invocations.
- API-surface verification reports only the expected unapproved experimental
  navigation/manual/shared-target/Operation/action symbols; neither checked-in
  baseline is changed.
- Focused semantic presentation replacement: 3/3.
- Final semantic navigation state/source/arbiter cluster: 153/153. The final
  trait path additionally proves it cannot move or recover a scene without its
  prior concrete reader attachment.
- DatadogTrace: 151/151 at the latest Trace-affecting checkpoint.
- Xcode 27 generic iOS Release and visionOS package builds succeed. Current
  repository SwiftLint is clean across 713 source and 699 test files. Unaffected
  module suites remain at their recorded checkpoints and must rerun at final
  freeze.
- `EXP-141` independently has seven semantic occurrences, 25 exact-view actions,
  25 exact-view Resources, and zero errors/crashes.
- Frozen archives preserve every run ID, session ID, UUID, commit, scenario,
  failed attempt, and earlier suite count; their checksums are in
  [Archive/README.md](Archive/README.md).

No hardware row is promoted from simulator evidence. `EXP-039` remains a
deterministic-harness gap rather than a device queue item because its candidate
was never constructed.

## EXP-159 acceptance update

Targeted continuous-action start/stop is accepted for the bounded live-view API
batch: 15/15 mapper assertions and exact backend final names, stop attributes,
UUIDs, B-before-A order, empty-slot no-op, and legacy source-A→representative-B
ownership. Full RUM 1,260/1,260; probe 166/166; ObjC 8/8; Release/lint PASS.
The first run correctly failed when native background ended A before its stop;
this does not prove sustained simultaneous-window use. See the
[EXP-159 record](Experiments/EXP-143-199.md#exp-159--explicit-scene-targeted-long-running-actions).

## Release blockers

The finite [release checklist](PLAN.md) replaces the former expandable downstream
row. Each family T01–T15 states explicit target, captured ownership or documented
process fallback; each gate has an owner, dependency, decisive test and environment.

1. D10 is the remaining assessed production-review repair. Preserve the accepted
   D01–D09/D11/D12 results and EXP-159 ownership evidence.
2. Preserve P02/P03 frozen-budget evidence from EXP-166/172.
   R05/R06 still need accepted presentation occurrence and multi-observer coverage;
   extraction is still deferred until freeze.
3. Finish named T03–T14 contracts after their repair dependencies. Complete
   hardware H01–H16 when the required topology/gesture is available; simulator
   serial scenes and posted notifications cannot replace that evidence.
4. Close C03/C06 environment gaps, stable API review, final supported-platform
   matrix (including macOS/watchOS), Replay crash safety and Duo27.1 acceptance.

No product decision blocks internal repair work. Execute defined EXP-173 for D10/R06 accepted
presentation state and same-ID occurrence coverage, followed by R05
multi-observer fan-out. Preserve the accepted P03 lifetime and stale-callback evidence.
Do not rerun accepted experiments merely to resume.

## Evidence routing

- Ordered work and hardware queue: [PLAN.md](PLAN.md)
- Searchable experiment status: [EXPERIMENTS.md](EXPERIMENTS.md)
- New detailed records: [Experiments/EXP-143-199.md](Experiments/EXP-143-199.md)
- Historical exact evidence: [Archive/EXPERIMENTS_THROUGH_EXP-142.md](Archive/EXPERIMENTS_THROUGH_EXP-142.md)
- Rejected paths: [REJECTED_APPROACHES.md](REJECTED_APPROACHES.md)
- SwiftUI/manual API contract: [NAVIGATION_API.md](NAVIGATION_API.md)
- Operation contract: [OPERATIONS.md](OPERATIONS.md)
- Tool workflow: [TOOLING_RUNBOOK.md](TOOLING_RUNBOOK.md)
~~~~

## Moved 04

Superseded restart history

Source: .continue-here.md. Original excerpt SHA-256: d384d4016368359f6c26ef24c4218c2a49c9bddd9d0c1eb9d43a6906820f4a7a.

~~~~markdown
# Continue multi-scene RUM work here

Created: 2026-09-16
Updated: 2026-09-17

## Restart position

**Safe EXP-178 SDK checkpoint:** signed `1c6104cacb95751137c700e1812bcb1c0f05a359`.
419 affected tests,8 ObjC,46 attribute integration on26.5, strict lint and
iOS/watchOS Release pass. The27 legacy host attempt is inconclusive before tests.
Native/backend T05 acceptance remains unimplemented and OPEN. Perform the user's
bounded documentation consolidation now, using documentation-only validation;
then continue the frozen EXP-178 native contract without rerunning accepted SDK
checks. The detailed EXP-178 record and durable result own all attempts.

- Branch: `valpertui/multiple-windows-scenes`.
- Current SDK checkpoint is signed `1e9c4788d` (EXP-177 errors accepted);
  accepted T03 Resource starts remain `5e41d0b11`.
  EXP-169 `a9aaf25a7` remains unsigned locally under the authorized fallback.
  accepted EXP-159 remains `af63657f0` (15/15 mapper/backend). EXP-160/161 change
  tooling/documentation only. Do not rerun
  EXP-158/159 or accepted baseline/acceptance runs merely to resume.
- Current finite release register: **32/66 gates closed**. Read PLAN and
  release-gates.json; every remaining deliverable has owner/dependency/test/env.
- EXP-160 completed: C01/C02/C04/C05/P01/P04 pass on the recorded 27/26.5
  simulator workloads. P02 fails 3 allocations/416 bytes per enabled event
  against 1/64 budget. P03 fails 220 entries in each disconnected/activity registry.
  C03 legacy 27 is inconclusive (both revisions trap in UIKit); 26.5 real lifecycle
  passes. C06 minimum 15 runtime is unavailable; compile-only proof is separate.
- EXP-161 completed: automatic preflight/frozen build/clean install/local/topology/
  backend workflow PASS. 166 fresh probe tests, 15 assertions/86 signals, 7 exact actions,
  3 session-only views, 0 errors/crashes. 24 Python and 3 Node controls pass. Both prior
  tooling-invalid attempts remain preserved in Results/acceptance and the ledger.
- The user's production-review request is assessed in REVIEW_TRIAGE.md. All 12
  findings are relevant D01–D12 repair gates; keep source proof separate from
  mounted SwiftUI/real OS proof. The review now carries a live disposition table at the user's request.
- EXP-162 passes: two failing full-target controls, four watchOS/macOS Debug/
  Release builds, 70 Resource/action plus 28 WebView iOS tests, zero lint violations.
  Definition `1aeca86ff`, watchOS repair `e420528f7`, macOS repair `af8864528`
  are signed; the durable result closes D01/D02 only.
- EXP-163 passes: three recipient metadata failures reproduced on unchanged SDK
  source, then 212 affected tests and strict lint pass after repair. D12 closes
  and T02 is restored; definition `d86ded7f8` and SDK fix `084dff4c1` are signed.
- EXP-164 passes: two failing background getter controls, 31 affected tests,
  mounted-controller fixture 19/19 with zero background hierarchy reads and zero
  Main Thread Checker diagnostics (control: 5 reads/4 diagnostics). D09 closes.
  Unit/runtime tooling-invalid attempts remain in the durable result.
- EXP-165 passes: legacy container failure reproduced, 102 affected tests,
  mounted WKWebView/Replay 19/19 versus control18/19, four collector controls and
  strict lint. D11 closes. The initial deflate-collector-invalid attempt remains
  preserved. Definition `32f446de5` and SDK `9a1ee83a5` are signed.
- EXP-166 passes: signed SDK `5eb3c1aac`, three failing cross-core controls,
  282 affected tests plus stronger session/clock checks, probe build and strict
  lint; complete watchOS RUM/macOS Core Debug/Release builds. Full Release ABBA
  on27/26.5 meets1 allocation/64 bytes per enabled event, ordinary0/0, unchanged
  latency and full-context reentrancy budgets. D04/P02 close; P01/P04 stay closed.
  Diagnostic candidates and the initial snapshot regression remain recorded.
- EXP-167 passes: six failing scope controls, 198 affected tests with 44 new
  matrix cases, and two real iPad simulator scenes with 47/47 runtime checks
  versus control 20/47. Signed SDK `0aaafa7bd` resolves old ownership before
  restoration and shares immediate/delayed policy. D05/D06 close; the initial
  readiness-invalid native attempt remains preserved. No backend/physical claim.
- EXP-168 passes: signed SDK `7b77f60eb`, 303 affected tests, strict lint and
  37/37 mounted lifetime checks on both 27/26.5. Control leaks 25 registrations
  and states; candidate has zero survivors and restores three method implementations
  after SDK stop. D03 and bounded R02 review close. The first 26.5 fixture
  incorrectly required a 27-only arbiter; its INCONCLUSIVE attempt is preserved.
- EXP-169 passes: four failing authority controls, 119 affected tests, strict
  lint and mounted explicit/capability hosts 29/29 versus control19/29. D07 closes:
  empty/missing prerequisites leave automatic tracking eligible; first input owns
  its immediate marker. Definition `9abc3d979` and SDK `a9aaf25a7` are unsigned
  locally after signing-agent timeouts, as authorized.
- EXP-170 passes at signed `66d1ccb02`: three failing controls, seven focused
  and314 affected tests, strict lint, mounted51/51 versus39/51. Reconnect Resource/
  Log work belongs to the fresh Home; unchanged SDK sends it to Peer. Rejected
  readers acquire no authority; delayed retained-host remount is fresh. D08 closes;
  R04's no-body remount evidence is recorded separately in EXP-171. Invalid test/package and inconclusive fixture
  attempts are preserved; no genuine OS/physical ordering is claimed.
- EXP-171 passes at signed `4ba7179c6`: two failing no-body controls,318 affected
  tests and strict lint, mounted57/57 versus43/57. The first retained-reader mount
  starts with zero source observers, then restores Latest and owns its immediate
  Resource/Log markers before a body rebind. Weak source/handler release and source
  withdrawal pass. R04 closes its bounded review; H08/H09 remain physical.
- EXP-172 passes at signed `4653e0a72`: three failing controls,326 affected tests,
  strict lint, Release ABBA27/26.5 with zero retired entries/weak survivors and
  original heap limits met. All eight ordinary automatic/manual runs and watchOS
  Release compile pass; seven oracle controls pass. P03 closes. Source snapshots,
  constructor adaptation, raw samples and corrected test fixture attempt are durable.
- EXP-173 passes at signed `7619eb8a2`: six failing initial controls plus a native
  rematerialization regression,337 affected tests, strict lint, eight oracle controls
  and mounted77/77 versus55/77. D10/R06 close. The invalid hook build and both
  valid failed candidates remain in the durable result. All12 safety findings
  have repair evidence; the review stays as a live disposition/history record.
- EXP-174 passes at signed `368c62a72`: three deterministic failing controls,
  nine new regressions and346 affected tests. Nested initial/commit publication,
  live observer membership, publisher/Observation return timing and two-host exact
  teardown pass; strict lint passes. R05 closes all bounded component reviews.
- EXP-175 passes at signed `aefe337b6`: four failing controls, seven new
  regressions and379 affected tests. Metrics/completion stay on the original
  Resource owner; unrelated live action counts and clock-only expiry are correct.
  The fixed-clock fixture correction is preserved. T03 remains open.
- EXP-176 passes at signed SDK `5e41d0b11` and fixture `797ab135c`: ten new
  regressions,397 affected cases across396+1,8 Objective-C API checks, iOS/watchOS
  Release and strict lint. Frozen run `exp176-20260917T164857Z-a72e79966b23`
  passes167 probe tests,22/22 local expectations/77 signals and backend5 Resources/
  4 errors/5 views across2 sessions, peer counters0/0 and0 crashes. All6 Swift/
  Objective-C starts and automatic success/error retain original owners after
  actual A background, B manual-view navigation and session renewal.53 Python/
  3 connector controls pass. All four failed native attempts remain recorded;
  mapper AnyEncodable decoding, asynchronous barriers and serial topology are
  explicit lessons. T03 closes. No simultaneous visibility/physical claim.
- EXP-177 passes at signed SDK `1e9c4788d`, fixture `50f6ef170` and frozen
  HEAD `42f2d3883`:3 failing controls→11 new/376 affected tests,8 ObjC,
  iOS/watchOS Release and strict lint.168 probe/67 Python/3 connector checks pass.
  Run `exp177-20260917T173444Z-28b735bf7f34` passes24/24 local/61 signals,
  one callback and backend9 errors/3 views/2 actions with7/2 error counts,
  0 Resources/crashes. Explicit targets preserve independent fallback and captured
  Resource owners; unsampled/missing-recipient callbacks complete after writes.
  Invalid build/lint/control attempts are retained. T04 closes.
- **Current executable task:** execute defined EXP-178 for T05 view attributes/removal.
  The admission record freezes its20 marker/3 view backend contract. Cover all4 single/batch add/remove forms and existing
  global attribute precedence, custom/NOP fallback, closed/stale targets and
  current occurrences. Reuse the accepted T04 error marker and A01 runner to
  prove exact mapper/backend attribute states. T06 timing/loading follows.
  Do not rerun accepted experiments merely to resume. Deferred extraction remains
  after freeze; posted notifications never close hardware gates.
- Physical queue remains at H01/EXP-129 until capable iPad/Duo hardware is live.
  Latest discovery reports paired iPhone 16 Pro Max (27.2), Apple Watch and iPad unavailable. Recheck capabilities before device work. iOS 27 and 26.5 simulators are available; iOS 15 is not.
- Tooling and planning checkpoints are now committed and signatures verified:
  `a6e45d2bb` acceptance workflow, `6552ae261` baseline measurements, and
  `85c0d47a0` finite release gates and review triage. The following policy/handoff
  commit also records local unsigned-run support; resolve its actual HEAD on resume.
- Evidence checkpoints `0f91747a4` (EXP-162) and `6b7a53dd7` (EXP-163) are
  unsigned locally after signing-agent timeouts. EXP-164 definition `1060d4f89`
  and SDK checkpoint `a9abc092b` also used the fallback. Earlier SDK fixes remain
  signed. EXP-168 tooling `8ea8d1451` and evidence `58e06cfb1` are unsigned after
  signing-agent timeout/refusal; SDK `7b77f60eb` is signed. Resolve later
  commit signatures from actual HEAD.
  Verify/sign all unsigned checkpoints before any
  future authorized push; no push is authorized now.
- **Commit policy, updated by the user on 2026-09-17:** sign directly whenever
  signing is available. If the signing agent is unavailable, continue committing
  locally with `--no-gpg-sign`; do not stop work waiting for it. This supersedes
  the earlier signed-only instruction and repository/skill guidance. Signing is
  required before a remote push; no push is authorized here. Verify all outgoing
  commit signatures before any future authorized push, signing any local unsigned
  checkpoints first. Preserve their source trees and evidence identities.
- Every commit uses `--only --` with an explicit file list. Never include the
  staged local xcconfig. Verify the actual diff and protected paths after each
  component commit. The two earlier signing failures remain historical evidence;
  the later successful signatures remove the blocker.
- The local unsigned-preflight follow-up passes 27 Python controls, including
  three isolated Git-fixture checks. EXP-161 runtime evidence remains pinned to
  its original frozen runner; no accepted runtime was rerun for this policy change.

## Protected working-tree state

These paths belong to the user and are intentionally outside the checkpoint:

- `Datadog/Datadog.xcodeproj/project.pbxproj` is modified and unstaged.
- `xcconfigs/Datadog.local.xcconfig` is staged. It contains local configuration;
  never log its contents and never commit it.

`DatadogRUM/MultiSceneSupport/PRODUCTION_SAFETY_REVIEW.md` must now be kept
current and committed with explicit paths, per the user's later instruction.
Preserve its historical evidence and update finding dispositions as gates close.
This supersedes the earlier instruction to leave that review untracked/unchanged;
the two protected project/configuration paths above remain protected.

Every future commit must use an explicit path list. Never use `git commit -a`,
and never use a broad staging command that can capture either protected path.

## Restart reading order

1. [MULTI_SCENE_SUPPORT.md](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/MULTI_SCENE_SUPPORT.md)
2. [PLAN.md](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/MultiSceneSupport/PLAN.md) and [REVIEW_TRIAGE.md](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/MultiSceneSupport/REVIEW_TRIAGE.md)
3. [ASSESSMENT.md](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/MultiSceneSupport/ASSESSMENT.md)
4. [BASELINES.md](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/MultiSceneSupport/BASELINES.md) and [COMPONENT_REVIEW.md](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/MultiSceneSupport/COMPONENT_REVIEW.md)
5. EXP-160 through EXP-176 in [EXP-143-199.md](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/MultiSceneSupport/Experiments/EXP-143-199.md); inspect EXP-159 only for a relevant regression.
6. [TOOLING_RUNBOOK.md](/Users/valentin.pertuisot/work/dd-sdk-ios/DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md)

Do not load the frozen experiment archive unless investigating a specific older
experiment.

## Environment rediscovery

Before executing another experiment:

- Re-resolve Xcode MCP workspace identifiers.
- Re-query simulator and physical-device availability.
- Revalidate Datadog authentication before backend queries.
- Use `/Applications/Xcode_27.app`.
- Do not trust remembered MCP interaction/session IDs or temporary artifact
  paths from the prior session.

No experiment or test rerun is required merely to resume. EXP-159 is accepted
within its documented boundary. D01/D02 are accepted by EXP-162. On resume,
finish EXP-176 native/backend acceptance for T03; baseline and acceptance tooling
already exist and have measured results.
~~~~

## Moved 05

Previous experiment index and checkpoint narratives

Source: DatadogRUM/MultiSceneSupport/EXPERIMENTS.md. Original excerpt SHA-256: b8ce8e0cabd46cf85eb11915190f1fff8d3a278cd90ec6aa01d73b384bfaa0df.

~~~~markdown
# RUM multi-scene experiment index

Use this file to find the current status and exact detailed record for a named
experiment. Current support conclusions live in [ASSESSMENT.md](ASSESSMENT.md);
ordered work and the hardware queue live in [PLAN.md](PLAN.md). Search
[REJECTED_APPROACHES.md](REJECTED_APPROACHES.md) before revisiting an earlier
design or tooling path.

Full records through `EXP-142` are frozen in
[the historical experiment snapshot](Archive/EXPERIMENTS_THROUGH_EXP-142.md).
New full records belong in the active
[EXP-143-199 shard](Experiments/EXP-143-199.md). Do not renumber experiments.

Last updated: 2026-09-17

## Current checkpoint

Current release position: **32/66 gates closed**. All12 original safety findings
and all6 bounded responsibility reviews have repair/review evidence. EXP-176 closes
T03 at SDK `5e41d0b11` and fixture `797ab135c`:397 affected cases across396+1,
8 Objective-C checks, iOS/watchOS Release,167 probe tests,22 local expectations/
77 signals and exact backend5 Resources/4 errors/5 views across2 sessions.
All failed attempts remain preserved. EXP-177 closes T04 at signed SDK `1e9c4788d`:376 SDK/8 ObjC, iOS/watchOS Release,
168 probe tests,24/24 local/61 signals and exact9 error/3 view/2 action backend
owners with7/2 error counts,1 callback and0 Resources/crashes. T05/T06 follow. Recent identities and
attempts are in the finite gate register and active shard.

The checkpoints below preserve the earlier telemetry/navigation milestones;
they do not override this current release position.


- Last accepted public telemetry slice: `EXP-159`, targeted long-running action start/stop.
  Bounded synchronous live-view runtime passes 15/15 and exact backend ownership;
  full RUM 1,260/1,260, probe 166/166, Objective-C 8/8, Release and lint pass.
  The earlier background-interrupted attempt remains INCONCLUSIVE. Next work is
  finite release gates, early baselines, incremental review, and acceptance
  automation before any further telemetry expansion.

- Latest physical-device attempt is `EXP-157`. `EXP-156` now closes the tooling
  gate: after the earlier connection, unsigned-install, and restricted-context
  signing failures, a copied `arm64` build passed strict/deep verification,
  clean install, and launch on the wired iPad. The first `EXP-131` runtime then
  timed out before scene B or any Operation call because the scenario still
  used the unrelated legacy occurrence-source Home boundary. It emitted only
  automatic hosting-controller views. The scenario now uses the same explicit
  non-navigating Home setup already accepted for `EXP-155`; focused tests pass
  2/2 and the complete probe passes 163/163. The corrected physical run passes
  24/24 across two native scenes. Backend intake contains all eight raw steps
  and four exact reduced Operations: success/failure A→B, alpha A→A, and beta
  B→B ending before alpha. The Operation contract is accepted. Both scene
  geometries were full-screen and only B was foreground-active at completion,
  so simultaneous on-screen visibility remains a separate human-arranged Stage
  Manager/split-window row. The physical iPad is currently unavailable, so the
  unchanged hardware queue is paused rather than reinterpreted through simulator
  evidence.
- Latest runtime experiment is `EXP-158`. The generalized experimental
  `RUMViewTarget.current(in:)` keeps explicit and inferred action targets
  separate. Its serial two-native-scene run passes 9/9 while deliberately making
  B representative: explicit A owns A, explicit B owns B, and a source-A legacy
  action remains on B. Backend session
  `f67c75b2-e839-4701-a283-7e4355682b6a` confirms the same ownership across 30
  events. This accepts scene-targeted one-shot actions without approving stable
  API or changing source-less last-interacted behavior.
- Latest accepted SDK implementation, probe, and documentation checkpoint:
  `c2d1f1f9a` (`Target one-shot actions to a window scene`). Earlier SDK
  semantic-navigation checkpoint: `24cf5078a`
  (`Add observable semantic navigation adapters`). Latest migration fixture,
  harness, and probe-test checkpoint: `7da52ae6d`
  (`Expand semantic navigation probe coverage`). The signed `EXP-152` harness
  checkpoint is `0a67f3e36` (`Add native presentation dismissal probe`). The
  signed `EXP-153` harness checkpoint is `d6d813736`
  (`Exercise callback-driven semantic navigation`). The signed `EXP-154`
  scenario checkpoint is `7fd6a891a`; its accepted readiness correction is
  `f92d72909`. The signed Operation implementation, scenario, and accepted
  harness correction are `b0524bb5b`, `3e567a494`, and `eb1dd2fdc`. The signed
  inferred-Operation physical harness correction is `4695d092c`.
  Earlier
  semantic engine checkpoints remain `a84061840`, `354422d88`, `651b173c6`,
  and `47bc08eca`; the detailed ledger preserves the preceding native,
  restoration, presentation, and sibling commits.
- Documentation-refactor baseline: `5fc2099e9`
  (`Document repeated semantic route validation`).
- Frozen archive commit: `e51a83b15`.
- Latest validation: accepted explicit and capability paths each pass 42/42 with
  eight backend views, 26 actions, 26 Resources, no automatic duplicate, and
  zero errors/crashes. Accepted opaque fallback passes 5/5 and backend intake
  confirms its Detail ownership. Three additional 43/43 runs and backend
  sessions close explicit precedence, stable reconstruction, and adversarial
  source replacement. The real-reader synchronous bounce additionally passes
  17/17 locally and in backend intake without changing Detail ownership. The
  EXP-149's lifetime matrix passes 20/20. The current native probe passes
  164/164 and the affected SwiftUI test file passes 193/193. The focused
  Observation/adapter matrix passes 8/8. Exact Xcode 27 iOS Release and visionOS
  package builds succeed. Repository SwiftLint passes across 713 source and 699
  test files with zero violations. API
  verification reports only the intentionally unaccepted experimental Swift
  navigation and scene-targeted manual-view prototypes; reference baselines were
  not updated. The frozen EXP-153 runtime passes 42/42 plus its registration
  assertion; backend intake contains eight views, 13 actions, 13 Resources, one
  long task, one session, one vital, and no error or crash bucket. The EXP-154
  run then passes 25/25; backend intake contains seven views, six
  actions, six Resources, five long tasks, one session, one vital, and no error
  or crash bucket. EXP-155 adds a 3/3 focused pass, a 163/163 complete probe,
  clean lint, and a 24/24 runtime/backend pass with two scene-local Home views,
  eight raw steps, four correctly reduced Operations, and no error or crash.
  EXP-158 adds a 9/9 runtime/backend pass, an 8/8 Objective-C smoke pass, a
  successful Release simulator build, and a clean complete DatadogRUM run:
  1,255 test cases, 1,291 expanded device/configuration invocations, and zero
  failures.

Status describes the contract proved, not whether a diagnostic successfully found
a defect. Compound status preserves mixed evidence. `PREPARED` means the
driver/oracle exists but runtime acceptance is pending. `PLANNED` means the
contract is defined but implementation and driver/oracle are not yet complete.

## Current checkpoint and next experiment

`EXP-146` has accepted the shared engine, arbitrary host, explicit adapter source,
optional capability, opaque automatic fallback, runtime precedence, stable
reconstruction, adversarial capability replacement, deterministic reader bounce,
and focused disconnect fencing. Final two-window host removal is hardware-gated
after two identical simulator-system crashes before the discriminator. `EXP-147`
now accepts the realistic existing-router migration shape after source audit,
route and presentation growth, 154/154 tests, and final frozen-source backend
validation. `EXP-148` moves the generic policy into the SDK-owned iOS 27
prototype, corrects equal-route identity and pending-source authority/precedence,
passes 9/9 focused tests and 153/153 probe tests, and repeats the final 38/38
oracle against frozen SDK plus probe sources. `EXP-149` closes the deterministic
observed-source lifetime and scene matrix at 20/20: the actual SwiftUI host keeps
one subscription through reconstruction and publisher replacement, two observed
sources stay scene-local, exact disconnect releases only the disconnected source,
and an unrelated automatic subtree stays eligible. `EXP-150` then rejects the
first value-only parity candidate: a destination read during host reconstruction
cannot establish a fresh reveal before synchronous post-dismiss work. `EXP-151`
supplies the earlier signal for existing iOS 27 `@Observable` routers. Its
one-shot `.didSet` adapter rearms before the setter returns and the frozen runtime
plus backend session close the same 38-expectation oracle. Sequential/nested
mutation, reconstruction, teardown, independent-property, and background-misuse
tests are closed. `EXP-152` then proves the actual native sheet and cover
`onDismiss` callbacks run after the accepted Home mutation and use those fresh
occurrences, without creating another Home. `EXP-153` closes callback-driven
third-party parity through one custom-container boundary and the existing
publisher host, with a 42/42 local/backend run and one stable registration.
`EXP-154` closes serial two-native-scene Observation parity at 25/25 and exact
backend ownership after one deterministic duplicated-readiness harness failure.
`EXP-155` then accepts the bounded Operation `.current(in:)` engine proof at
24/24 with exact raw and reduced backend ownership after three invalid harness
attempts. `EXP-156` closes the physical tooling preflight after two disconnected
attempts, one expected unsigned-install rejection, correction of a sandbox-only
zero-identity result, and a successful verified install and launch. `EXP-157`
then records the first `EXP-131` runtime as harness-inconclusive before scene B
or any Operation call. Its corrected run passes 24/24 across two native scenes,
and backend intake proves eight raw steps plus four exact reduced Operations.
This accepts inferred cross-scene Operation attribution while retaining a human
follow-up for simultaneous on-screen visibility. `EXP-158` then generalizes the
experimental target and accepts one-shot explicit action routing: explicit A/B
actions own their requested scene, while an unchanged source-less action still
uses representative B. The 2026-09-17 current-source routing audit now defines
EXP-159 for explicit long-running action start/stop before implementation.
Proceed with that bounded simulator-capable slice while the physical iPad is
unavailable. Resume `EXP-129` and the
unchanged physical queue when hardware returns, then prepare the navigation,
Operation, and shared target shapes for API review. Interactive
dismissal/cancellation and genuine OS disconnect remain hardware rows. The
ordered acceptance contract is in
[PLAN.md](PLAN.md).

## Complete experiment ledger

| ID | Date | Status | Area | Question/result | Detailed record |
| --- | --- | --- | --- | --- | --- |
| EXP-001 | 2026-09-11 | FAIL + INCONCLUSIVE · backend | Core views | Single-window harness, payload markers, and backend queries work. Three second-window attempts ended in simulator-wide `backboardd` respawns; the second captured baseline scene B replacing still-visible A first. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `a9fab1c4-5cb6-4468-9d1a-dc0936116c46` |
| EXP-002 | 2026-09-11 | PASS · backend | Cross-surface | First fixed two-window proof: A and B views coexist; B navigation does not stop A; delayed resource/span/operation retain the intended B lifecycle. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `574be7dd-4482-48e5-b4cc-eaaa332179bd` |
| EXP-003 | 2026-09-11 | PASS · backend | Actions | Manual B action emits once instead of fanning into A; mixed UIKit/SwiftUI navigation remains scene-isolated. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `4d7dc23b-721d-4038-8c89-3b29a1c373c9` |
| EXP-004 | 2026-09-11 | PASS · backend | Cross-surface | Concurrent UIKit and SwiftUI views coexist; Session Replay uploads are accepted with no SDK crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `6a0b61d0-85a8-4915-b02e-63ab53fa13db` |
| EXP-005 | 2026-09-11 | PASS + INCONCLUSIVE · backend | SwiftUI navigation | Physical SwiftUI navigation action and destination are correct in one scene; opening B reproduces the simulator compositor crash, not an SDK crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `e7bf0f3e-2e46-4487-af4f-072cd7ba8ab8` |
| EXP-006 | 2026-09-11 | PASS · backend | Resources/Traces | Actual URLSession boundary: synchronous UIKit work and task resume can retain B; scene connection and `viewDidAppear` loading can fall to representative A. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` |
| EXP-007 | 2026-09-11 | PASS + FAIL · backend | Cross-surface | Structured requests retained B and correctly kept/dropped their action at 20/200 ms. The same run exposed the pre-fix explicit-session-stop loss of still-visible scene A. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `8a71b04b-ee69-4670-bdb1-28a6a3625662` |
| EXP-008 | 2026-09-11 | PASS · backend | Lifecycle/restoration | Explicit session stop restores both active scene branches; delayed B work remains on B after navigation. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `e03e31d3-eb19-4955-9782-1b583f37b28f` |
| EXP-009 | 2026-09-11 | PASS · backend | Resources/Traces | Three-minute causality proof: structured `Task` retains B; detached task, GCD, and timer use representative A. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `70ccd6cf-1514-4387-86ef-25cc255744c4` |
| EXP-010 | 2026-09-11 | FAIL · backend | SwiftUI navigation | SwiftUI `.onAppear` requests precede the tracked view and land on the preceding view; delayed task work is correct. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `5ebc59df-6fc1-4620-bcb2-1177d9ab3409` |
| EXP-011 | 2026-09-11 | FAIL · backend | SwiftUI navigation | `UIView.willMove(toWindow:)` remains too late for `.onAppear` and immediate `.task`; pre-correction navigation emitted a 0.79 ms duplicate Home. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `fd44bcd2-cde3-4488-a9f4-7756683d85f4` |
| EXP-012 | 2026-09-11 | FAIL · backend | SwiftUI navigation | Child-controller bridge also remains too late. It avoided synthetic/duplicate views in this run and stayed crash-free, but offered no ordering benefit and was removed. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `16e48aa6-6826-49ea-b764-6c0af6f16c0b` |
| EXP-013 | 2026-09-12 | PASS · backend | SwiftUI navigation | Scene custom trait reached SwiftUI before the hidden reader and all six Home/Detail lifecycle resources resolved to the correct view, but outer callbacks still preceded the RUM view by 35/34 ms on Home and 2/1 ms on Detail. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `68786559-42b4-4087-8e34-997e77d081c5` |
| EXP-014 | 2026-09-12 | PASS · backend | SwiftUI navigation | Adding `onChange(initial:)` reduced the callback-to-view gap to 2-3 ms for both Home and Detail. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `92326a81-441e-48b9-97b3-3db2b00bc3ab` |
| EXP-015 | 2026-09-12 | PASS · backend | SwiftUI navigation | Four synchronous custom RUM actions invoked in customer outer `.onAppear`/immediate `.task` before the view payload were all processed on the intended new Home/Detail view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `c77883d4-80fe-4730-a3ff-575221a3c262` |
| EXP-016 | 2026-09-12 | PASS · backend | Cross-surface | SwiftUI scene B navigation and delayed operation/resource work remained on B while scene C opened. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `91864fb5-cace-4f29-a348-5769bf2ffa65` |
| EXP-017 | 2026-09-12 | PASS after INVALID · backend | UIKit navigation | UIKit modal presentation/dismissal and duplicate-name A/B views remained independent. The first delayed-work switch attempt was invalidated by a stale scrolled control, which led to fixed toolbar controls in both probe UIs. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `31d0a951-095a-4a71-8c48-b6e4fb4d0af2` |
| EXP-018 | 2026-09-12 | PASS · backend | Resources/Traces | Using the fixed toolbar switch, a UIKit B trace and operation kept B Home ownership while A became active. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `76599137-09c8-4fb1-b54a-92b3c9ff04d1` |
| EXP-019 | 2026-09-12 | PASS + FAIL · backend | Cross-surface | Broad UIKit/SwiftUI teardown matrix: 18 views, 17 actions, 33 resources, 4 long tasks, zero errors/crashes, and replay available. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `972c83f7-9c13-4ea3-b5b6-d43857bb7815` |
| EXP-020 | 2026-09-12 | PASS · backend | Operations | Post-fix teardown proof. Operation key `206E691E-33AC-4BF1-8D26-E48D81315D9A` started in scene D, D closed one second later, and intake retained both raw steps on D Home view `547eb0b9-5743-47f7-ab07-c309e5b5bb29`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `c8d2aa31-127a-4d4c-a910-8e56eea5fb48` |
| EXP-021 | 2026-09-12 | FAIL · backend | SwiftUI navigation | First concurrent automatic-SwiftUI run using `DefaultSwiftUIRUMViewsPredicate`. Scene-A and scene-B taps and reactivation stayed isolated, but Home and Detail lifecycle resources landed on the preceding view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `76f40f1f-554f-4842-86a1-7bf4955b734c` |
| EXP-022 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Target-runtime automatic Home -> Detail reproduction without opening a second window. Home `.onAppear` and immediate `.task` remained on UIKit Home; Detail's three lifecycle resources and tap remained on its source navigation host. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `5c807364-100d-44b1-8d35-9d5cfd802fc5` |
| EXP-023 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Rejected `viewIsAppearing` experiment. Home `.onAppear` and immediate `.task` remained on UIKit Home; all three Detail lifecycle resources remained on the source navigation host; transient roots remained. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `13e39eae-ccc8-47a6-8125-3f52fab589b8` |
| EXP-024 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Rejected pre-base-`viewWillAppear` candidate. Home `.onAppear` and immediate `.task` used `ApplicationLaunch`; its delayed task and all three Detail lifecycle resources reused Home navigation-host view `7f2ca0fc-31fe-4902-bafb-7a7029b2758c`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `b4bbfa9a-3094-4345-b64e-bb1728bec061` |
| EXP-025 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Rejected post-base-`viewWillAppear` ordering. Home lifecycle work remained on `ApplicationLaunch`; its delayed task and all three Detail resources reused Home host `445ec932-6eb3-49bf-a25b-aff6bacbc29a`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `20462f01-45d6-4838-9102-151467c4c47f` |
| EXP-026 | 2026-09-12 | PASS · backend | SwiftUI navigation | Same-binary manual-mode control after adding the switch. Explicit tracking emitted `SwiftUI scene-A Home` before completion of its three lifecycle requests; all three backend resources use that view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `0b5749cf-e4fd-4bd5-a3e8-4789d3ee6d97` |
| EXP-027 | 2026-09-12 | FAIL · backend | SwiftUI navigation | First standalone native SwiftUI single-window control. Home `.onAppear` and immediate `.task` actions/resources used `ApplicationLaunch` `9514e96c-4cf8-4efb-a55e-35c58ba4b61e`; delayed Home plus all three Detail phases used navigation host `2810e9e8-9676-4b6b-8838-c8efb78b00ad`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `native-single-20260912171659` |
| EXP-028 | 2026-09-12 | FAIL · backend | SwiftUI navigation | First native `WindowGroup` plus `openWindow` proof. Scene A and B received distinct native sessions, but B Home `.onAppear` and immediate `.task` actions/resources used scene A Detail view `b33cbe9a-4613-4327-9e2f-a6ceadba5896`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `native-swiftui-20260912171529` |
| EXP-029 | 2026-09-12 | FAIL · source | SwiftUI navigation | Local LLDB timing/reflection inspection. Root base `viewWillAppear` had no title or children, then Home `.onAppear` ran before the navigation-controller/host callbacks. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `lldb-native-lifecycle-20260912` |
| EXP-030 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Existing explicit `.trackRUMView` control with the modifier inside each screen. Home lifecycle markers ultimately resolved correctly, but Detail `.onAppear` and immediate `.task` actions/resources used Home `4fed08f3-610f-4b6c-bea1-aff019e2e2b4`; only delayed Detail work used Detail `868d14a5-16a6-4425-84c5-338d25677f01`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-030` |
| EXP-031 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Moving unchanged `.trackRUMView` outside the fully constructed screen did not establish earlier semantics. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-031` |
| EXP-032 | 2026-09-12 | PASS · backend | SwiftUI navigation | First explicit early-mount candidate. The inherited scene trait triggered the `.trackRUMView` start while the hidden platform reader was created. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-032` |
| EXP-033 | 2026-09-12 | PASS · backend | SwiftUI navigation | Three clean two-window early-mount runs. Across 72 lifecycle markers, every A/B Home/Detail on-appear, immediate-task, and delayed-task action/resource mapped once to its exact semantic view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-033` |
| EXP-034 | 2026-09-12 | PASS · backend | SwiftUI navigation | A registered but never navigated-to Detail destination produced no Detail platform lifecycle, RUM view, action, or resource. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-034` |
| EXP-035 | 2026-09-12 | PASS · backend | SwiftUI navigation | Three complete push/pop cycles produced the correct seven-occurrence RUM path: Home, Detail, Home, Detail, Home, Detail, Home, each with a distinct view UUID and strict stop-before-start ordering. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-035` |
| EXP-036 | 2026-09-12 | PASS · backend; bounded | SwiftUI navigation | An explicitly tracked but unselected tab produced neither a platform-content `onAppear` log nor a `ProbeOffscreenTabView` RUM view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-036` |
| EXP-037 | 2026-09-12 | FAIL · backend | SwiftUI navigation | A cancelled 50-point interactive back swipe emitted a false roughly half-second Home occurrence and restarted Detail although Detail stayed visible. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-037` |
| EXP-038 | 2026-09-12 | PASS · backend | SwiftUI navigation | Two clean repetitions completed the three-run bar for the final iOS-27-gated candidate. Each backend session had exactly five views, 12 lifecycle actions, and 12 lifecycle resources; every A/B Home/Detail phase mapped once to its exact UUID, with zero fallback or duplicate semantic view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-038` |
| EXP-039 | 2026-09-12 | INCONCLUSIVE · backend | SwiftUI navigation | Inconclusive construction-only stress. `ViewThatFits` rejected an oversized tracked candidate without constructing its platform reader or invoking its appearance callbacks, so it could not test construction without semantic appearance. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-039` |
| EXP-040 | 2026-09-12 | PASS · backend | Presentations | Explicit early-mount modal pass. Client and backend emitted the exact completed path `Home₁ → Sheet → Home₂`, with distinct UUIDs `0ec34c52…`, `7c8e644b…`, and `45b791dd…` despite retained Home state. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-040` |
| EXP-041 | 2026-09-13 | PASS + INCONCLUSIVE · backend | Lifecycle/restoration | Mixed immediate scene-close result. B Home started and stopped once; all six B lifecycle action/resource markers, including delayed completions after `dismissWindow`, retained B UUID `fbf4b50b…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-041` |
| EXP-042 | 2026-09-13 | PASS + INCONCLUSIVE · backend | Lifecycle/restoration | Partial restoration pass with platform-limited topology. Before intentional termination, A/B Home views and all markers were isolated. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-042` |
| EXP-043 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Public-UIKit cancellation diagnostic. At the speculative Home `onAppear`, the retained hidden reader resolved `NavigationStackHostingController<AnyView>` and a coordinator with `initiallyInteractive=true`; cancellation was not known until coordinator completion. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-043` |
| EXP-044 | 2026-09-13 | PASS · backend | SwiftUI navigation | Explicit cancellation-gate pass. A short edge swipe invoked speculative Home callbacks but emitted no Home occurrence or replacement Detail; the UI and RUM branch remained on Detail `0b3bebb8…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-044` |
| EXP-045 | 2026-09-13 | PASS · tests | SwiftUI navigation | Post-run review found that a recreated view could mount before its reader had responder ancestry, and that one scene-wide pending bucket could swallow unrelated lifecycle. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-045` |
| EXP-046 | 2026-09-13 | PASS after INVALID · backend | SwiftUI navigation | Probe-only scene-root/path prototype pass. One authoritative typed path recreated a hidden semantic tracker at each mutation. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-046` |
| EXP-047 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Rejected root-background placement. A's Home/Detail and both final Detail views were correct, but B Home `.onAppear` and immediate work used A Detail before B's hidden sibling tracker existed; only B's delayed work used B Home. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-047` |
| EXP-048 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Rejected whole-stack wrapper. B's first Home work still used A Detail, and changing the wrapper identity rebuilt the `NavigationStack`, replaying retained Home lifecycle work after each Detail start. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-048` |
| EXP-049 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Rejected stable first-child placement. It removed the whole-stack lifecycle replay and preserved one view per mutation, but B Home `.onAppear` and immediate work still used A Detail. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-049` |
| EXP-050 | 2026-09-13 | PASS · backend | SwiftUI navigation | Route-owned boundary pass. Existing explicit tracking was applied directly to each Home and typed Detail builder while the bound path recorded mutations. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-050` |
| EXP-051 | 2026-09-13 | PASS · backend | SwiftUI navigation | Route-owned occurrence/cancellation pass. The cancelled edge drag produced no path commit or RUM transition. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-051` |
| EXP-052 | 2026-09-13 | PASS · backend | SwiftUI navigation | Same-turn programmatic push/revert pass. The probe wrote `[.detail]` and then `[]`; SwiftUI exposed both binding mutations but no Detail lifecycle or RUM view, and no second Home occurrence. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-052` |
| EXP-053 | 2026-09-13 | INVALID · harness | SwiftUI navigation | Invalid harness run, retained only to prevent a false SDK conclusion. Navigation-path mode accidentally excluded the new Alternate screen from explicit tracking. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-053` |
| EXP-054 | 2026-09-13 | PASS · backend | SwiftUI navigation | Corrected materialized replacement pass. After one second on Detail, replacing `[.detail]` with `[.alternate]` produced exactly `ApplicationLaunch → Home → Detail → Alternate`, with no intermediate/restarted Home or duplicate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-054` |
| EXP-055 | 2026-09-13 | FAIL · source | SwiftUI navigation | `UIHostingSceneDelegate` is public from iOS 26 and lets an application-owned `UISceneDelegate` declare a static SwiftUI `rootScene` and receive scene lifecycle for scenes activated through its configuration/request. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-055` |
| EXP-056 | 2026-09-13 | PASS · backend | SwiftUI navigation | Concurrent materialized replacement passed for view creation: backend contains exactly `ApplicationLaunch` plus A/B `Home → Detail → Alternate`, one UUID per occurrence, with no restarted Home, replay, warning, error, or crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-056` |
| EXP-057 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Reproduced semantic occurrence failure. Replacing `[.detail(1)]` with `[.detail(2)]` committed visible Detail 2 while reusing the same destination reader. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-057` |
| EXP-058 | 2026-09-13 | PASS · backend | SwiftUI navigation | Probe-only route-identity control passed. Applying `.id(route)` around the tracked destination made `[.detail(1)] → [.detail(2)]` emit exactly launch, Home, Detail₁, Detail₂, with two distinct same-named `ProbeDetailView` UUIDs, no intermediate Home, and all nine action/resource pairs on their exact occurrence. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-058` |
| EXP-059 | 2026-09-13 | PASS · backend | SwiftUI navigation | Two-window route-identity control passed for view creation. Backend contains exactly launch plus A/B `Home → Detail₁ → Detail₂`, with distinct same-named Detail UUIDs in each scene and no intermediate Home, replay, warning, error, or crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-059` |
| EXP-060 | 2026-09-13 | PASS · tests | SwiftUI navigation | Added an internal scene-local stack-slot replacement primitive for SwiftUI occurrence rollover. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-060` |
| EXP-061 | 2026-09-13 | PASS · tests | Core views | Fixed retained-scope contamination when a navigation path returns to the same platform identity. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-061` |
| EXP-062 | 2026-09-13 | PASS · tests | SwiftUI navigation | Added dormant internal route-occurrence propagation without changing the public API or current runtime path. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-062` |
| EXP-063 | 2026-09-13 | PASS · tests | Lifecycle/restoration | Closed state/handler divergence after scene teardown. The handler already stops and removes the disconnected scene's stack; the arbiter now silently invalidates only matching SwiftUI state, fences stale callbacks until an explicit platform remount, and retains keyed generation history so generation N cannot recreate a deleted entry. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-063` |
| EXP-064 | 2026-09-13 | FAIL · source | Lifecycle/restoration | Added retained-reader update re-registration and an explicit reader-mount path after silent scene teardown. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-064` |
| EXP-065 | 2026-09-13 | PASS · tests | Lifecycle/restoration | Hardened disconnect/reconnect and observer isolation after the `EXP-064` review. Ordinary unchanged updates are deduplicated; stale initial-trait input cannot resurrect disconnected state; inactive reconnect waits for semantic appearance; cancelled remount and reader-mount/disappear races rearm correctly; source-A disconnect preserves a pending migration to B; and detached or re-registered A observers cannot bypass B's coordinator gate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-065` |
| EXP-066 | 2026-09-13 | PASS · backend | Lifecycle/restoration | Probe-only retained-reader fault-injection pass. While scene B remained foreground-active and present in `connectedScenes`, the probe posted `UIScene.didDisconnectNotification`, then updated the same retained representable witness (`0x0000000113c51880`, generation 0→1). | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-066` |
| EXP-067 | 2026-09-13 | FAIL · source | Cross-surface | Split/adaptive navigation has no semantic model beyond one callback-ordered stack per scene. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-067` |
| EXP-068 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Regular-width route-owned `NavigationSplitView` reproduced the navigation-occurrence failure. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-068` |
| EXP-069 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Regular-width automatic `NavigationSplitView` failed semantic creation and attribution. It emitted launch, a setup-only fallback, a transient host, and one final hosting-controller view—no Detail(1), Detail(2), or Placeholder view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-069` |
| EXP-070 | 2026-09-13 | PASS · backend | SwiftUI navigation | Probe-only `.id(selection)` control passed in regular-width `NavigationSplitView`: launch → Detail₁ → Detail₂ → Placeholder used four distinct UUIDs, no Sidebar/Home interval, and all three immediate action/resource pairs used their matching occurrence. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-070` |
| EXP-071 | 2026-09-13 | FAIL · backend | UIKit navigation | Isolated stock `UISplitViewController` tracking reproduced a manufactured occurrence. The platform kept the same visible Primary controller and sent it no second appearance callback, but replacing Secondary₁ with a fresh same-class Secondary₂ emitted launch → Primary₁ → Secondary₁ → Primary₂ → Secondary₂. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-071` |
| EXP-072 | 2026-09-13 | FAIL · backend | UIKit navigation | Application-subclassed `UISplitViewController` reproduced two independent false occurrences. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-072` |
| EXP-073 | 2026-09-13 | FAIL · backend | UIKit navigation | A stable secondary `UINavigationController` proves the defect also affects ordinary push/pop within a split column. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-073` |
| EXP-074 | 2026-09-13 | PASS · backend | UIKit navigation | The iOS 27 multi-scene UIKit split-column handoff candidate fixes the stock root-replacement failure. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-074` |
| EXP-075 | 2026-09-13 | PASS · backend | UIKit navigation | The same candidate fixes nested secondary push/pop. The backend path is exactly launch → Primary → Secondary₁(first) → Secondary₂ → Secondary₁(returned), with no Primary interval. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-075` |
| EXP-076 | 2026-09-13 | SKIPPED · capability | SwiftUI navigation | Blocked before uninstall or launch, so this makes no runtime claim. The route-owned split probe hardcodes Detail₁ and automatically advances to Detail₂/Placeholder; no environment input reaches its existing nil branch. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-076` |
| EXP-077 | 2026-09-13 | PASS · tests | UIKit navigation | Post-run review found that a scene-only pending lookup let an unrelated UIKit appearance expose a sibling interval, and that app/scene background flushed removal while active before suspension. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-077` |
| EXP-078 | 2026-09-13 | PASS · backend; superseded | UIKit navigation | Stock root replacement passed with the exact four-view chain and marker ownership, but the source/build timestamp raced a later no-op conditional cleanup. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-078` |
| EXP-079 | 2026-09-13 | PASS · backend | UIKit navigation | Authoritative nested push/pop rerun on the hardened candidate passed. The exact backend chain is launch → Primary → Secondary₁(first) → Secondary₂ → Secondary₁(returned), with no Primary interval. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-079` |
| EXP-080 | 2026-09-13 | PASS · backend | UIKit navigation | Final post-rebuild stock root-replacement control passed on the exact current tree. The backend chain is launch → Primary → Secondary₁ → Secondary₂, with no restarted Primary. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-080` |
| EXP-081 | 2026-09-13 | INCONCLUSIVE · simulator | UIKit navigation | Tooling/harness discrimination only. Detached install-and-run could pass environment but had no LLDB process; RunProject could debug but not pass environment. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-081` |
| EXP-082 | 2026-09-13 | PASS · backend | UIKit navigation | A real long edge swipe committed the nested pop. The exact backend path is launch → Primary → Secondary₁(first) → Secondary₂ → fresh returned Secondary₁, with no false Primary. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-082` |
| EXP-083 | 2026-09-13 | PASS · backend | UIKit navigation | A real `UIPercentDrivenInteractiveTransition` advanced a nested pop to 35 percent and cancelled it. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-083` |
| EXP-084 | 2026-09-13 | PASS · backend | UIKit navigation | The same 35-percent public-UIKit transition finished instead. RUM emitted launch → Primary → S1(first) → S2 → fresh S1(returned), with no Primary interval. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-084` |
| EXP-085 | 2026-09-13 | FAIL · source | SwiftUI navigation | No supported transparent SwiftUI navigation hook exposes both committed route identity and an early semantic destination boundary. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-085` |
| EXP-086 | 2026-09-13 | PASS + INCONCLUSIVE · backend | UIKit navigation | Two scene-owned split sequences overlapped: B's S2 push began 0.714 ms after A's pop started. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-086` |
| EXP-087 | 2026-09-13 | PASS + SKIPPED · backend/capability | SwiftUI navigation | The new initial-nil/sequence-disable split control passed its empty-detail baseline: the UI showed only Selections and backend intake contained no Detail occurrence, error, or crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-087` |
| EXP-088 | 2026-09-13 | PASS · tests | Actions | Public manual `addAction`/`startAction`/`stopAction` and all three `startResource` overloads now prefer the exact RUM view in a trustworthy execution-local handoff, then its scene, then the unchanged process representative. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-088` |
| EXP-089 | 2026-09-13 | INCONCLUSIVE · backend | Actions | First physical filtered-control run on the `EXP-088` implementation. The predicate rejected the probe button and emitted no automatic tap. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-089` |
| EXP-090 | 2026-09-13 | PASS · backend | SwiftUI navigation | The debug-only keyed binding created distinct Detail1 `1c759…` and Detail2 `c4f1…` RUM UUIDs while preserving one customer state token `e1c37b44…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-090` |
| EXP-091 | 2026-09-13 | PASS · backend | SwiftUI navigation | A same-turn Home → Detail → Home path write coalesced before Detail materialized. Intake contained only launch and the original Home: no Detail and no restarted Home. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-091` |
| EXP-092 | 2026-09-13 | FAIL · backend | SwiftUI navigation | The first run proved that retained Home eventually receives a fresh UUID after Detail while keeping its customer state token. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-092` |
| EXP-093 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Applying `.id` only to the hidden reader did not move returned Home creation before its outer lifecycle marker. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-093` |
| EXP-094 | 2026-09-13 | PASS · mapper | SwiftUI navigation | The path setter ran at 11:59:46.714891, Home's appearance marker at 11:59:46.719548, and the fresh Home payload at 11:59:46.731364. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-094` |
| EXP-095 | 2026-09-13 | FAIL · backend | SwiftUI navigation | First weak per-window retained-route source attempt failed. The source delivered `false`; Home2 was created later and the appearance action/resource remained on Detail. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-095` |
| EXP-096 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Rebinding the registration from both reader reconciliation callbacks still delivered `false`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-096` |
| EXP-097 | 2026-09-13 | PASS · mapper | SwiftUI navigation | Temporary debug-only eligibility labels found two live registrations: Detail rejected the Home key, while retained Home matched but had no current scene. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-097` |
| EXP-098 | 2026-09-13 | PASS · backend | SwiftUI navigation | Retaining the last concrete scene across ordinary hidden-reader detachment passed. The exact backend path was Home `96aad43e…` → Detail `06a622ff…` → fresh returned Home `8ad9240d…`; Home reused state token `749f53ae…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-098` |
| EXP-099 | 2026-09-13 | PASS · backend | SwiftUI navigation | After routing source delivery through the interactive-transition arbiter, a normal Back-button pop retained the pass: Home `24453c4e…` → Detail `8de298b6…` → fresh Home `e20f3c08…`, with the same Home state token and both immediate marker events on Home2. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-099` |
| EXP-100 | 2026-09-13 | INCONCLUSIVE · simulator | SwiftUI navigation | Both single, bounded edge drags were ignored by the simulator: Detail remained active and no path, coordinator, source, or lifecycle signal followed either gesture. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-100` |
| EXP-101 | 2026-09-13 | PASS · tests | Cross-surface | Commits `fb6b3bde7` through `251f6b8bc` close exact-view representative updates, Resource completion ownership, manual error/view/mutation routing, internal view-command handoff, and native/OpenTelemetry span-start parity. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-101` |
| EXP-102 | 2026-09-13 | PASS · backend | SwiftUI navigation | Regular-width single-scene split occurrence pass without customer `.id`. One retained Detail witness moved from Detail 1 to Detail 2 while the keyed generation advanced 1 → 2 → 3. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-102` |
| EXP-103 | 2026-09-13 | PASS + INCONCLUSIVE · backend | SwiftUI navigation | Both native scenes reached regular width and independently retained their Detail witness while advancing generation 1 → 2 → 3. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-103` |
| EXP-104 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Retained split-return failure baseline. Detail₁ `2be7a2d9…` → Detail₂ `532c2db1…` → Placeholder `6334cd0c…` was correct. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-104` |
| EXP-105 | 2026-09-13 | PASS · backend | SwiftUI navigation | Fixed retained split return. The source-created returned Detail₂ UUID `761fe74b…` remained active while SwiftUI replaced the platform reader, and the replacement state adopted that identity without another start. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-105` |
| EXP-106 | 2026-09-13 | PASS · mapper | Tooling | Named-scenario harness startup proof. The valid `regression.single-scene` launch emitted its complete resolved manifest as the first structured record, then initialized Datadog and produced the expected Home/Detail payload. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-106` |
| EXP-107 | 2026-09-13 | PASS + INCONCLUSIVE · mapper | Tooling | Structured-recorder/oracle phase. Versioned JSONL keeps probe source separate from mapper-observed RUM ownership; snapshot reduction derives first-observed starts and active-to-inactive stops. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-107` |
| EXP-108 | 2026-09-13 | PASS + INCONCLUSIVE · mapper | Tooling | Exact probe scene-registry phase. Seven new tests cover logical/native identity, alias rejection, disconnect/reconnect generations, stale-handle rejection, weak windows, scene-local route/presentation/future-context state, and peer isolation; the full probe plan passes 31/31. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-108` |
| EXP-109 | 2026-09-13 | PASS · backend | SwiftUI navigation | Signal-driven Home → Detail → Home acceptance. After a clean uninstall, all three runs produced exactly one local `PASS` with 7/7 expectations and six acknowledged steps. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-109` |
| EXP-110 | 2026-09-13 | PASS · backend | SwiftUI navigation | Signal-driven stack abort and replacement acceptance. The first clean trio proved the driver and view chains, then the oracle was strengthened to require a decisive action and Resource on the final view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-110` |
| EXP-111 | 2026-09-13 | PASS + FAIL · backend | SwiftUI navigation | Signal-driven split acceptance and automatic failure baseline. The corrected route-owned runs pass 10/10 and 13/13: Detail₁ → Detail₂ → Placeholder and Detail₁ → Detail₂₁ → Placeholder → fresh Detail₂₂ each have one distinct UUID plus an exact action/Resource pair. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-111` |
| EXP-112 | 2026-09-13 | PASS · backend | UIKit navigation | Signal-driven UIKit cancellation/completion acceptance plus a shipping structural-view fix. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-112` |
| EXP-113 | 2026-09-13 | PASS + INCONCLUSIVE · backend | Lifecycle/restoration | Exact scene-lifecycle driver acceptance. `open-window` dispatches through exact source A and waits for exact target B readiness; `close-window` dispatches through exact B and waits for B disconnect. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-113` |
| EXP-114 | 2026-09-13 | INCONCLUSIVE · simulator | Lifecycle/restoration | Exact activation-harness boundary. The first scenario version acknowledged ten exact-scene commands, but its source-labelled markers were plain public RUM calls with no SDK provenance. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-114` |
| EXP-115 | 2026-09-13 | PASS · backend | SwiftUI navigation | Target-scoped SwiftUI authority pass. Navigation-occurrence mode enabled `DefaultSwiftUIRUMViewsPredicate` at the same time as explicit route-owned tracking. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-115` |
| EXP-116 | 2026-09-13 | PASS · backend | SwiftUI navigation | Once-per-container SwiftUI integration-shape pass. A probe-only wrapper consumes one bound `NavigationStack` path and centralized route-to-RUM resolver, owns root/destination materialization, and injects the existing route-owned tracking boundary without putting metadata into Home/Detail view types. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-116` |
| EXP-117 | 2026-09-13 | INVALID · harness | Tooling | Clean-run isolation failure in the harness workflow, not an SDK-semantic failure. Both back-to-back Xcode launches passed their local oracle, but the test bundle had not been uninstalled. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-117` |
| EXP-118 | 2026-09-13 | INCONCLUSIVE · simulator | SwiftUI navigation | Prepared automatic/semantic scene-coexistence discriminator; simulator-inconclusive after two explicitly uninstalled runs because `backboardd` aborted in Metal/CoreAnimation before the terminal oracle. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-118` |
| EXP-119 | 2026-09-13 | FAIL · backend | Presentations | Exceptional explicit SwiftUI Sheet over automatic Home. The first run exposed a probe-only source label defect, fixed in `dd1b1cf34`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-119` |
| EXP-120 | 2026-09-14 | FAIL after INVALID · backend | Manual views | Existing direct keyed manual API over automatic Home fails authoritative coexistence. Attempt A never started because the scenario was omitted from a second driver allowlist; the catalog now owns that selection. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-120` |
| EXP-121 | 2026-09-14 | FAIL · backend | Manual views | First internal scene-targeted manual-stack run after `29c8cec2c`. Compose M1 remained authoritative and owned its active action/Resource, closing the `EXP-120` preemption. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-121` |
| EXP-122 | 2026-09-14 | PASS · backend | Manual views | Clean exact-scene manual-view acceptance after `b1a0fb6b8`. The oracle passes 16/16. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-122` |
| EXP-123 | 2026-09-14 | FAIL · backend | Presentations | Exact-scene Sheet lifecycle without a UI-attached suppression boundary. The semantic Sheet M1 was authoritative, but automatic discovery still emitted structural `NavigationStackHostingController` churn and a redundant automatic `ProbeSheetView` presentation-host occurrence. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-123` |
| EXP-124 | 2026-09-14 | INVALID · oracle; semantic PASS · backend | Presentations | First suppression-only presentation-boundary run. Mapper output contains exactly launch, the startup fallback, H1, semantic Sheet M1, and fresh H2; active work owns M1 and both dismiss pairs own H2, with no automatic `ProbeSheetView`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-124` |
| EXP-125 | 2026-09-14 | PASS · backend | Presentations | Clean complete-destination Sheet acceptance after `f452e9e3f` and `fad83f58f`. The oracle passes 14/14. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-125` |
| EXP-126 | 2026-09-14 | PASS after INCONCLUSIVE · backend | Presentations | Independent complete-destination `fullScreenCover` acceptance after `c70920c94`. The first Xcode interaction session expired before capture and receives no semantic or backend claim. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-126` |
| EXP-127 | 2026-09-14 | PASS after INVALID · backend | Manual views | Sibling-container authority acceptance after `45ec5656a`. Two `NavigationStack` branches mount under one outer SwiftUI host; a required ancestry assertion proves distinct left and right controller branches. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-127` |
| EXP-128 | 2026-09-14 | PASS after INCONCLUSIVE · backend | Manual views | Nested keyed-manual authority and duplicate-start acceptance. Attempt A timed out because Compose C1's exact mapper snapshot preceded the driver's `rum-view:compose#1` wait; immutable exact-view waits now search recorded evidence before subscribing. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-128` |
| EXP-129 | 2026-09-14 | INCONCLUSIVE · simulator | Manual views | Prepared exact same-key A/B isolation with reverse-order stop. The 91-test local plan proves the scenario and adversarial oracle: A/B Compose must have distinct UUIDs, exact work cannot cross scenes, stopping B cannot preempt A, and each returned Home must be fresh. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-129` |
| EXP-130 | 2026-09-14 | PASS · backend | Operations | Operation per-step navigation and duplicate-start acceptance. An explicit uninstall plus missing-container check established a clean run. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-130` |
| EXP-131 | 2026-09-14 | PREPARED · tests; hardware required | Operations | Prepared `operations.cross-scene.lifecycle`. Its exact eight-step driver starts success/failure in A and completes them in B, then starts same-name `parallel-alpha` and `parallel-beta` instances in A and B and completes beta before alpha. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-131` |
| EXP-132 | 2026-09-14 | PASS after INCONCLUSIVE · backend | Actions | Real UIKit scroll/navigation acceptance. Earlier Xcode interaction sessions expired before a gesture and are invalid tooling attempts. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-132` |
| EXP-133 | 2026-09-14 | PASS after INCONCLUSIVE · backend | Resources/Traces | Trace-only automatic URLSession owner-freezing acceptance. Attempt A reached the trace mapper with A ownership after B became representative, but the Xcode interaction session ended before a terminal result; no crash report, fatal/assertion output, or UI crash state existed, so it is tooling-incomplete rather than an SDK-crash claim. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-133` |
| EXP-134 | 2026-09-14 | PASS · backend | Resources/Traces | Independent Trace-only reverse-completion acceptance. A/Home H1 `b0bff76c…` starts request A, B/Home H1 `6c67dece…` starts request B, then B completes first while A is representative and A completes second while B is representative. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-134` |
| EXP-135 | 2026-09-15 | FAIL · backend; approved fallback classified | Actions | Ordinary SwiftUI Button → structured-task causal-boundary result. A hierarchy-derived physical tap emits exactly one automatic `tap on SwiftUI_Button` action on A/Home H1 `308f0a66…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-135` |
| EXP-136 | 2026-09-15 | INCONCLUSIVE · simulator | Resources/Traces | Shared/coalesced Trace-only request discriminator. One underlying task is created on A/Home; B joins it without creating or resuming another task and then should release it. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-136` |
| EXP-137 | 2026-09-15 | PASS · backend | Manual views | First customer-shaped scene-targeted Swift SPI acceptance. The probe resolves its real `UIWindowScene` and calls `startView(key:name:in:attributes:)` / `stopView(key:in:attributes:)` rather than the internal handler protocol. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-137` |
| EXP-138 | 2026-09-15 | PASS after INVALID · backend | Manual views | Customer-shaped nested-manual acceptance and harness-isolation fix. The first run passed 29/29 locally and had the correct seven-view session, but C1/P1/C2 view documents retained the preceding launch's run ID because SwiftUI restored a `WindowGroup` value outside the deleted app container. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-138` |
| EXP-139 | 2026-09-15 | PASS · backend | Presentations | Customer-shaped scene-targeted Sheet acceptance. The 14/14 oracle and backend contain H1 `8a5f8cc8…` → one semantic Sheet `83705cb0…` → fresh H2 `4fb5c337…`, with no automatic Sheet duplicate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-139` |
| EXP-140 | 2026-09-15 | PASS · backend | Presentations | Customer-shaped scene-targeted full-screen-cover acceptance. The 14/14 oracle and backend contain H1 `43326c6e…` → one semantic Cover `1d7f7dd0…` → fresh H2 `238b6fa3…`, with no automatic cover duplicate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-140` |
| EXP-141 | 2026-09-15 | PASS · backend | SwiftUI navigation | Customer-shaped complete-destination semantic API acceptance. The 38/38 oracle and backend contain seven distinct semantic occurrences H1/D1/H2/Sheet/H3/Cover/H4 plus ApplicationLaunch, with no automatic duplicate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-141` |
| EXP-142 | 2026-09-15 | PASS after FAIL · backend; weak-oracle PASS excluded | SwiftUI navigation | Repeated equal-route acceptance through real `NavigationLink(value:)` controls. A stronger reveal-before-callback oracle exposed returned Detail work on D2 before fresh D3. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-142` |
| EXP-143 | 2026-09-15 | PASS after FAIL, rejected candidates, and tooling-invalid retries · backend | SwiftUI navigation | Initial repeated restoration, external same/different-type replacement, rejected proposals, and canonicalized writes preserve only accepted path occurrences. The final canonical run starts Alternate before `onAppear`/immediate work, emits no speculative Detail or automatic duplicate, and passes 19/19 plus exact backend ownership. | [active record](Experiments/EXP-143-199.md#exp-143--external-semantic-router-mutations-and-restoration) |
| EXP-144 | 2026-09-16 | PASS after SDK FAIL and harness-invalid retry · backend | SwiftUI navigation | Direct Sheet → Cover → Sheet replacement emits H1/S1/F1/S2/fresh H2 with no intermediate Home or automatic duplicate. The final run passes 43/43; backend intake has the same five semantic UUIDs, 19 exact-view actions, 19 exact-view Resources, and zero errors/crashes. | [active record](Experiments/EXP-143-199.md#exp-144--semantic-presentation-replacement) |
| EXP-145 | 2026-09-16 | PASS after two INVALID harness attempts · backend | SwiftUI navigation | The actual semantic SPI preserves the `EXP-127` sibling boundary. Home commits to Detail beneath left manual authority, emits no intermediate/automatic view, and reveals one fresh Detail afterward. Final run passes 19/19; backend intake has exactly launch/Home/manual/Detail, 11 exact actions, 11 exact Resources, and zero errors/crashes. | [active record](Experiments/EXP-143-199.md#exp-145--semantic-sibling-container-isolation) |
| EXP-146 | 2026-09-16 | ENGINE/ADAPTER PASS after SDK FAIL and INVALID attempts; final removal INCONCLUSIVE · tests + backend | SwiftUI navigation/lifecycle | A container-independent engine and deterministic adapter produce exact occurrences and backend owners. Explicit/capability paths pass 42/42; precedence/reconstruction/replacement pass 43/43; opaque fallback passes 5/5; synchronous real-reader reattach passes 17/17. Focused disconnect fencing passes. Two clean final-removal attempts hit simulator `backboardd` before host removal. This is not customer-integration approval. | [active record](Experiments/EXP-143-199.md#exp-146--container-independent-semantic-navigation-host) |
| EXP-147 | 2026-09-16 | PASS after INVALID · source audit + tests + backend | SwiftUI integration | The realistic fixture has 25 routes, seven presentations, three observable routers, native/local-state and opaque arms. Customer files and all 12 navigation methods remain RUM-free; standard SwiftUI is unchanged; adding one route and one presentation adds zero RUM code; 154/154 tests pass. Final frozen-source run `exp147-router-stream-20260916T052101Z` passes 38/38 with exact backend ownership, no automatic duplicate, and zero errors/crashes. The first 38/38 run remains INVALID because source changed during it. | [active record](Experiments/EXP-143-199.md#exp-147--customer-integration-migration-cost) |
| EXP-148 | 2026-09-16 | PASS after intermediate and pre-lint pass · tests + backend | SwiftUI integration | The route-count-independent router-stream policy now lives in the iOS 27 SDK prototype rather than the fixture: one observed accepted-state stream, automatic metadata with sparse overrides, fresh equal-route occurrences, delayed authority until the first trustworthy state, and strict explicit-source precedence. Focused tests pass 9/9, the probe passes 153/153, lint is clean, and the generic Release build succeeds. Authoritative frozen-source run `exp148-sdk-observed-postlint-20260916T063742Z` passes 38/38 in backend session `c951c32e-12a7-4bc4-bc5e-bdaf2f16f8aa`, with exact eight-view and 22-bucket ownership, no automatic duplicate, and zero errors/crashes. | [active record](Experiments/EXP-143-199.md#exp-148--sdk-owned-observable-router-adapter) |
| EXP-149 | 2026-09-16 | PASS · focused tests | SwiftUI integration/lifecycle | The actual observed host subscribes once across a SwiftUI reconstruction that supplies a different publisher; the replacement remains unsubscribed. Two SDK-owned observed adapters attach to A/B independently, posted disconnect of A releases only A and rejects later A updates while B advances. Automatic suppression remains local and an unrelated subtree stays eligible. The complete semantic/observed lifetime matrix passes 20/20. | [active record](Experiments/EXP-143-199.md#exp-149--observed-source-lifetime-and-scene-isolation) |
| EXP-150 | 2026-09-16 | FAIL · mapper + backend; tests remain green | SwiftUI integration/timing | A one-boundary `currentDestination` value preserves standard SwiftUI and passes state-level parity tests, but it observes dismissal only during the next render. Frozen iPadOS 27 run `exp150-current-destination-20260916T072321Z` fails at 17/38: immediate sheet work stays on Compose and immediate cover work stays on Attachment; fresh Home starts one signal later in both cases. Backend session `2294a609-76f9-47be-a643-ab51edc5b638` confirms both wrong action/Resource owners, while settled work is correct and the app does not crash. This API shape is not an exact customer candidate. | [active record](Experiments/EXP-143-199.md#exp-150--render-time-current-destination-boundary) |
| EXP-151 | 2026-09-16 | PASS · tests + mapper + backend | SwiftUI integration/timing | An iOS 27 one-shot Observation `.didSet` adapter observes one atomically updated accepted-destination property on an existing `@Observable` router and rearms synchronously. Focused tests pass 8/8, the affected SwiftUI file passes 193/193, the probe passes 154/154, and Xcode 27 iOS Release plus visionOS package builds succeed. Post-review frozen run `exp151-observation-router-postreview-20260916T083131Z` passes 38/38; backend session `ea9adc0e-5a00-4290-9580-fb4df6bc18e7` has eight views, 11 actions, 11 Resources, no error bucket/crash, and exact fresh-Home ownership for immediate and settled sheet/cover dismissal work. Plain local `@State` remains fallback-only and the API spelling remains experimental. | [active record](Experiments/EXP-143-199.md#exp-151--one-shot-observation-router-boundary) |
| EXP-152 | 2026-09-16 | PASS · tests + mapper + backend | SwiftUI integration/timing | Harness-only characterization over the accepted Observation adapter waits for real Sheet/Cover content appearance, then records SwiftUI's actual `onDismiss` callbacks. Frozen run `exp152-native-dismiss-callbacks-20260916T094300Z` passes 38/38; each callback fires once after accepted Home state, creates no extra Home, and its immediate/settled action and Resource pairs own fresh H3/H4. Backend session `fee27d61-1eb7-4eb6-8525-7af74a53ed7e` has eight views, 11 actions, 11 Resources, and zero errors/crashes. This closes native callback characterization without replacing the stronger synchronous mutation oracle; interactive gesture dismissal remains a physical/human row. | [active record](Experiments/EXP-143-199.md#exp-152--native-swiftui-dismissal-callback-characterization) |
| EXP-153 | 2026-09-16 | PASS · tests + mapper + backend | SwiftUI integration/third-party adapters | A true custom visual container exposes synchronous accepted snapshots to one dedicated adapter, which bridges into the existing SDK-owned publisher host. No screen or navigation method changes, retroactive conformance, or new SDK API are required. Focused tests pass 7/7, the probe passes 161/161, lint and Release pass, and frozen run `exp153-third-party-callback-20260916T103122Z` passes 42/42 plus `registrations=1 active=1`. Backend session `f2d2fb24-02d6-4bd9-9df9-ee353b899e69` has eight views, 13 actions, 13 Resources, exact H1/D1/H2/Sheet/H3/Cover/H4 ownership, and zero errors/crashes. Opaque state remains fallback-only; two-native-scene runtime parity is next. | [active record](Experiments/EXP-143-199.md#exp-153--callback-driven-third-party-navigation-adapter) |
| EXP-154 | 2026-09-16 | PASS after HARNESS FAIL · tests + mapper + backend | SwiftUI integration/multi-scene | Two real native scenes independently mount per-window Observation routers and each complete H1 → D1 → fresh H2. Attempt 1 rejected a redundant readiness wait after `open-window` had already consumed B's signal; the app and partial attribution remained healthy. Corrected frozen run `exp154-observation-two-scenes-serial-fix-20260916T111921Z` passes 25/25. Backend session `a6a5afd5-8089-4996-9805-ed62fb76927d` has seven views, six actions, six Resources, exact A/B marker ownership, and zero errors/crashes. This closes serial native-scene parity, not simultaneous visibility or lifecycle acceptance. | [active record](Experiments/EXP-143-199.md#exp-154--serial-two-native-scene-observation-parity) |
| EXP-155 | 2026-09-16 | PASS after three INVALID attempts · tests + mapper + backend | Operations/API prototype | The iOS 27 `.current(in:)` SPI keeps explicit and inferred targets separate and resolves every Operation step independently. Corrected run `exp155-operation-explicit-target-serial-manual-boundaries-20260916T124918Z` passes 24/24. Backend session `bcb168fd-b5df-42ed-b416-b505a42e6e76` has eight raw steps and four reduced Operations with exact A→B success/failure, A→A alpha, B→B beta, and beta-before-alpha completion. The API shape remains experimental. | [active record](Experiments/EXP-143-199.md#exp-155--explicit-cross-scene-operation-targeting) |
| EXP-156 | 2026-09-16 | PASS · physical-device tooling | Hardware automation | Two preflights found only a disconnected local-network record. A third passed repeated wired inventories and an `arm64` build; the expected unsigned rejection exposed signing. The restricted-context zero-identity result was false: one of two login-keychain identities matches the installed device profile. A copied app passed strict/deep verification, clean install, and physical launch. | [active record](Experiments/EXP-143-199.md#exp-156--physical-ipad-automation-preflight) |
| EXP-157 | 2026-09-16 | PASS · physical Operations + backend; INCONCLUSIVE · simultaneous visibility | Operations/hardware | First signed `EXP-131` launch exposed a stale Home fixture before any Operation. With explicit per-scene Home boundaries, the physical retry passes 24/24 across two native scenes; backend contains eight raw steps and four exact reduced Operations with A→B, A→A, B→B ownership and beta-before-alpha completion. Both scenes were full-screen and A was background while B was active, so simultaneous on-screen visibility remains human-gated. | [active record](Experiments/EXP-143-199.md#exp-157--physical-inferred-operation-retry) |
| EXP-158 | 2026-09-16 | PASS · tests + mapper + backend | Actions/API prototype | The generalized iOS 27 `RUMViewTarget.current(in:)` routes one-shot actions to a requested scene while retaining independent inferred fallback. Run `exp158-sim-66f922ee-19a3-4941-b8ca-c518216e6b0d` passes 9/9: explicit A and B own their requested Home, while a source-A legacy action remains on representative B. Backend session `f67c75b2-e839-4701-a283-7e4355682b6a` confirms the same owners across 30 events. The probe passes 164/164, Objective-C smoke passes 8/8, and the full RUM suite has zero failures. Stable API and long-running actions remain open. | [active record](Experiments/EXP-143-199.md#exp-158--explicit-scene-targeted-one-shot-action) |
| EXP-159 | 2026-09-17 | PASS · tests + mapper + backend | Actions/API prototype | Targeted long-running action start/stop passes 15/15 in a bounded live-view batch, with exact backend owners, reverse completion, empty-slot isolation, and unchanged legacy fallback. The earlier background-interrupted attempt remains INCONCLUSIVE; sustained simultaneous-window use remains hardware-gated. | [active record](Experiments/EXP-143-199.md#exp-159--explicit-scene-targeted-long-running-actions) |
| EXP-160 | 2026-09-17 | MIXED · six baseline gates closed; P02/P03 fail | Early baselines | Ordinary automatic/manual/custom/NOP/26.5, dispatch and exact reentrancy pass; enabled handoff3 allocations/416bytes exceeds1/64 budget;220 retained scene entries. Legacy27 inconclusive;15 runtime unavailable. | [active record](Experiments/EXP-143-199.md#exp-160--early-compatibility-and-performance-baseline) |
| EXP-161 | 2026-09-17 | PASS · A01 | Acceptance workflow | Fully automated166tests,15/15 local,7actions/3views/0errors backend; two tooling-invalid attempts retained;24Python+3Node controls. | [active record](Experiments/EXP-143-199.md#exp-161--automated-acceptance-pipeline) |
| EXP-162 | 2026-09-17 | PASS · D01/D02 | Platform compatibility | Two failing full-target controls; watchOS RUM/macOS WebView Debug and Release pass; 70 Resource/action and 28 WebView iOS tests plus lint pass. | [active record](Experiments/EXP-143-199.md#exp-162--restore-watchos-resource-and-macos-webview-compilation) |
| EXP-163 | 2026-09-17 | PASS · D12; T02 restored | Existing-API compatibility | Three recipient metadata failures reproduced; 212 affected tests and strict source/test lint pass. Own overdue-stop attributes retained; peer metadata remains isolated. | [active record](Experiments/EXP-143-199.md#exp-163--preserve-overdue-action-stop-attributes-without-peer-leakage) |
| EXP-164 | 2026-09-17 | PASS · D09 | Controller thread compatibility | Two failing getter controls; 31 affected tests pass. Mounted fixture 19/19, zero background reads/MTC diagnostics versus control 5 reads/4 diagnostics. Tooling-invalid attempts retained. | [active record](Experiments/EXP-143-199.md#exp-164--preserve-controller-api-caller-thread-compatibility) |
| EXP-165 | PASS | D11: legacy container restored; 102 tests, 19/19 mounted bridge/Replay checks and four collector controls | [Record](Experiments/EXP-143-199.md#exp-165--preserve-legacy-nativewebview-replay-correlation) |
| EXP-166 | PASS | D04/P02: 282 tests; core-scoped consumers; full27/26.5 ABBA1 allocation/64 bytes with latency/reentrancy budgets preserved | [Record](Experiments/EXP-143-199.md#exp-166--isolate-ui-event-handoff-by-sdk-lifecycle-and-reduce-allocations) |
| EXP-167 | PASS | D05/D06: six failing controls, 198 tests/44 new cases, two native scenes 47/47 versus 20/47; old ownership and eligible peers preserved | [Record](Experiments/EXP-143-199.md#exp-167--preserve-navigation-ownership-across-session-restoration) |
| EXP-168 | PASS | D03/R02: 303 tests; 37/37 mounted checks on27/26.5; 25 leaked registrations reduced to zero, teardown restored; P03 registry budget remains open | [Record](Experiments/EXP-143-199.md#exp-168--release-keyed-swiftui-registrations-and-instrumentation) |
| EXP-169 | PASS | D07: four failing controls, 119 tests, mounted explicit/capability hosts29/29 versus19/29; automatic-before-input and immediate semantic owners | [Record](Experiments/EXP-143-199.md#exp-169--keep-automatic-tracking-until-semantic-input-is-ready) |

| EXP-170 | PASS | D08: three failing controls,314 tests and mounted51/51 versus39/51; fresh reconnect Resource/Log owners and delayed retained-host remount | [Record](Experiments/EXP-143-199.md#exp-170--accept-semantic-reconnects-only-after-a-live-attachment) |

| EXP-171 | PASS | R04: two failing no-body controls,318 tests, mounted57/57 versus43/57; first retained-reader callback owns latest input before body rebind | [Record](Experiments/EXP-143-199.md#exp-171--restore-retained-hosts-from-the-reader-without-body-reconstruction) |

| EXP-172 | PASS | P03:326 tests, three failing controls; Release ABBA27/26.5 zero retired entries/weak survivors within frozen heap limits; eight ordinary smoke runs and watchOS Release pass | [Record](Experiments/EXP-143-199.md#exp-172--retire-disconnected-scene-history-without-accepting-stale-callbacks) |
| EXP-173 | PASS | D10/R06 closed:337 tests, mounted77/77 versus55/77; accepted Binding and occurrence callbacks, rematerialization regression fixed; all four native attempts retained | [Record](Experiments/EXP-143-199.md#exp-173--commit-accepted-presentation-state-and-fence-occurrence-callbacks) |
| EXP-174 | PASS | R05 closed: three failing controls, nine new regressions and346 affected tests; monotonic synchronous generations, membership and exact two-host teardown | [Record](Experiments/EXP-143-199.md#exp-174--preserve-monotonic-reentrant-observer-delivery) |
| EXP-175 | PASS | Four failed controls repaired, seven new regressions and379 affected tests; completion/metrics stay on original owner without foreign action counts. Full T03 target/backend gate stays open | [Record](Experiments/EXP-143-199.md#exp-175--keep-resource-completion-on-its-owning-scope) |
| EXP-176 | PASS | T03 closed:397 affected/8 ObjC, iOS/watchOS Release;167 probe tests,22 local/77 signals and exact5 Resource/4 error/5 view backend owners across2 sessions, peer counters0/0; all failed attempts retained | [Record](Experiments/EXP-143-199.md#exp-176--accept-explicit-resource-starts-and-captured-completion-owners) |
| EXP-177 | PASS | T04 closed:376 SDK/8 ObjC, Release;168 probe,24/24 local/61 signals,1 callback and exact backend9 errors/3 views/2 actions with7/2 counts,0 Resources/crashes;67 Python/3 connector controls | [Record](Experiments/EXP-143-199.md#exp-177--target-current-view-errors-without-changing-resource-owners) |
| EXP-178 | SDK PASS; native PLANNED | T05 remains OPEN: signed1c6104cac passes419 SDK/8 ObjC/46 integration26.5, lint and iOS/watchOS Release;27 legacy host inconclusive;20-marker native/backend contract pending | [Record](Experiments/EXP-143-199.md#exp-178--target-view-attributes-and-removal) |

## Simulator-inconclusive and hardware-required evidence

[PLAN.md owns the executable physical-device and human-driven
queue](PLAN.md#physical-device-and-human-driven-queue). These compact locators
ensure every existing environment-bound experiment remains visible here.

| Priority | Experiments | Required capability |
| --- | --- | --- |
| P0 | `EXP-100` | Human SwiftUI edge-pop cancellation and completion |
| P0 | `EXP-081` | Human UIKit edge-pop cancel followed by completed pop |
| P0 | `EXP-086`, `EXP-103` | Stable simultaneously visible split navigation |
| P0 | `EXP-041`, `EXP-089`, `EXP-113` | B representative, visible-A work, exact B close without A disturbance |
| P0 | `EXP-114` | Real activation/focus handoff with foreground target and background peer |
| P0 | `EXP-118` | Semantic scene A coexisting with automatic scene B |
| P0 | `EXP-129` | Same manual key in A/B with reverse-order stops |
| P0 | `EXP-131` | Cross-scene Operations and distinct-key reverse completion |
| P0 | `EXP-136` | One A-created, B-joined shared Trace request |
| P0 | `EXP-146` lifetime follow-up | Actual semantic-host removal plus genuine scene disconnect/reconnect without A resurrection, duplicate stop, or B disturbance |
| P1 | `EXP-076`, `EXP-087` | Acknowledged regular/compact/regular adaptive resize |
| P1 | `EXP-042` | Concurrent two-window restoration |
| P1 | `EXP-001` | UIKit-hosted SwiftUI parity, required gate H16 |

`EXP-039` is not admitted release scope: its rejected candidate was never
constructed. F02 owns documented automatic/opaque limits; do not create another
reflection experiment without a named gate or concrete regression. The plan also
retains forward-looking hardware gates for genuine reconnect, per-scene
background/foreground, and the final iPhone Duo/iOS 27.1 release matrix.

## Detailed evidence routing

- [Active records: EXP-143-199](Experiments/EXP-143-199.md)
- [Frozen experiment history through EXP-142](Archive/EXPERIMENTS_THROUGH_EXP-142.md)
- [Archive integrity and lookup rules](Archive/README.md)
- [Rejected approaches and attempts not to repeat](REJECTED_APPROACHES.md)
- [Tooling and documentation workflow](TOOLING_RUNBOOK.md)

For `EXP-001` through `EXP-029`, the ledger locator uses a run/session token
because the frozen chronology has broad date headings. Later rows use the stable
experiment ID. One lookup here followed by one targeted search in the linked
record is sufficient; do not load the archive wholesale.
~~~~

## Moved 06

Earlier runbook experiment-specific appendices

Source: DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md. Original excerpt SHA-256: 46a7158de342acfd1b87cdd5b88843ac1e58528085bf69e90c44b440fa7351c6.

~~~~markdown
## EXP-159 operational discriminators

- A discovered test with `No result`/`notRun` invalidates current-build acceptance,
  even if every older test passes. EXP-159 initially returned164 passes with two
  new tests unexecuted; fresh derived data produced 166/166.
- Resolve live-view prerequisites before the action interval. Native background
  can correctly close a view/action between suspended driver steps. An API-only
  synchronous batch is valid only with both live views and unchanged exact
  completion oracle; it does not close sustained multi-window hardware gates.
- Preserve final names and stop-phase attributes, exact owner UUIDs, counts, and
  B-before-A ordering. Neither timeout nor a same-name early completion can pass.
- Current full-module CLI uses `-enableCodeCoverage NO` for the previously
  documented finalization issue; this is not a skipped test or a Release-build flag.
- Mixed OSLog/stdout lines can contain a valid probe JSON object away from the
  start of the line. Preserve raw logs and decode complete JSON objects at their
  prefix; never manufacture missing records. Check sequence continuity after
  terminal capture. EXP-159 recovered sequence 49 verbatim this way, yielding
  all sequences 1–94; the stdio-only original remains available.

## EXP-165 mounted WebView compatibility runner

`tools/multi-scene/webview-correlation/run.py --control COMMIT --candidate COMMIT
--output NEW.json` creates frozen isolated Core/RUM/WebView/Replay apps and uses
a fresh iOS 27 simulator discovery. It verifies clean install, executable/source
identity and fresh run IDs, then captures dummy-token telemetry on loopback only.
The actual WKWebView bridge waits for exact browser payload acknowledgement before
the next native ownership mutation. Acknowledgement is repeatable, not consumed.

Decode the SDK's `Content-Encoding: deflate` as zlib, as well as gzip. The first
collector attempt missed deflate and is preserved as INVALID; missing payloads
must not be reported as SDK failures. Four focused collector controls pass.
Acceptance requires all 19 checks plus a native Replay-enabled payload, a control
that specifically loses the legacy container, and a candidate that preserves it
without peer fallback. Never commit raw intake payloads; keep compact ownership
summaries and artifact hashes. See the fixture README for its exact one-window
boundary; T10 owns two-container/backend evidence.

## EXP-166 shared handoff acceptance

Use `tools/multi-scene/handoff-isolation/README.md` for the staged runner.
Freeze the explicit SDK directories and copied baseline fixture before building;
only adapt internal owner arguments/accessors. Keep original EXP-160 fixtures,
protocol and thresholds unchanged. Wait for every build/test/profile job to
finish before the complete 27/26.5 ABBA window. Diagnostic probes never close a
performance gate. Record actual calibrated count/requested bytes, full-context
nested/throwing checks, source/build identities and separate platform compiles.

A pure TaskLocal optimization changed the synchronous snapshot contract even
though isolation passed. Keep the discriminating entry-snapshot/child-refresh
control. Foreign context must not activate the legacy third-party callback;
assert that boundary separately from direct Resource ownership through completion.
The accepted runner reaches 1 allocation/64 bytes; never raise the frozen budget
or substitute retained heap for allocation churn. Closed D04/P02 does not close
retained-state, backend, minimum-runtime or physical-topology gates.


## EXP-167 native restoration acceptance

`tools/multi-scene/session-restoration/run.py` builds explicit pinned control and
candidate SDK copies, clean-installs both on a discovered iOS 27 iPad simulator,
requests a second native scene, and produces 47 named checks with source/build
identity and run-ID validation. It reuses baseline extraction helpers; it never
reads the main project or local xcconfig. The README defines six cases and exact
owner/inventory assertions. Controlled expiration times do not prove physical OS
lifecycle behavior or backend ownership.

Observe application readiness after scene activation, with a bounded retry:
the callback may precede UIApplication becoming active. The first attempt missed
this boundary and is retained as INVALID. The accepted repeat rebuilds both arms
and requires real topology before interpreting semantic failures. Read snapshots
before sending markers, and preserve exact new-session view inventories; a later
action can otherwise hide a missing restoration branch. Maximum-duration cases
must refresh activity before their deadline so they cannot pass as timeouts.


## EXP-168 mounted SwiftUI lifetime acceptance

`tools/multi-scene/swiftui-lifetime/run.py` runs frozen signed control/candidate
apps on discovered27/26.5 simulators, with fresh installations and run IDs.
Its37 checks require actual keyed registration and RUM destination before each
host removal, weak-object counts after bounded main-queue draining, and exact
restoration of three real method implementations after SDK release. The fixture
only reads method implementations; it does not replace them. Keep sources alive
past removal to prove their weak registration entries do not extend SDK lifetime.

Record availability as an oracle prerequisite. The first26.5 attempt incorrectly
required the27-only transition arbiter and remains INCONCLUSIVE; the revised
fixture requires the correct presence/absence before interpreting lifetime checks.
Do not substitute controller release or process RSS for registration/state and
instrumentation release. Mounted lifetime acceptance does not close P03's
separate disconnected-history budget or physical scene lifecycle gates.


## EXP-169 pending semantic authority

`tools/multi-scene/pending-authority/run.py` repeats the frozen explicit/capability
host comparison on a discovered iOS27 simulator. Require all29 named checks,
real native mount/authority registry, clean installation and new run IDs. Automatic
eligibility and mapper ownership must be checked before first semantic input;
the unchanged control can correctly own later semantic work while losing all
ordinary automatic work before it. Submit the immediate marker directly after
input, before waiting for another render or lifecycle callback. Record both
phases, exact occurrence IDs and duplicate/cancellation negatives.

The four unit controls also cover absent instrumentation and attachment with the
actual registry. Source selection is not authority. This acceptance does not
prove disconnected publication/reconnect (D08), reentrant fan-out (R05), registry
retirement (P03), or physical/backend/minimum-runtime gates. Local unsigned commits
remain eligible under the user's policy; outgoing history must be signed before
any separately authorized push.

## EXP-170 accepted reconnect publication

Definition is in EXP-143-199.md. Use actual handler rejection and separate inherited
traits from reader mounts; a posted lifecycle sequence is deterministic evidence
only. Capture immediate Resource/Log ownership at the accepted reader boundary,
then inspect it without submitting a repair navigation command. Freeze both arms,
prove clean installation and exact required-check inventory, and preserve invalid
attempts. Reuse source/build helpers with explicit SDK directory allowlists; never
read the protected project/configuration. Physical H09 remains separate.

For the D08 fixture, enable automatic SwiftUI instrumentation with a predicate
that returns nil so the real authority registry exists without synthetic automatic
destinations. Read scene snapshots after draining the queued commands, but submit
Resource/Log calls immediately after the reader boundary. Do not install an
artificial authoritative-nil UI handoff in an ordinary lifecycle callback. Clear
the retained reader's onMount before reconstruction and require SwiftUI's actual
update to rebind it; checking only the root value is insufficient. Allow only the
known ApplicationLaunch startup view in addition to the exact scene destinations.
Strict lint uses tools/lint/sources.swiftlint.yml and tests.swiftlint.yml, each
with an explicit changed-file list; a configuration-free run is not the repo gate.

EXP-170 accepted attempt3: run.py at tools/multi-scene/reconnect-acceptance,
control7826eabc1/candidate66d1ccb02,51 required checks; control39/51 versus
candidate51/51. The runtime inventory requires real mounted readers/registry and
callback rebinding, exact fresh view/session owners, three Home occurrences and
one unchanged logical peer. Package attempt1 and fixture attempt2 remain in the
durable result. Physical H09 cannot close from these posted lifecycle controls.

## EXP-171 retained reader boundary

The definition requires no body/source reconciliation between teardown and the
retained reader remount. Capture the actual reader callback before removal;
reinstall it immediately before readding the retained hosting controller, and
submit Resource/Log markers inside that callback after SDK delivery. Require the
callback to run before any subsequent render; missing callback interception is
inconclusive. Do not assign a new root value to repair the source before this
boundary. Unit controls must enforce the same no-rebind sequence independently.

EXP-171 accepted attempt1: control2da21c041/candidate4ba7179c6,57 required
checks; control43/57 versus candidate57/57. Both first mounted reader callbacks
run with zero source observers; the candidate reobserves and owns the immediately
submitted Resource/Log markers. The root value is never reassigned. SDK/fixture/
binary identities remain frozen. Results/EXP-171-retained-reader.json retains all
checks, exact owners,318 test selectors and test-summary hashes. R04 closes only
its bounded component review, leaving physical H08/H09 unchanged.

## EXP-172 retained scene state

Keep the BASELINES.md protocol prefix frozen. The isolated logical-cycle fixture
must declare an empty initial scene inventory, introduce20 warm-up plus100+100
unique lifetimes, and tear down every introduced scene. Count every scene-owning
collection, not only the old registry names. Preserve raw malloc-zone heap samples
separately from ownership counts. Use fresh Release27/26.5 processes in ABBA order;
P01/P02/P04 dispatch measurements are not being rerun. Verify stale callbacks cannot
recreate retired entries before treating zero counts as acceptance. Initial live
peer/late SDK initialization and main-thread inventory controls are required.


Use `tools/multi-scene/scene-retention/run.py` with explicit control/candidate
revisions and a new output path. It archives seven allowed SDK source paths,
uses unchanged baseline App/allocation helpers, and records the one empty-inventory
constructor adaptation. It performs watchOS Release compile, discovers27/26.5,
proves clean installation and executable/run/topology identity, executes complete
Release ABBA, then checks ordinary automatic/manual exact owners. The summary
retains all raw samples and failed setup attempts. Seven negative oracle tests
cover registry renaming, incomplete boundaries, weak survivors and frozen limits.
EXP-172's first native attempt passed16 launches; keep its accepted result pinned.
Do not use a synchronous global queue call to prove background initialization:
GCD may execute it on the caller. The unit fixture uses async dispatch and a
bounded semaphore to hold the main seed until the handler is released.


## EXP-173 accepted presentation boundaries

Define control and closure separately for D10 and R06. An internal behavior-neutral
Binding-factory relocation can expose the actual production closure to tests;
record failing controls before changing its order. Native evidence must mount
real sheet/cover content and deliver actual dismissal callbacks. Submit markers
at setter-return/callback boundaries before awaiting another frame, then inspect
queued events after drain. Distinguish a rejected proposal, accepted descriptor,
customer item ID and occurrence UUID. Preserve old callback closures for stale
same-ID and A→B→A controls. Opaque setter internals are not an accepted-state
observation source; exact interior work uses the existing source contract.


The EXP-173 native harness uses observation-only Debug hooks in isolated copies
of both SDK arms. Record archived source identity separately from the compiled
hooked identity. The hook exposes existing Binding and boundary callback values;
it must not mutate application or SDK state. Explicitly type the captured generic
Binding, and capture initializer function fields through local constants instead
of mutating `self`. The first invalid build is preserved. No hook enters production
source or the public API.


EXP-173 acceptance is durable in `Results/EXP-173-presentation-acceptance.json`.
Use `tools/multi-scene/presentation-acceptance/run.py` and its README for the
repeatable frozen control/candidate workflow. Attempt1 failed hook compilation;
attempts2/3 exposed real candidate occurrence churn, and attempt4 passes77/77
versus55/77. Require stability before injecting an old callback: otherwise native
content rematerialization can be misdiagnosed as a stale-callback failure. A content
onDisappear alone is not accepted dismissal; inspect the current Binding.
The eight oracle controls include before-render and restored-run rejection.
Archive and observation-hook compiled identities remain separate; logical peer
and injected callbacks cannot close physical scene-ordering gates.

## EXP-174 observer reentrancy controls

Use whichever observer receives the outer snapshot first to trigger the nested
commit, so the control is deterministic without depending on Dictionary order.
Record per-observer generation sequences and assert the latest at nested return.
Removal must affect pending delivery and newly added observers receive only the
current snapshot. Initial publication needs the same oracle as commit. Run actual
SDK source/observed-adapter/handler objects in XCTest; no physical/backend claim
is appropriate for this synchronous in-memory gate. Keep the protected project
and local configuration untouched and retain all failed controls before repair.

EXP-174 is accepted at signed `368c62a72`: three failed controls and346 passing
affected tests, with nine new regressions. The durable observer-delivery JSON
records source identity and exact selectors. Its source-review environment is
intentional; a new simulator app or backend run would not improve this synchronous
fan-out oracle. Do not rerun it merely to resume. T03 needs its own captured-start
and exact completion/backend discriminator before implementation.

## EXP-175 Resource completion discriminator

Keep the new session's continuous action alive while the old Resource completes.
An immediately completed custom action cannot expose leaked completion counters.
Assert emitted action Resource/error counts plus exact old Resource/error view and
session IDs, not only the Resource event's correct owner. Include scene-targeted
completion after navigation, metrics, duplicate completion and clock expiration.
This regression slice does not close T03's explicit-start/backend gate.

EXP-175 is accepted at signed `aefe337b6`: four failing controls and379 affected
tests, seven of them new. The result retains the6/7 fixture attempt whose exact
100ms expectation differed by24ns at a wall-clock origin. Use a fixed reference-
date origin for this discriminator; do not widen the assertion enough to accept
150ms activity extension. No native/backend run is claimed. Continue with T03's
explicit-start and captured-owner fixture, keeping the new live-action counters.

## EXP-176 Resource acceptance boundary

Extend the existing A01 runner with an explicitly selected, frozen Resource
contract; retain the accepted action scenario. Verify request release barriers,
original mapper occurrence/session, exact Resource/error IDs and peer-action
counters. Expected network errors are distinct from zero-crash acceptance.
Backend inventories use complete session queries so restored run IDs cannot hide.
Keep the mechanical target-plumbing control separate from the actual SDK routing
repair. Reuse the clean-install, source/build, bridge nonce and failed-attempt
rules; do not copy a previous run/session identifier.

EXP-176 SDK preparation is signed `5e41d0b11`. The397 affected checks are396
passing cases in the broad run plus the corrected final case; preserve both
artifacts and do not describe them as one397/397 run.8 Objective-C API checks and
Release pass. The SDK test host is legacy and supplies no UIWindowScene; actual
Swift/Objective-C target overload execution belongs in the native acceptance app.
A URLSession failure may include response headers: require one error and no
success event for that start, with the original owner/status. Preserve the failed
representative-restoration controls and response-plus-error attempt. `devicectl`
now lists simulated devices too; filter `hardwareProperties.reality == physical`
before reporting hardware availability. Physical iPad/iPhone remain unavailable.

The EXP-176 runner now accepts the named Resource scenario through an optional
`scenario` argument to `connector_driver.js`; omission retains the action contract.
Expected backend counts travel in nonce-bound requests. Resource/error queries
cover both entire sessions; the peer action has its explicit phase query. Expected
network errors must preserve status/URL/owner and remain separate from zero-crash
checks. Full fixture contracts and runner sources are frozen before build/install.
50 Python controls pass;167 probe tests passed after a `viewPath` fixture correction.
The acceptance invocation performs the final fresh build after fixture completion.

Decode mapper context with `AttributeValue.dd.decode`, including AnyEncodable from
Objective-C APIs. A direct Swift `as? String` can discard labels even when backend
serialization is correct. Preserve the local failure and independent backend
diagnostic; do not substitute backend labels into a failed local oracle.

EXP-176 is accepted at signed fixture `797ab135c` (SDK `5e41d0b11`), run
`exp176-20260917T164857Z-a72e79966b23`:167 tests,22/22 local/77 signals and
backend5 Resources/4 expected errors/5 complete views across2 sessions, fresh
peer counters0/0 and0 crashes.53 Python and3 connector controls pass. All four
native failures are retained. For serial topology, capture A before it backgrounds;
wait for actual retirement, navigate foreground B and renew B before release.
Do not retry manual starts on background A or substitute artificial foreground
notifications. Mapper-confirmed navigation/new-session barriers precede release.
The acceptance script performs fresh source/build/install/auth checks every run;
no accepted scenario is rerun merely for resumption. T04 is next.

### EXP-177 acceptance preparation

The defined T04 slice extends the existing acceptance runner with a named error
contract:8 current-view errors (6 A/2 B),1 captured-A Resource error,2 named actions,
no Resource event and complete session view/error inventories. Freeze payload,
action counts and exactly-once callback barriers before a native run. Retain the
EXP-176 lessons: decode AnyEncodable; consume readiness once; require current A/B
before synchronous targets; never wait until A has ended and claim a live-A target.
Backend and mapper must agree on exact owners, not just counts.

EXP-177 preparation: signed SDK `1e9c4788d`;376 SDK/8 ObjC/168 probe checks,
iOS/watchOS Release and67 Python/3 connector controls pass. Named scenario is
`errors.explicit-target.current-view-cross-scene-serial`; runner selects T04 and
a fresh exp177 run ID. Inventory is9 errors,2 named actions,3 session views,
0 Resources/crashes; callback and payload guards are strict. Initial native
private-property compile error and a no-op test mutation are preserved. Run
repository lint with explicit source/test configs; default SwiftLint is not valid.

EXP-177 first native attempt is accepted: `exp177-20260917T173444Z-28b735bf7f34`,
frozen signed42f2d3883, sourcecb88001a47be2b77, binary88bc5ad533120ac7.
168 probe tests,24 local expectations/61 signals,1 callback, exact backend
9 errors/3 views/2 actions,0 Resources/crashes. All protected-path postconditions
pass. Do not repeat this run merely to resume; reuse its discriminators for T05.

### EXP-178 preparation

T05 is defined before implementation. Freeze10 A/B attribute checkpoints (20 error
markers),3 session views and0 Resources/crashes. Both Swift and Objective-C single/
batch add/remove execute. Prove peer isolation, exact key absence and existing
global/view/event precedence with independent backend synthetic field projections.
Retain T04's accepted target marker API, readiness, clean-install and identity guards.
~~~~

## Moved 07

Superseded documentation update workflow

Source: DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md. Original excerpt SHA-256: d76e9a1fa19b7e12a21486648252a1eb30f31179c8a5f1fef8a4574a4100bd12.

~~~~markdown
## Documentation reading and update workflow

Use progressive disclosure; do not load the frozen history wholesale.

1. To resume work, read the [canonical overview](../MULTI_SCENE_SUPPORT.md) and
   the current execution slice in [PLAN.md](PLAN.md).
2. To check current support, read [ASSESSMENT.md](ASSESSMENT.md).
3. To locate evidence, search [EXPERIMENTS.md](EXPERIMENTS.md), then open only
   the linked detailed record or targeted archive range.
4. Before designing an experiment, search the relevant section of
   [REJECTED_APPROACHES.md](REJECTED_APPROACHES.md).
5. To record an experiment, append its full record to the active numbered shard,
   add one compact index row, and update only the affected assessment rows and
   plan items. Keep attempts with different validity or outcomes distinguishable.
6. When a shard's numeric range is full, freeze it and create the next bounded
   range without renumbering any experiment.

The frozen `Archive/` snapshots are integrity records. Do not edit them to repair
relative links; use [their manifest](Archive/README.md) and targeted search.

~~~~

## Moved 08

Historical procedure example

Source: DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md. Original excerpt SHA-256: 71d57e48a9b3976a17635c6e375919865bce4cac21441f435dcc048925741d8c.

~~~~markdown
On the 2026-09-15 test host, `/Applications/Xcode.app` was Xcode 26.6
(`17F113`), while `/Applications/Xcode_27.app` was Xcode 27.0 (`27A266a`) and
`xcode-select` selected the latter. A Release build invoked explicitly through the
26.6 installation completed but warned that the iOS 27 deployment target was
unsupported. Treat that result as invalid evidence. The accepted build used
`/Applications/Xcode_27.app/Contents/Developer/usr/bin/xcodebuild` and the iOS
27.0 simulator SDK.

~~~~

## Moved 09

Historical procedure example

Source: DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md. Original excerpt SHA-256: 9ff7f7f6533f29e5deefbcf56d4c07a4f3fb4f23b8438a7f3f31672df638cc69.

~~~~markdown
EXP-162's [durable manifest](Results/EXP-162-platform-compatibility.json) records
this watchOS RUM/macOS WebView check, with focused iOS regressions. The isolated
packages exclude the protected project and local xcconfig. The repository's
SPM build helper renames the main workspace, so this experiment did not invoke
or modify it. Compile evidence does not substitute for an unavailable runtime.

~~~~

## Moved 10

Historical procedure example

Source: DatadogRUM/MultiSceneSupport/TOOLING_RUNBOOK.md. Original excerpt SHA-256: 90dc8b80e347cc5ddd03cde2702b390a686f24d2c6a0b02852ecfbcac60f8375.

~~~~markdown
`EXP-156` records the concrete boundary and correction: the wired preflight and
`arm64` build pass; the unsigned probe is rejected; a restricted identity query
incorrectly reports zero; the user-context query finds two valid identities;
one matches the installed device profile; and a copied app passes strict/deep
verification, clean install, and launch. None of its build, signing, or install
evidence is RUM evidence.

~~~~

## Moved 11

Earlier review progress preface and repair order

Source: DatadogRUM/MultiSceneSupport/PRODUCTION_SAFETY_REVIEW.md. Original excerpt SHA-256: e8edb58486ecf399a01b1fd0b9fe78f6cece9f3e9b47382433bb8f32a29f2d91.

~~~~markdown
**Production safety review of multi-scene SDK instrumentation**

Updated 2026-09-17 during plan execution. **Release remains on hold: all 12
review findings are closed, 0 remain open.** The finite checklist has 32/66
release gates closed. [PLAN.md](PLAN.md) owns the release contract and
[REVIEW_TRIAGE.md](REVIEW_TRIAGE.md) owns assessed repair order and evidence limits.
Review IDs R01–R12 below map to repair gates D01–D12, not PLAN's responsibility
review gates R01–R06.

| Finding / gate | Current disposition | Evidence or next decisive check |
| --- | --- | --- |
| R01 / D01 | CLOSED | EXP-162, signed `e420528f7`: full watchOS RUM Debug/Release builds and 70 iOS Resource/action tests |
| R02 / D02 | CLOSED | EXP-162, signed `af8864528`: full macOS WebView Debug/Release builds and 28 iOS bridge tests |
| R03 / D03 | CLOSED | EXP-168, signed `7b77f60eb`: 303 tests; mounted 27/26.5 checks 37/37 each, zero weak survivors and three method implementations restored after SDK stop |
| R04 / D04 | CLOSED | EXP-166, signed `5eb3c1aac`: 282 affected tests, core/task/lifetime and all-consumer isolation; allocation1/64 and latency/reentrancy budgets pass on27/26.5 |
| R05 / D05 | CLOSED | EXP-167, signed `0aaafa7bd`: failing source-less start/identity-stop controls, 198 tests and two-native-scene 47/47 runtime acceptance |
| R06 / D06 | CLOSED | EXP-167: controlled timeout/max-duration lifecycle boundaries, fresh peer IDs and exact action/Resource owners; background and legacy controls |
| R07 / D07 | CLOSED | EXP-169, local unsigned `a9aaf25a7`: four failing controls, 119 tests and mounted29/29; automatic eligibility before input and exact immediate semantic owners |
| R08 / D08 | CLOSED | EXP-170, signed `66d1ccb02`: three failing controls,314 affected tests and mounted51/51 versus39/51; fresh reconnect Resource/Log owners, peer continuity and delayed remount. H09 still requires genuine OS ordering. |
| R09 / D09 | CLOSED | EXP-164 at local `a9abc092b`: 31 tests and actual mounted fixture 19/19; zero background reads/MTC diagnostics versus control 5 reads/4 diagnostics |
| R10 / D10 | CLOSED | EXP-173, signed `7619eb8a2`:337 tests; actual mounted Bindings/sheet/cover77/77 versus55/77, exact Resource/Log owners and native dismissal; all failed attempts preserved |
| R11 / D11 | CLOSED | EXP-165, signed `9a1ee83a5`: 102 tests, 19/19 mounted WebView/Replay checks; legacy association restored, peers excluded |
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
window concurrency. EXP-165 closes D11 with mounted WebView/Replay correlation;
EXP-166 closes D04/P02 with [ownership](Results/EXP-166-handoff-isolation.json)
and [paired performance](Results/EXP-166-handoff-performance.json) evidence;
EXP-167 closes D05/D06 with [restoration evidence](Results/EXP-167-session-restoration.json):
198 tests and 47/47 checks in two native simulator scenes. EXP-168 closes D03
with [mounted lifetime evidence](Results/EXP-168-swiftui-lifetime.json) on27/26.5.
EXP-169 closes D07 with [pending-authority evidence](Results/EXP-169-pending-authority.json).
EXP-170 closes D08 with [reconnect evidence](Results/EXP-170-reconnect-acceptance.json)
and EXP-171 closes bounded R04 with [retained-reader evidence](Results/EXP-171-retained-reader.json):
318 tests and mounted57/57 versus43/57 at the first callback before any body rebind.
EXP-172 closes the additional P03 registry-growth risk with
[retention evidence](Results/EXP-172-scene-retention.json):326 tests, complete
Release ABBA on27/26.5, zero retired entries/weak survivors and heap increases
within the original limits. The original220-entry control still fails. Ordinary
automatic/manual and watchOS Release checks pass. EXP-173 closes D10 and the
additional same-ID occurrence risk with [presentation evidence](Results/EXP-173-presentation-acceptance.json):
337 tests and mounted77/77. Its first native candidate exposed content
rematerialization before injected old callbacks; the accepted fix preserves that
occurrence while its Binding remains accepted. All12 original findings are now
closed. EXP-174 also closes the bounded R05 observer reentrancy review with
three deterministic failures repaired and346 tests; [evidence](Results/EXP-174-observer-delivery.json).
EXP-175 repairs the separately listed pre-existing late Resource/action count
defect at signed `aefe337b6`: four failing controls and379 affected tests;
[evidence](Results/EXP-175-resource-completion.json). Physical and final release gates remain. EXP-176 SDK preparation also repairs two reproduced T03 risks: restoration
selected the first branch instead of the previous representative, and URLSession
success removed a Resource before a response-plus-error completion. Signed
`5e41d0b11` passes397 affected checks across396+1,8 Objective-C checks and Release;
[native/backend acceptance closes T03](Results/EXP-176-resource-start.json):
signed fixture `797ab135c` passes167 tests,22 local expectations/77 signals and
exact5 Resource/4 error/5 view inventories across2 sessions, with fresh peer counts0/0
and0 crashes. Actual serial A background and B session renewal are covered;
simultaneous/physical hardware gates remain. watchOS Release also passes after
these shared Resource changes. Keep this review as the disposition and historical evidence record; it
is not release certification.

EXP-177 is admitted for T04. Its audit retains the accepted T03 Resource-error
contract and adds explicit current-view error ownership and completion controls.
No-recipient/unsampled callback losses are reproduced and repaired at signed SDK
`1e9c4788d`:376 affected/11 new tests, delayed-write and reentrancy checks,8 ObjC
and iOS/watchOS Release pass. [T04 evidence](Results/EXP-177-current-view-errors.json)
now closes T04: frozen42f2d3883 passes168 probe tests,24/24 local/61 signals,
one callback and exact backend9 errors/3 views/2 actions with7/2 error counts,
0 Resources/crashes. All12 original dispositions remain closed. Release remains
held for the remaining finite gates; T05 view attributes/removal is next.

EXP-178 is admitted for T05 attribute isolation and removal. Its bounded SDK and
native/backend contract preserves accepted Resource/error ownership and global
attribute precedence. All original review dispositions remain unchanged.

**Safer implementation direction and repair order**

1. **Restore compatibility first:** fix R01/R02, then R09/R11/R12. Add the missing supported-platform builds and focused legacy regressions. These changes can be small and reviewed independently.
2. **Give execution context an owner:** address R04 with one internal core/generation-aware handoff contract shared by Logs, Trace, RUM resources, and network instrumentation. Preserve the existing distinction between absent context and a known scene with no valid view.
3. **Resolve routing before changing state:** fix R05/R06 with a single internal resolution/restoration policy. Reusing an unresolved process representative after mutating the tree is intrinsically fragile. Keep resource completion tied to operation ownership, not a newly chosen representative.
4. **Make SwiftUI lifetime and authority explicit:** fix R03/R07/R08 with cancellable registrations, disconnected-scene epochs, and authority acquired only after an accepted destination can be published. Use transient detach, suspended scene, and final owner destruction as distinct states. Remove bound-modifier callbacks rather than relying solely on disappearance cleanup.
5. **Unify accepted-state handling:** fix R10 and presentation occurrence identity. Path, presentation, and router adapters should all feed accepted transitions to the same small state machine. After behavior is covered, split the 6,613-line modifier file by responsibility: attachment, registration lifetime, authority, transition state, and public adapters. Splitting alone will not fix the ownership problems; avoid a broad rewrite before the regression cases exist.

**Validation needed to close this review**

Turn the reproductions into failing regression tests before changing behavior, then run the relevant RUM, Internal/network, Logs, Trace, WebView, and Objective-C suites. Add compile coverage for watchOS, macOS, tvOS, visionOS, and the repository's supported iOS/toolchain compatibility paths. Newer semantic APIs must remain availability-gated while iOS 15+ legacy behavior stays valid.

Use a mounted SwiftUI host for retain/release, rejected presentation writes, delayed detach/remount, stale trait after disconnect, and same-ID presentation transitions. Exercise at least two live scenes with session stop/expiration and asynchronous completion. Capture actual emitted ownership and action/resource counts. Run Main Thread Checker for the existing controller APIs and memory growth checks over repeated navigation/window creation; retain the planned physical iPad/Duo and release-performance gates.

~~~~

## Moved 12

Original triage chronology and repair ordering

Source: DatadogRUM/MultiSceneSupport/REVIEW_TRIAGE.md. Original excerpt SHA-256: 24770c50ea2b1123d8c66e89447365b08fd66847f9c4d153e514823ed58b4edd.

~~~~markdown
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
and mounted29/29 acceptance. EXP-170 closes D08; EXP-171 closes bounded R04,
and EXP-172 closes P03 registry retention under its frozen budget. EXP-173 closes
D10/R06 with337 tests and mounted77/77 at signed `7619eb8a2`; all12 original
findings now have repair evidence. EXP-174 closes bounded R05 observer fan-out
with346 tests at signed `368c62a72`. T03 Resource ownership is next. Existing
accepted experiment slices remain valid within their recorded boundaries.

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
   EXP-169/170/171. P03 registry retirement passes EXP-172. Execute defined
   EXP-173 closes D10/R06 accepted presentations; EXP-174 closes R05 observer
   fan-out with deterministic nested commit/remove/add regressions. Each fix is a small
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
~~~~

## Moved 13

Superseded component-review framing

Source: DatadogRUM/MultiSceneSupport/COMPONENT_REVIEW.md. Original excerpt SHA-256: 27a08aaa5a60dadc87eb4fb2572ddbfc1a8ea8abf127999005185de9940e6e55.

~~~~markdown
# Incremental multi-scene component review

Original review 2026-09-17 against `af63657f08dbecb66e7c3ae97ed53fc8f7b065b9`.
R02 was reviewed again at signed `7b77f60eb` during EXP-168, and R04 at signed
`66d1ccb02`/`4ba7179c6` during EXP-170/171. R06 was reviewed again at signed
`7619eb8a2` during EXP-173, and R05 at signed `368c62a72` during EXP-174. Original line ranges
below refer to the original review; current symbol names identify the boundaries.
The 6,613-line `SwiftUIViewModifier.swift` was reviewed by responsibility before
further API expansion. This is a source review with existing regression evidence,
not final independent release sign-off or a new device run. Deferred extraction
remains in [its separate plan](DEFERRED_SINGLE_SCENE_EXTRACTION.md).

The original review consulted `PRODUCTION_SAFETY_REVIEW.md` without editing it.
That document now has a tracked live disposition table at the user’s request.
Its historical reproductions are attributed to that review;
this pass independently inspected the SwiftUI source paths below. D01–D12 in the
release register preserve its finite repair/triage obligations. None closes merely
because a report exists. No production source changed during this review.

~~~~
