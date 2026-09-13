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
semantic route input must be installed at every materialized destination, and
that it needs an occurrence identity independent of platform lifetime. Root-only
placements fail; different-type replacement passes; same-type Detail₁ → Detail₂
collapses until probe-only `.id(route)` supplies that missing identity. `.id` is
diagnostic evidence, not the customer solution, because it also resets customer
SwiftUI state.

The dormant internal implementation (`EXP-060` through `EXP-065`) adds atomic
scene-local occurrence replacement, retained-scope isolation, keyed occurrence
state, disconnect invalidation, retained-reader re-registration, cancellation
rearming, migration preservation, and stale-observer isolation. Its final focused
set passes 74/74 and the complete RUM plan passes 1,108/1,108. `EXP-066` then
passes the same retained-reader path through probe fault injection, emitted
payloads, and backend intake while clearly stopping short of a genuine OS
disconnect/reconnect claim. `EXP-067` identifies a separate split-navigation
gap: the SDK has one callback-ordered stack per scene, but no pane or committed
route-occurrence model. `EXP-068` reproduces that gap in regular-width SwiftUI:
same-type Detail(1) → Detail(2) reuses one RUM UUID and misattributes Detail(2)'s
action/resource, while different-type Placeholder starts correctly. `EXP-069`
shows automatic mode is worse: all three semantic selections are absent and
their markers use launch or hosting-controller views. `EXP-070` restores the
exact three-selection chain with probe-only `.id(selection)`, while also proving
that control replaces customer content lifetime. No public occurrence key is
wired. `EXP-071` then confirms that stock UIKit split replacement manufactures a
fresh Primary occurrence between two secondaries even though Primary never
reappears. `EXP-072` adds a distinct compatibility issue: an application subclass
of the split container itself becomes a short-lived RUM view. `EXP-073` extends
the ordering failure to nested push/pop. `EXP-074`/`EXP-075` validate an iOS 27
multi-scene-only handoff candidate: both backend paths lose the false Primary,
and a reused controller returning on pop still receives a fresh RUM UUID.
`EXP-077` hardens unrelated callback/background/disconnect ordering in 57/57
handler tests; `EXP-079`/`EXP-080` repeat both native passes on that revision.
`EXP-082` through `EXP-084` add a physical committed pop and deterministic
cancel/finish pair: cancellation emits nothing speculative; committed paths give
the reused controller a fresh UUID. `EXP-086` proves A/B overlap but exposes
fullscreen harness limits and the approved source-less fallback. `EXP-087` passes
the empty-detail baseline; simulator resize remains unavailable.
[ASSESSMENT.md](MultiSceneSupport/ASSESSMENT.md) owns the full conclusions;
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md) owns each run and rejected draft.

| Surface | Current branch status | Remaining release condition |
| --- | --- | --- |
| UIKit views and navigation | Experimental pass for independent stacks, push/pop, modal, duplicate names, and teardown; iOS 27 split replacement, physical pop, deterministic cancel/finish, and an overlapping B sequence pass without false sibling views while retaining fresh returned-path UUIDs; an app-subclassed split still adds a container view | Prove both scenes complete in a simultaneously visible topology, complete adaptive/lifecycle/normal-app validation, review subclass-container compatibility, then restoration and iPhone Duo validation |
| Explicit SwiftUI tracking | Experimental iOS 27 early-start pass across three A/B runs, dormant/unselected controls, repeated push/pop, modal occurrence navigation, crash-safe B teardown, one restored native scene, a native/backend cancellation-gate pass, focused reconnect hardening, and a synthetic retained-reader runtime/backend pass; same-type split selection collapses without identity and passes with state-resetting `.id` control | Occurrence-aware split correction that preserves customer state, live simultaneous-transition isolation, aborted/preloaded containers, concurrent restoration, genuine OS reconnect, and visible-peer continuity on close |
| Automatic native SwiftUI | Transparent discovery fails; route-owned controls pass initial A/B creation, push/cancel/pop, abort, and different-type replacement; same-type replacement fails without a token and passes with probe-only route identity; automatic split has no semantic selection views; Xcode 27 exposes no transparent semantic hook | Review and connect an occurrence-token API without changing customer SwiftUI identity; then cover retained-customer-state runtime, split/adaptive navigation, restoration, mixing rules, and unsupported shapes |
| Actions | Source-bearing UIKit/SwiftUI taps emit once on their scene; execution-local manual action calls now prefer exact handoff view/scene; SwiftUI scroll passes | Live handoff validation, UIKit deceleration, and later source-less work remaining representative |
| Resources and traces | Correct when trustworthy provenance exists and is frozen at start; manual Resource starts now consume the same exact execution-local owner, while completions remain key-owned | Four pending causal cases, live handoff/reverse completion, compatibility, and overhead proof |
| Operations | Internal per-step cross-window routing and exact identity pass focused tests | Public target API review and live A-to-B/duplicate-start backend runs |
| Lifecycle and sessions | Independent close, state/handler disconnect alignment, fresh or retained-reader remount, cancellation rearming, and rollover are covered; synthetic retained-reader teardown/remount passes runtime, payload, and backend validation | Genuine OS disconnect/reconnect, live background/foreground, and concurrent restoration |
| Other signals | Focused ownership exists for logs, mirrored errors, WebView, vitals, fatal context, and profiling identity | Targeted two-window runtime proof and explicit process-wide limitations |
| Session Replay | Coexists in tested two-window runs without an SDK crash | No scene-correct replay work is required here |
| Normal applications | Full module suites, lint, and package build pass | Live single-scene and custom-handler behavior plus `sendEvent` overhead/reentrancy |

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

The branch is `valpertui/multiple-windows-scenes`. The native probe is committed
at `e56262485`, reconciled assessment at `2fb8dd9b5`, and documentation split at
`6fa2baf24`. Local implementation checkpoints are `4ddfa9a3a`, `1eea12c27`,
`61031e16f`, `77dd05c4a`, `bce1cdbd4`, and `7d7bc0814`. These six development
commits are unsigned and must not be pushed.
The native lifecycle/reflection experiment is `EXP-029`; explicit baseline,
early-mount, stress, cancellation-control, final-repeat, and gate-hardening work
is `EXP-030` through `EXP-045`; typed-path placement, occurrence, and aborted
mutation experiments continue through `EXP-059`; internal occurrence,
disconnect, and retained-reader hardening continues through `EXP-065`; the
synthetic retained-reader integration control is `EXP-066`; and split-navigation
source analysis, failures, controls, hardening, and native reruns continue through
`EXP-087`. `EXP-088` is the manual handoff fix and focused/full-suite checkpoint.
This remains an experimental branch, not a release-ready support claim.

### Exact next work

The next loop should finish the bounded UIKit split regression matrix, then return
directly to the automatic-tracking P0 integration.

1. Keep the `EXP-077` UIKit candidate double-gated to iOS 27 and declared
   multi-scene applications. `EXP-082` through `EXP-084` validate nested paths.
   `EXP-086` overlaps A/B, but fullscreen replacement stalls A without
   activation-state evidence. Repeat with both scenes demonstrably visible, then
   finish lifecycle and ordinary-app checks.
   Treat `EXP-072`'s subclass container as a separate compatibility decision.
2. Preserve `EXP-068` as the failing route-owned regular-width
   `NavigationSplitView` baseline: Detail(1) → Detail(2) reused one RUM UUID and
   misattributed Detail(2)'s markers. `EXP-069` separately proves automatic mode
   creates no semantic selection views. `EXP-070` proves an occurrence identity
   restores the exact chain but `.id` also resets customer content. `EXP-087`
   proves stable no-selection creates no Detail. CoreDevice reports this simulator
   lacks Resizable App Management; rerun regular/compact/regular on a capable
   destination and repeat A/B replacement.
3. Turn the passing probe-only boundary from `EXP-050`/`EXP-051` into the
   smallest reviewable iOS 27 SwiftUI integration proposal. The path binding is
   semantic input, not the occurrence: `EXP-052` observed two same-turn writes
   without creating a view. The view start must be installed at the root and each
   typed destination builder; `EXP-047` through `EXP-049` reject detached root
   siblings/wrappers. `EXP-054` and `EXP-056` pass a materialized
   Detail-to-Alternate replacement in one and two scenes. `EXP-057` then proves
   that replacing one Detail value with another through the same SwiftUI type and
   RUM name reuses platform state and loses the second RUM occurrence. `EXP-058`
   proves a probe-only `.id(route)` control restores distinct UUIDs and exact
   marker attribution; `EXP-059` preserves those branches concurrently in A/B.
   Specify an occurrence token that resets only RUM tracking, not customer
   SwiftUI state, then validate that implementation against retained state and
   the split-navigation results.
   Then define route-descriptor and mixing rules for automatic discovery,
   per-screen explicit tracking, and unsupported `NavigationLink(destination:)`
   shapes. `EXP-029` rules out titles, reflection, and controller appearance;
   `EXP-085` confirms no supported Xcode 27 API fills that transparent semantic
   boundary. Do not add public API before normal RFC/API review.
4. Run a genuine iOS 27 OS disconnect/reconnect or restoration case where the
   platform lifecycle is observable. `EXP-066` validates runtime, payload, and
   backend integration only under synthetic notification injection while the
   scene and reader remain alive; it is not a platform lifecycle result.
5. Complete the Operations public-target API review, including the scene-aware
   manual-key prerequisite. Then run live A-to-B success, A-to-B failure, and
   duplicate-start flows; inspect raw vitals, reduced Operations, and warnings.
6. Prove no normal-app degradation with a live single-scene app, automatic action
   tracking on and off, an ordinary custom URLSession handler, and measured
   `sendEvent` recursion and overhead.
7. Finish the explicit construction/visibility matrix with a demonstrably
   constructed-but-not-presented destination, visible-peer close continuity,
   simultaneous A/B transitions, `NavigationSplitView`, UIKit split/adaptive
   collapse, UIKit scroll through deceleration, per-scene background/foreground,
   disconnect/reconnect, and concurrent restoration. `EXP-052` covers only a
   coalesced unmaterialized write; `EXP-039` never constructed its rejected child;
   and `EXP-042` restored only one scene. Repeat the release matrix on iOS 27.1
   and iPhone Duo when that destination is available.
8. Close only the missing Resource/Trace causal rows and downstream runtime rows
   in [PLAN.md](MultiSceneSupport/PLAN.md). Remove provisional machinery that does
   not change a supported result.

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

- `DatadogRUM`: 1,122/1,122 passed after execution-local manual action/Resource
  targeting, with zero failures, skips, or not-run tests.
- Explicit SwiftUI transition arbiter: 38/38 focused tests passed; legacy and
  dormant keyed view state-machine coverage is 34/34, plus two passing targeted
  handler regressions (74/74 total).
- Session/application-scope occurrence isolation: 75/75 and 27/27 tests passed,
  including retained Home₁ pending work across a distinct Home₂ occurrence
  and restored same-identity replacement.
- Operations-focused classes: 99/99 passed in the full run, comprising 26/26
  `RUMFeatureOperationManagerTests` and 73/73 `RUMSessionScopeTests`.
- `DatadogInternal`: 477/477 passed.
- `DatadogLogs`: 95/95 passed.
- `DatadogTrace`: 147/147 passed.
- `DatadogWebViewTracking`: 31/31 passed.
- `DatadogProfiling`: 233/233 passed.
- The native SwiftUI probe and integration probe build through Xcode 27.
- The generic iOS Swift Package build and repository lint pass; lint covered 713
  source and 699 test files.

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
