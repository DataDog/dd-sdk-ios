# RUM multi-scene support

This is the canonical entry point for concurrent `UIWindowScene` support in
Datadog RUM. It records the current contract, support status, decisions, and exact
resume point. Detailed evidence and chronology are split by ownership so future
work can start here without reading the complete experiment history.
It remains separate from `RUM_FEATURE.md` until the behavior is implemented,
validated, and ready to become a supported contract.

Last updated: 2026-09-13

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
signal-driven stack, split, UIKit-transition, and scene-lifecycle scenarios now
pass 43/43 tests.
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
Native gesture synthesis remains unavailable and is kept separate from this
deterministic programmatic proof.
Detailed conclusions live in [ASSESSMENT.md](MultiSceneSupport/ASSESSMENT.md);
exact runs and rejected paths live in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

| Surface | Current branch status | Remaining release condition |
| --- | --- | --- |
| UIKit views and navigation | Independent stacks, push/pop, modal, duplicate names, and teardown pass experimentally. On iOS 27 in declared multi-scene apps, regular split Primary/supplementary columns are now structural rather than RUM views. Deterministic cancel keeps S2 and finish creates fresh S1; both have exact backend action/Resource ownership | Cover the application-subclassed container and startup-host fallback, then prove simultaneous visibility, adaptive/lifecycle/restoration, live normal-app compatibility, and iPhone Duo behavior |
| Explicit/semantic SwiftUI tracking | Experimental iOS 27 early-start, retained-return, modal, repeated push/pop, crash-safe teardown, restoration, synthetic reconnect, and customer-state-preserving keyed-occurrence controls pass; single- and two-window split replacement plus a retained split return preserve customer state and exact markers | Turn the debug occurrence input/source into the reviewed container-level path/router integration, prove a recognized native interactive gesture, then cover adaptive navigation, stable simultaneous visibility, genuine reconnect, and concurrent restoration |
| Automatic native SwiftUI | Transparent discovery remains semantically late; route-owned controls prove initial creation, abort, different- and same-type stack/split replacement, and retained Home without resetting customer state, but only through an internal debug integration; automatic split has no semantic selection views | Preserve automatic tracking as the zero-code default and its scene isolation, make the optional semantic integration authoritative without duplicates in its target, and validate automatic-only compatibility outside it |
| Actions | Source-bearing UIKit/SwiftUI taps emit once on their scene; exact-view actions refresh the process representative; public manual errors, view mutations, and internal view work consume exact handoff view/scene when present; source-less work retains last-interacted fallback | Repeat exact precedence with simultaneously visible A/B and a different representative; finish UIKit deceleration and targeted downstream runtime rows |
| Resources and traces | Trustworthy start provenance is frozen; manual Resource completions remain with their captured owner; automatic URLSession completion and OpenTelemetry spans now use the same scene-handoff model | Finish the bounded causal matrix, simultaneous-window/reverse-completion proof, normal-handler compatibility, and overhead measurement |
| Operations | Internal per-step cross-window routing and exact identity pass focused tests | Public target API review and live A-to-B/duplicate-start backend runs |
| Lifecycle and sessions | Independent close, rollover, fresh/retained-reader remount, and cancellation rearming are covered; exact A-to-B open and B close are now signal-driven, and A continues on its original Home occurrence after B disconnects; hidden detached readers retain only their last concrete scene proof, which disconnect clears before requiring a new mount | Exact activation, stable simultaneous-visible peer continuity, genuine OS disconnect/reconnect, live background/foreground, and concurrent restoration |
| Other signals | Focused ownership exists for logs, mirrored errors, WebView, vitals, fatal context, and profiling identity | Targeted two-window runtime proof and explicit process-wide limitations |
| Session Replay | Coexists in tested two-window runs without an SDK crash | No scene-correct replay work is required here |
| Normal applications | DatadogRUM 1,153/1,153, DatadogTrace 151/151, repository lint, and both probes build | Live single-scene and custom-handler behavior plus `sendEvent` overhead/reentrancy |

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
14. Resource and Trace work is limited to preserving trustworthy provenance and a
   shared frozen owner. The SDK does not guess after causality is lost and does
   not defend developer-written handlers that rewrite a request across automatic
   capture or first-party header-injection boundaries.
15. Operations use exact application-wide `(name, operationKey)` identity; scenes
   never namespace it. Every step resolves its view independently. A last-proven
   snapshot is a fallback, not permanent ownership by the start scene.
16. Starting the same Operation identity twice tracks only the latest start in
    the client. A later success or failure ends only that instance; the earlier
    backend operation remains open until its four-hour timeout. The SDK emits no
    synthetic end. Customers must use a unique key for every concurrent instance.
17. The Operation view-target escape hatch requires normal Swift, Objective-C,
    protocol-compatibility, and RFC review. Existing APIs retain inferred behavior,
    and no internal RUM view UUID becomes public.
18. Delivery priority is view occurrence/lifecycle and navigation; scene-aware
    manual views; downstream ownership; normal-app compatibility; then Session
    Replay crash safety. Multi-pane modeling and Execution Context serialization
    remain follow-up work.

The complete Operation contract, proposed Swift and Objective-C escape hatch,
customer workflow, and required tests live only in
[OPERATIONS.md](MultiSceneSupport/OPERATIONS.md).

## Resume here

### Checkpoint

The branch is `valpertui/multiple-windows-scenes`. The latest production SDK
checkpoint is `f4c8669c0` (`Treat regular split primaries as structural`). The
latest harness checkpoint is `45e5999e4` (`Coordinate probe scene lifecycle
explicitly`), following `df0322619` and documentation checkpoint `4f1bf4d55`.
All are unsigned local development commits and must not be pushed. The
chronological checkpoint table in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md) is authoritative.

`EXP-090` through `EXP-105` establish the debug SwiftUI occurrence mechanics,
including abort, replacement, retained return, state preservation, and remount.
`EXP-106` through `EXP-113` make stack, split, UIKit transition, and exact
open/close results signal-driven, locally self-validating, and backend-confirmed.
Native gesture, activation, adaptive topology, and genuine lifecycle rows remain
separate. The complete
chronology and every failed attempt live in [EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

### Exact next work

The deterministic harness is complete through `EXP-113`; [PLAN.md](MultiSceneSupport/PLAN.md)
owns the finished phases and full release matrix. Continue in this order:

1. Extend exact scene execution from the now-passing open/close slice to
   activation, foreground/background lifecycle acknowledgements, and stable
   simultaneous-visible peer continuity.
2. Prepare RFC/API review for the optional container-level SwiftUI semantic
   integration. It must consume a customer path/router and centralized resolver,
   coexist with automatic tracking, preserve customer state, and suppress
   duplicate automatic views only within its target container.
3. Prepare the scene-aware manual view start/stop API and Objective-C companion.
   The same manual key must coexist in A and B, and stopping A must not stop B.
4. Route recognized native gestures, adaptive resize, and stable simultaneous A/B
   topology through the real-device/human queue; ignored simulator input is not
   evidence.
5. Run genuine disconnect/reconnect, per-scene background/foreground, and
   concurrent restoration.
6. Complete Operations public-target API review and live A-to-B/duplicate-start
   validation. Keep application-wide `(name, operationKey)` identity.
7. Finish the bounded Resource/Trace and downstream-signal runtime rows, then prove
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
- Operations resolve every step independently. Trustworthy new context replaces
  the last-proven snapshot; the snapshot and then process representative are
  fallbacks. Identity is the exact application-wide `(name, operationKey)` tuple.
- Profiling uses the same typed Operation identity and distinguishes omitted from
  empty keys.
- Session Replay is required only to coexist without an SDK crash.
- The standalone probe now resolves 35 named scenarios from command-line input,
  preserves exact known legacy environment profiles, and fails closed before SDK
  initialization. It records ordered versioned JSONL signals, keeps call-site
  source separate from mapper-observed RUM ownership, derives view start/stop from
  snapshots, and evaluates ordered/negative expectations using only `PASS`,
  `FAIL`, `SKIPPED`, and `INCONCLUSIVE`. Its observable driver waits for exact
  scene, path/selection, destination, and RUM-occurrence signals. Home return,
  abort, same-/different-type replacement, split replacement, and retained split
  return plus deterministic UIKit cancel/finish and exact scene open/close pass
  43/43 tests and clean live runs with one final verdict per run. The automatic SwiftUI split control
  produces the intended semantic `FAIL`.
  This improves evidence quality but does not change the RUM support verdict.
- UIKit split scenario manifests forbid Primary as a RUM view. On iOS 27 in a
  declared multi-scene app, the shipping handler now ignores regular-width
  Primary/supplementary columns while retaining their probe lifecycle as
  structural diagnostic evidence. Cancellation keeps S2's UUID and completion
  creates a fresh returned S1 UUID. The startup SwiftUI hosting fallback and
  application-subclassed split-container case remain separate gaps.

### Validation snapshot

As of 2026-09-13:

- Complete suites pass: RUM 1,153/1,153, Internal 477/477, Logs 95/95,
  Trace 151/151, WebView 31/31, and Profiling 233/233.
- Focused retained-route, occurrence-isolation, transition-arbiter, Operations,
  and OpenTelemetry ownership regressions pass. Native SwiftUI gestures remain
  unproven because `EXP-100` produced no navigation signal.
- The named runner validates fail-closed startup (`EXP-106`), and its recorder,
  oracle, scene registry, and observable driver pass 43/43. Clean runs prove
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
- Both probes build through Xcode 27; package build, recorded repository lint, and
  focused changed-source lint pass at their stated checkpoints.

These are regression and implementation checks, not substitutes for the missing
runtime rows. Detailed run evidence remains in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

### Blockers and workspace safety

Public SwiftUI and Operation API work requires normal RFC/API review. The
configured signing agent remains unavailable, so the user approved unsigned
development-cycle checkpoints with the explicit restriction that they must not
be pushed. The experiment history preserves the signing failure and exact commit
boundaries.
The iOS 27 integration-runner half-and-half layout repeatedly respawned
`backboardd`, although the standalone native `WindowGroup` probe opens two windows.
The current iPad simulator also rejects `devicectl appResize` because it lacks
Resizable App Management; adaptive width proof needs a capable destination.
The current Xcode device-interaction request returns `Skill not found`, so native
gesture synthesis and visual interaction claims remain unavailable. This no
longer blocks structured programmatic navigation: the signal-driven driver uses
exact scene controls and observable acknowledgements. It does not turn those
programmatic runs into native-gesture evidence.
Ignored native edge drags, fullscreen-only peer-window layouts, partial scene
restoration, and unsupported resize are tracked in the dedicated
[real-device and human-driven rerun queue](MultiSceneSupport/EXPERIMENTS.md#real-device-and-human-driven-rerun-queue).
Those rows require observable path/coordinator/lifecycle evidence, not more
unverified simulator touches.

Do not stage, commit, revert, or expose
`Datadog/Datadog.xcodeproj/project.pbxproj` or
`xcconfigs/Datadog.local.xcconfig`. Both predate this work and the latter contains
local credentials. Use exact path lists for every commit.

Rejected experiments and do-not-repeat guidance are authoritative in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md#attempts-not-to-repeat).

## Open API-review questions

Product behavior is settled for this project. API review still needs to choose:

- the concrete container-level SwiftUI modifier, path abstraction, root
  descriptor, route-resolver shape, and iOS 27 availability surface;
- the authority/deduplication boundary between that semantic integration,
  automatic discovery, and exceptional manual views;
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
