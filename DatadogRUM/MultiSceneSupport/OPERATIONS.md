# RUM Operations multi-scene contract

Read this document when changing Operation identity, per-step view attribution,
duplicate-start behavior, the proposed public targeting API, customer guidance,
or Operations tests. This is the authoritative home for the Operations contract;
the [canonical overview](../MULTI_SCENE_SUPPORT.md) carries only its summary.

Last updated: 2026-09-15

## RUM Operations contract and API review proposal

The implemented internal contract is:

1. Resolve every start, update, retry, success, and failure independently.
2. Prefer an explicit customer target, then a reliably inferred call-site view
   and scene, then the operation's last-proven view snapshot, then the existing
   process representative for compatibility.
3. Whenever an explicit or reliably inferred target resolves a live tracked view,
   refresh the operation's retained snapshot with that view. A process-
   representative fallback is not proof and must not overwrite the snapshot.
4. Use exact `(name, operationKey)` identity across every scene. Two independent
   instances with the same name need different opaque keys.
5. On a duplicate start, emit both starts as requested, replace only the SDK's
   locally tracked latest instance, and emit no client-side end. A later success
   or failure ends that latest instance. The earlier backend operation remains
   open until its four-hour timeout.

The internal routing and warning changes are implemented. The customer-shaped
escape hatch should now be implemented and exercised as an iOS 27
experimental/SPI surface. This validates its Swift and Objective-C call sites,
protocol-conformance fallback, and runtime usefulness before normal API review.
It must not be promoted to the supported public API surface until that review
approves the exact names and contracts. A value-type proposal that does not
expose internal RUM UUIDs is:

```swift
public struct RUMOperationViewTarget {
    public static let inferred: Self

    @MainActor
    public static func current(in scene: UIWindowScene) -> Self

    @MainActor
    public static func tracked(key: String, in scene: UIWindowScene) -> Self

    @MainActor
    public static func tracked(_ viewController: UIViewController) -> Self
}
```

The current APIs would remain unchanged. New overloads would add a `view` argument
to `startOperation`, `succeedOperation`, and `failOperation`; any future public
update or retry API must add the same targeting capability. For example:

```swift
rum.startOperation(
    name: "thread_open",
    operationKey: operationKey,
    view: .current(in: sceneA)
)

rum.succeedOperation(
    name: "thread_open",
    operationKey: operationKey,
    view: .current(in: sceneB)
)
```

The `view` argument must remain required on these overloads so it does not become
ambiguous with the existing convenience methods. The SDK should synchronously
turn UIKit objects into opaque values before enqueueing the command: a scene's
persistent identifier, a manual `ViewIdentifier.key`, or a controller's
`ObjectIdentifier`. It must not retain UIKit objects on the RUM queue.
`current(in:)` resolves the current tracked view in the given scene.
`tracked(key:in:)` matches a manually tracked key inside that scene, and
`tracked(_:)` matches the tracked controller instance.

The command must preserve the explicit target separately from its independently
captured call-site inference. Collapsing both into the existing `command.target`
would skip precedence level 2 whenever an explicit target cannot resolve. Session
processing must resolve the explicit candidate first, then the inferred candidate;
only a candidate that resolves to a live tracked view is trustworthy. The manager
then applies its retained snapshot and process-representative fallbacks. Supporting
the exact-view forms requires an internal logical target keyed by `ViewIdentifier`
plus a scene where the identity is not globally unique, never a public RUM UUID.

To avoid making a new requirement on every external `RUMMonitorProtocol`
conformer, the experimental prototype should use extension-only overloads backed
by a private targeting capability, with the existing inferred method called
exactly once for custom conformers and the NOP monitor. The Objective-C surface
needs a
`DDRUMOperationViewTarget` companion with `inferred`, `currentInScene:`,
`trackedViewWithKey:inScene:`, and `trackedViewController:` factories. Use the
same availability decision as the scene-targeted manual-view prerequisite in
[NAVIGATION_API.md](NAVIGATION_API.md). `UIWindowScene` predates the SDK's iOS 15
minimum, but the validated coexistence contract currently targets declared
multi-scene applications on iOS 27. API review must choose whether to expose the
overloads broadly with legacy-compatible behavior or annotate them for iOS 27;
the Operations proposal must not decide that independently.

One required prerequisite remains: the existing `startView(key:)` API cannot
explicitly bind that manual key to a scene. The next implementation slice adds
iOS 27 experimental/SPI scene-targeted manual keyed-view start/stop overloads and
Objective-C counterparts, then replaces the probe's internal-only calls with
those customer-shaped calls. The same key
may be active independently in A and B, and an explicit stop in A must close only
A. Existing APIs retain inferred/last-interacted behavior, while an explicit scene
wins over the process representative. This establishes deterministic ownership
for the Operation target without exposing internal RUM UUIDs. The concrete
starting point and automatic-view coexistence constraint are consolidated in
[NAVIGATION_API.md](NAVIGATION_API.md).

Customer documentation shipped with that API must state that scenes do not
disambiguate Operations automatically. For a cross-window Operation:

1. Generate one opaque operation key.
2. Start the Operation in scene A.
3. Pass the key to scene B through application window-routing state or
   `NSUserActivity`.
4. Complete it in scene B with the exact same name and key.
5. Explicitly provide the start/end view when call-site inference is unavailable.

Independent loads in identical windows must use distinct identities, for example
`feed_load/key-A-1` and `feed_load/key-B-1`. Reusing a key, or omitting it for
concurrent same-name work, can leave the earlier Operation open until the four-
hour backend timeout.

## Current runtime evidence

`EXP-130` adds a clean named probe for the part of the contract that can be
decided without stable simultaneous windows. It passes 27/27 locally and raises
the full probe plan to 93/93. Backend intake contains seven raw Operation steps
and three reduced Operations:

- success starts on Home H1 and ends on fresh Detail D1;
- failure starts on Home H2 and ends on fresh Detail D2 with its failure reason;
- a duplicate identity starts on Home H3, starts again on Detail D3, and ends on
  D3. The reduced Operation uses D3 for both ends, while the earlier H3 raw start
  has no synthetic end and remains open for the four-hour timeout.

The exact corrected duplicate warning appeared and the session had no error event
or app/SDK crash. The probe's local signals intentionally attest only that the SDK
API was invoked from the expected scene and navigation occurrence. Operation-step
vitals bypass public event mappers, so raw and reduced backend documents are the
attribution oracle. This result closes same-scene navigation, failure, and
duplicate semantics; it does not close A-to-B completion or the public target.
Exact run, session, view, and artifact identifiers remain in the
[experiment ledger](EXPERIMENTS.md).

`EXP-131` prepares the remaining live discriminator without weakening that
evidence boundary. Its `operations.cross-scene.lifecycle` driver starts success
and failure in A and completes them in B. It then starts same-name Operations
with distinct `parallel-alpha` and `parallel-beta` keys in A and B and completes
B before A. The 100/100 hostless plan verifies all eight invocations and rejects
shared A/B view identity, wrong-scene B ownership, a B completion on A, and A
owner drift after B completes. It deliberately makes no live or backend claim;
the unchanged scenario is queued for iPhone Duo or a physical multi-window iPad.

Required test coverage is tracked explicitly:

| Required case | Current coverage | Status |
| --- | --- | --- |
| Start in A, succeed in B | Manager/session-scope assertions plus the exact `EXP-131` hostless driver and ownership oracle | Focused/hostless pass; live backend pending |
| Start in A, fail in B | Manager failure assertions plus the exact `EXP-131` hostless driver and ownership oracle | Focused/hostless pass; live backend pending |
| Start in A1, navigate in A, end in A2 | Manager/session-scope assertions plus `EXP-130` success and failure backend documents | Focused and live backend pass |
| Parallel A/B, same name, different keys | Manager identity/view sequence plus `EXP-131` `parallel-alpha`/`parallel-beta` driver | Focused/hostless pass; live backend pending |
| Reverse-order completion | Manager sequence plus `EXP-131` B-before-A driver order | Focused/hostless pass; live backend pending |
| Explicit target overrides wrong representative | Session-scope internal scene-target regression | Internal pass; experimental overload pending after manual-view prerequisite |
| Trustworthy inferred B overrides stored A | Manager scene-B step regression, including update/retry snapshot refresh | Focused pass |
| Closed origin with no new context uses snapshot | Manager vital/message retained-view assertions plus backend teardown run | Focused and backend pass |
| Closed origin then explicit B completion uses B | Manager exact-view assertion | Internal pass; experimental overload pending after manual-view prerequisite |
| Duplicate identity has corrected warning and no synthetic end | Manager warning plus exact `[start, start, end]` step sequence, with both a reused key and omitted key; `EXP-130` raw/reduced backend proof | Focused and live backend pass; earlier raw start is orphaned as specified |
| Existing single-scene and source-less behavior | Representative-change and legacy no-view regressions | Focused pass; current full 1,169-test RUM suite passes |

API review must settle the public type/name and exact Swift/Objective-C signatures
for the approved scene-targeted keyed-view prerequisite. The requested
application-wide identity means that scenes do not
namespace an Operation; it does not add a new cross-session persistence contract.
The manager and its retained view snapshot remain session-local, while duplicate
starts follow the explicitly requested four-hour orphan-timeout warning. Any
change to cross-session Operation semantics is separate backend/product work and
does not block the multi-scene implementation. Emitted steps remain best-effort
and are never rejected only because local tracking state is absent.
