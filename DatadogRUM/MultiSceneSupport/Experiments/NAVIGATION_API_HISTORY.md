# Navigation API design and experiment history

Historical excerpts from the reviewed navigation draft before its 2026-09-24
split. Read only for a specific older design, failure or experiment. Statements
such as "current", "now" and "passes" refer to their recorded checkpoints; they
are not a present release verdict or an execution queue.

The [current navigation contract](../NAVIGATION_API.md) owns behavior and the
[stable API review](../STABLE_API_REVIEW.md) owns declarations and approval.
The [experiment index](../EXPERIMENTS.md) routes to each detailed experiment;
those records remain the owners of raw evidence and acceptance outcomes.
The [consolidation record](../Results/navigation-documentation-consolidation-20260924.json)
binds the source draft, copied ranges and old-to-new sections. Excerpt wording is
preserved, with headings normalized and relative links adjusted for this folder.

## Status

The scene-targeted manual view proposal is implemented locally as an iOS15
experimental Swift SPI. Objective-C counterparts remain exposed only in Debug
or with the local DD_SCENE_API_VALIDATION flag. Provisional clients exercise
call sites, selectors, custom/NOP fallback and runtime behavior; normal public
exposure and RFC approval remain pending. `EXP-137` through
`EXP-140` cover automatic Home → manual/presentation → fresh Home using the
customer-shaped overloads. Do not promote these declarations to the supported
public API surface until review approves their names, availability, protocol
behavior, and Objective-C exposure. The native-convenience SwiftUI container is
also implemented as an iOS 27 experimental Swift SPI. `EXP-141` validates its complete
Home → Detail → Home → Sheet → Home → full-screen-cover → Home stream locally and
in backend intake while automatic tracking remains enabled. Examples below are
the exercised review starting point, not settled signatures. The compact
[integration guide](../SUPPORT_GUIDE.md) describes the current call sites and every
telemetry family's ownership boundary. `EXP-142`-`144`
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
`EXP-153` closes a third-party callback-driven path: one dedicated adapter
around a custom library-owned container reuses the SDK publisher host without
retroactive conformance, screen edits, navigation-method RUM calls, or another
SDK input primitive. `EXP-154` closes serial native-scene isolation: two real
scenes independently mount the Observation boundary, produce distinct
H1/D1/fresh-H2 occurrences, and retain exact action/Resource owners. This makes
the semantic shape ready for normal API review without claiming simultaneous
window visibility or hardware lifecycle acceptance.

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
Signed commit `01e5d1ffb` added the customer-shaped bridge. At that checkpoint,
the Swift form was `@_spi(Experimental)` and iOS27-only; Objective-C was Debug-only
because it cannot import a Swift SPI. [EXP-225](../Results/EXP-225-api-availability.json)
records the later provisional iOS15 declarations and internal fallback, with
Objective-C still restricted to Debug or `DD_SCENE_API_VALIDATION` builds.
At the original checkpoint, focused forwarding, NOP/custom conformer,
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

## Protocol compatibility recommendation

Prefer an extension-only public overload backed by an internal scene-targeting
capability implemented by `Monitor`. If the configured platform route lacks the
qualified capability, or the receiver is a third-party conformer or `NOPMonitor`,
call its existing inferred method exactly once. This preserves
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

1. Select the qualified route from OS, configuration and receiver capability
   before mutating view state. Keep matching start/stop calls on a coherent route.
2. For a scene-aware route, read only `scene.session.persistentIdentifier` on
   the main actor and forward the key, name, attributes and identifier.
3. Otherwise invoke the existing source-less start or stop exactly once,
   including its attributes. Do not drop the call, recurse through the new
   overload or search all scenes for a key.
4. The scene-aware capability routes through `RUMViewsHandler`; it must not emit
   the legacy direct command used by `EXP-120`. The legacy fallback deliberately
   preserves the existing inferred API's behavior.
5. Release every UIKit object before work crosses to the RUM queue.

The SDK deployment target remains iOS15. The amended ordinary API is callable
throughout that range: customers use the same scene-taking start and stop without
an iOS27 branch. Only the extra scene behavior is conditional inside the SDK.
Legacy fallback does not guarantee independent same-key A/B views, scene-local
automatic/manual coexistence or exact target ownership. Qualify each older-iPad
capability before enabling it; customers can then gain that behavior by updating
the SDK without changing their instrumentation. Existing iOS27 evidence does not
establish exact behavior on every older system. EXP-225 provisionally qualifies
the iOS15 declarations and legacy fallback at source `94842cc8ad7b`; exact
older-iPad scene capability remains disabled until separately qualified.
Normal public exposure still requires the recorded F01 decision.

## Automatic-tracking coexistence requirement

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

## Shared engine qualification

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

## Integration inputs and precedence

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
and attribute immediate plus settled work to fresh H3/H4. EXP-153 separately
proves that a synchronous accepted-state callback from a custom navigation
library can feed the existing publisher host through one stable boundary
adapter. EXP-154 then proves serial parity across two real native scenes. Normal
API review and genuine simultaneous-window acceptance remain. The continuous
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

The third-party library does not need to expose Combine or Observation directly.
EXP-153 accepts an adapter that seeds a current-value stream from the library's
current accepted snapshot, registers once for synchronous committed-state
callbacks, and translates route/presentation identities into semantic
destinations:

```swift
ThirdPartyRUMNavigationBoundary(navigator: navigator) {
    ThirdPartyNavigationContainer(navigator: navigator)
}
```

This is a conceptual integration shape, not an approved public name. The
adapter must receive current state synchronously, publish only accepted commits,
distinguish repeated equal-route occurrences, and remain stable through SwiftUI
reconstruction. A callback delivered only after the navigation method returns
does not satisfy the exact immediate-work contract. The accepted EXP-153 run
uses one registration for H1/D1/H2/Sheet/H3/Cover/H4 and passes all 42 local and
backend expectations without modifying the custom container's navigation
methods.

Exact reconstruction has an information boundary. At least one trustworthy
accepted-route, destination-materialization, transition-completion/cancellation,
observable-router/coordinator, or wrappable content-builder signal is required.
A completely opaque container remains scene-aware and crash-safe through
automatic tracking and exceptional manual instrumentation; the SDK must document
that exact semantic reconstruction is unavailable rather than guessing.

## Native convenience proof

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
38/38 without moving SDK policy into `onDismiss`. `EXP-153` closes honest
callback-driven custom/explicit parity at 42/42 through one stable adapter and
the existing publisher host. `EXP-154` closes serial two-native-scene
Observation parity at 25/25 with six exact marker pairs. The public-shape review
can now begin; simultaneous visibility, interactive dismissal, and genuine OS
disconnect remain hardware gates rather than prerequisites for reviewing the
semantic integration contract.

## Authority boundary

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

## Presentation state

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
and no decoy view. The complete RUM run passes 1,255/1,255 with zero failures at
the current downstream-target checkpoint; the current native probe passes
164/164. The synchronous real-reader bounce
passes 17/17, focused disconnect/lifetime tests pass 4/4, and handler tests pass
84/84 at their recorded checkpoint. `EXP-150` itself fails 17/38 because its
fresh H3/H4 occurrences start after synchronous post-dismiss work; backend
session `2294a609-76f9-47be-a643-ab51edc5b638` independently confirms Compose
and Attachment as the stale owners. Final host removal and genuine OS disconnect
remain hardware gates. `EXP-151` passes the replacement synchronous oracle, and
`EXP-152` passes actual native callback characterization with eight views, 11
actions, 11 Resources, and zero errors/crashes in backend session
`fee27d61-1eb7-4eb6-8525-7af74a53ed7e`. Repository lint and the Xcode 27 Release
build are clean at the EXP-152 checkpoint. `EXP-153` then passes 42/42 with one
stable callback-adapter registration; backend session
`f2d2fb24-02d6-4bd9-9df9-ee353b899e69` contains eight views, 13 actions, 13
Resources, and zero errors/crashes. Repository lint and the Xcode 27 Release
build also pass at its signed harness checkpoint. `EXP-154` then passes 25/25
across two real native scenes; backend session
`a6a5afd5-8089-4996-9805-ed62fb76927d` contains seven views, six actions, six
Resources, and zero errors/crashes, with distinct A/B H1/D1/H2 owners. Focused
tests pass 2/2, the full probe passes 162/162, lint and Release pass, and signed
readiness correction `f92d72909` freezes the accepted harness source.
API-surface verification remains the
expected-only rejection of unapproved experimental symbols; no prototype
baseline is changed before normal review.
