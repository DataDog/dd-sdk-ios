# Semantic, lifetime and automatic scenarios

Read only the scenario family needed by the admitted gate. Each linked fixture
README owns its exact check inventory; [evidence](EVIDENCE.md) and
[device procedures](DEVICE_INTERACTION.md) retain common boundaries.

## Semantic source and API integration

Start with deterministic ownership before a device happy path: accepted initial
identity, donor/nonreader callbacks, out-of-order generations, detach/disappear,
source replacement/reuse, disconnect/reconnect order, same-transfer versus fresh
cross-scene remount, and newer donor versus older destination. Preserve exact
occurrence/session/view identities and peer continuity, not just timeline names.

Seed trustworthy initial semantic state before host/root `onAppear` or `.task`.
Customer integration must not need internal RUM UUIDs. A source remains pinned
within a host lifetime: count resolutions and use a decoy second source to prove
that a later render cannot change it. Empty explicit/capability sources retain
automatic tracking until accepted attached state can replace it. Subscription alone
is not authority; cover absent handler and absent attachment with the real registry.

Nonreplaying publishers must supply a valid initial destination before suppression
and preserve explicit-over-capability/observed precedence. One-shot Observation
must rearm before synchronous delivery, including nested/back-to-back mutations;
ordinary render-time observation or a later task cannot close immediate ownership.
Keep continuous observation's next-suspension boundary and background fallback
explicit. Local `@State` without an observable source remains outside that guarantee.

Use accepted atomic navigation projections. Several separate property writes are
not one transaction. Binding adapters forward the transaction once, then read the
accepted value; rejection/canonicalization cannot commit the proposal. Opaque setter
interiors require an accepted-state callback/observation boundary for exact immediate
work. Sparse overrides remain an escape hatch, not per-screen/per-method migration.

Measure migration cost as named route/screen/navigation/integration edits and growth,
with no Datadog-specific customer state. Preserve ordinary sheet/cover behavior,
sparse overrides, automatic opaque fallback and the approved zero per-screen/per-
method target. A demo with SDK identifiers in app state is not that integration proof.
Use [NAVIGATION_API.md](../NAVIGATION_API.md) for product decisions and F01 for review.

A callback adapter must seed initial state, register once, handle equal routes,
cancel/commit and atomic presentation replacement, then tear down its token. If a
third-party callback arrives only after customer navigation returns, define that
different timing contract. Freeze both SDK and fixture before/after terminal and
backend checks, not only probe sources.

## Mounted lifetime and reconnect

Require real host appearance/disappearance, mounted registration/destination and
weak state/registration/instrumentation release after bounded drain. Keep sources
alive after removal so their deallocation cannot conceal a cycle. Verify original
method implementations restored after SDK stop; controller release or RSS alone
is insufficient. Do not add a synchronous MainActor XCTest wait that can itself
retain native hosts: keep a matched SDK-off control and condition-based async checks.
Start weak-release deadlines at the ownership-ending call, before event collection.

Separate inherited traits from accepted reader mounts. Reject disconnected
publication without consuming a generation. Reconnect callbacks must restore latest
accepted state before immediate Resource/Log markers, preserving peer continuity,
source pinning and weak configuration. For a no-body remount, capture the actual
reader callback before removal, restore it before readding the same host, observe
zero subscriptions first and submit markers inside the callback after SDK delivery.
Do not replace the root, reconcile the body or navigate to repair the observation.
Missing interception is inconclusive. Posted notifications are not actual OS order.

For pending Resource/view lifetime establish a live peer and process a public command
while it is active before requiring old restoration ownership to release. Prove
pending work, original owner, peer UUID/activity and SDK presence before teardown.
Retain legitimate configuration-delivery owners until their lifecycle ends. A leak
finding needs the actual retaining edge, not an SDK-off fixture's synchronous wait.
See [EXP-215](../Results/EXP-215-native-view-lifetime.json).

For display-link/core teardown observe the real native display-link and its owner,
not only a test double. Preserve linked lifetime and thread/reentrancy controls at
their recorded source boundary; [EXP-211](../Results/EXP-211-s2-lifetime.json)
owns the exact evidence. No automatic transfer to another composition follows.

## Presentation and observer ordering

Observe mounted sheet/cover `onAppear` before dismissal. At setter return and native
dismissal callbacks submit work before awaiting. Distinguish proposed/accepted values,
item ID and occurrence UUID. Retain rejection, canonicalization, same-ID style
replacement and A→B→A controls. A current accepted occurrence survives content
rematerialization; establish stability before injecting a stale callback.

Replacement can omit a style's `onDismiss`; do not invent callbacks or use them as
a commit signal. Keep the style recorder interval continuous when required and
reject an old callback reviving/stopping a newer occurrence. Synchronous dismissal
mutation and immediate/settled work need the correct pre/postrender boundary; a
later `onDismiss` proves a weaker contract. Container detach and scene disconnect
still cancel independently.

For observer reentrancy, whichever observer receives the outer value first triggers
nesting. Do not assume Dictionary order. Assert every live observer's generation at
nested return, lookup membership after removal, and give new observers only current
state. Initial and ordinary publication use the same oracle and actual source,
adapter and host objects. A simulator/backend run adds nothing to this synchronous
in-memory contract. See [EXP-174](../Results/EXP-174-observer-delivery.json).

## Resource, action and task controls

For late completion keep a *continuous* new-session action alive. An immediately
completed action hides leaked counts. Assert old Resource/error owner and foreign
action Resource/error counts, metrics, duplicates, fixed expiry and clock boundaries.
Use a fixed reference origin for nanoseconds; never widen time limits. Inspect
actual `actionStartTime` expiry rather than an unused private activity timestamp.

Before holding an HTTP body, witness real Foundation response plus initial bytes
and no completion. Perform readiness mutations before fulfilling expectations.
Preserve exact callback body/count, reverse completion, nil owner, sampling and
unknown-manual compatibility. Mock interception does not certify this networking
boundary. A failed required body uses Error1/Resource0 with received status; do not
replace it with an empty-byte heuristic. The original manual/100ms controls remain.
[EXP-214](../Results/EXP-214-resource-action-design.json) owns that approved design.

URLSession state changes may complete after resume/suspend returns. Establish each
state expectation immediately before its own operation and require its exact
bounded transition. Do not precreate a second running expectation, repeat the
operation or accept completed/canceling substitutes. Preserve header and callback
semantics. Cancellation during mutation admits no transport and preserves its error.

For terminal retention, first witness preparation/interception, drain completion
and metrics on their actual queue, remove test handlers, invalidate/drain session
and leave autorelease scope before weak-task release. A completed live task may
retain weak identity but no strong preparation value. Release the task and count
live weak members; weak-table capacity is not object lifetime. Include warm-up,
use per-task bounded weak slots, and keep reflection outside numeric measurements.
Inspect terminal values under the coordinator lock after callbacks can replace them,
then drop tasks before weak observation. SDK-unbound growth is not instrumentation
attribution. [EXP-199](../Results/EXP-199-terminal-task-ownership.json) owns red/green.

## Automatic-only comparisons and input diagnostics

Validate each required native effect witness before asking for human input. In the
automatic fixture, UIKit receipt text and SwiftUI accessibility labels are distinct
observations; a readable label cannot replace an omitted UILabel.text value. Keep
callback, exact increment and owner checks. See the [fixture contract](../../../tools/multi-scene/automatic-coverage/README.md).

For a new split sitting stopped only by input-proof validation, the user-authorized
[RUM-only alternative](../Results/S2-rum-only-20261001.json) may replace another
capture repair. Use the separately bound `human_rum_only_runtime.py` continuation;
its [fixture procedure](../../../tools/multi-scene/automatic-coverage/README.md) binds the original
stop and classification. Pin `rum_only.py` in a new plan and obtain designated
review before native use. Enable it before qualification; run `ready_controls` through `diagnose`,
use `run_journey`, then grade the complete local mapper inventory with `verdict`.
INCOMPLETE stays fatal; pause the matrix to classify FAIL or insufficient comparable
input. Window/source binding, durable evidence, process, interruption and cell
cutoff remain fatal. Targets/counters/callback order are diagnostics. H14 still needs
actual fold proof; without it a split cell can credit only C09/C10. Never rewrite an
old verdict. The four-cell second-grader replay is offline evidence only.

Keep UIKit views/actions and SwiftUI views/actions separate. Use unchanged app
sources, public default predicates and qualified native input; semantic hosts,
manual calls or marker actions cannot substitute. Compare genuine old/new build
SDKs, freeze installed binaries, and retain known naming/control limitations.
A Duo 27.1/regular 27.0 comparison has an OS-patch confound; same-device build pairs
isolate rebuild changes. Mapper evidence alone is not a backend result.

A rebuild can make Sidebar and Detail visible together where the older SDK showed
one column. Compare native effects and event owners within each actual layout;
do not require equal View counts, occurrence ordinals or navigation sequences
across compilers. Retain unknown/foreign/duplicate-owner checks and classify
inherited single-current-view limitations. General tab/split capture redesign is
out of scope. Assess a complete foreground prefix separately from an incomplete
Home boundary; never discard later rows or promote restoration to scenario proof.
An opt-in comparison may seal its foreground prefix before cleanup, preserving the
complete later stream separately. It must still prove release and fresh native
idle; a comparison cutoff cannot authorize removal or qualify Home lifecycle.

Observe callbacks/value changes independently of RUM. End pending actions with a
qualified real background boundary, not termination. Freeze pre-pose geometry and
active-display state; acknowledge native change with unchanged scene identity in a
one-use run-bound receipt. Fold claims need changed display/native evidence before
work. A duplicate-size window is not a resize; old compatibility geometry can stay
unchanged through a genuine display transition if independently proven.

Old applications and modern collectors have separate identities. A collector
adaptation may change only declared target-app paths, preserving and rechecking both
installed apps and runner. Manifest-only variants preserve Swift/Mach-O bytes and
change only the declared plist flag; require actual one-scene topology and reject
mixed-flag comparisons. Separate manifests prevent parallel update races.

Bind bounded replays to unchanged apps/collectors and preserve original source order
and failures. Same-source variability, exact foreground owners and callback sequences
come before SDK attribution. A delayed stack sample may arrive near recovery; retain
its timestamp. Idle app stacks and XCTest snapshot work do not qualify performance.
Collector disappearance with a responsive app is partial input evidence; a successful
button does not qualify switches/scrolls. Stop at the declared attempt limit.

Passive input observations must not change the stimulus. A passing native test can
still fail the diagnostic ownership/boundary oracle. Do not loosen that oracle or
run its skipped arm. A new callback-side witness needs a separate definition,
exactly-once static-super calls, unchanged UIAction/button path and independently
reviewed runner guards. [EXP-218](../Results/EXP-218-native-input-observation.json)
and [EXP-220](../Results/EXP-220-native-input-callback.json) retain distinct scopes;
the cursor alone states whether execution is currently admitted.

For UIKit-hosted SwiftUI, UIKit transition completion and SwiftUI appearance/
disappearance are independent receipts. Keep completion and exact mapper ownership
before each native boundary. Validate the complete SwiftUI occurrence stream with
paired appear/disappear and no overlap before the same content reappears; do not
assume an outgoing SwiftUI callback is synchronous with UIKit completion. A local
re-audit cannot supply missing backend evidence or rewrite the original verdict.

For ordinary single-scene interactive navigation/dismissal, use the
[transition fixture](../../../tools/multi-scene/interactive-transitions/README.md).
Bind the actual coordinator at gesture begin; callback-only animation registration
is valid even when no animation is queued. Keep native controller/model results
separate from RUM owner assertions. Manual SwiftUI path hashes are process-local;
automatic paths retain exact comparison. Record unchanged baseline limitations
separately without changing failed semantic expectations into passes.
Restoration must equal the original actual display, orientation, owned window and
selection, not merely reach a smaller display. Reserve each complete cell inside
one immutable aggregate stage clock. Keep the uploader alive until backend capture
is durable, then seal the stopped stream and rejoin saved responses only.

## S2 native/WebView delayed ownership

Use the [WebView fixture](../../../tools/multi-scene/webview-correlation/S2/README.md)
`navigation-ttl` mode for the finite S2 contract. Capture actual callbacks and
deactivation clocks before checking delayed-event ownership; collect backend
evidence after native behavior. No fold or backend wait belongs inside the inactive
cache interval. Per-cell admissions bind exact source/build and absolute deadlines.
A late response remains diagnostic evidence and cannot rewrite the original result.
Keep native behavior, complete backend inventory and cleanup verdicts separate.

## Specialized fixture entry points

| Contract | Read only when needed | Preserve |
| --- | --- | --- |
| Core-scoped handoff | [handoff fixture](../../../tools/multi-scene/handoff-isolation/README.md) | Entry snapshot/child refresh, nested/throwing full context, foreign-core callbacks; TaskLocal isolation alone is insufficient |
| Session restoration | [restoration fixture](../../../tools/multi-scene/session-restoration/README.md) | Snapshot before repair markers, full restored inventory, max-duration activity refresh, actual activation readiness |
| Keyed lifetime | [lifetime fixture](../../../tools/multi-scene/swiftui-lifetime/README.md) | Weak registration/state/instrumentation, source held alive, restored methods, OS-specific prerequisites |
| Pending authority | [pending fixture](../../../tools/multi-scene/pending-authority/README.md) | Real automatic eligibility before first accepted explicit/capability input, immediate marker |
| Reconnect | [reconnect fixture](../../../tools/multi-scene/reconnect-acceptance/README.md) | Real registry, nil predicate, reader/trait distinction, no artificial authoritative nil |
| Scene retention | [retention fixture](../../../tools/multi-scene/scene-retention/README.md) | Frozen initial inventory, 20 warm-up then 100+100 lifetimes, each owning collection/weak survivor, stale/initial-peer controls |
| Accepted presentations | [presentation fixture](../../../tools/multi-scene/presentation-acceptance/README.md) | Accepted setter return, native callbacks, occurrence fencing, pre-injection stability |
| Replay coexistence | [scope disposition](../Results/S1-replay-scope-disposition.json) | Host crash safety and other-feature continuity only; no captured-content repair or full Replay suite |

Reuse existing Replay configuration/dependencies for coexistence. `hasReplay` is
only an enablement precondition, not evidence of recorder progress. Preserve native
scene/activation and RUM owner checks at the admitted boundaries; generic markers
must not pollute a finite inventory. Serial reactivation requires observed old-view
stop/background before fresh Home. Keep the app alive through the upload boundary.
No per-scene content, simultaneous-visible or physical-Duo claim follows.
