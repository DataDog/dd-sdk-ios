# Multi-scene RUM API proposal for iOS Guild review

**Status: proposed public API; review and approval are pending.** This document
presents the first stable API proposal for multi-scene ownership and semantic
SwiftUI navigation. Experimental implementation and validation support the design,
but these are not yet supported public APIs. This is a standalone companion to
the [executive summary](GUILD_EXECUTIVE_SUMMARY.md), prepared on September 21,
2026; status reviewed September 24, 2026. The
[stable API review](STABLE_API_REVIEW.md) owns the decisions and approval record.

The product behavior described below is the approved project direction. The
review asks us to agree on the public names, availability, integration contract,
compatibility and safety requirements before promoting the experimental surface.

**The customer problem has two parts: identifying the scene that produced work,
and identifying the committed destination within that scene.** Two independently
navigable windows must be able to keep their own current RUM views. A SwiftUI
screen's construction or appearance alone does not reliably identify a user's
visit, particularly across repeated navigation, sheets and dismissals.

The immediate delivery priority is unchanged behavior or improvements for an
existing app rebuilt with the iOS 27 SDK on iPhone Duo. Reliability fixes and
single-scene Duo readiness can ship separately from this proposed API. The new
surface belongs to the later full multi-scene release.

**The shared model is one current destination per scene within one application
RUM session.** Views from different scenes may overlap. Backgrounding a scene
ends only its visible view; foregrounding starts a fresh occurrence. Losing focus
while remaining visible does not end that view. Sidebars, split panes and tab
bars remain structural regions; modeling multiple current panes within one scene
is a separate project.

When no trustworthy source is available, generic work uses one process
representative, intended to be the last-interacted view. This fallback is best
effort and emits once. Scene identity remains internal ownership state. This
proposal introduces no separate scene sessions, temporary window attributes,
public RUM UUIDs, returned view handles or network-format changes.

**Manual views gain scene-taking overloads, and telemetry APIs share a
scene-current target.** These ordinary APIs are proposed across the SDK's
iOS 15+ range, with OS and capability checks inside the SDK. Customers can use one
integration without wrapping every call in an iOS 27 availability check. The
scene argument is required when choosing the new overload; existing calls remain
unchanged. All these additions are iOS-only.

The following review examples show the proposed call-site shape. Application
variables are illustrative. Ordinary declarations and fallback are implemented
provisionally at source `94842cc8ad7b`, with optimized iOS17.5/iOS27 client checks
recorded in [EXP-225](Results/EXP-225-api-availability.json). Swift still requires
experimental imports; Objective-C remains restricted to Debug or validation
builds. Public approval, normal Release exposure and final qualification remain
required before this proposal ships. Semantic SwiftUI APIs retain iOS27 guards.

~~~swift
// Inside the application's MainActor-isolated UI integration, on iOS 15+:
monitor.startView(key: "compose", name: "Compose", in: scene)
monitor.addTiming(
    name: "editor_ready",
    view: RUMViewTarget.current(in: scene)
)

// Later, when the manually tracked destination ends:
monitor.stopView(key: "compose", in: scene)
~~~

Where a family's enhanced scene behavior is unavailable, the SDK invokes the
equivalent existing RUM method exactly once. It preserves the event, attributes,
completion behavior and existing pairing; only the extra scene behavior is
absent. The choice uses OS, configuration and qualified capability before state
is mutated. Custom and NOP monitors retain their existing forwarding behavior.

This fallback preserves legacy inferred/process ownership. It does not guarantee
independent same-key views or exact scene attribution on every older system.
Each older-iPad improvement needs its own bounded ownership validation before
being enabled. Once qualified, it can benefit customers through an SDK update
without further instrumentation edits. The target value and its experimental
migration alias follow the same iOS 15+ availability proposal.

On a qualified scene-aware path, the same manual key can be active independently
in two scenes. A scene-targeted
start pairs with a stop for that same scene and key; mixing it with a source-less
stop is unsupported. Distinct manual keys may nest. Stopping the top manual view
reveals the latest accepted underlying destination as a fresh occurrence.
Automatic navigation may continue underneath it, but intermediate destinations
that never became current and visible produce no RUM view. Restarting an already
active scene/key remains instrumentation misuse and must remain crash-safe.

`RUMViewTarget.current(in:)` captures only the scene identifier on MainActor.
On a qualified scene-aware route, the SDK resolves that scene's live current
view when it processes the command.
The target does not retain UIKit objects, freeze a view UUID or provide access to
an ended view. If no live target resolves, independent inference and the
telemetry family's existing fallback still apply. Global monitor attributes
remain process-wide.

| API family | Ownership contract |
| --- | --- |
| One-shot Actions, errors, feature-flag evaluations, timings, view loading time and view attributes | Resolve the explicit scene-current target or use the applicable inferred/fallback path. |
| Continuous Actions | Targeted start and stop retain the family's existing pairing rules. A scene-current target is not a universal async-operation ownership handle. |
| Resource starts | Resolve ownership at start. Existing completion, error and metrics paths preserve that captured owner; they do not accept a new target. |
| Operations | Identity remains application-wide `(name, operationKey)`; scenes do not namespace it. Each start, success or failure resolves its own view context. A last-proven snapshot is a fallback, not permanent ownership by the start scene. |

Concurrent Operations must use distinct keys. Reusing an active Operation
identity tracks only the latest start locally; the SDK does not synthesize an
end for the earlier instance.

**Semantic SwiftUI tracking observes accepted navigation at the existing
router or container boundary.** A RUM view represents a committed navigation
occurrence. For example:

~~~text
Home, visit 1 -> Detail, visit 1 -> Home, visit 2
~~~

Returning to Home starts a new view occurrence even when the same platform view
or route value is reused. Cancelled or rejected transitions create no occurrence.
A sheet or full-screen cover becomes the current destination; dismissing it
reveals a fresh occurrence underneath. Immediate work from appearance, task
startup or dismissal must be attributed to the intended occurrence.

The proposed `RUMNavigationHost` accepts the application's existing navigation
as content. It does not own layout, gestures, animation, deep links or navigation
state. Customers retain `NavigationStack`, destination modifiers, `.sheet`,
`.fullScreenCover`, UIKit coordinators and custom or third-party navigation.
The host and its destination/metadata types remain iOS 27+; this amendment does
not backport the semantic engine.

| Host form | Intended use | What it can promise |
| --- | --- | --- |
| Content-only host | Wrap existing content without an exact accepted-state source. | Automatic compatibility and best-effort discovery; wrapping opaque navigation alone does not establish exact semantics. |
| Accepted-state Publisher host | Connect an existing router or a boundary adapter once. | Exact ownership when the source synchronously supplies accepted state with stable occurrence identity and the required timing. |
| Observation host | Read an existing observable router's accepted destination. | Exact ownership when one atomic accepted-state property is read synchronously, without side effects. Requires iOS 27+ and compiler 6.4+. |

An accepted-state Publisher integration can look like this:

~~~swift
// Inside the application's MainActor-isolated SwiftUI integration.
// acceptedStates and currentRUMDestination are application-owned projections.
if #available(iOS 27.0, *) {
    RUMNavigationHost(
        observing: router.acceptedStates,
        destination: { $0.currentRUMDestination },
        metadata: .automatic
    ) {
        ExistingApplicationNavigation(router: router)
    }
} else {
    ExistingApplicationNavigation(router: router)
}
~~~

The integration should scale with independent routers or containers, not the
number of screens, routes, sheets or navigation methods. A third-party router
need not directly expose Combine or Observation: one adapter can translate its
existing synchronous accepted-state callbacks into a Publisher. It must preserve
the source across SwiftUI reconstruction and avoid repeated registrations.

The exact-source contract is:

- Supply the current accepted state synchronously when the host attaches. Waiting
  for a descendant task is too late to guarantee initial appearance ownership.
- Publish accepted commits before immediate lifecycle work. A proposed transition
  or eventual render-time observation is insufficient.
- Distinguish separate occurrences of equal route values when the router permits
  them. In-memory occurrence tokens are application identities, not RUM UUIDs.
- For the Observation form, project from one atomically updated accepted-state
  property. Separate property writes are separate commits; the SDK does not
  invent a transaction across them.
- Keep the source stable and maintain one subscription per container. An empty
  configured source does not seize semantic authority or silently select another
  source.

The Observation form is additionally guarded by `#if compiler(>=6.4)` and
`#available(iOS 27.0, *)`. With an older compiler on iOS 27, an accepted-state
Publisher can be used when available. Earlier operating systems retain existing
automatic/manual tracking. Opaque local `@State` and late callbacks retain
best-effort tracking or sparse manual exceptions.

Semantic authority begins only after an accepted destination materializes. It is
local to that exact container, suppresses its duplicate automatic view, and
releases at final teardown. Automatic tracking continues in unrelated containers
and scenes. Construction of an aborted or preloaded container alone must not
create a tracked occurrence.

**Metadata is automatic by default, with sparse optional overrides.** Destination
types and enum cases supply names. Associated values, occurrence tokens and scene
identifiers are not automatically serialized. An exhaustive per-route business
name resolver is optional and must not become a requirement for correct tracking.

**The validation explains why the proposal requires these boundaries.** These
findings come from the experimental implementation and focused application
journeys. They support API review; the final shipped implementation must pass its
own compatibility and release checks.

| Investigation | What was exercised and uncovered | Consequence for the API |
| --- | --- | --- |
| Scene-aware manual views | Manual start/stop journeys exercised matching scene/key pairs, nested manual views and fresh underlying occurrences. Native physical-iPad tiled-window evidence also established same-key isolation in the exercised topology. | Keep explicit scene/key pairing and distinguish physical simultaneous visibility from serial scene tests. |
| Existing-router integration | A host around unchanged navigation followed Home, Detail, return, sheet and cover journeys. Local and backend events verified distinct occurrences, downstream ownership and no duplicate automatic view. | Prefer one accepted-state boundary integration with automatic metadata. |
| Render-time destination input | Reading only the destination at a later render produced the right eventual navigation sequence, but immediate dismissal Actions and Resources still belonged to the outgoing presentation. | Do not expose a plain render-time destination value as an exact tracking contract. |
| Synchronous Observation | Observing the accepted stored state during mutation attributed immediate dismissal work to the fresh underlying occurrence. Real sheet and cover dismissal callbacks were checked separately. | Require a synchronous, side-effect-free projection from atomic accepted state and the corresponding compiler guard. |
| Third-party navigation adapter | A stable adapter seeded current state and subscribed once to synchronous accepted callbacks, preserving ownership without editing every navigation method. | Use the accepted-state Publisher as the stable adapter boundary. |
| Initial state and reconstruction | Checks covered empty input, reconstruction, teardown and local automatic/semantic authority. A late initial value cannot guarantee ownership of earlier lifecycle work. | Keep stable sources, synchronous initial state and authority limited to accepted materialized destinations. |
| Monitor compatibility and Objective-C | EXP-225 exercises built-in, custom and NOP forwarding plus optimized main/off-main Objective-C clients under DD_SCENE_API_VALIDATION. It qualifies provisional fallback and guarded entry safety, with normal Release declarations still hidden. | Approve the safety contract and verify normal-import clients and the public Objective-C header before promotion. |

Duo simulator results cover exercised geometry, lifecycle and attribution.
Physical iPhone and iPad evidence complements those checks, but physical Duo
acceptance and the remaining concurrent-window, restoration and interactive
lifecycle combinations remain separate obligations. There is no simulator-to-
hardware equivalence claim.

**The public review has eight decisions.**

| Decision | Proposed first stable release | Required disposition |
| --- | --- | --- |
| Availability | Ordinary scene-taking calls, target/alias and Objective-C companions are callable on iOS 15+, with SDK-owned fallback. Semantic host/destination/metadata APIs remain iOS 27+; Observation also requires compiler 6.4+. All additions are iOS-only. | Compile unguarded ordinary callers targeting iOS 15; test older-runtime fallback and qualify each older-iPad scene capability before enabling it. Keep semantic client guards. |
| Target shape and names | Promote `RUMViewTarget.current(in:)` and the 21 Swift overloads below, keeping the `view:` argument required. Keep `RUMOperationViewTarget` as an experimental migration alias. | Approve naming and breadth. No additional inferred, manual-key or controller target factories are proposed. |
| Public protocol compatibility | Add extension-only overloads using existing private built-in capabilities. Custom/NOP conformers call their existing inferred method once. | Verify external conformers without new protocol requirements, recursion or a changed shared-monitor return type. Exact custom scene targeting is not promised. |
| Objective-C | Promote the 20 targeted selectors and `DDRUMViewTarget.currentInScene:`, with the nullable factory and safe off-main behavior described below. | Approve the safety contract and validate a Release client. The Swift Error completion overload remains Swift-only. |
| Semantic host | Promote the content-only, accepted-state Publisher and Observation initializers, `RUMNavigationDestination` and `RUMNavigationMetadata`. | Approve the source contract and clearly document opaque-container limitations. |
| Adapter boundary | Keep low-level transition/capability types, the transitions initializer, `RUMNavigationStack` and its presentation types experimental. | Confirm the Publisher host as the first stable third-party adapter boundary. |
| Metadata and lifetime | Automatic metadata, sparse overrides, no automatic serialization of associated values/tokens/scene IDs, and container-local authority after accepted materialization. | Confirm privacy, source stability, authority and teardown rules. |
| Migration and ownership | Existing APIs/defaults remain available. Exact semantic integration is optional. Manual views pair by scene/key; Resources capture ownership at start; each Operation step resolves context. | Approve the migration contract and validate it in client fixtures and documentation. |

Approval of the proposal remains pending. Product direction and experimental
passes do not substitute for an attributable RFC decision.

**Objective-C needs an approved safe entry contract before Release exposure.**
The provisional entry shims at source `94842cc8ad7b` check the calling thread
before entering actor-isolated Swift code or accessing UIKit. EXP-225 qualifies
optimized main/off-main clients on iOS17.5 and iOS27 under the validation flag.
The normal Release header still hides these declarations.

The proposal is to check the calling thread before entering actor-isolated Swift
code or accessing UIKit, as implemented provisionally. The factory returns `nil`
off-main with a nullable Objective-C result. Invalid off-main targeted calls return
safely, without synchronously dispatching to main, retaining the scene, deferring a UIKit
read or silently targeting another view. Valid main-thread calls preserve the
qualified targeted behavior or the documented legacy fallback; being on an older
OS is not invalid usage. Swift factories and overloads remain MainActor-isolated.

A Release client must verify factory, manual-view and telemetry calls both on
and off main: no SDK trap or deadlock, no invalid UIKit access or retention,
no foreign telemetry and exactly-once valid custom/NOP fallback. The nullable
factory changes the experimental shape and needs explicit reviewer agreement.

**The stable API review owns the declaration inventory.** Review the
[21 Swift overloads and target factory](STABLE_API_REVIEW.md#swift-target-surface),
[20 Objective-C selectors and factory](STABLE_API_REVIEW.md#objective-c-selector-inventory),
and [semantic host, destination and metadata APIs](STABLE_API_REVIEW.md#stable-semantic-host-proposal)
there. Those inventories preserve signatures, defaults and the source revision;
this Guild document keeps the design decisions and adoption examples.

Ordinary additions are proposed as iOS-only and iOS15+, matching the provisional
implementation at `94842cc8ad7b`. Semantic APIs retain iOS27 guards, with
compiler>=6.4 additionally required for Observation. The host's `in:` argument
selects the Datadog SDK core, not a UIWindowScene. Public approval remains pending.

**Adoption is optional and depends on the application's existing navigation.**

| Existing integration | Expected adoption work | Compatibility requirement |
| --- | --- | --- |
| Ordinary single-scene automatic/manual app | Keep its current setup and API calls. | Preserve ordinary behavior and older-system paths. |
| New ordinary scene-taking calls | Use the same overloads on iOS 15+, without a caller iOS 27 branch. | Keep start/stop routing coherent, preserve legacy fallback once, and enable exact older-iPad behavior only after qualification. |
| Native multi-scene UIKit | Keep automatic tracking; optionally target exceptional manual views or telemetry. | Preserve peer scenes and the scene/key lifecycle. |
| Existing observable router | Add one host and destination projection per independent boundary. | Keep navigation and presentation code; avoid per-screen instrumentation. |
| Third-party router/coordinator | Add one stable accepted-state Publisher adapter. | Require synchronous accepted state and callbacks for exact semantics; avoid retroactive conformance. |
| Opaque SwiftUI/local state | Keep automatic tracking and optional manual exceptions. | Explain structural naming and timing limitations. |
| Custom monitor or NOP | Keep existing conformance. | Forward once to the existing method; do not promise custom scene targeting. |
| Experimental consumer | Move only approved calls to the stable import after promotion. | Retain experimental imports for types deliberately kept experimental. |

**Release requires review, implementation and independent acceptance.**

| Deliverable | Owner | Dependency | Decisive result and environment |
| --- | --- | --- | --- |
| Approve or amend the eight API decisions | RUM API reviewers | Proposed behavior and documented findings | Recorded RFC approval and cross-platform alignment. |
| Expose the approved declarations and safe Objective-C bridges | SDK implementer | Recorded API decision | Matching declarations and positive/negative forwarding and thread-safety checks in Xcode, simulator and an Objective-C Release client. |
| Verify customer compatibility | SDK implementer and compatibility reviewers | Approved exposure | Normal imports, external conformers and unguarded ordinary Swift/Objective-C clients targeting iOS 15 work. Semantic clients retain their OS/compiler guards; older-runtime fallback preserves behavior once. |
| Qualify optional older-iPad scene behavior before enabling it | SDK implementer and ownership reviewers | A selected capability is proposed for enablement; compatible call sites | On iPadOS 17.5, check same-key A/B manual views and reverse stops, current-view events and delayed Resource completion after navigation. Enable only qualified families; other families retain fallback. |
| Publish API baselines and integration guidance | SDK implementer and documentation reviewers | Reviewed declarations | Reviewed generated API diff and compiling customer examples. |
| Qualify the actual release candidate | Release and validation owners | Selected production source plus the checks above | Remaining ownership/lifecycle scenarios, representative application performance, required hardware and final source/build acceptance. |

The SDK's iOS 15 deployment compatibility remains required. Available runtime
execution starts at iOS 17.5; compiling for iOS 15 must not be described as an
iOS 15 runtime test. Physical Duo acceptance belongs to full multi-scene release
qualification. API approval alone does not close those checks.

Application-visible frame rate, hitches, CPU, memory and retained-state behavior
must be evaluated for the changes selected for release. Session Replay is in
scope only for host crash safety and coexistence with other SDK features;
captured-content correctness is outside this proposal.

True multi-pane tracking, backend Window Execution Context serialization, extra
target factories and new dependencies remain separate work. API promotion does
not include unrelated internal extraction.

**Feedback is most useful on these points:** whether scene-current targeting is
clear enough to distinguish from captured start ownership; whether accepted-state
integration is practical for customer routers; and whether the proposed public
surface, Objective-C safety and availability rules provide a small, compatible
first release.

Supporting material: [product behavior](../MULTI_SCENE_SUPPORT.md),
[detailed navigation contract](NAVIGATION_API.md),
[Operation semantics](OPERATIONS.md),
[integration guide](SUPPORT_GUIDE.md),
[current validation assessment](ASSESSMENT.md), and
[internal API review source](STABLE_API_REVIEW.md). These documents retain the
engineering history; this review is intended to stand on its own.
