# RUM Operations multi-scene contract

Read this document when changing Operation identity, per-step view attribution,
duplicate-start behavior, the proposed public targeting API, customer guidance,
or Operations tests. This is the authoritative home for the Operations contract;
the [canonical overview](../MULTI_SCENE_SUPPORT.md) carries only its summary.

Last updated: 2026-09-13

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

The internal routing and warning changes are implemented. The public escape hatch
is deliberately not implemented until API review because it changes the SDK
surface and needs Swift, Objective-C, and protocol-conformance compatibility
decisions. A value-type proposal that does not expose internal RUM UUIDs is:

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
conformer, review should use extension-only overloads backed by a private targeting
capability, with the existing inferred method called exactly once for custom
conformers and the NOP monitor. The Objective-C surface needs a
`DDRUMOperationViewTarget` companion with `inferred`, `currentInScene:`,
`trackedViewWithKey:inScene:`, and `trackedViewController:` factories. Use the
repository's existing non-watchOS UIKit availability convention rather than
gating the API to iOS 27; `UIWindowScene` predates the SDK's iOS 15 minimum.

One prerequisite remains: the public `startView(key:)` API cannot explicitly bind
that manual key to a scene. A keyed target is deterministic only if the view
already received scene ownership through internal/SwiftUI tracking. API review
must therefore include scene-targeted manual keyed-view start/stop overloads, or
drop the keyed target until that ownership can be established safely.

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

Required test coverage is tracked explicitly:

| Required case | Current coverage | Status |
| --- | --- | --- |
| Start in A, succeed in B | Manager and session-scope start/end view assertions | Focused pass; live backend pending |
| Start in A, fail in B | Manager start/end view and failure-reason assertions | Focused pass; live backend pending |
| Start in A1, navigate in A, end in A2 | Manager and session-scope navigation assertions | Focused pass |
| Parallel A/B, same name, different keys | Manager identity and view sequence | Focused pass |
| Reverse-order completion | Manager identity and view sequence | Focused pass |
| Explicit target overrides wrong representative | Session-scope internal scene-target regression | Internal pass; public overload test pending API review |
| Trustworthy inferred B overrides stored A | Manager scene-B step regression, including update/retry snapshot refresh | Focused pass |
| Closed origin with no new context uses snapshot | Manager vital/message retained-view assertions plus backend teardown run | Focused and backend pass |
| Closed origin then explicit B completion uses B | Manager exact-view assertion | Internal pass; public overload test pending API review |
| Duplicate identity has corrected warning and no synthetic end | Manager warning plus exact `[start, start, end]` step sequence, with both a reused key and omitted key | Focused pass; live warning/raw-vital proof pending |
| Existing single-scene and source-less behavior | Representative-change and legacy no-view regressions | Focused pass; current full 1,122-test RUM suite passes |

API review must settle the public type/name and the scene-targeted keyed-view
prerequisite. The requested application-wide identity means that scenes do not
namespace an Operation; it does not add a new cross-session persistence contract.
The manager and its retained view snapshot remain session-local, while duplicate
starts follow the explicitly requested four-hour orphan-timeout warning. Any
change to cross-session Operation semantics is separate backend/product work and
does not block the multi-scene implementation. Emitted steps remain best-effort
and are never rejected only because local tracking state is absent.
