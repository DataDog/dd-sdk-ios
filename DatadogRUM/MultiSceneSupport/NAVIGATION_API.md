# RUM multi-scene navigation API proposal

This document owns the current scene-aware manual-view and SwiftUI navigation
contract. Product behavior is approved; public API review remains pending.
Last reviewed: 2026-09-24.

| Read next | Purpose |
| --- | --- |
| [Stable API review](STABLE_API_REVIEW.md) | Canonical declarations, eight API decisions and approval record |
| [Integration guide](SUPPORT_GUIDE.md) | Customer examples and telemetry ownership |
| [Navigation history](Experiments/NAVIGATION_API_HISTORY.md) | Earlier designs, rejected inputs and experiment observations |
| [Assessment](ASSESSMENT.md) and [release checklist](PLAN.md) | Present support limits and remaining release obligations |

## Status

Ordinary scene-taking calls and their target value are implemented provisionally
at source `94842cc8ad7b104c1394c236b98b95b6c24a0956`, as recorded in
[EXP-225](Results/EXP-225-api-availability.json). Swift declarations are iOS15+
experimental SPI. Objective-C companions remain limited to Debug or
`DD_SCENE_API_VALIDATION` builds. The SDK chooses qualified scene behavior or
exactly-once legacy fallback internally; customers do not add iOS27 branches
around these ordinary calls. Exact older-iPad scene behavior remains disabled
until its family is qualified.

The semantic SwiftUI host, destination/metadata types and experimental native
navigation convenience remain iOS27+. The Observation initializer additionally
requires compiler>=6.4. Neither provisional implementation nor the earlier
experiments approve normal public exposure or close final compatibility gates.

Automatic UIKit and SwiftUI tracking remain the default. Exact semantic tracking
is optional at an existing router or container boundary. Customers keep their
navigation containers, routes, destination modifiers, sheets and covers.
Integration cost scales with independent flows, not screen count. Adding a route
or presentation requires no RUM code unless the customer chooses a metadata
override.

Each scene has one current destination within the shared application session.
Home H1 → Detail D1 → Home H2 produces three distinct RUM occurrences. Structural
panes and tabs are not concurrent RUM views. No API exposes RUM UUIDs, serializes
scene identifiers, or adds temporary window attributes or session boundaries.

## Existing API and implementation constraints

Existing keyed manual calls retain inferred behavior. An attached controller
supplies its scene; unattached controllers and keyed calls use trustworthy
execution handoff where available, then the process representative. The new
scene-taking calls do not change those methods.

Factories capture only `scene.session.persistentIdentifier` on the main actor.
The RUM queue must not retain scenes, windows, controllers, SwiftUI views, paths
or routers. `RUMViewTarget.current(in:)` captures a scene identity; a qualified
route resolves its live current view when processing the command. It does not
freeze a view occurrence. [The integration guide](SUPPORT_GUIDE.md#telemetry-ownership)
separately defines start-owned Resources and other telemetry families.

`RUMMonitorProtocol` remains publicly conformable. Review must cover the built-in
monitor, custom conformers, mocks and NOP implementations without adding protocol
witnesses, changing the shared-monitor return type or introducing recursion.
The [history](Experiments/NAVIGATION_API_HISTORY.md#existing-api-and-implementation-constraints)
retains the original bridge investigation.

## Scene-aware manual views

### Recommended Swift call site

These are proposed public call sites inside a MainActor-isolated UI integration.
The provisional implementation still requires an experimental import.

```swift
rum.startView(key: "compose", name: "Compose", in: windowScene)
// Record work while the exceptional manual view is active.
rum.stopView(key: "compose", in: windowScene)
```

The scene argument is required. Pair targeted start and stop with the same scene
and key. A legacy `stopView(key:)` is not a matching stop and must not search other
scenes for a key. No returned lifecycle handle or internal RUM UUID is involved.
The [canonical Swift inventory](STABLE_API_REVIEW.md#swift-target-surface) owns
signatures and defaults.

An attached view controller already identifies its scene, so the first proposal
adds no contradictory scene argument to controller forms. The only proposed
first-release target factory is `RUMViewTarget.current(in:)`; manual-key and
tracked-controller factories remain outside this release.

### Protocol compatibility recommendation

Use extension overloads backed by the built-in monitor's private targeting
capability. Select the route from OS, configuration and the qualified family
capability before mutating state. Matching start/stop calls must stay coherent.

On the scene-aware route, capture the identifier on main and route manual entries
through `RUMViewsHandler`'s per-scene stack. The old direct command cannot preserve
manual authority across automatic appearances. On an unsupported route, or for a
custom/NOP conformer, invoke the existing method once with the same attributes and
completion behavior. Do not drop the event, recurse, or require a second customer
fallback call. Release UIKit objects before crossing to the RUM queue.

Legacy fallback preserves inferred/process ownership and existing pairing rules.
It does not promise independent same-key A/B views or exact older-system scene
ownership. Qualify each older-iPad capability before enabling it. The
[review alternatives](Experiments/NAVIGATION_API_HISTORY.md#protocol-compatibility-recommendation)
explain why a new protocol requirement or concrete-monitor API was not selected.

### Objective-C companion

The [canonical Objective-C inventory](STABLE_API_REVIEW.md#objective-c-selector-inventory)
owns selector names. Companions share Swift's iOS15 callability and route
selection. The provisional thread guard returns nil from an off-main factory
and safely ignores invalid off-main targeted calls before UIKit or actor access.
The [safety review contract](STABLE_API_REVIEW.md#objective-c-safety-before-release-exposure)
and ordinary Release exposure still require F01 approval.

### Automatic-tracking coexistence requirement

A targeted manual view owns only its scene/key and suppresses its duplicate
automatic view. The per-scene stack keeps a manual suffix authoritative while
trustworthy automatic navigation continues beneath it. Retain only the latest
committed underlying destination; staged intermediates emit no current view.
Stopping the exact manual entry applies stop-call attributes and reveals that
latest destination as a fresh occurrence:

```text
automatic Home H1 → manual Compose M1 → automatic Home H2
```

H2 must differ from H1. The scene must not remain off-view, emit a duplicate,
reveal a generic hosting fallback instead of the retained semantic destination,
or affect a peer scene. A newly trustworthy semantic destination may replace
the retained candidate beneath manual authority.

Distinct manual keys may nest. Stopping Preview above Compose creates a fresh
Compose occurrence. Repeating an already active `(scene, key)` is instrumentation
misuse; remain crash-safe without restart, reference-counting or handle semantics.
Same-key entries in different scenes remain independent on qualified routes.
[The coexistence history](Experiments/NAVIGATION_API_HISTORY.md#automatic-tracking-coexistence-requirement)
retains the failed direct-command attempts and exact-owner discriminators.

## SwiftUI semantic navigation

### Customer compatibility and engine boundary

The semantic engine handles scene ownership, accepted destinations,
materialization, commit/cancellation, reveal and occurrence identity. The
application keeps layout, animation, gestures, deep links and presentation state.
Do not require Datadog replacements for `.sheet`, `.fullScreenCover`, destination
modifiers or customer navigation containers. The same contract applies to custom
SwiftUI containers, third-party routers and UIKit navigation hosting SwiftUI.

`RUMNavigationHost` attaches the scene and authority boundary around customer
content. The stable proposal has content-only, accepted-state Publisher and
Observation forms; their declarations live in the
[canonical semantic API inventory](STABLE_API_REVIEW.md#stable-semantic-host-proposal).
A content-only host retains automatic inference and crash-safe fallback. It does
not promise exact reconstruction without a trustworthy source.

### Integration inputs and precedence

Exact input uses this precedence:

1. An explicit stable source from an existing-router or third-party adapter.
2. An optional type-erased capability supplied by the container.
3. Native adapter knowledge in the experimental `RUMNavigationStack` convenience.
4. Scene-aware automatic discovery.
5. Existing process-representative fallback.

The first-release stable adapter uses the accepted-state Publisher host.
Low-level prepare/commit/cancel APIs, capability types and the transitions host
initializer remain experimental. They must not require RUM calls in every
navigate, pop, present or dismiss method.

```swift
// Proposed call site inside a MainActor-isolated SwiftUI integration.
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
```

The source must synchronously supply the accepted current destination when the
host first evaluates and publish accepted commits early enough to own immediate
lifecycle work. A descendant `.task`, render-time destination value, callback
after the navigation method returns or later suspension point cannot supply that
guarantee. Eventual correct state does not repair earlier attribution.

A configured source with no initial value does not select a lower-precedence
capability or suppress automatic tracking. Authority begins only after a
trustworthy destination is accepted and materialized. Pin the selected source
across SwiftUI reconstruction so a computed replacement cannot replay or
disconnect the current occurrence. The host obtains its scene from the inherited
iOS27 trait; its `in:` argument selects the Datadog core, not a UIWindowScene.

The Observation form reads one atomically updated accepted-state property through
a stable, side-effect-free projection. Synchronous one-shot `.didSet` observation
rearms before the setter returns. Separate route/presentation writes are separate
commits; the SDK does not invent a transaction between them. Guard this initializer
with both iOS27 availability and compiler>=6.4. Use the Publisher form when the
compiler cannot build it. Plain local SwiftUI `@State` is not an Observable
source, and continuous Observation delivered later cannot own earlier work.

A third-party adapter may seed a current-value stream from accepted state and
register once for synchronous committed-state callbacks. It must distinguish
equal-route occurrences and keep one registration through reconstruction. The
library need not expose Combine or Observation directly. Prefer an explicit
adapter over retroactive conformance, and add no library dependency to the core.
If no trustworthy state, materialization, transition or content-builder signal
exists, retain automatic tracking and sparse manual exceptions; document the
limit instead of guessing. The
[input history](Experiments/NAVIGATION_API_HISTORY.md#integration-inputs-and-precedence)
retains rejected inputs and the timing evidence behind these rules.

### Native convenience proof

`RUMNavigationStack` and its presentation helpers remain experimental and
optional. They share the semantic engine and should preserve native navigation
behavior. Binding writes reconcile with the accepted getter; an uncommitted
proposal cannot advance RUM state. Inherited scene context may promote only an
already reader-proven dormant boundary in the same scene; it cannot recover or
migrate disconnected state. The
[native-convenience history](Experiments/NAVIGATION_API_HISTORY.md#native-convenience-proof)
contains the original API shape, implementation revisions and experiment results.

### Resolver and path model

Automatic metadata is the default, with sparse centralized overrides. Exactness
must not depend on a RUM-only exhaustive route/presentation resolver. A complete
resolver is optional when the app already owns one or wants complete custom
naming. Do not use a nil result to mean both automatic fallback and intentional
absence of a RUM destination. Associated values, occurrence tokens and scene IDs
are never automatically serialized.

Typed `Binding<[Route]>` input can expose committed order and repeated values to
a native adapter. A type-erased `NavigationPath` exposes no public sequence of
its elements, so heterogeneous paths need another trustworthy semantic source.
Do not promise arbitrary path introspection or require path conversion.

Occurrence identity belongs to a committed position and transition, not the
route's Hashable value, its metadata or a SwiftUI view value. Equal routes may
create distinct occurrences. A same-turn push/revert or cancelled interactive
transition creates no speculative view. Completed return navigation creates a
fresh occurrence while preserving application state. Occurrence tokens stay in
memory and are neither RUM UUIDs nor telemetry attributes.

### Authority boundary

Authority is local to the exact native subtree and scene. Semantic or exceptional
manual instrumentation suppresses its own automatic duplicate while unrelated
containers continue tracking. A suppression-only reader publishes no lifecycle;
the centralized router remains the semantic owner. A missing or collapsed
sibling-controller topology is inconclusive evidence, even if event counts match.

Exceptional `.trackRUMView` instrumentation owns only its explicit occurrence.
Returning must reveal a fresh destination before outside customer work, or the
integration must disclose that timing limitation. The
[authority history](Experiments/NAVIGATION_API_HISTORY.md#authority-boundary)
retains ancestry witnesses and sibling/scene isolation findings.

### Presentation state

Sheets, full-screen covers, UIKit presentations and custom overlays change the
scene's one current destination. They are not concurrent views. With a trustworthy
source, dismissal starts a fresh underlying occurrence before post-dismiss work
and suppresses only the presentation's duplicate. Otherwise automatic tracking
remains the fallback and standard presentation call sites stay unchanged.

A same-turn presentation proposal that never commits starts no view. Direct
Sheet → Cover → Sheet replacement keeps the underlying view hidden until final
dismissal and gives each committed presentation its own occurrence. Router
semantic authority and native-subtree suppression have different lifetimes:
final aggregate processing may outlive semantic stop. The
[presentation history](Experiments/NAVIGATION_API_HISTORY.md#presentation-state)
retains the independent sheet/cover journeys and their exact-owner evidence.

## Required review and test matrix

EXP-225 supplies provisional iOS15-targeted client compilation, older-runtime
legacy parity with automatic tracking on/off, and exactly-once custom/NOP
forwarding. Approved normal-import Swift and Objective-C Release clients remain
required before public promotion. Check attributes,
completion behavior and coherent start/stop routing. Run the bounded older-iPad
owner discriminator before enabling each scene-aware family; iPadOS17.5 is the
available execution baseline, not evidence of iOS15 execution. These checks
leave semantic-host iOS27 and Observation compiler guards intact.

Qualified scene-aware manual views require:

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
- native convenience, existing-router, and callback-driven third-party adapters
  produce identical occurrence semantics without retroactive conformance;
- a callback-driven adapter seeds the current accepted snapshot synchronously,
  publishes only accepted commits before the navigation method returns,
  distinguishes equal-route occurrences, and keeps one registration through
  SwiftUI reconstruction;
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

## API review

The [stable API review](STABLE_API_REVIEW.md) owns the eight decisions, declaration
inventory and attributable approval record. Stable proposals include accepted-state
Publisher/Observation hosts and scene-current targeting. Low-level transitions,
capabilities and native convenience remain experimental. Manual-key/controller
target factories are outside the first release.

[Operation targeting](OPERATIONS.md) and other telemetry share that review.
The [gate register](release-gates.json) owns remaining acceptance; this split adds
no gates, changes no verdicts and approves no public declarations. Historical
observations moved to [navigation history](Experiments/NAVIGATION_API_HISTORY.md),
with the section map in the
[consolidation record](Results/navigation-documentation-consolidation-20260924.json).
