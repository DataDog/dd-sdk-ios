# RUM multi-scene navigation API proposal

Read this document when reviewing the optional SwiftUI semantic-navigation
integration or scene-aware manual view APIs. The product behavior is approved;
the concrete public API is not. The [canonical overview](../MULTI_SCENE_SUPPORT.md)
owns the support verdict, [PLAN.md](PLAN.md) owns delivery order, and
[EXPERIMENTS.md](EXPERIMENTS.md) owns runtime evidence.

Last updated: 2026-09-14

## Status

Do not implement or publish the APIs in this document before normal API and RFC
review. They change public Swift and Objective-C surfaces and affect view
lifecycle behavior. The examples below are review starting points, not settled
signatures.

The approved behavior is:

- automatic SwiftUI tracking remains the zero-code default;
- exact SwiftUI navigation may be installed once per independent navigation
  container and consumes the customer's existing path or router;
- route-to-RUM metadata is centralized rather than repeated in destinations;
- one committed navigation occurrence creates one RUM view ID, so
  Home H1 -> Detail D1 -> Home H2 uses three distinct IDs;
- a semantic container or exceptional manual view is authoritative only within
  its target and suppresses only its duplicate automatic view;
- each scene has one current destination; structural panes and tabs are not
  parallel RUM views;
- the same manual key can be active independently in different scenes; and
- no public API accepts a RUM UUID, serializes a scene identifier, or introduces
  an interim window attribute or session boundary.

## Existing API and implementation constraints

Today, keyed manual views are process-inferred:

```swift
rum.startView(key: "compose", name: "Compose")
rum.stopView(key: "compose")
```

An attached `UIViewController` already supplies its `windowScene`; an unattached
controller and keyed calls use the current execution handoff when available,
then the process representative. That fallback remains unchanged.

The internal command model already accepts a scene target, and focused tests
prove that the same `ViewIdentifier` can coexist in scene A and scene B and that
stopping A leaves B active. A public bridge therefore needs to capture
`scene.session.persistentIdentifier` synchronously and route the existing
start/stop intent. It does not need a second scene registry or a wire change, but
`EXP-120` proves it cannot send the existing direct command unchanged: that path
bypasses the platform-view stack and has no authority over later automatic
appearances.

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

### Automatic-tracking coexistence requirement

The public monitor's direct keyed commands currently bypass
`RUMViewsHandler`'s per-scene platform-view stack. A start can replace the
current automatic view, but a later direct stop has no retained platform entry
from which to restart the underlying occurrence. More importantly, an automatic
appearance after the direct start can immediately preempt the manual view. The
new overload cannot be declared complete by routing `.scene` alone.

Implementation must either integrate targeted manual entries with the same
per-scene view stack or provide an equivalent, tested reveal mechanism. Required
result:

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

The smallest internal design is a weak scene-targeted manual-view capability on
`Monitor`, bound to `RUMViewsHandler` when instrumentation is published. Targeted
start and stop use the handler's per-scene stack. While a manual suffix is active,
later automatic appearances are staged immediately below it without emitting RUM
commands; removing the exact scene/key manual entry applies stop-call attributes
and reveals the newest valid underlying entry as a fresh occurrence. Nested
manuals must keep the entire manual suffix authoritative. Existing source-less
methods remain on their inferred direct-command path.

`EXP-119` also shows a
narrower existing modifier boundary: an exceptional explicit Sheet S1 correctly
suppresses its automatic duplicate and automatic Home H2 eventually returns, but
work in SwiftUI's immediate `onDismiss` callback still belongs to S1 because H2
has not started yet. Settled work belongs to H2. This is a real attribution gap,
not a reason to weaken the oracle.

## SwiftUI semantic navigation

### Required customer shape

Integration occurs once per independent container and uses application-owned
state:

```swift
RUMNavigationStack(
    path: $router.path,
    root: RUMView(name: "Home"),
    destination: router.rumView
) {
    HomeView()
} destinationContent: { route in
    router.view(for: route)
}
```

The product's preferred modifier-shaped spelling remains valid as an ergonomic
goal:

```swift
NavigationStack(path: $router.path) {
    HomeView()
}
.trackRUMNavigation(
    path: $router.path,
    root: RUMView(name: "Home"),
    destination: router.rumView
)
```

The implementation cannot be selected from spelling alone. `EXP-047` through
`EXP-049` show that a passive modifier outside an already-built
`NavigationStack` learns about a destination too late for its first lifecycle
work. `EXP-116` passes because the probe wrapper owns the root and typed
destination builders and installs the route-owned tracking boundary where each
destination materializes. A final modifier is acceptable only if it provides an
equivalent materialization boundary; a path observer by itself is not.

### Resolver and path model

The first review should prefer a typed application route, normally an enum, and
a centralized nonoptional resolver:

```swift
@MainActor
func rumView(for route: AppRoute) -> RUMView
```

An optional result is ambiguous between "allow automatic tracking here" and
"intentionally emit no RUM destination." If partial semantic coverage is needed,
model that choice explicitly rather than giving `nil` two meanings.

A typed `Binding<[Route]>` can expose committed order and repeated values. A
type-erased `NavigationPath` does not provide a public sequence of its elements,
so support for heterogeneous paths requires a different integration or an
application router that exposes its semantic route list. API review must not
promise arbitrary `NavigationPath` introspection.

Occurrence identity belongs to a committed path position and transition, not to
`Route`, `Hashable`, a destination view value, or its RUM metadata. Equal routes
can create different occurrences. A same-turn push and revert creates none.
Interactive cancellation retains the prior occurrence; completion creates the
returned destination's fresh occurrence.

### Authority boundary

The current internal authority registry suppresses automatic discovery when an
active explicit reader is contained by an automatic candidate controller.
`EXP-115` proves this for one container and `EXP-118` partially proves that scene
A does not suppress scene B. Before shipping, cover two independent navigation
containers hosted by one SwiftUI controller. One explicit container must not
silence automatic tracking in an unrelated sibling container.

Exceptional `.trackRUMView` instrumentation remains supported alongside a
semantic container. It owns only its explicit occurrence. Returning from that
exception must reveal a fresh current destination before customer work that is
semantically outside the exception, or the limitation must remain explicit until
the container/router integration can provide that earlier signal.

### Presentation state

The first API review must decide whether the navigation integration observes only
the stack path or the router's complete current destination, including sheets and
full-screen covers. A stack-only API can satisfy push/pop semantics but cannot by
itself close the immediate-dismiss gap from `EXP-119`. Do not silently treat a
presented destination as a second concurrent view; it replaces the scene's one
current destination until dismissal.

## Required review and test matrix

Scene-aware manual views require:

- same key in A and B, then stop A and prove B remains active;
- reverse-order stops and repeated occurrences;
- explicit A target overriding a B process representative;
- explicit target with no current A view that does not fall into B;
- manual exceptional view over automatic H1 -> M1 -> fresh H2;
- automatic appearance or replacement while M1 is active is staged beneath M1
  and emits no intervening current view;
- nested targeted manual entries preserve an authoritative manual suffix;
- automatic tracking continuing in another scene and sibling container;
- scene close while the manual view is active;
- stop-call attributes are applied to M1's stop event;
- the restarted H2 UUID differs from H1;
- Swift and Objective-C forwarding parity;
- `NOPMonitor` and third-party conformer fallback invoked exactly once; and
- no retained `UIWindowScene`, `UIWindow`, or controller after capture.

Semantic SwiftUI navigation requires:

- Home H1 -> Detail D1 -> Home H2 with distinct IDs;
- equal same-named Detail D1 -> Detail D2 occurrences;
- same-turn push/revert and interactive cancellation with no speculative view;
- state preservation when only the RUM occurrence rotates;
- root, destination, modal, and retained-return lifecycle work on the intended
  occurrence;
- coexistence with automatic tracking, a manual exception, a sibling container,
  and another scene without duplicate or global suppression;
- one current destination for split/tab structures;
- scene disconnect, reconnect, restoration, and session rollover; and
- unchanged automatic-only and single-scene behavior.

## API-review questions

1. Wrapper, modifier with destination builders, or another shape that provides
   the proven materialization boundary?
2. Typed `[Route]` only in the first release, or a router protocol that can also
   describe heterogeneous paths and presentation state?
3. Reuse `RUMView` as route metadata or introduce a smaller navigation-specific
   descriptor with an explicit tracked/untracked decision?
4. Extension-only manual overload with private capability, or defaulted public
   protocol requirements after library-evolution review?
5. Does the first semantic API own modal presentation state, or does the manual
   reveal mechanism close `EXP-119` independently?
6. Can the authority registry isolate sibling containers inside one hosting
   controller without unsupported SwiftUI hierarchy assumptions?
7. Do targeted manual keys share the existing keyed namespace with semantic
   SwiftUI occurrences, and what is the exact duplicate targeted-start behavior?
8. How should Objective-C callers that invoke a `UIWindowScene` overload away
   from the main thread be handled without retaining or asynchronously dereferencing
   the scene?

The Operation target proposal and its additional exact-view forms remain in
[OPERATIONS.md](OPERATIONS.md). Both reviews should share one internal logical
target representation, but they do not need to expose one public type unless that
improves actual call sites.
