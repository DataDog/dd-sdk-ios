# RUM Operations multi-scene contract

Read this document when changing Operation identity, per-step view attribution,
duplicate-start behavior, the proposed public targeting API, customer guidance,
or Operations tests. This is the authoritative home for the Operations contract;
the [canonical overview](../MULTI_SCENE_SUPPORT.md) carries only its summary.

Last updated: 2026-09-16

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

The internal routing and warning changes are implemented, and the scene-targeted
manual-view prerequisite passes through customer-shaped Swift calls in `EXP-137`
through `EXP-140`. `EXP-155` now implements and accepts the first bounded
Operation escape hatch as an iOS 27 experimental/SPI surface. Its Swift and
Objective-C call sites, custom-conformer/NOP fallback, explicit-over-inferred
precedence, unresolved-target fallback, and cross-scene runtime usefulness pass.
It must not be promoted to the supported public API surface until normal review
approves the exact names and contracts. `EXP-158` then demonstrates that the
same scene-current concept applies to one-shot actions, so the experimental
value is now named `RUMViewTarget` rather than being Operation-specific. The
earlier Swift `RUMOperationViewTarget` spelling remains an SPI type alias while
review is pending. The longer-term value-type proposal, which never exposes
internal RUM UUIDs, remains:

```swift
public struct RUMViewTarget {
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

The first bounded SPI should expose only `current(in:)`. It is sufficient to
exercise the approved cross-window customer workflow and does not pre-decide how
manual keys or controller identity should be represented publicly. Existing
source-less methods already provide inferred/default behavior, so the first SPI
does not need a redundant `.inferred` value. API review can add
`tracked(key:in:)`, `tracked(_:)`, and an explicit inferred spelling after the
value type and Objective-C companion have real call-site evidence.

The command must preserve the explicit target separately from its independently
captured call-site inference. Collapsing both into the existing `command.target`
would skip precedence level 2 whenever an explicit target cannot resolve. Session
processing must resolve the explicit candidate first, then the inferred candidate;
only a candidate that resolves to a live tracked view is trustworthy. The manager
then applies its retained snapshot and process-representative fallbacks. Supporting
the exact-view forms requires an internal logical target keyed by `ViewIdentifier`
plus a scene where the identity is not globally unique, never a public RUM UUID.

To avoid making a new requirement on every external `RUMMonitorProtocol`
conformer, the experimental prototype uses extension-only overloads backed by a
private targeting capability. A custom conformer or NOP monitor calls the
existing inferred method exactly once. The generalized Objective-C companion is
`DDRUMViewTarget` and likewise exposes only `currentInScene:` in Debug builds.
`inferred`,
`trackedViewWithKey:inScene:`, and `trackedViewController:` remain API-review
options rather than implemented claims. The SPI uses the same iOS 27 availability
boundary as the scene-targeted manual-view prerequisite in
[NAVIGATION_API.md](NAVIGATION_API.md). Stable review must choose whether to keep
that boundary or expose broader legacy-compatible behavior.

The scene-targeted manual prerequisite is now implemented as an iOS 27 Swift SPI
with Debug-only Objective-C companions. `EXP-137` through `EXP-140` replace the
probe's internal-only calls with the customer-shaped overloads and validate
manual, nested, duplicate-start, Sheet, and full-screen-cover paths. The same-key
A/B live discriminator remains hardware-gated, but no longer blocks implementing
the Operation target: `.current(in:)` needs only the existing scene/current-view
lookup and exposes no internal RUM UUID. The concrete manual-view evidence is in
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

`EXP-131` defines the inferred cross-scene discriminator without weakening that
evidence boundary. Its `operations.cross-scene.lifecycle` driver starts success
and failure in A and completes them in B. It then starts same-name Operations
with distinct `parallel-alpha` and `parallel-beta` keys in A and B and completes
B before A. The 100/100 hostless plan verifies all eight invocations and rejects
shared A/B view identity, wrong-scene B ownership, a B completion on A, and A
owner drift after B completes. Its initial physical run was harness-inconclusive
before any Operation because the non-navigating scenario still depended on a
stale navigation occurrence source. `EXP-157` replaces only that irrelevant Home
boundary, then passes 24/24 on two physical native scenes. Backend session
`1dd8d491-19a4-4b67-bfa5-13df5b2a73a6` contains all eight raw steps and four
exact A→B/A→A/B→B reduced Operations, with beta completing before alpha. This
accepts inferred cross-scene ownership. Both windows were full-screen rather
than simultaneously visible, so only the topology qualifier remains human-gated.

`EXP-155` closes the explicit-target discriminator without requiring simultaneous
visibility. Its corrected serial two-native-scene run deliberately makes the
opposite scene the process representative around every call while passing an
explicit `.current(in:)` target. The 24/24 local oracle and backend session
`bcb168fd-b5df-42ed-b416-b505a42e6e76` contain two distinct Home owners, exactly
eight raw `operation_step` vitals, and exactly four reduced Operations:

- cross-success A→B;
- cross-failure A→B with failure reason `error`;
- parallel-alpha A→A;
- parallel-beta B→B, whose end precedes alpha's end.

Three preceding attempts remain documented as invalid: one restored the wrong
logical scene despite a clean container, one was confounded by an accessibility
capture timeout, and a capture-free retry proved the stale occurrence-source
harness never seeded Home. The signed correction `eb1dd2fdc` uses explicit
per-scene Home boundaries because this experiment targets Operation routing, not
navigation. This is accepted engine and call-site evidence, not stable API
approval. `EXP-157` separately accepts the inferred physical call-site row.

The last-proven snapshot described by this document is Operation-instance state:
it protects later Operation steps when their originating scene has closed. The
shared `RUMViewTarget` does not give one-shot actions an Operation snapshot; an
action resolves its explicit target, then its independently captured inference,
then the existing representative behavior.

Required test coverage is tracked explicitly:

| Required case | Current coverage | Status |
| --- | --- | --- |
| Start in A, succeed in B | Manager/session-scope assertions, explicit-target `EXP-155`, and inferred physical `EXP-157` raw/reduced backend proof | Focused plus explicit and inferred live backend pass |
| Start in A, fail in B | Manager failure assertions, explicit-target `EXP-155`, and inferred physical `EXP-157` raw/reduced backend proof | Focused plus explicit and inferred live backend pass |
| Start in A1, navigate in A, end in A2 | Manager/session-scope assertions plus `EXP-130` success and failure backend documents | Focused and live backend pass |
| Parallel A/B, same name, different keys | Manager identity/view sequence plus explicit-target `EXP-155` and inferred physical `EXP-157` alpha/beta runs | Focused plus explicit and inferred live backend pass |
| Reverse-order completion | Manager sequence plus `EXP-155` and `EXP-157` raw beta-before-alpha completion | Focused plus explicit and inferred live backend pass |
| Explicit target overrides wrong representative | Session-scope regression plus every customer-shaped `EXP-155` call opposing the representative | Focused and live backend pass |
| Trustworthy inferred B overrides stored A | Manager scene-B step regression, including update/retry snapshot refresh | Focused pass |
| Closed origin with no new context uses snapshot | Manager vital/message retained-view assertions plus backend teardown run | Focused and backend pass |
| Closed origin then explicit B completion uses B | Manager exact-view assertion | Internal pass; public-shaped close/re-target runtime remains a later target-form row |
| Duplicate identity has corrected warning and no synthetic end | Manager warning plus exact `[start, start, end]` step sequence, with both a reused key and omitted key; `EXP-130` raw/reduced backend proof | Focused and live backend pass; earlier raw start is orphaned as specified |
| Existing single-scene and source-less behavior | Representative-change and legacy no-view regressions | Focused pass; current full 1,255-test RUM suite passes with zero failures |

API review must settle the public Operation target type/name, availability, and
exact Swift/Objective-C signatures. It must also decide whether and how to add
manual-key/controller forms. That review blocks stable exposure, not the now-
accepted `.current(in:)` SPI experiment. The requested
application-wide identity means that scenes do not
namespace an Operation; it does not add a new cross-session persistence contract.
The manager and its retained view snapshot remain session-local, while duplicate
starts follow the explicitly requested four-hour orphan-timeout warning. Any
change to cross-session Operation semantics is separate backend/product work and
does not block the multi-scene implementation. Emitted steps remain best-effort
and are never rejected only because local tracking state is absent.
