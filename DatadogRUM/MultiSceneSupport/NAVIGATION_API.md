# RUM multi-scene navigation API proposal

Read this document when reviewing the optional SwiftUI semantic-navigation
integration or scene-aware manual view APIs. The product behavior is approved;
the concrete public API is not. The [canonical overview](../MULTI_SCENE_SUPPORT.md)
owns the support verdict, [PLAN.md](PLAN.md) owns delivery order, and
[EXPERIMENTS.md](EXPERIMENTS.md) owns runtime evidence.

Last updated: 2026-09-16

## Status

The scene-targeted manual view proposal is implemented and exercised as an
iOS 27 experimental Swift SPI, with Debug-only Objective-C counterparts. The
prototype validates customer call sites, exact selectors, custom/NOP fallback,
and runtime usefulness before normal API and RFC review. `EXP-137` through
`EXP-140` cover automatic Home → manual/presentation → fresh Home using the
customer-shaped overloads. Do not promote these declarations to the supported
public API surface until review approves their names, availability, protocol
behavior, and Objective-C exposure. The native-convenience SwiftUI container is
also implemented as an iOS 27 experimental Swift SPI. `EXP-141` validates its complete
Home → Detail → Home → Sheet → Home → full-screen-cover → Home stream locally and
in backend intake while automatic tracking remains enabled. Examples below are
the exercised review starting point, not settled signatures. `EXP-142`-`144`
then close repeated equal routes, external router/restoration behavior, and
direct Sheet ↔ Cover replacement without an intermediate underlying view;
`EXP-145` closes its actual-SPI sibling authority boundary.

Revised product constraints supersede the assumption that this
`RUMNavigationStack` shape should be the main customer API. It remains valuable
proof and may remain an optional native convenience, but exact multi-scene
support must also accept arbitrary customer-owned navigation containers through
a container-independent host, optional type-erased capability, or explicit
transition source/adapter. Standard navigation and presentation code must remain
standard.

`EXP-146` validates the shared engine and adapter-author boundary. Its explicit
`RUMNavigationTransitions` publisher is a deterministic harness adapter, not the
accepted normal customer integration. `EXP-147` now validates a low-cost
existing-router candidate: one subscription and one outer boundary, zero screen
or navigation-method edits, automatic metadata with one sparse override, and no
RUM-code growth when a route and presentation are added. `EXP-148` moves generic
state observation, occurrence identity, automatic metadata, sparse overrides,
and delayed authority into the SDK-owned iOS 27 prototype. Its final frozen run
passes the same 38/38 local/backend oracle. This validates an experimental
existing-router path, not stable public names. `EXP-149` closes deterministic
host reconstruction and scene-local source lifetime. `EXP-150` rejects a plain
render-time destination value, `EXP-151` accepts one-shot Observation `.didSet`
over one atomic accepted-state property, and `EXP-152` confirms actual native
Sheet/Cover `onDismiss` callbacks then use the fresh revealed occurrences.

The approved behavior is:

- automatic SwiftUI tracking remains the zero-code default;
- exact SwiftUI navigation may be installed once per independent navigation
  container or router without replacing the customer's container, route model,
  destination modifiers, sheets, or covers;
- usable metadata is automatic by default; optional custom naming is centralized
  and sparse rather than repeated in destinations;
- one committed navigation occurrence creates one RUM view ID, so
  Home H1 -> Detail D1 -> Home H2 uses three distinct IDs;
- a semantic container or exceptional manual view is authoritative only within
  its target and suppresses only its duplicate automatic view;
- navigation may continue beneath manual authority, but only the latest committed
  underlying destination can be revealed and it starts as a fresh occurrence;
- different manual keys may nest, while re-starting an active `(scene, key)` is
  instrumentation misuse and receives only crash-safe handling;
- targeted starts pair only with targeted stops for the same scene and key;
- the shared engine accepts exact presentation transitions when a trustworthy
  source exposes them, while ordinary sheets and full-screen covers remain
  unchanged and automatic tracking supplies the opaque-container fallback;
- each scene has one current destination; structural panes and tabs are not
  parallel RUM views;
- the same manual key can be active independently in different scenes; and
- no public API accepts a RUM UUID, serializes a scene identifier, or introduces
  an interim window attribute or session boundary.

Customer integration cost must scale with containers or routers, not the number
of screens or presentations. For a 100-screen app with 10 independent
containers, the target is roughly 10 flow-boundary integrations or adapter
entries, not edits in 100 destinations. Exactness must not require an exhaustive
RUM-only route or presentation resolver, calls in every navigation method, or
new RUM code whenever another destination is added.

## Existing API and implementation constraints

Today, keyed manual views are process-inferred:

```swift
rum.startView(key: "compose", name: "Compose")
rum.stopView(key: "compose")
```

An attached `UIViewController` already supplies its `windowScene`; an unattached
controller and keyed calls use the current execution handoff when available,
then the process representative. That fallback remains unchanged.

The internal command model accepts a scene target, and focused tests
prove that the same `ViewIdentifier` can coexist in scene A and scene B and that
stopping A leaves B active. A public bridge therefore needs to capture
`scene.session.persistentIdentifier` synchronously and route the existing
start/stop intent. It does not need a second scene registry or a wire change.
`EXP-120` proves it cannot send the existing direct command unchanged because
that path bypasses the platform-view stack and has no authority over later
automatic appearances. Commits `29c8cec2c` and `b1a0fb6b8` implement and harden
the internal stack route; `EXP-122` validates it locally and in backend intake.
Signed commit `01e5d1ffb` adds the customer-shaped bridge. The Swift form is
`@_spi(Experimental)` and iOS 27-only. The Objective-C form is Debug-only because
Objective-C cannot import a Swift SPI. Focused forwarding, NOP/custom conformer,
instrumentation-stack, and selector smoke tests pass. The probe uses the real
overloads in Debug and Release, and `EXP-137` through `EXP-140` validate manual,
nested, duplicate-start, Sheet, and full-screen-cover semantics in mapper output
and backend intake. Stable promotion remains absent pending review.

`UIWindowScene` is main-actor isolated in the Xcode 27 SDK. The proposed factories
and overloads must capture only the stable identifier on the main actor. The RUM
queue must not retain the scene, window, view controller, SwiftUI view, path, or
router.

`RUMMonitorProtocol` is publicly conformable. Adding a required method can affect
source and binary compatibility, while convenience overloads can recurse if the
concrete monitor does not implement the underlying requirement. Review must
therefore cover real `Monitor`, `NOPMonitor`, mocks, and external conformers.

## Scene-aware manual views

### Recommended Swift call site

The smallest call-site addition follows the approved conceptual API:

```swift
@MainActor
rum.startView(
    key: "compose",
    name: "Compose",
    in: windowScene
)

@MainActor
rum.stopView(
    key: "compose",
    in: windowScene
)
```

Review starting point:

```swift
#if os(iOS)
@MainActor
func startView(
    key: String,
    name: String? = nil,
    in scene: UIWindowScene,
    attributes: [AttributeKey: AttributeValue] = [:]
)

@MainActor
func stopView(
    key: String,
    in scene: UIWindowScene,
    attributes: [AttributeKey: AttributeValue] = [:]
)
#endif
```

The scene argument is required on the new overloads. The existing methods remain
unchanged and keep inferred/last-interacted behavior. A default such as
`scene: nil` would make the distinction less visible and risks overload
ambiguity.

A targeted start must be stopped through the targeted overload using the same
scene and key. Mixing a targeted start with `stopView(key:)` is unsupported; the
legacy call retains its source-less inferred behavior and must not search every
scene for a matching key. The initial design deliberately returns no handle and
exposes no internal RUM UUID.

The initial proposal does not add a scene argument to the view-controller forms.
An attached controller already identifies its scene, and accepting both a
controller and a contradictory scene creates an avoidable precedence rule. The
Operation target can still accept a tracked controller because it identifies an
already tracked view rather than starting a new one.

### Protocol compatibility recommendation

Prefer an extension-only public overload backed by an internal scene-targeting
capability implemented by `Monitor`. If the receiver is a third-party conformer
or `NOPMonitor`, call its existing inferred method exactly once. This preserves
source compatibility and avoids a recursive default implementation. API review
must explicitly accept and document that a custom monitor without the private
capability cannot honor the new scene target.

The alternative is adding defaulted requirements to `RUMMonitorViewProtocol`.
That makes the semantic contract visible to custom conformers but requires a full
library-evolution and Objective-C compatibility review. Do not choose it only to
make the declaration look symmetrical.

The review alternatives are:

| Shape | Exact SDK behavior | External conformers | Compatibility cost | Recommendation |
| --- | --- | --- | --- | --- |
| Extension-only overload plus private capability | `Monitor` captures the scene ID and uses the proven handler stack | Existing conformers compile unchanged and fall back once to their legacy implementation | No new protocol witness; explicit scene semantics are unavailable through a custom conformer | Preferred first release |
| Defaulted protocol requirement | Same SDK route | A conformer can implement exact scene behavior through the existential | Requires library-evolution, binary-compatibility, mock, and Objective-C review | Use only if exact third-party-conformer dispatch is a requirement |
| New concrete monitor surface | Could provide exact dispatch | Avoids protocol extension dispatch | `RUMMonitor.shared()` currently returns `RUMMonitorProtocol`; changing that shape is substantially broader | Reject for this project |

For the preferred shape, the implementation sequence is fixed even though the
stable public declaration is not yet approved:

1. On the main actor, read only `scene.session.persistentIdentifier`.
2. If the receiver implements the private scene-targeted capability, forward the
   key, name, attributes, and internal scene identifier to it.
3. Otherwise invoke the existing source-less start or stop exactly once. Do not
   recurse through the new overload and do not search all scenes.
4. The capability routes through `RUMViewsHandler`; it must not emit the legacy
   direct command used by `EXP-120`.
5. Release every UIKit object before work crosses to the RUM queue.

The SDK deployment target remains iOS 15, but the validated automatic/manual
coexistence machinery is the declared-multi-scene iOS 27 path. The experimental
prototype uses an iOS 27 availability annotation. API review should choose
explicitly between retaining that annotation and a wider API
availability whose pre-iOS-27 behavior is documented as legacy-compatible rather
than multi-scene acceptance. The branch contains no evidence supporting a broad
pre-iOS-27 correctness claim.

### Objective-C companion

The Objective-C wrapper should expose selectors equivalent to:

```objc
- (void)startViewWithKey:(NSString *)key
                    name:(nullable NSString *)name
                 inScene:(UIWindowScene *)scene
              attributes:(NSDictionary<NSString *, id> *)attributes;

- (void)stopViewWithKey:(NSString *)key
                 inScene:(UIWindowScene *)scene
              attributes:(NSDictionary<NSString *, id> *)attributes;
```

Exact selector spelling remains an API-review decision. Both wrappers must
forward to the same Swift scene-targeted path and must not look up a global key
without the scene.

The Debug prototype includes an Objective-C compile/smoke test for those exact
selectors. Swift customer call sites resolve a real `UIWindowScene` in the probe;
the Release build proves they do not rely on `@testable` access. Objective-C
Release exposure still requires API review because that language has no SPI
boundary.

### Automatic-tracking coexistence requirement

The public monitor's direct keyed commands currently bypass
`RUMViewsHandler`'s per-scene platform-view stack. A start can replace the
current automatic view, but a later direct stop has no retained platform entry
from which to restart the underlying occurrence. More importantly, an automatic
appearance after the direct start can immediately preempt the manual view. The
new overload cannot be declared complete by routing `.scene` alone.

The internal implementation now integrates targeted manual entries with the same
per-scene view stack and provides a tested reveal mechanism. The still-unreviewed
public overload must route through that capability. Required result:

```text
automatic Home H1
manual Compose M1
automatic Home H2
```

H2 is a fresh occurrence. It must not reuse H1, leave the scene off-view, create
a duplicate automatic view, or affect another scene. `EXP-120` exercises the
existing direct keyed API with this exact shape. Across its valid runs, Compose
M1 survived only 31–48 ms before an automatic fallback started. Compose received
none of the decisive action/Resource pairs; the fallback owned active and
immediate-stop work, while only settled work used fresh H2. Mapper evidence and
backend intake agree, so direct commands are conclusively not coexistence-safe.

The smallest internal design is implemented as a weak scene-targeted manual-view
capability on `Monitor`, bound to `RUMViewsHandler` when instrumentation is
published. Targeted start and stop use the handler's per-scene stack. While a
manual suffix is active, later trustworthy automatic appearances are staged
without emitting RUM commands. Only the latest committed current destination is
eligible immediately below the suffix; other navigation-history entries stay
dormant and do not emit merely because they were staged. Removing the exact
scene/key manual entry applies stop-call attributes and reveals only that latest
destination as a fresh occurrence.

Nested manuals with distinct keys keep the entire manual suffix authoritative.
Stopping Attachment Preview above Compose starts a fresh Compose occurrence; it
does not resume the old Compose view ID. Starting the same `(scene, key)` while it
is already active is instrumentation misuse. The implementation must remain
crash-safe but need not invent restart, reference-counting, or handle semantics.
Existing source-less methods remain on their inferred direct-command path.

`EXP-121` validates the authority portion: M1 owns its active action/Resource,
but the first implementation staged and revealed a generic hosting fallback
before H2. Commit `b1a0fb6b8` retains the last semantic destination across that
structural churn and rejects known generic SwiftUI hosting/navigation-stack
fallbacks while manual authority is active. It does not reject a newly
trustworthy semantic destination, which can still replace the retained candidate
below M1. The clean `EXP-122` run passes 16/16 with exactly H1 → M1 → fresh H2;
M1 owns active work and the same H2 owns immediate plus settled post-stop work.
Backend intake confirms all owners and reports no error or crash.

Commit `f452e9e3f` covers the remaining approved internal manual rules. Several
committed automatic destinations beneath M1 emit no intermediate current view
and reveal only the latest as a fresh occurrence. Stopping nested Preview starts
a fresh Compose occurrence. Repeating an active `(scene, key)` start is ignored
crash-safely without restart or reference counting. These tests validate
internal behavior; they do not add or approve the public overloads.

`EXP-128` validates the nesting and duplicate rules through the real probe rather
than fixtures alone. It produces automatic Home H1 → Compose C1 → Preview P1 →
fresh Compose C2 → fresh automatic Home H2. A duplicate active Compose start
creates no C3 and does not move the duplicate marker action/Resource away from
C2. Backend intake confirms distinct C1/C2 and H1/H2 IDs with no error or crash.
The first attempt timed out only because the C1 mapper snapshot arrived before
the driver began waiting; exact immutable occurrence waits now also consume
already-recorded evidence. Same-key A/B isolation remains a separate live row.

`EXP-129` implements that separate discriminator. It starts the same customer
key in A and B, stops B before A, and requires distinct Compose occurrences,
continued A authority after B stops, and fresh returned Home occurrences in both
scenes. The scenario uses an internal debug-only scene-context marker to model a
trustworthy UI-event call site; it does not change the existing source-less
fallback. Its adversarial fixtures and full probe plan pass 91/91. The clean
iPad simulator run reached both native scenes but lost the Xcode/device session
before the first manual start, so the public-design evidence remains source and
hostless-contract evidence until the same named scenario passes on capable
hardware.

`EXP-119` is the legacy modifier baseline: Sheet S1 suppresses its duplicate and
automatic Home H2 eventually returns, but immediate `onDismiss` work still owns
S1. `EXP-123` proves that exact-scene handler routing alone is also insufficient
because automatic discovery can separately emit the presentation hosting
controller. The complete internal shape has two responsibilities: the router
publishes the semantic destination, and a UI-attached boundary suppresses
automatic discovery only for the matching native subtree through dismissal.
`EXP-125` validates exact H1 → Sheet M1 → fresh H2, no automatic Sheet, and
immediate plus settled dismiss work on H2. Commit `c70920c94` clones the
discriminator for `fullScreenCover`; `EXP-126` independently passes the same
14/14 contract with no automatic `ProbeFullScreenCoverView`. The two presentation
styles now have separate local and backend evidence.

`EXP-127` covers the remaining internal sibling boundary. Two independent
`NavigationStack` branches mount below one outer SwiftUI host, and a mandatory
`UIViewController` ancestry witness proves they are distinct real controller
branches before the oracle can pass. Left-side manual authority does not make a
right-side automatic candidate ineligible: right Home commits to Detail beneath
M1, no intermediate view becomes current, and exact stop reveals one fresh
right-side Detail occurrence. The first run also established a harness rule: a
probe-only hierarchy reader must be excluded by its exact predicate type or it
can become a late automatic RUM view itself.

## SwiftUI semantic navigation

### Customer compatibility and engine boundary

Using RUM must not require customers to replace standard or existing navigation.
Normal SwiftUI remains normal SwiftUI:

```swift
NavigationStack(path: $path) {
    ContentView()
        .navigationDestination(for: Route.self) { route in
            destination(for: route)
        }
}
.sheet(item: $draft) { draft in
    ComposeView(draft: draft)
}
.fullScreenCover(item: $attachment) { attachment in
    AttachmentPreview(attachment: attachment)
}
```

Do not require `rumSheet`, `rumFullScreenCover`, Datadog destination modifiers,
a Datadog router, or conversion of local presentation state into one centralized
enum solely for RUM. The same rule applies to internal and third-party SwiftUI
containers, coordinators, UIKit navigation containing SwiftUI, and custom
transitions. Agent-generated native SwiftUI must continue to work without
Datadog-specific knowledge.

The semantic navigation engine therefore sits below any visual container:

```text
Native NavigationStack adapter ─┐
Customer container capability ──┤
Router/transition source ────────┼─→ scene-scoped semantic engine ─→ RUM views
UIKit coordinator adapter ───────┤
Automatic discovery ─────────────┘
```

The engine understands scene ownership, destination metadata/materialization,
transition preparation, commit/cancellation, reveal, and occurrence identity.
It does not own layout, gestures, animation, deep links, custom configuration,
or presentation behavior. Those remain properties of the customer's container.

A Datadog-owned outer host may attach the scene/authority boundary while accepting
any customer `View` as its content. For native SwiftUI, the intended low-cost
shape is one container integration with automatic metadata:

```swift
RUMNavigationHost(metadata: .automatic) {
    NavigationStack(path: $path) {
        ExistingContent()
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
    }
    .sheet(item: $draft) { ComposeView(draft: $0) }
    .fullScreenCover(item: $attachment) { AttachmentPreview(attachment: $0) }
}
```

Without another capability, this host supplies scene attachment, target-local
automatic deduplication, best-effort inference, and crash-safe compatibility
fallback. It must not mirror the customer's container parameters.

An application that already owns an observable router may connect one dedicated
adapter at that boundary. Its navigation methods remain unchanged:

```swift
RUMNavigationHost(
    transitions: router.rumNavigationTransitions,
    metadata: .automatic
) {
    ExistingApplicationNavigation(router: router)
}
```

Sparse overrides may add business names for exceptional destinations. They are a
policy layer, not a correctness prerequisite. A centralized exhaustive resolver
is acceptable only when the application already owns one or deliberately wants
complete custom naming.

`EXP-146` validates the engine behind these shapes with one outer host and a
deterministic explicit-source adapter around unchanged `NavigationStack`,
`.sheet`, and `.fullScreenCover` code. It passes 42/42 and produces
H1/D1/H2/Sheet/H3/Cover/H4 as distinct occurrences with exact downstream
ownership and no automatic duplicate. The optional capability passes the same
oracle; opaque content retains automatic capture. Runtime precedence and source
stability also pass. These are engine and adapter-author results. `EXP-147`
separately proves that an application with an existing accepted router-state
stream can integrate at one boundary without route-proportional transition
publishing. `EXP-148` moves that route-count-independent policy into DatadogRUM,
including fresh equal-route occurrence tokens and automatic metadata. It still
does not approve a public SDK API or prove exact native/opaque reconstruction
where no trustworthy stream exists.

### Integration inputs and precedence

Exact semantic input follows this order:

1. An explicit stable source supplied by a dedicated existing-router or
   third-party adapter.
2. An optional type-erased capability exposed by the supplied container.
3. Native adapter knowledge when the optional `RUMNavigationStack` convenience
   is used.
4. Scene-aware automatic discovery.
5. Existing process-representative compatibility fallback.

The current SDK-owned existing-router prototype consumes accepted state once at
the container boundary:

```swift
RUMNavigationHost(
    observing: router.$state,
    destination: { state in state.currentRUMDestination },
    metadata: .automatic
) {
    ExistingApplicationNavigation(router: router)
}
```

The projection identifies the current root, route, or presentation; it is not an
exhaustive business-name resolver. Equal route values need an in-memory
occurrence discriminator only when the source permits the same value at multiple
positions. That token is not a RUM UUID and is never serialized.

Do not replace this signal with a plain destination value evaluated by the outer
SwiftUI host:

```swift
// Rejected as an exact API by EXP-150.
RUMNavigationHost(currentDestination: destination(for: router.state)) {
    ExistingApplicationNavigation(router: router)
}
```

`EXP-150` proves that this value arrives one render too late for the approved
dismissal contract. Both sheet and full-screen-cover immediate action/Resource
pairs remain on the dismissed presentation; the fresh underlying occurrence
starts afterward. Eventual final state, passing state-level parity tests, and
correct settled work do not repair that attribution loss.

For an existing iOS 27 `@Observable` router, a second candidate can observe the
accepted stored value during mutation through one-shot Observation `.didSet`
tracking and rearm after every event. Conceptually:

```swift
RUMNavigationHost(
    observingCurrentDestination: { destination(for: router.state) },
    metadata: .automatic
) {
    ExistingApplicationNavigation(router: router)
}
```

EXP-151 accepts the one-shot `.didSet` primitive for an existing iOS 27
`@Observable` router, but not this public spelling. The adapter delivers the
stored destination and rearms before the setter returns; its frozen 38/38 run and
backend session place immediate and settled sheet/cover dismissal work on fresh
revealed occurrences. The projection must be stable, side-effect-free, and read
one atomically updated property representing the complete accepted destination.
If it reads independently mutated route and presentation properties, each
`.didSet` is a separate committed signal and the intermediate combination is
observable; the SDK does not invent a transaction across those writes.

Sequential and nested mutations, teardown, SwiftUI reconstruction, and an
invalid background mutation's crash-safe latest-state fallback pass focused
tests. The iOS Release and visionOS package builds also pass; the semantic host
remains iOS 27-only in the current platform conditional. EXP-152 separately
waits for real presentation content appearance and proves actual Sheet/Cover
`onDismiss` callbacks run once after accepted Home state, create no extra Home,
and attribute immediate plus settled work to fresh H3/H4. Custom/third-party and
genuine concurrent two-scene parity plus API review remain. The continuous
Observation API is explicitly too late because it delivers at a later suspension
point. Plain local SwiftUI `@State`
does not conform to `Observable`, so this candidate must not imply exact
opaque/native-local-state support.

Conceptual optional capability:

```swift
@MainActor
public protocol RUMNavigationTransitionProviding {
    var rumNavigationTransitions: RUMNavigationTransitions { get }
}
```

The source must remain stable across SwiftUI view-value reconstruction. Prefer a
type-erased source without an associated route type when runtime detection is
required. Transition timing, current-destination metadata, materialization, and
presentation state may be separate capabilities rather than one large protocol;
do not use Objective-C-style optional requirements.

The source's low-level prepare/commit/cancel methods are engine and adapter-author
primitives. They must not normally appear in every customer navigate, pop,
present, or dismiss method. If an adapter cannot subscribe once to trustworthy
existing state or transitions, the integration should retain scene-aware
automatic tracking and sparse manual exceptions rather than require widespread
bridge calls.

For exact initial lifecycle attribution, the source should synchronously expose
its current committed destination when the host first evaluates. Publishing it
from a descendant `.task` remains too late for root `onAppear` and the synchronous
prefix of an immediate task. A configured source with no initial value does not
silently select a lower-precedence capability and does not suppress automatic
tracking before its first trustworthy destination; precision upgrades only when
that value arrives. The host resolves the scene from its inherited iOS 27 scene
trait; customers do not supply an internal RUM UUID or native scene identifier.
The first source selected by a host is pinned across SwiftUI view-value
reconstruction so a freshly computed capability cannot replay or disconnect the
current occurrence.

Imported third-party containers should normally use an explicit source or
reusable adapter rather than a retroactive conformance:

```swift
RUMNavigationHost(transitions: router.rumNavigationTransitions) {
    ThirdPartyNavigationStack(router: router) {
        ApplicationContent()
    }
}
```

Datadog may ship optional library adapters without adding those libraries as core
SDK dependencies. Explicit input is authoritative only for its target and must
not suppress unrelated automatic containers.

Exact reconstruction has an information boundary. At least one trustworthy
accepted-route, destination-materialization, transition-completion/cancellation,
observable-router/coordinator, or wrappable content-builder signal is required.
A completely opaque container remains scene-aware and crash-safe through
automatic tracking and exceptional manual instrumentation; the SDK must document
that exact semantic reconstruction is unavailable rather than guessing.

### Native convenience proof

The current `RUMNavigationStack` may remain as an optional native convenience:

```swift
RUMNavigationStack(
    path: $router.path,
    presented: $router.presentation,
    root: RUMView(name: "Home"),
    destination: router.rumView,
    presentation: router.rumPresentation
) {
    HomeView()
} destinationContent: { route in
    router.view(for: route)
} presentedContent: { presentation in
    router.view(for: presentation)
}
```

It must behave as closely as practical to native `NavigationStack`, use the same
container-independent engine, and never be a prerequisite for exact multi-scene
support. Its current builder-owning form is important evidence: `EXP-047` through
`EXP-049` prove that a passive modifier outside an already-built stack learns the
destination too late, while `EXP-116` proves that a materialization boundary can
start the occurrence before lifecycle work.

The iOS 27 SPI accepts a typed `Binding<[Route]>`, centralized root/destination
resolution, one optional presentation binding, and root/destination/presented
builders. It answers implementation-feasibility questions but not the final
customer shape. `EXP-141` through `EXP-145` validate complete destinations,
repeated/restored equal routes, rejected/canonicalized writes, atomic Sheet ↔
Cover replacement, and sibling-container authority.

The implementation preserves the customer's `[Route]` element type and keeps
occurrence identity inside materialized RUM boundaries. Binding writes reconcile
against the accepted getter, so uncommitted proposals do not advance RUM state.
The inherited iOS 27 scene trait may promote only an already reader-proven
same-scene dormant boundary; it cannot migrate or recover disconnected state.
These mechanics should move into the shared engine without weakening any current
fixture.

They now do in the experimental implementation: `a84061840` extracts the
scene-scoped engine and makes both the native convenience and arbitrary-content
host delegate to it. `354422d88` supplies the deterministic explicit-source
adapter probe, and `651b173c6` validates the identical container with optional capability
and opaque automatic fallback. `47bc08eca` then exercises runtime precedence,
repeated reconstruction, and deliberate source replacement. Focused lifetime work
adds a synchronous real-reader bounce, source release, and posted-disconnect
fencing; final host removal and genuine OS disconnect remain hardware rows.
`EXP-147` closes the migration-cost obligation for the existing-router candidate.
`EXP-148` closes the SDK-owned publisher-observable-router baseline with the same source
diff and runtime semantics. `EXP-149` closes actual host subscription
reconstruction, publisher replacement, two-scene isolation, posted-disconnect
cleanup, and unrelated automatic-subtree coexistence at 20/20. `EXP-150` then
rejects value-only render-time observation after its frozen runtime and backend
session place both immediate dismissal pairs on the outgoing presentation.
`EXP-151` accepts one-shot Observation `.didSet` as the early iOS 27 router
signal: focused atomic-state, ordering, nested-reentrancy, reconstruction,
teardown, and background-misuse tests pass, and its post-review frozen 38/38
runtime plus backend session assign both dismissal pairs to fresh underlying
occurrences. `EXP-152` then closes actual programmatic native callback timing at
38/38 without moving SDK policy into `onDismiss`. The next proof obligation is
two-scene and honest custom/explicit adapter parity before public-shape review;
interactive dismissal and genuine OS disconnect remain hardware gates.

### Resolver and path model

When an application already exposes a typed route or router, a native adapter may
use a centralized nonoptional resolver:

```swift
@MainActor
func rumView(for route: AppRoute) -> RUMView
```

This is an adapter option when the application already owns or deliberately wants
complete route metadata, not a requirement to create a Datadog router, enumerate
every destination, or rewrite local presentation state. Automatic metadata is the
default and sparse overrides are sufficient. An optional result is ambiguous between "allow
automatic tracking here" and "intentionally emit no RUM destination." If partial
semantic coverage is needed,
model that choice explicitly rather than giving `nil` two meanings.

A typed `Binding<[Route]>` can expose committed order and repeated values to the
native convenience adapter. A type-erased `NavigationPath` does not provide a
public sequence of its elements, so support for heterogeneous paths requires a
different source, coordinator, or
application router that exposes semantic transitions. API review must not
promise arbitrary `NavigationPath` introspection or require path conversion.

Occurrence identity belongs to a committed path position and transition, not to
`Route`, `Hashable`, a destination view value, or its RUM metadata. Equal routes
can create different occurrences. A same-turn push and revert creates none.
Interactive cancellation retains the prior occurrence; completion creates the
returned destination's fresh occurrence.

### Authority boundary

The current internal authority registry suppresses automatic discovery when an
active explicit or suppression-only reader is contained by an automatic
candidate controller. The suppression-only form publishes no RUM lifecycle; a
centralized router remains its sole semantic owner.
`EXP-115` proves this for one container, `EXP-118` partially proves that scene A
does not suppress scene B, `EXP-127` proves containment remains local across
two sibling controller branches hosted below one outer SwiftUI root. The latter
passes only after observing both exact controller ancestries; a missing or
collapsed topology is `INCONCLUSIVE`, not authority evidence. This closes the
internal isolation question without approving how the public integration creates
and owns the boundary. `EXP-145` reruns that topology through the actual native
convenience SPI and passes 19/19 locally plus exact backend ownership, proving
the current public-shape prototype does not globalize authority. `EXP-129` adds
the exact same-key A/B contract, but its
live acceptance remains hardware-inconclusive before manual authority began.

Exceptional `.trackRUMView` instrumentation remains supported alongside a
semantic container. It owns only its explicit occurrence. Returning from that
exception must reveal a fresh current destination before customer work that is
semantically outside the exception, or the limitation must remain explicit until
the container/router integration can provide that earlier signal.

### Presentation state

The shared engine models sheets, covers, UIKit presentations, and custom overlays
as the same semantic fact: the scene's current destination changed. A presented
destination replaces the scene's one current destination; it is never a second
concurrent RUM view. An exact adapter or transition source may report those
changes through the common engine. Otherwise standard automatic tracking remains
the fallback.

Do not create Datadog equivalents for every presentation API. Existing `.sheet`
and `.fullScreenCover` call sites remain unchanged. When trustworthy semantic
input exists, dismissal starts a fresh underlying occurrence before post-dismiss
customer work and suppresses only the presented destination's duplicate. A
same-turn proposal that never commits starts no view. The internal Sheet path
passes this contract in `EXP-125`; `EXP-126` repeats it independently for
`fullScreenCover`. Router authority and native-subtree suppression deliberately
have different lifetimes because a final aggregate may outlive semantic stop.

The customer-shaped reruns close the remaining prototype-usefulness question.
`EXP-137` passes 16/16 for Home H1 → Compose M1 → fresh H2 through the Swift SPI.
`EXP-138` passes 29/29 for H1 → Compose C1 → Preview P1 → fresh Compose C2 →
fresh H2, including duplicate active-key crash safety. `EXP-139` and `EXP-140`
independently pass 14/14 for Sheet and full-screen cover, with exactly one
semantic presentation and fresh H2 before immediate dismissal work. All four
backend sessions agree with mapper ownership and contain zero errors/crashes.
`EXP-141` then exercises the actual container SPI as one complete stream. It
passes 38/38 with distinct H1/D1/H2/Sheet/H3/Cover/H4 IDs, no automatic duplicate,
and immediate, settled, and delayed post-dismiss work on fresh H3/H4. Its exact
backend session contains those seven semantic views plus ApplicationLaunch, 25
actions, 25 Resources, and zero errors/crashes. `EXP-144` then replaces Sheet
with Cover and Cover with a fresh Sheet while keeping the underlying Home hidden,
before final dismissal creates fresh H2. Its final run passes 43/43; backend
intake contains the same five semantic occurrences, 19 actions, 19 Resources,
and zero errors/crashes. `EXP-145` adds actual-SPI sibling isolation: left manual
authority keeps right Detail hidden until exact stop, then one fresh Detail owns
post-stop work. `EXP-146` then moves those mechanics into the shared engine and
passes 42/42 through an arbitrary host plus deterministic stable-source adapter
while leaving standard presentation APIs intact. Its backend session contains the
eight views including ApplicationLaunch, 26 exact-view actions, 26 exact-view Resources, and
zero errors/crashes; launch owns no downstream work. The optional capability
repeats that 42/42 contract, while opaque fallback passes 5/5 with automatic
capture and no semantic view. Runtime precedence, repeated source resolution,
and adversarial replacement each pass 43/43 with the same exact backend owners
and no decoy view. The complete RUM run passes
1,262/1,263 and the sole unrelated timeseries timing failure passes immediately
in isolation; the current native probe passes 155/155. The synchronous real-reader bounce
passes 17/17, focused disconnect/lifetime tests pass 4/4, and handler tests pass
84/84 at their recorded checkpoint. `EXP-150` itself fails 17/38 because its
fresh H3/H4 occurrences start after synchronous post-dismiss work; backend
session `2294a609-76f9-47be-a643-ab51edc5b638` independently confirms Compose
and Attachment as the stale owners. Final host removal and genuine OS disconnect
remain hardware gates. `EXP-151` passes the replacement synchronous oracle, and
`EXP-152` passes actual native callback characterization with eight views, 11
actions, 11 Resources, and zero errors/crashes in backend session
`fee27d61-1eb7-4eb6-8525-7af74a53ed7e`. Repository lint and the Xcode 27 Release
build are clean at the EXP-152 checkpoint. API-surface verification remains the
expected-only rejection of unapproved experimental symbols; no prototype
baseline is changed before normal review.

## Required review and test matrix

Scene-aware manual views require:

- same key in A and B, then stop A and prove B remains active;
- reverse-order stops and repeated occurrences;
- explicit A target overriding a B process representative;
- explicit target with no current A view that does not fall into B;
- manual exceptional view over automatic H1 -> M1 -> fresh H2;
- automatic appearance or replacement while M1 is active is staged beneath M1
  and emits no intervening current view;
- several underlying commits while M1 is active emit none of the intermediate
  destinations and reveal only the latest committed destination as a fresh view;
- nested targeted manual entries preserve an authoritative manual suffix and
  stopping Preview above Compose starts a fresh Compose occurrence;
- duplicate active `(scene, key)` starts remain crash-safe without restart,
  reference-counting, or handle semantics;
- a targeted start followed by a legacy source-less stop does not act as a
  supported pair or search another scene;
- automatic tracking continuing in another scene and sibling container;
- scene close while the manual view is active;
- stop-call attributes are applied to M1's stop event;
- the restarted H2 UUID differs from H1;
- Swift and Objective-C forwarding parity;
- `NOPMonitor` and third-party conformer fallback invoked exactly once; and
- no retained `UIWindowScene`, `UIWindow`, or controller after capture.

Semantic SwiftUI navigation requires:

- automatic metadata sufficient for correctness, with sparse optional custom
  overrides and no required exhaustive RUM-only resolver;
- zero screen-file edits and zero per-navigation-method RUM calls in the
  realistic `EXP-147` baseline integration;
- adding another route or presentation requires no RUM code unless the customer
  chooses a custom metadata override;
- a non-conforming custom container receives baseline scene-aware automatic
  tracking without changing its navigation implementation;
- the same container with a stable optional capability receives exact semantic
  tracking;
- an explicit transition source overrides capability and automatic inference;
- native convenience, conforming custom, and explicit third-party-style adapters
  produce identical occurrence semantics;
- Home H1 -> Detail D1 -> Home H2 with distinct IDs;
- equal same-named Detail D1 -> Detail D2 occurrences;
- same-turn push/revert and interactive cancellation with no speculative view;
- state preservation when only the RUM occurrence rotates;
- root, destination, modal, and retained-return lifecycle work on the intended
  occurrence;
- Sheet and full-screen-cover present/dismiss sequences through the shared
  semantic source, with standard presentation call sites unchanged and a fresh
  reveal before immediate post-dismiss work;
- direct Sheet → Cover → Sheet replacement with no intermediate underlying view,
  distinct presentation IDs, and one fresh reveal only after final dismissal;
- coexistence with automatic tracking, a manual exception, a sibling container,
  and another scene without duplicate or global suppression;
- two enhanced containers in different scenes remain isolated, while one
  enhanced container does not suppress an unrelated automatic container;
- SwiftUI container reconstruction preserves the stable transition source and
  does not replay or disconnect the current occurrence; a later computed
  capability source cannot replace the first selected source;
- one current destination for split/tab structures;
- scene disconnect, reconnect, restoration, and session rollover; and
- unchanged automatic-only, source-less, and single-scene behavior.

## API-review questions

No product-behavior decision blocks the next experiment. `EXP-148` validates the
SDK-owned low-cost publisher path, `EXP-149` closes its deterministic lifetime
and scene-isolation matrix, `EXP-151` accepts the iOS 27 Observation input for
one atomic accepted-state property, and `EXP-152` closes programmatic native
dismissal callback timing. EXP-146's low-level semantic oracle alone remains
insufficient for API promotion. The next implementation experiment is
custom/third-party and two-scene adapter parity. The remaining questions are
public shape, compatibility, and implementation-boundary review:

1. Which parts of the transition source remain internal, become adapter-author
   SPI, or warrant public exposure, and what are the exact host/adapter names?
2. Which small type-erased capabilities should be independently detectable, and
   how should runtime discovery preserve a stable source across SwiftUI value
   reconstruction without retaining customer containers?
3. How much native `NavigationStack` convenience should `RUMNavigationStack`
   expose while delegating to the shared engine and avoiding a mirrored Apple API
   surface?
4. What automatic metadata policy supplies usable names/paths without customer
   enumeration, and should sparse overrides reuse `RUMView` or a smaller
   navigation-specific descriptor?
5. Extension-only manual overload with private capability, or defaulted public
   protocol requirements after library-evolution review?
6. How should the public integration create, retain, and remove the proven
   container-local authority boundary without exposing controller hierarchy or
   requiring customers to understand its internal containment model?
7. How should Objective-C callers that invoke a `UIWindowScene` overload away
   from the main thread be handled without retaining or asynchronously dereferencing
   the scene?

The Operation target proposal and its additional exact-view forms remain in
[OPERATIONS.md](OPERATIONS.md). Both reviews should share one internal logical
target representation, but they do not need to expose one public type unless that
improves actual call sites.
