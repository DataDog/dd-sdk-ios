# Telemetry contract adapters

[Acceptance router](../README.md) · Read only the procedure for the selected owning result.
Current admission and qualification live in that result; this procedure grants neither.

## Resource contract (EXP-176/T03)

`resource-scenario-contract.json` pins six actual Swift/Objective-C target starts,
one legacy fallback, two paused URLSession tasks and a new-session peer action.
`resource_contract.py` requires22 app expectations plus independent strict checks:
native Home mapper owners before starts, all starts before A backgrounds and B navigates/renews,
zero completion before release, five Resources and four expected network errors
on the original owners, exact request/status/method/size/duration fields, and zero
old Resource/error counts on the fresh peer action. Session-only queries inventory
all five views and all Resource/error events across both sessions; no run filter
can conceal restored metadata or extra events. The separate crash count stays zero.

The custom URLProtocol holds actual instrumented tasks, then delivers a successful
response or response headers/body followed by failure. It makes no external network
request. Success is observed before the error is released, preserving the declared
serial completion timeline. The SDK's independent unit checks cover missing targets,
completed-key reuse and compatibility fallback; native acceptance executes all six
experimental entry points in real UIWindowScenes.

A passing SDK/probe unit build
alone does not close T03. Commit the fixture/runner before acceptance and retain all
failed native/backend attempts alongside the final durable result.

For the serial simulator contract, capture A before it backgrounds. Verify its real
background state and retired current owner, navigate B, then renew B in a fresh
session. Starting a manual view on already-background A is ineligible; do not
manufacture foreground state or weaken the original-owner oracle to pass it.

T04 current-view errors: pass scenario `errors.explicit-target.current-view-cross-scene-serial`
to the connector driver. The runner freezes error-scenario-contract.json and requires
9 errors,2 actions,3 views,0 Resources/crashes and exactly1 completion callback.
Each admitted contract has independent operational and backend mutation controls.

## Attribute contract (EXP-178/T05)

Pass scenario `attributes.explicit-target.current-view-cross-scene-serial`.
`attribute-scenario-contract.json` freezes ten A/B checkpoints and42 app
expectations. All eight real Swift/Objective-C attribute mutations execute in one
synchronous batch under contradictory peer inference. Pre-call native readiness
and live mapper ownership must precede the batch, and each typed mapper snapshot
is joined to its exact error ID and owner. Whole-session backend queries require
all20 errors,3 views and0 Resources/crashes, with independent typed values and
key absence. Removal must reveal the original global shadow and leave the peer
unchanged; the final process update reaches both views.

The optional `attributeState` signal field contains only validated synthetic
values. JSON decoding rejects numeric/Boolean coercion. Backend projection admits
only the fixture's bounded values, preserves missing keys and normalizes the one
known flattened nested key. Invalid values produce a fixed invalid marker.
Negative controls reject peer mutation, wrong types, removed keys, detached
snapshot IDs, stale identity and late guards. The runner requires at least170
probe tests for this contract; its fresh build runs the complete current suite.

## Timing contract (EXP-179/T06)

Pass scenario `timing.explicit-target.current-view-cross-scene-serial`.
`timing-scenario-contract.json` freezes eight paired checkpoints and34 app
expectations. Real Swift/Objective-C calls target the opposite inferred scene.
The local oracle joins each marker to the immediately preceding mapper view
snapshot by sequence, exact view/session and document version. It rejects stale
or late snapshot bindings, noninteger durations, non-growing replacements,
changed loading under overwrite false, unchanged loading under true, peer
mutations and foreign final keys.

Whole-session backend queries require16 marker errors,3 views and0 Resources/
crashes. Final custom timing/loading values must match the mapper exactly.
Intermediate revisions can be collapsed by ingestion and are established by
ordered mapper evidence. The runner requires at least172 probe tests and runs the
complete current suite. Earlier action/Resource/error/attribute contracts remain
independently selectable and keep their original inventories.

## Flag/internal mutation contract (EXP-180/T07)

Pass scenario `flags.explicit-target.internal-mutations-cross-scene-serial`.
The frozen contract requires eight paired checkpoints and34 app expectations.
Real Swift/Objective-C calls replace flags on the requested live view under peer
inference. Internal sample/FBC calls use an exact owner with a contradictory scene.
An accepted timing update flushes each view before its marker; the marker binds to
the immediately preceding mapper snapshot by sequence, view/session and document
version. Flag values retain Boolean, integer, string and nested types. Build
minimum/maximum/average and FBC must match the declared samples on only their owner;
the internal attribute must never appear in custom context.

Whole-session queries require16 marker errors,3 views and0 Resources/crashes.
Every error preserves its checkpoint's typed flags. Final persisted view flags
and sample aggregates match mapper evidence; intermediate view revisions remain
local ordered evidence. FBC is Flutter-only downstream: native backend records
must omit it. Exact local FBC ownership and JSON encoding remain required; this
fixture does not claim Flutter runtime or ingestion acceptance. The runner requires at least175 probe tests and executes
the complete suite. It preserves all five earlier contracts.

Negative controls reject stale identity, consumed readiness, late guards/snapshot
bindings, wrong owners, missing/duplicate events, Boolean/number coercion, incorrect
replacement/peer values, malformed aggregates, internal-key leakage and restored
backend run IDs. Connector projection retains only declared synthetic flag values,
normalizes the known nested flag fields and rejects ambiguous representations.

The native contract exercises explicit flag calls and internal mutations. The
asynchronous Flags reporter/message-bus ownership contract is covered separately by
the experiment's actual reporter, Core-bus and RUM-receiver integration checks.


The named EXP-181 Trace contract freezes nine native/OTel/URLSession spans and
20 app expectations. It binds exact encoded trace/span identities to independent
starting RUM owners, verifies held loaders and peer completion before dispatch,
and compares the entire APM run plus full RUM session. The connector uses the
installed system Ruby YAML/JSON libraries for span responses, with preflight and
negative controls rejecting objects, aliases, duplicate keys and truncated data.
No SDK dependency is added. Display durations cannot substitute for exact
nanosecond values. Physical shared-request topology remains H07.


APM search yields operationname/resourcename and exact decimal spanid/parentid
strings. The bridge converts IDs with BigInt, retrieves each complete root trace,
and joins full trace/span/parent identities before reading private RUM meta tags.
Search and detail must agree on operation, resource, service and run identity.
Known native/OTel operation hyphens normalize to underscores. HTTP resource
grouping is retained as evidence; the exact original http.url from both responses
must match the mapper URL. Duration comes only from the indexed integer
nanoseconds, never the rounded duration_ms shown by trace details.


Independent trace details are fetched together, every result is checked, and one
bounded system-Ruby call decodes their YAML pages. Read-only bridge helpers use the
read-only sandbox; setup and evidence writes keep escalation. The runner records
backend_bridge_timings and retains its300s deadline. A late response is not acceptance.


## Logs and mirrored errors (EXP-182/T09)

Pass scenario logs.captured-emission.native-mirrors-cross-scene-serial.
The frozen contract has six encoded logs, three mirrors, two final actions and
twenty-four app expectations. Live action snapshots bind to independently mapped
Home views and final action records. B must represent before A logs; the detached
source-less pair must have an empty handoff. Guards precede each pair and all
mirrors precede the action stops. No arbitrary log messages are recorded: the
evidence decoder accepts only the six declared synthetic phase/messages.

Preflight authenticates RUM and Logs reads. The source fingerprint now includes
DatadogLogs. A fresh build requires at least181 probe tests. Backend acceptance
counts the whole unique log run with DDSQL, reads every page, and independently
groups all ten selected semantic fields. Require six unique phases, each with
count1, complete group metadata and exact raw/group/local agreement. Backend IDs
remain null when unexposed; preserve and deduplicate any exposed IDs. The runner
checks the full RUM session for three errors, two actions, three
views and no Resources/crashes. Error and log owners/actions must agree exactly;
private routing metadata must be absent. Attribute namespace ambiguity,
malformed counts and incomplete/duplicate inventories fail closed. Logs/DDSQL
tool guides must be loaded before running the connector.

## WebView containers (EXP-183/T10)

Pass scenario webview.captured-container.native-navigation-rebind-serial.
The contract freezes six real WebKit callbacks: original A/B, A navigation,
A detached, the same A WebView rebound into B, and B after A tracking teardown.
It requires two actual WebView instances in distinct native scenes, fresh document
nonces, callback acknowledgement before attachment mutations and Replay-enabled
native owners from independent RUM mapper output. Each callback observes and
then forwards the real message to the SDK handler; it is input evidence, not
the receiver's encoded output. Browser inputs carry deliberate peer-scene spoof
metadata to test replacement/removal.

The strict oracle requires fourteen app expectations and every pre-boundary
guard, exact callback/document/instance identity and browser dates after dispatch
guards. All twelve backend views are counted and paginated for the whole native
session: six independently mapped native views and six unique browser views.
Five browser events must name their exact native container; the detached event
must have no container. Native application/session replacement, Replay state,
zero counts, duration and private scene-key absence are checked directly.
Wrong owners, stale/restored identities, late guards, premature teardown,
duplicate inventories, ambiguous field representations and type coercion fail.

The source inventory includes WebViewTracking and SessionReplay. A fresh build
requires at least184 probe tests. This bounded controlled-payload bridge fixture
does not certify the Browser SDK, per-scene Replay correctness, simultaneous
visibility or the physical F05 coexistence gate.


## Shared vitals acceptance (EXP-186/T13)

Use vitals.shared-process.cross-scene-serial through the existing connector driver.
The frozen contract requires196 probe tests and30 native expectations from14
ordered guards plus two Home starts. A must produce actual100ms reader samples
before opening B; native background retirement precedes B sampling. Targeted
timing checkpoints request updates without modifying observed metric values.
Unrelated Actions/Resources, long tasks, hangs and memory warnings are disabled.

After stopping the session, require exactly three inactive views, one session
and zero extra telemetry. Query the whole session. Compare actual final
CPU/memory/refresh and optional slow-frame values with exact identities,
presence/integers and the predeclared floating tolerance. At most three fresh
view reads,10s apart, may wait for an earlier valid interval/still-active view.
Wrong owners, malformed/extra data or interval regression/overshoot fail at once.
Persist vitals-records.json and backend-exchanges.json in the durable summary.
This simulator workflow does not satisfy the required representative physical
sample, simultaneous visibility or Duo acceptance.


EXP-186 attempt A establishes one narrow backend representation exception:
an empty mapper slowFrames array may appear as an absent backend field.
Record field presence separately; never treat explicit null or a missing
nonempty array as equivalent. Preserve the original projected values and the
failed run, and rerun from a newly frozen source/tooling identity.
