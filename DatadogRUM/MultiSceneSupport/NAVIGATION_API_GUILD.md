# RUM navigation design for iOS Guild review

**Status: product direction approved; public API and release qualification
pending.** This document explains scene-aware manual views and optional semantic
SwiftUI navigation without requiring knowledge of the investigation history.
It accompanies the [Guild API review](STABLE_API_REVIEW_GUILD.md). The
[stable API review](STABLE_API_REVIEW.md) owns the complete declaration inventory. Prepared September 21, 2026;
status reviewed September 24, 2026. The [navigation contract](NAVIGATION_API.md)
owns the detailed behavior; this document is its standalone Guild presentation.

The proposal is backed by an experimental implementation and focused application
validation. Examples below illustrate the proposed API, not currently supported
public declarations. Reliability fixes and single-scene iPhone Duo readiness
remain separate delivery steps; adopting this navigation API is not a prerequisite
for those improvements.

**The goal is to track what the user actually navigated to, with the correct
scene and occurrence owning the resulting work.** Automatic SwiftUI tracking
remains the default. Exact semantic tracking is an optional integration at an
existing router or container boundary. Customers keep their navigation,
presentation APIs and application state.

Three distinctions determine the design:

| Concept | Meaning |
| --- | --- |
| Scene | An independently navigable application window. Different scenes can have overlapping RUM views within one application session. |
| Destination | The scene's currently accepted screen or presentation. Each scene has one current destination; sidebars, split panes and tab bars are structural regions. |
| Occurrence | One committed visit to a destination. Returning to a retained screen creates a fresh RUM view occurrence without resetting the application's view state. |

For example:

~~~text
Home, visit 1 -> Detail, visit 1 -> Home, visit 2
~~~

These are three distinct RUM views. Two equal Detail route values can also
represent different visits. A cancelled transition retains the prior occurrence.
A proposed push immediately reverted before commitment creates no speculative
view.

Backgrounding one scene ends only that scene's visible view; foregrounding starts
a fresh occurrence. Losing focus while remaining visible does not end it.
Generic work with no trustworthy source retains a documented process-level
fallback, intended to use the last-interacted view. It emits once and is not an
exact scene-ownership guarantee.

**The host observes existing navigation through a trustworthy accepted-state
signal.** Accepted state means the destination the application's navigation
actually committed to, including rejection or normalization of a requested
change. Merely seeing the requested route or a later rendered value is
insufficient for exact attribution.

~~~mermaid
flowchart LR
    router["Existing router or coordinator"] --> state["Accepted navigation state"]
    state --> host["RUMNavigationHost"]
    content["Existing navigation and presentation UI"] --> host
    host --> engine["Scene-scoped semantic engine"]
    engine --> views["RUM view occurrences"]
~~~

The host accepts arbitrary customer content. The engine handles scene ownership,
committed occurrences, presentations, return visits and local suppression of
duplicate automatic tracking. Layout, gestures, animations, deep links and
navigation state remain owned by the application.

The integration should scale with independent flows. For a 100-screen app with
10 independent routers, the intended cost is roughly 10 boundary integrations.
It must not require RUM calls in every navigate, pop, present or dismiss method,
or additional tracking code whenever a route is added. Customers need not create
a Datadog router or consolidate local presentation state solely for RUM.

**The proposed stable host has three entry points.**

| Entry point | Intended integration | Precision requirement |
| --- | --- | --- |
| `RUMNavigationHost(in:content:)` | Wrap content without providing an exact source. | Automatic compatibility and best-effort discovery. Wrapping an opaque stack does not by itself provide exact semantics. |
| `RUMNavigationHost(observing:destination:metadata:in:content:)` | Observe an existing accepted-state Publisher or a third-party adapter. | Synchronous initial state, accepted commits early enough for immediate lifecycle work, and stable occurrence/source identity. |
| `RUMNavigationHost(observingCurrentDestination:metadata:in:content:)` | Observe an existing observable router's accepted destination. | A side-effect-free projection from one atomically updated accepted-state property; iOS 27+ and compiler 6.4+. |

The semantic host and its destination/metadata types remain iOS-only and proposed
for iOS 27 and later. Ordinary scene-taking monitor APIs are separately proposed
across the SDK's iOS 15+ range, with platform checks and legacy fallback inside
the SDK. This amendment does not backport the semantic host.
Examples assume a MainActor-isolated iOS integration; application variables and
projection methods are illustrative. Experimental imports remain necessary
until the approved public exposure is implemented.

**An existing accepted-state Publisher is the main adapter boundary.**

~~~swift
if #available(iOS 27.0, *) {
    RUMNavigationHost(
        observing: router.acceptedStates,
        destination: { state in state.currentRUMDestination },
        metadata: .automatic
    ) {
        ExistingApplicationNavigation(router: router)
    }
} else {
    ExistingApplicationNavigation(router: router)
}
~~~

Here, `acceptedStates` and `currentRUMDestination` belong to the application
or its boundary adapter. The Publisher has `Output == State` and
`Failure == Never`; its destination projection is MainActor-isolated.
The projection identifies a root, route or presentation. It does not require an
exhaustive business-name mapping.

An exact source must meet these requirements:

- Synchronously provide the current accepted destination when the host attaches.
  Emitting it from a descendant task arrives too late to guarantee ownership of
  initial appearance work.
- Emit accepted commits before immediate destination work can run. A proposed
  Binding write is not sufficient when the application's setter can reject or
  normalize it.
- Distinguish separate committed occurrences of equal route values when the
  router permits them. An occurrence token is an in-memory application identity,
  never a public RUM UUID or serialized attribute.
- Keep the source stable across SwiftUI view-value reconstruction. One container
  retains one subscription; rebuilding a view must not replay the active visit.
- Preserve the selected source. A newly computed capability must not silently
  replace it and disconnect or restart the current occurrence.

A configured source with no initial value does not acquire semantic authority
and does not silently switch to a different source. Automatic tracking remains
available until a trustworthy destination can materialize. Its later arrival
cannot retroactively establish exact ownership for earlier work.

**The Observation form is available for an existing atomic accepted-state
property.**

~~~swift
#if compiler(>=6.4)
if #available(iOS 27.0, *) {
    RUMNavigationHost(
        observingCurrentDestination: {
            destination(for: router.state)
        },
        metadata: .automatic
    ) {
        ExistingApplicationNavigation(router: router)
    }
} else {
    ExistingApplicationNavigation(router: router)
}
#else
ExistingApplicationNavigation(router: router)
#endif
~~~

The prototype uses synchronous observation of the accepted stored value during
mutation and rearms before the setter returns. This is what allows the revealed
destination to own immediate work after a dismissal.

The projection must read one atomically updated property and have no side effects.
If route and presentation live in independently mutated properties, each write
is a separate commit and intermediate combinations are observable. The SDK does
not create a transaction across those writes.

The fallback shown above keeps the existing integration. An accepted-state
Publisher is another option on iOS 27 when the compiler cannot build the
Observation form. Plain local SwiftUI state and callbacks delivered at a later
suspension point do not satisfy this exact-source contract.

**Third-party navigation can adapt at the same boundary.** A library does not
need to expose Combine or Observation itself. A reusable adapter can:

1. Read the library's current accepted snapshot synchronously.
2. Register once for its existing synchronous committed-state callbacks.
3. Translate route and presentation identities into semantic destinations.
4. Feed the accepted-state Publisher host while preserving normal container code.
5. Release the subscription when the boundary is finally destroyed.

This requires trustworthy callbacks early enough to precede immediate customer
work. If the library only provides a late notification, the integration must
retain automatic best-effort tracking or manual exceptions. Exact support must
not be claimed by reconstructing unavailable state.

The first stable proposal does not require retroactive conformance of imported
navigation types. Low-level transition publishers, container capabilities and
the native `RUMNavigationStack` convenience remain experimental. The accepted-
state Publisher host is the proposed stable adapter interface.

**Names and route identity must not become an instrumentation burden.**

`RUMNavigationDestination` describes roots, routes and presentations.
`RUMNavigationMetadata.automatic` derives usable metadata from types and enum
cases; sparse overrides can supply business names or paths. Associated values,
occurrence tokens and scene identifiers are not automatically serialized.
Customers may choose exhaustive custom naming, but it is not required for
correct tracking.

Occurrence identity must remain separate from the customer's route type and
SwiftUI view identity. An early repeated-route approach wrapped route values in
a private type; that broke ordinary `NavigationLink(value:)` and
`navigationDestination(for:)` matching. The design preserves the customer's
route values and keeps RUM occurrence identity inside the tracking boundary.

Typed paths or existing routers may supply semantic order directly. This
proposal does not promise arbitrary introspection of opaque `NavigationPath`
content or require customers to convert their path representation. A trustworthy
router, coordinator or adapter signal is needed where navigation state is opaque.

If partial semantic coverage is exposed, the API must distinguish “allow
automatic tracking here” from “intentionally produce no destination.” An
ambiguous optional resolver must not give both meanings to `nil`.

**Presentation transitions follow the same occurrence model.**

| Accepted navigation | Required RUM behavior |
| --- | --- |
| Home -> Sheet -> Home | One Sheet occurrence and a fresh Home occurrence after dismissal. |
| Home -> full-screen cover -> Home | The same ownership rule, validated independently from sheets. |
| Sheet -> Cover -> Sheet while Home stays hidden | Distinct presentation occurrences, with no intermediate Home view. |
| Final dismissal of that presentation sequence | One fresh underlying Home occurrence. |
| Rejected presentation write or uncommitted same-turn proposal | Preserve accepted state and create no speculative presentation view. |
| Cancelled interactive transition | Preserve the existing occurrence; successful completion follows the fresh-return rule. |

Customers retain `.sheet`, `.fullScreenCover`, UIKit presentation APIs and
custom overlays. The SDK does not introduce a corresponding family of
Datadog-specific presentation modifiers.

A fresh occurrence must be established in time for work that semantically belongs
to the revealed destination. Actual native `onDismiss` callbacks were checked
separately from state-level tests. Those checks showed that the synchronous
accepted-state signal had already established the fresh owner before callback
entry. They do not make `onDismiss` itself a universal commit signal.

**Semantic authority and manual exceptions are local.** Authority means that a
tracking boundary owns the semantic view and suppresses its duplicate automatic
view. It starts only after an accepted destination can materialize. Constructing
a preloaded or abandoned container is not enough.

Automatic discovery must remain eligible in unrelated controller subtrees and
other scenes. Those containers still participate in the one-current-destination
policy within their own scene. Proof of local authority requires observing the
actual controller branches; a missing or collapsed test topology is inconclusive.

An explicit manual exception owns its tracked occurrence. Navigation may continue
beneath it, but only the latest accepted underlying destination is eligible when
the exception ends. Hidden intermediate destinations produce no RUM views.
Returning from the exception creates a fresh occurrence.

**Scene-aware manual views make that exception explicit.**

The amended ordinary API is callable on iOS 15+ without a customer iOS 27 branch.
This proposed public shape is implemented provisionally at source `94842cc8ad7b`.
[EXP-225](Results/EXP-225-api-availability.json) qualifies its iOS15 declarations
and older-runtime fallback using experimental imports/validation builds. Public
approval, normal Release exposure and final owner qualification remain pending.

~~~swift
// Start from the application's MainActor-isolated UI boundary.
monitor.startView(key: "compose", name: "Compose", in: scene)

// Later, stop from the corresponding UI boundary.
monitor.stopView(key: "compose", in: scene)
~~~

The required `in:` argument identifies the scene on the new overloads.
Existing source-less methods retain their inferred behavior. An attached view
controller already supplies its scene, so this first proposal does not add
potentially contradictory controller-plus-scene overloads.

The SDK selects the qualified path by OS, configuration and capability before
mutating view state, keeping the start/stop pair coherent. When scene behavior is
unavailable, it invokes the equivalent existing method exactly once with the
same attributes. Ordinary telemetry targets use the same approach, preserving
completion behavior and each family's existing ownership rules. An older OS
must not turn a valid event into a no-op.

Legacy fallback retains inferred/process ownership; it does not promise
independent same-key A/B views. Exact older-iPad support must be qualified by
family before being enabled. The same customer integration can then benefit
from an SDK update without another instrumentation edit.

On a qualified scene-aware path, the pairing rules are:

- The same key can be active independently in two scenes. Stopping one must
  preserve the other.
- A targeted start pairs only with a targeted stop for the same scene and key.
  A legacy stop must not search all scenes for a matching key.
- Distinct manual keys can nest. Ending Preview above Compose starts a fresh
  Compose occurrence, then ending Compose reveals a fresh underlying destination.
- Repeating an already active scene/key is instrumentation misuse. The SDK
  remains crash-safe without adding restart, reference-counting or handle rules.
- Stop-call attributes belong to the stopped manual occurrence.
- Closing a scene or ending its manual view must not affect a visible peer.

Simply adding a scene identifier to the old direct keyed command proved
insufficient. Automatic appearances could immediately preempt the manual view,
and a direct stop could not reliably restore the underlying semantic destination.
The experimental implementation routes targeted manual entries through the
shared per-scene view handler, which retains the latest accepted underlying
destination through structural SwiftUI changes.

Only the scene's identifier is captured on MainActor. UIKit objects are released
before work crosses to the RUM queue. The first stable proposal uses public
extension overloads backed by a private built-in capability. Existing external
and NOP monitor conformers retain their protocol requirements and invoke the
legacy method once; they cannot promise exact targeting without that capability.

The Objective-C companion shares the proposed iOS 15+ callability and internal
fallback. It uses
`startViewWithKey:name:inScene:attributes:` and
`stopViewWithKey:inScene:attributes:`. EXP-225 exercises these selectors and
main/off-main handling in optimized clients with `DD_SCENE_API_VALIDATION`.
Approval of the safety contract, normal Release exposure and public-client
verification remain required, as described in the
[Guild API proposal](STABLE_API_REVIEW_GUILD.md).

**Exact navigation does not make every later asynchronous callback causal.**
On a qualified scene-aware route, a scene-current telemetry target resolves the
live view when its command is processed; it is not a snapshot of the occurrence
that created the target.
Resources and automatic Traces preserve their captured start owner. Source-less
work with no surviving trustworthy context retains its documented fallback.

Validation therefore distinguishes work that runs while a manual view is
authoritative from work after its exact stop. A delayed callback that can cross
that boundary cannot be assigned a fixed expected owner unless its timing or
captured provenance is established.

**The investigation established both working behavior and useful failure cases.**
The following findings describe what was exercised, what was learned and the
remaining limits. They are evidence from the experimental implementation, not
blanket certification of a future release candidate.

| Investigation | Finding | Design or validation consequence |
| --- | --- | --- |
| Manual and automatic coexistence | Direct keyed commands allowed an automatic fallback to preempt the manual view. Shared scene-stack routing preserved manual ownership and revealed the correct fresh underlying destination. | Test the whole manual interval and immediate post-stop work, not just successful start/stop calls. |
| Nested manual views | Compose -> Preview -> fresh Compose -> fresh underlying view worked with distinct occurrences and exact downstream owners. Duplicate active-key instrumentation remained crash-safe. | Retain nesting and pairing checks without introducing public handles. |
| Repeated equal routes | A run initially passed 22 checks because its marker executed after the fresh view had started. Stronger assertions exposed appearance work still attributed to the previous occurrence. | Verify ownership at callback entry as well as final distinct IDs. The earlier pass is not acceptance evidence. |
| Restored paths | Some real-device runs had correct final ownership while deterministic callback permutations still exposed bootstrap and replacement-reader faults. | Combine application journeys with ordering, reconstruction and disconnect controls. A clean single run is insufficient. |
| Arbitrary host and existing router | The shared engine reproduced navigation and presentation semantics around unchanged content. A boundary integration required no screen or navigation-method edits; adding routes did not grow RUM-specific instrumentation. | Keep the host independent of navigation UI and metadata automatic by default. |
| Render-time destination value | Final navigation looked correct, but immediate sheet and cover dismissal work belonged to the outgoing presentation. | Reject a plain render-time destination value as an exact API. |
| Synchronous Observation and native dismissal | Atomic accepted-state observation assigned immediate dismissal work to fresh revealed occurrences. Separate native callback checks confirmed the accepted owner existed before callback entry. | Keep the early accepted-state signal and the native callback check as separate requirements. |
| Third-party callback adapter | One stable registration delivered initial and accepted state through the existing Publisher host with correct local/backend ownership. | Support adapters at a single existing boundary without per-method RUM calls or a new public input primitive. |
| Host reconstruction and source lifetime | Focused checks covered repeated reconstruction, attempted source replacement, local automatic coexistence and posted disconnect cleanup. | Pin the source, prevent duplicate subscriptions and distinguish transient detachment from final teardown. |
| Scene and sibling isolation | Serial native-scene journeys and witnessed sibling controller branches established scoped ownership in those configurations. Later physical-iPad checks added same-key tiled manual isolation and settled semantic/automatic coexistence. | Keep those precise scopes. They do not establish every simultaneous, interactive, reconnect or physical Duo combination. |

Local event observations and backend ownership checks were used together.
Assertions include exact occurrence identity, immediate/settled ownership,
absence of duplicate automatic views, peer continuity and bounded lifetime.
Passing counts, delivered callbacks and absence of crashes cannot establish
those semantics by themselves.

**The remaining acceptance work is grouped by behavior.** This summarizes the
existing obligations for the actual release source; it does not introduce an
experiment quota or declare every row complete.

| Area | Decisive checks | Required setting |
| --- | --- | --- |
| Occurrence identity | Fresh return visits; equal routes; rejected or normalized writes; cancellation without speculative views; preserved application state. | Deterministic ordering tests and native application journeys. |
| Lifecycle ownership | Root, route, modal and retained-return work uses the intended owner at the critical callback boundary. | Native callbacks plus local events and backend ownership. |
| Presentations | Sheets and covers independently; atomic replacement without a hidden underlying view; fresh reveal before immediate dismissal work. | Native programmatic journeys and remaining interactive device scenarios. |
| Manual exceptions | Same key across scenes, reverse stops, nested keys, stop attributes, underlying commits and safe misuse; no foreign scene mutation. | Unit/integration controls and witnessed multi-window topology. |
| Authority and lifetime | No duplicate or global suppression; stable source/subscription; teardown, scene reconnect, restoration and session rollover preserve only eligible state. | Deterministic lifetime controls plus real OS lifecycle scenarios. |
| Customer compatibility | Automatic-only, source-less, single-scene and legacy paths; external/NOP conformers; unguarded ordinary Swift/Objective-C calls targeting iOS 15 and exactly-once fallback. Keep semantic-host OS/compiler guards. | Release client builds and available older-system runtime tests. |
| Before enabling optional older-iPad scene support | Qualify manual A/B ownership and reverse stops, current-view events and delayed Resource completion after navigation before enabling each enhanced family; preserve legacy behavior elsewhere. | Bounded iPadOS 17.5 multi-window checks with exact ownership assertions. |
| Application impact | Representative frame rate, hitches, CPU, memory and retained-state behavior for the included production changes. | Controlled before/after application measurements and appropriate physical devices. |
| Stable exposure | Approved names, availability, adapter boundary, metadata/privacy behavior, client examples and API baselines. | Recorded RFC decision, review and release qualification. |

The SDK must remain compatible with its iOS 15 deployment target. The available
older runtime is iOS 17.5; deployment compilation is not an iOS 15 runtime test.
Duo simulator evidence supports the exercised geometry, lifecycle and ownership
logic. Physical Duo behavior and remaining hardware-sensitive combinations
require separate acceptance; no percentage of simulator-to-device equivalence
is claimed.

**The current public recommendation is deliberately bounded.** Promote the three
host forms and destination/metadata types on iOS 27+, and ordinary scene-aware
targeting across iOS 15+ with internal fallback, after recorded API approval and
release qualification. The provisional implementation does
not close those requirements.
Keep `RUMNavigationTransitions`, `RUMNavigationTransitionProviding`, the
transitions host initializer, `RUMNavigationStack` and its presentation helpers
experimental. The native convenience established useful feasibility evidence,
but it is not the proposed required customer integration.

No public RUM UUIDs, returned view handles, additional scene sessions, temporary
window attributes or wire-format changes are introduced. True multi-pane
tracking and backend window visualization remain separate work. Session Replay
is limited to host safety and coexistence with other SDK features, not captured-
content correctness.

**The Guild feedback requested is concrete:**

- Can the routers our customers use provide accepted state at the required
  boundary, without widespread instrumentation or navigation rewrites?
- Is the distinction between automatic best effort and exact accepted-state
  tracking clear enough to communicate and support?
- Are fresh return occurrences, equal-route identity and local authority
  understandable from the proposed API?
- Are the Publisher and atomic Observation forms sufficient for a first stable
  release, with low-level and native convenience APIs remaining experimental?
- Are the availability, custom-monitor fallback and Objective-C safety rules
  compatible with the clients we need to support?

Supporting material: [Guild API review](STABLE_API_REVIEW_GUILD.md),
[product contract](../MULTI_SCENE_SUPPORT.md),
[current validation assessment](ASSESSMENT.md),
[current navigation contract](NAVIGATION_API.md),
[design and experiment history](Experiments/NAVIGATION_API_HISTORY.md), and
[recorded design lessons](REJECTED_APPROACHES.md).
