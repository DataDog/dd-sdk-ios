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

The branch is not ready for a support claim because transparent native SwiftUI
view creation remains a P0 gap. In a standalone iOS 27 `WindowGroup` probe,
scene-B `.onAppear` and immediate `.task` work inherited scene A's last view before
scene B's first hosting-controller view existed (`EXP-028`). LLDB then showed that
Home and Detail semantic callbacks precede every usable public controller
appearance boundary, while the apparent iOS 27 reflection replacement reports a
registered destination rather than the visible screen (`EXP-029`). Another
controller swizzle, a navigation-title heuristic, or that reflection path is not
a valid fix.

An iOS 27-only candidate fixes the same early-work failure for explicit
`.trackRUMView` instrumentation in the exercised matrix. Three clean A/B runs
preserved all 72 lifecycle action/resource markers on exact Home/Detail UUIDs;
dormant and unselected content, repeated push/pop, modal presentation, immediate
scene-B teardown, and one restored scene also passed (`EXP-030` through
`EXP-042`). These runs do not establish a general SwiftUI
construction/visibility guarantee, simultaneous visible-peer continuity, or
concurrent restoration.

The interactive completion gate now suppresses a cancelled pop and emits a fresh
Home occurrence only when the pop commits (`EXP-043` through `EXP-045`). A
completed `Home → Detail → Home` path therefore creates three RUM views—two
distinct Home UUIDs around Detail—even if SwiftUI reuses the same platform item.
A cancelled or unmaterialized transition creates none.

Probe-only typed-path experiments (`EXP-046` through `EXP-059`) establish that
semantic route input must be installed at every materialized destination and
needs an occurrence identity independent of platform lifetime. Root-only
placements fail; different-type replacement passes; same-type Detail₁ → Detail₂
collapses until probe-only `.id(route)` supplies the missing identity. `.id` is
diagnostic evidence, not the customer solution, because it resets customer
SwiftUI state.

The internal keyed-occurrence implementation (`EXP-060` through `EXP-066`) adds
atomic scene-local replacement, retained-scope isolation, disconnect fencing,
retained-reader registration, interactive cancellation, migration preservation,
and stale-observer isolation. The later probe source proves the missing runtime
property without resetting customer state: `EXP-090` gives same-type Detail₁ and
Detail₂ distinct RUM UUIDs while preserving one SwiftUI state token, and
`EXP-091` creates no occurrence for a coalesced push/revert. `EXP-092` through
`EXP-097` isolate returned-route ordering and show that SwiftUI detaches the
retained Home reader before it becomes visible again. `EXP-098` and `EXP-099`
then synchronously reveal that retained Home through a per-window occurrence
source, producing Home₁ → Detail → Home₂ and attributing immediate post-pop
action/resource work to Home₂ before `onAppear`. The source uses the last
concrete scene attachment only as a fallback, clears it on disconnect, and routes
through the interactive arbiter. It is an internal debug experiment, not a public
or automatic shipping integration.

`EXP-067` through `EXP-087` retain the split-navigation and UIKit ordering
baselines. `EXP-102`/`EXP-103` now fix the route-owned SwiftUI same-type split
collapse experimentally: retained Detail content receives fresh RUM occurrences
in one and two windows without customer `.id`. Transparent automatic mode still
creates no semantic selection views.
The iOS 27 UIKit handoff removes false Primary intervals and preserves fresh
returned-controller occurrences, while simultaneous visible topology and resize
remain open. `EXP-089` exercises filtered manual-event fallback. `EXP-100` does
not prove native interactive cancel/finish because both synthetic edge drags were
ignored; focused arbiter cancellation and completion paths do pass. `EXP-101`
records the broader exact-view routing hardening and the current full-suite
results: DatadogRUM 1,147/1,147 and DatadogTrace 151/151.
[ASSESSMENT.md](MultiSceneSupport/ASSESSMENT.md) owns the full conclusions;
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md) owns each run and rejected draft.

| Surface | Current branch status | Remaining release condition |
| --- | --- | --- |
| UIKit views and navigation | Experimental pass for independent stacks, push/pop, modal, duplicate names, and teardown; iOS 27 split replacement, physical pop, deterministic cancel/finish, and an overlapping B sequence pass without false sibling views while retaining fresh returned-path UUIDs; an app-subclassed split still adds a container view | Prove both scenes complete in a simultaneously visible topology, complete adaptive/lifecycle/normal-app validation, review subclass-container compatibility, then restoration and iPhone Duo validation |
| Explicit SwiftUI tracking | Experimental iOS 27 early-start, retained-return, modal, repeated push/pop, crash-safe teardown, restoration, synthetic reconnect, and customer-state-preserving keyed-occurrence controls pass; single- and two-window split replacement now preserve retained Detail state and exact markers | Turn the debug occurrence input/source into a reviewed integration, prove a recognized native interactive gesture, then cover returned split selection, adaptive navigation, stable simultaneous visibility, genuine reconnect, and concurrent restoration |
| Automatic native SwiftUI | Transparent discovery still fails; route-owned controls prove initial creation, abort, different- and same-type stack/split replacement, and retained Home without resetting customer state, but only through an internal debug integration; automatic split has no semantic selection views | Define and review the iOS 27 integration and mixing rules, then connect it to automatic root/destination creation and validate adaptive/restored/unsupported shapes |
| Actions | Source-bearing UIKit/SwiftUI taps emit once on their scene; exact-view actions refresh the process representative; public manual errors, view mutations, and internal view work consume exact handoff view/scene when present; source-less work retains last-interacted fallback | Repeat exact precedence with simultaneously visible A/B and a different representative; finish UIKit deceleration and targeted downstream runtime rows |
| Resources and traces | Trustworthy start provenance is frozen; manual Resource completions remain with their captured owner; automatic URLSession completion and OpenTelemetry spans now use the same scene-handoff model | Finish the bounded causal matrix, simultaneous-window/reverse-completion proof, normal-handler compatibility, and overhead measurement |
| Operations | Internal per-step cross-window routing and exact identity pass focused tests | Public target API review and live A-to-B/duplicate-start backend runs |
| Lifecycle and sessions | Independent close, rollover, fresh/retained-reader remount, and cancellation rearming are covered; hidden detached readers retain only their last concrete scene proof, which disconnect clears before requiring a new mount | Genuine OS disconnect/reconnect, live background/foreground, and concurrent restoration |
| Other signals | Focused ownership exists for logs, mirrored errors, WebView, vitals, fatal context, and profiling identity | Targeted two-window runtime proof and explicit process-wide limitations |
| Session Replay | Coexists in tested two-window runs without an SDK crash | No scene-correct replay work is required here |
| Normal applications | DatadogRUM 1,147/1,147, DatadogTrace 151/151, focused lint, and both probes build | Live single-scene and custom-handler behavior plus `sendEvent` overhead/reentrancy |

Generic work with no trustworthy source still emits once on the process
representative, intended to be the last-interacted view. This preserves existing
instrumentation but is not exact attribution. Resource/Trace work is limited to
preserving provenance that actually exists; request rewrites across capture or
first-party boundaries are developer misuse and outside this project.

The detailed basis is in [ASSESSMENT.md](MultiSceneSupport/ASSESSMENT.md); exact
payload and backend proof is indexed in [EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

## Confirmed product decisions

1. Generic work with no trustworthy source uses the process representative,
   intended to be the last-interacted view. It emits once and is never broadcast.
   This compatibility fallback can be inaccurate and must not be presented as
   exact ownership.
2. Entering the background ends only that scene's visible view; foregrounding
   restarts it. Merely losing focus while remaining visible does not end a view.
3. Concurrent scene views overlap within one application RUM session. Scene
   identity remains internal and is not added to the intake schema.
4. Process-wide long tasks, hangs, memory warnings, and crashes emit once on the
   process representative. Shared process/render-loop vitals are not duplicated
   as independent per-window measurements.
5. Session Replay needs crash-free coexistence only. Scene-correct recording,
   touch routing, and replay context are out of scope for this project.
6. iPhone Duo on iOS 27.1 is the release target. Semantic multi-scene support
   before iOS 27 is not required, while normal apps on every supported deployment
   target must remain compatible.
7. On the OS range where multi-scene semantics are claimed, SwiftUI lifecycle
   work must belong to the intended RUM view. The contract is semantic
   attribution, not observable ordering between customer callbacks and internal
   command or payload emission. Unsupported SwiftUI internals are not an
   acceptable fix.
8. A RUM view represents one committed navigation-path occurrence, not the
   lifetime or identity of a SwiftUI value, `UIView`, or view controller. Returning
   to the same Home platform item after Detail starts a new Home view ID; a
   cancelled transition starts no occurrence.
9. Resource and Trace work is limited to preserving trustworthy provenance and a
   shared frozen owner. The SDK does not guess after causality is lost and does
   not defend developer-written handlers that rewrite a request across automatic
   capture or first-party header-injection boundaries.
10. Operations use exact application-wide `(name, operationKey)` identity; scenes
   never namespace it. Every step resolves its view independently. A last-proven
   snapshot is a fallback, not permanent ownership by the start scene.
11. Starting the same Operation identity twice tracks only the latest start in
    the client. A later success or failure ends only that instance; the earlier
    backend operation remains open until its four-hour timeout. The SDK emits no
    synthetic end. Customers must use a unique key for every concurrent instance.
12. The Operation view-target escape hatch requires normal Swift, Objective-C,
    protocol-compatibility, and RFC review. Existing APIs retain inferred behavior,
    and no internal RUM view UUID becomes public.

The complete Operation contract, proposed Swift and Objective-C escape hatch,
customer workflow, and required tests live only in
[OPERATIONS.md](MultiSceneSupport/OPERATIONS.md).

## Resume here

### Checkpoint

The branch is `valpertui/multiple-windows-scenes`; the latest implementation
checkpoint is `96222a6b1` (`Add keyed SwiftUI split navigation probe`). It follows
the retained-route and exact-view routing checkpoints through `eece6ec17`. All
are unsigned local development commits and must not be pushed. The chronological
checkpoint table in [EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md) is
authoritative.

`EXP-090` through `EXP-103` are the latest SwiftUI occurrence loop: same-type
replacement preserves customer state, coalesced abort creates no view, retained
Home ordering and failed approaches are isolated, and the per-window source gives
returned Home a fresh RUM UUID before immediate work. `EXP-100` records two ignored
native edge drags, so it is not cancellation/finish evidence. `EXP-101` records
the wider routing hardening; `EXP-102`/`EXP-103` pass same-type split replacement
without customer-state reset in one and two scenes. This remains an experimental
branch, not a release-ready support claim.

### Exact next work

The next loop stays on the automatic SwiftUI P0 rather than returning to a broad
UIKit sweep:

1. Turn the `EXP-098`/`EXP-099` debug keyed-occurrence source into the smallest
   reviewable iOS 27 integration contract. Preserve customer SwiftUI identity and
   state, keep one source per window root, install tracking at the root and every
   materialized destination, and define how it mixes with automatic discovery and
   explicit `.trackRUMView`. Do not add public API before normal RFC/API review.
2. Obtain a recognized native interactive SwiftUI pop and prove both cancellation
   and completion. Keep the focused arbiter tests, but do not reuse `EXP-100`'s
   ignored edge drags as evidence.
3. Preserve the passing regular-width `NavigationSplitView` replacement from
   `EXP-102`/`EXP-103`, then add return to a previously selected retained Detail
   and adaptive collapse/expansion on a capable destination.
4. Repeat simultaneous A/B navigation in a topology where both windows are visibly
   active and can complete independently. Retain the iOS 27 UIKit handoff and
   review the separate application-subclass predicate issue.
5. Run genuine scene disconnect/reconnect, per-scene background/foreground, and
   concurrent restoration. A retained scene snapshot is fallback evidence only;
   disconnect must fence it until a new concrete mount.
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
  retained split Detail occurrences in two windows. This is integration evidence,
  not a shipped API.
- Operations resolve every step independently. Trustworthy new context replaces
  the last-proven snapshot; the snapshot and then process representative are
  fallbacks. Identity is the exact application-wide `(name, operationKey)` tuple.
- Profiling uses the same typed Operation identity and distinguishes omitted from
  empty keys.
- Session Replay is required only to coexist without an SDK crash.

The trait-backed SwiftUI result is a semantic-attribution guarantee, not a
callback-order guarantee. `EXP-015` showed that synchronous actions and resources
invoked 0.3-4 ms before the new view payload were processed on the intended view.
The narrower iOS 27 early-mount path in `EXP-032` and `EXP-033` enqueues explicit
Home/Detail starts before all tested lifecycle work. Automatic native tracking
does not yet have either semantic result.

### Validation snapshot

As of 2026-09-13:

- `DatadogRUM`: 1,147/1,147 passed after the retained-route source and broader
  exact-view routing hardening, with zero failures.
- Retained-route source: 13/13 focused tests passed, including ordinary detach,
  explicit unresolved attachment rejection, disconnect fencing, scene migration,
  stale/duplicate generation rejection, A/B same-key isolation, and arbiter
  cancellation/completion.
- Explicit SwiftUI transition arbiter: its focused cancellation/completion paths
  pass; native gesture recognition remains unproven because both `EXP-100` drags
  were ignored before any navigation signal.
- Session/application-scope occurrence isolation: 75/75 and 27/27 tests passed,
  including retained Home₁ pending work across a distinct Home₂ occurrence
  and restored same-identity replacement.
- Operations-focused classes: 99/99 passed in the full run, comprising 26/26
  `RUMFeatureOperationManagerTests` and 73/73 `RUMSessionScopeTests`.
- `DatadogInternal`: 477/477 passed.
- `DatadogLogs`: 95/95 passed.
- `DatadogTrace`: 151/151 passed, including 4/4 focused OpenTelemetry handoff
  tests.
- `EXP-102`/`EXP-103`: backend intake contains the exact single- and two-window
  split occurrence chains, with 3/3 and 6/6 action/Resource marker pairs and zero
  RUM errors. The later `EXP-103` simulator `backboardd` crash occurred after both
  accepted upload batches and produced no probe-app crash report.
- `DatadogWebViewTracking`: 31/31 passed.
- `DatadogProfiling`: 233/233 passed.
- The native SwiftUI probe and integration probe build through Xcode 27.
- The generic iOS Swift Package build and repository lint pass at their recorded
  checkpoints; focused source/test lint for the retained-route slice has zero
  violations.

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

## Open product questions from the goal review

- Which reviewed SwiftUI integration should install semantic tracking at the root
  and every destination builder before lifecycle work on iOS 27: an SDK-owned
  typed-route builder, a customer resolver attached to each destination, or a
  narrower explicit tracking contract? Detached root wrappers, transparent
  controller/title/reflection discovery, and lifecycle-only hooks are disproven.
  Adding public API requires RFC review. A narrower explicit-only contract would
  change the release scope and cannot satisfy the current automatic-tracking gate
  without an explicit product decision.
- Should the Operation target review include scene-aware manual keyed-view
  start/stop so `.tracked(key:in:)` is deterministic, or should that target form
  be deferred? The current public `startView(key:)` cannot explicitly establish
  scene ownership.
- For `NavigationSplitView` or `UISplitViewController`, does “proper view” mean one
  current destination/detail view per scene, or separate simultaneously active RUM
  views for visible panes? The current architecture intentionally supports one
  active view branch per scene, so the latter would be a separate model change.
- Is correct event-to-view attribution inside one RUM session sufficient product
  representation for parallel window histories, or must the RUM product visibly
  distinguish window branches? Raw intake and the reducer accept overlap, but no
  scene identifier is serialized and product UI presentation has not been reviewed.

## Completion gates

[PLAN.md](MultiSceneSupport/PLAN.md#completion-gates) owns the exhaustive release
checklist. The support claim remains experimental until:

- automatically tracked SwiftUI creates the semantic root and destination before
  lifecycle work is attributed in both native `WindowGroup` and UIKit-hosted
  applications;
- the explicit iOS 27 early-start path passes aborted/preloaded containers,
  live simultaneous transitions, split navigation, visible-peer close continuity,
  surviving-reader reconnect, and restoration without
  inventing a view for construction alone; modal occurrence navigation and
  crash-safe close ownership already pass;
- UIKit and SwiftUI navigation, including cancelled interactive transitions,
  actions, lifecycle, disconnect, and restoration pass the concurrent-scene
  matrix;
- Operations pass live cross-window and duplicate-start validation and ship only
  with the reviewed explicit target API;
- bounded Resource/Trace provenance and source-less fallback behavior pass the
  remaining runtime cases without adding request-rewrite scope;
- downstream signals have explicit runtime-backed support levels and Session
  Replay continues to coexist without an SDK crash;
- live ordinary-app regression, custom-handler, and event-dispatch performance
  checks pass; and
- the complete matrix passes on iPhone Duo with iOS 27.1.
