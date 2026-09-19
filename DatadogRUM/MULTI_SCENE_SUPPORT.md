# RUM multi-scene support

This document owns the stable project goal, approved behavior and non-goals.
The implementation remains experimental until the finite release gates pass and
normal API review approves the supported surface. Keep it separate from
RUM_FEATURE.md until that contract is ready to ship.

Current support and evidence limits: [ASSESSMENT.md](MultiSceneSupport/ASSESSMENT.md).
Authoritative obligations/status: [release-gates.json](MultiSceneSupport/release-gates.json)
and its generated [checklist](MultiSceneSupport/PLAN.md).
The sole restart cursor is [.continue-here.md](../.continue-here.md).
Concrete pending public API proposal: [stable API review](MultiSceneSupport/STABLE_API_REVIEW.md).

## Goal

RUM must correctly represent applications that have two or more independently
navigable windows at the same time. Opening, foregrounding, backgrounding, or
closing one scene must not end or replace the view that remains visible in another
scene. Automatically and manually captured events must be attributed to the scene
that produced them whenever that identity is available.

The immediate compatibility priority is that RUM is no worse for an existing
application rebuilt with the iOS27 SDK on iPhone Duo, even without major app-side
support changes. Assess automatic UIKit and SwiftUI views and actions separately;
pre-existing limitations are acceptable when unchanged and clearly documented.
C07–C10 own this finite no-adoption comparison independently of optional exact
semantic APIs and their pending review.

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

## Behavioral acceptance boundaries

Construction alone must never create a tracked occurrence: aborted and preloaded
containers remain untracked until a committed destination exists. The early-start
path must preserve immediate lifecycle-work ownership, cancelled transitions,
visible-peer continuity, surviving-reader reconnect and restoration. The same
contract applies to native WindowGroup and UIKit-hosted SwiftUI applications.

Source-bearing downstream work must preserve trustworthy provenance; source-less
work retains its documented fallback. Compatibility includes ordinary apps,
custom handlers and dispatch cost. Internal scene ownership must remain suitable
for future Window Execution Context mapping. These are existing obligations of
the [finite release gates](MultiSceneSupport/PLAN.md), including its physical
Duo27.1 matrix; no SDK or review checkpoint alone establishes them all.

## Non-goals and release boundaries

- One current destination per scene; simultaneous multi-pane/tab modeling is a
  separate project.
- Window Execution Context serialization and backend visualization remain
  follow-up work. Preserve internal ownership without an interim wire format.
- Session Replay must coexist without SDK crashes; scene-correct replay is out
  of scope.
- Earlier-system semantic multi-scene support is optional where it would
  compromise the iOS27+ solution. Ordinary supported apps, including iOS15,
  remain a compatibility requirement.
- Do not guess provenance after causality is lost or expand scope to developer
  request rewrites across capture/first-party boundaries.
- Profiling and shared process/render metrics remain process-level.
- Stable API names, overload breadth and Objective-C Release exposure require
  review. No internal RUM UUIDs or returned view handles become public.
- Generic single-scene extraction starts only after multi-scene freeze, under
  [its separate plan](MultiSceneSupport/DEFERRED_SINGLE_SCENE_EXTRACTION.md).

## Document map

| Question | Owning document |
| --- | --- |
| What is approved? | This overview; [navigation API contract](MultiSceneSupport/NAVIGATION_API.md) and [Operation contract](MultiSceneSupport/OPERATIONS.md) own detailed proposals. |
| What remains and what closes it? | [Gate register](MultiSceneSupport/release-gates.json), generated [PLAN](MultiSceneSupport/PLAN.md) and [progress](MultiSceneSupport/Results/release-progress.json). |
| What is supported and how strong is the proof? | [Assessment](MultiSceneSupport/ASSESSMENT.md). |
| Where should work resume? | [.continue-here.md](../.continue-here.md), exclusively. |
| How does an application integrate and attribute telemetry? | [Integration guide](MultiSceneSupport/SUPPORT_GUIDE.md), pending F01 approval and F02 publication checks. |
| What executes the final compatibility gate? | [Finite matrix](MultiSceneSupport/FINAL_COMPATIBILITY.md), with results owned by F03. |
| Where is an experiment? | [Compact index](MultiSceneSupport/EXPERIMENTS.md), then its exact detailed record; never load frozen history wholesale. |
| How should a run be executed? | [Runbook](MultiSceneSupport/TOOLING_RUNBOOK.md) and [document update rules](MultiSceneSupport/TOOLING_RUNBOOK.md#documentation-reading-and-update-workflow). |
| Which thresholds and lessons remain fixed? | [Baselines](MultiSceneSupport/BASELINES.md) and [rejected approaches](MultiSceneSupport/REJECTED_APPROACHES.md). |
| What did reviews find and how were findings resolved? | [Safety review](MultiSceneSupport/PRODUCTION_SAFETY_REVIEW.md), [triage](MultiSceneSupport/REVIEW_TRIAGE.md), [component review](MultiSceneSupport/COMPONENT_REVIEW.md). |
| Where did superseded prose move? | [Documentation checkpoint](MultiSceneSupport/Experiments/DOCUMENTATION_CHECKPOINT_EXP-178.md); history cannot direct execution. |
