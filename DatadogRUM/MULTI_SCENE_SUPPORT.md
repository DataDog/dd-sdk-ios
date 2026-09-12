# RUM multi-scene support

This is the canonical entry point for concurrent `UIWindowScene` support in
Datadog RUM. It records the current contract, support status, decisions, and exact
resume point. Detailed evidence and chronology are split by ownership so future
work can start here without reading the complete experiment history.
It remains separate from `RUM_FEATURE.md` until the behavior is implemented,
validated, and ready to become a supported contract.

Last updated: 2026-09-12

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

All support statements distinguish source inspection, focused tests, local
runtime observation, emitted payloads, backend intake, and reduced product data.

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

| Surface | Current branch status | Remaining release condition |
| --- | --- | --- |
| UIKit views and navigation | Experimental pass for independent stacks, push/pop, modal, duplicate names, and teardown | Split/adaptive navigation, restoration, lifecycle matrix, and iPhone Duo validation |
| Explicit SwiftUI tracking | Experimental pass; iOS 17+ trait bridge preserves tested lifecycle attribution | Repeated stress and supported-OS validation |
| Automatic native SwiftUI | Fails early root/destination semantics | Reviewed iOS 27 root/navigation integration that publishes semantic identity before lifecycle work |
| Actions | Taps and SwiftUI scroll are scene-correct once the view exists | UIKit deceleration and filtered-interaction representative edge |
| Resources and traces | Correct when trustworthy provenance exists and is frozen at start | Four pending causal cases, live reverse completion, compatibility, and overhead proof |
| Operations | Internal per-step cross-window routing and exact identity pass focused tests | Public target API review and live A-to-B/duplicate-start backend runs |
| Lifecycle and sessions | Independent close and rollover are covered | Background/foreground, reconnect, and restoration |
| Other signals | Focused ownership exists for logs, mirrored errors, WebView, vitals, fatal context, and profiling identity | Targeted two-window runtime proof and explicit process-wide limitations |
| Session Replay | Coexists in tested two-window runs without an SDK crash | No scene-correct replay work is required here |
| Normal applications | Full module suites, lint, and package build pass | Live single-scene and custom-handler behavior plus `sendEvent` overhead/reentrancy |

Generic work with no trustworthy source still emits once on the process
representative, intended to be the last-interacted view. This preserves existing
instrumentation but is not exact attribution. Resource/Trace work is limited to
preserving provenance that actually exists; request rewrites across capture or
first-party boundaries are developer misuse and outside this project.

The detailed basis for every status is in
[ASSESSMENT.md](MultiSceneSupport/ASSESSMENT.md). Exact payload and backend proof
is indexed in [EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

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
6. iPhone Duo on iOS 27.1 is the release target. Semantic multi-scene support on
   iOS 15/16 is not required, while normal apps on every supported deployment
   target must remain compatible.
7. On the supported OS range, SwiftUI lifecycle work must belong to the intended
   RUM view. The contract is semantic attribution, not observable ordering between
   customer callbacks and internal command or payload emission. Unsupported
   SwiftUI internals are not an acceptable fix.
8. Resource and Trace work is limited to preserving trustworthy provenance and a
   shared frozen owner. The SDK does not guess after causality is lost and does
   not defend developer-written handlers that rewrite a request across automatic
   capture or first-party header-injection boundaries.
9. Operations use exact application-wide `(name, operationKey)` identity; scenes
   never namespace it. Every step resolves its view independently. A last-proven
   snapshot is a fallback, not permanent ownership by the start scene.
10. Starting the same Operation identity twice tracks only the latest start in
    the client. A later success or failure ends only that instance; the earlier
    backend operation remains open until its four-hour timeout. The SDK emits no
    synthetic end. Customers must use a unique key for every concurrent instance.
11. The Operation view-target escape hatch requires normal Swift, Objective-C,
    protocol-compatibility, and RFC review. Existing APIs retain inferred behavior,
    and no internal RUM view UUID becomes public.

The complete Operation contract, proposed Swift and Objective-C escape hatch,
customer workflow, and required tests live only in
[OPERATIONS.md](MultiSceneSupport/OPERATIONS.md).

## Resume here

### Checkpoint

The branch is `valpertui/multiple-windows-scenes`. The standalone native SwiftUI
probe is committed at `e56262485`. The reconciled pre-split assessment is committed
at `2fb8dd9b5`. The native lifecycle/reflection experiment is complete and is
recorded as `EXP-029`. This remains an experimental branch, not a release-ready
support claim.

### Exact next work

1. Prepare the smallest reviewable iOS 27 SwiftUI root/navigation integration
   proposal and validate its semantics against the native `WindowGroup` probe.
   `EXP-029` rules out navigation titles, the old and apparent-new reflection
   paths, base `viewWillAppear`, and direct
   `UIHostingController.viewWillAppear` as sufficiently early transparent hooks.
   Do not add public API before normal RFC/API review.
2. Complete the Operations public-target API review, including the scene-aware
   manual-key prerequisite. Then run live A-to-B success, A-to-B failure, and
   duplicate-start flows; inspect raw vitals, reduced Operations, and warnings.
3. Prove no normal-app degradation with a live single-scene app, automatic action
   tracking on and off, an ordinary custom URLSession handler, and measured
   `sendEvent` recursion and overhead.
4. Run `NavigationSplitView`, UIKit split/adaptive collapse, UIKit scroll through
   deceleration, per-scene background/foreground, disconnect/reconnect, and
   restoration. Repeat the release matrix on iOS 27.1 and iPhone Duo when that
   destination is available.
5. Close only the missing Resource/Trace causal rows and downstream runtime rows
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
- Operations resolve every step independently. Trustworthy new context replaces
  the last-proven snapshot; the snapshot and then process representative are
  fallbacks. Identity is the exact application-wide `(name, operationKey)` tuple.
- Profiling uses the same typed Operation identity and distinguishes omitted from
  empty keys.
- Session Replay is required only to coexist without an SDK crash.

The trait-backed SwiftUI result is a semantic-attribution guarantee, not a
callback-order guarantee. `EXP-015` showed that synchronous actions and resources
invoked 0.3-4 ms before the new view payload were processed on the intended view.
Automatic native tracking does not yet have that semantic result.

### Validation snapshot

As of 2026-09-12:

- `DatadogRUM`: 1,033/1,033 passed.
- Operations-focused tests: 98/98 passed, comprising 26/26
  `RUMFeatureOperationManagerTests` and 72/72 `RUMSessionScopeTests`.
- `DatadogInternal`: 477/477 passed.
- `DatadogLogs`: 95/95 passed.
- `DatadogTrace`: 147/147 passed.
- `DatadogWebViewTracking`: 31/31 passed.
- `DatadogProfiling`: 233/233 passed.
- The native SwiftUI probe and integration probe build through Xcode 27.
- The generic iOS Swift Package build and repository lint pass; lint covered 713
  source and 699 test files.

These are regression and implementation checks, not substitutes for the missing
runtime rows. Result-bundle names and full run evidence remain in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

### Blockers and workspace safety

Public SwiftUI and Operation API work requires normal RFC/API review. There is no
active signing blocker; every checkpoint must remain signed, with no unsigned
fallback. The iOS 27 integration-runner half-and-half layout repeatedly respawned
`backboardd`, although the standalone native `WindowGroup` probe opens two windows.

Do not stage, commit, revert, or expose
`Datadog/Datadog.xcodeproj/project.pbxproj` or
`xcconfigs/Datadog.local.xcconfig`. Both predate this work and the latter contains
local credentials. Use exact path lists for every commit.

Rejected experiments and do-not-repeat guidance are authoritative in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md#attempts-not-to-repeat).

## Open product questions from the goal review

- Which reviewed SwiftUI integration should supply semantic root and destination
  identity before lifecycle work on iOS 27: a bound navigation/root wrapper, a
  narrower explicit tracking contract, or another supported Apple API boundary?
  The transparent controller/title/reflection candidates tested so far are
  disproven, and adding public API requires RFC review.
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

- automatically tracked native SwiftUI creates the semantic root and destination
  before lifecycle work is attributed;
- UIKit and SwiftUI navigation, actions, lifecycle, disconnect, and restoration
  pass the concurrent-scene matrix;
- Operations pass live cross-window and duplicate-start validation and ship only
  with the reviewed explicit target API;
- bounded Resource/Trace provenance and source-less fallback behavior pass the
  remaining runtime cases without adding request-rewrite scope;
- downstream signals have explicit runtime-backed support levels and Session
  Replay continues to coexist without an SDK crash;
- live ordinary-app regression, custom-handler, and event-dispatch performance
  checks pass; and
- the complete matrix passes on iPhone Duo with iOS 27.1.
