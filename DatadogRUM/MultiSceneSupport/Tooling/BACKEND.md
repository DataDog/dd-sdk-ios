# Backend ownership and telemetry

Read for authenticated collection or interpretation. The
[evidence contract](EVIDENCE.md) applies to every family. Use the owning fixture's
exact phase budgets, inventories and controls; historical numbers below its result
are not defaults for another run.

## Access and query scope

Discover the actual Datadog toolsets and organization, then perform a useful read
for the required family. RUM, Logs, APM and Profiling have separate access paths.
A configured server, type list or unrelated service aggregate establishes neither
retrieval nor this run's telemetry. Never read credentials or browser session storage.
If a supported UI/export path is needed, use the user's sign-in and original export.

Scope queries to the synthetic service/run and independently query complete RUM
sessions. RUM probe attributes are under `@context.probe.run_id`; APM commonly uses
`@probe.run_id`. Preserve actual response namespaces, including source fields
outside custom attributes. Missing values must not be supplied from expectations.
Query every view in a session to expose restored old run IDs, then group exact
view/action/resource owners and compare raw events with reduced entities. Include
errors, SDK telemetry and crashes as the scenario specifies.

Use bounded polling, retain full raw payloads, counts and exhausted-page receipts,
and reject explicit or textual truncation. A zero count with empty `JSON_DATA` can
represent an empty exhausted inventory; require its count/provenance. Never accept
only an owner-filtered subset, a lower-bound ingestion count or sampled details.
Freeze decoders and all helper sources before collection; verify them before every
projection/assembly. Persist fulfilled siblings even if another parallel read fails.
Late raw data remains evidence without satisfying an earlier deadline.

For raw MCP pagination, metadata `count` describes the full query, including an
empty terminal page. Require a stable total on every page, contiguous offsets,
terminal exhaustion and exact independent COUNT; a page-length check is wrong.
Use [the transport decoder](../../../tools/multi-scene/acceptance/app_journey_transport.py).
Freeze persisted SDK tags separately from compiled/installed versions: tag
[normalization](https://docs.datadoghq.com/getting_started/tagging/) can replace `+`
with `_`. Compare each exact expected representation; never relax binary identity.
Publish initial readiness only after the complete capture validates; partial pages
must remain a separate file that cannot release native input.

For native/WebView app journeys, keep Browser service and SDK version separate from
native values. The bridge replaces application/session IDs, not those Browser fields.
Inventory the full application/session without native service/version filters, then
reconcile the native partition. See the [offline app guards](../../../tools/multi-scene/acceptance/README.md#controlled-app-inventory-preparation).

## Cross-query identity and revisions

Opaque search-envelope IDs identify rows within a response; they are not stable
semantic event IDs across queries. Compare client rows by stable type/event identity
and relevant payload; compare server-derived session reducers by session, version,
initial view and terminal counts. Require reducers to settle independently of a
complete client count. Validate reducer type/marker/owner separately, retaining
all client-view checks for reducer-origin views.

Fold full/delta view records in strict unique `documentVersion` order. Require an
initial full state and final stopped state. A missing delta field means unchanged;
an explicit empty array clears it. A new full document replaces previous optional
fields. Retain missing-payload and explicit-empty-final-update controls. Backend
versions can differ from mapper input; compare other terminal fields exactly and
record both. Where exact SDK revisions matter, preserve an explicit mapper witness
rather than substituting the backend search counter.

Generated launch/TTID records precede probe tags. Bind them by unique service and
actual app/session/view/Vital identities plus a one-use startup exchange; preserve
absent probe fields and reject mismatched nonnil ones. A session reducer is not an
application-start action. Periodic vitals disabled does not disable first-frame TTID.

## Resources and URLSession

Keep complete-session Resource/error inventories, including restored view run IDs.
Bind starts to original mapper occurrence/session, URL/status, controlled request
arrival and response-release barriers; require no early completion. Preserve peer
action counters through navigation/session replacement. A response-plus-error body
completion has the approved outcome **one Error, zero successful Resources**, with
received status preserved. Unknown manual resources retain compatibility behavior.

Query derived spans by exact Resource trace/span key set. Client spans require
current run tags; a derived span may lack them only with exact origin, unique
service, app/session/view, URL, parent, duration, method and status. An NSError is
not a Resource-derived span. Network error category `Network` and source `network`
are distinct encoded fields. Keep Trace-only zero-Resource checks independent.

For registered durations, reconstruct native Date values from IEEE Double bits,
perform the SDK's subtraction/multiplication and round nearest with ties away from
zero, including declared phase offsets. Python truncation or ties-to-even is wrong.
Keep exact equality and ±1ns controls; reject nonfinite, reversed and out-of-range
values. Rounded backend start times cannot prove exact native nanoseconds.

The [URLSession qualification](../Results/EXP-202-backend-qualification.json) owns
its original four cells, per-phase waits, complete inventories and unchanged
baseline observations. Do not copy its historical timing limits into a new contract.

## Captured Trace

Capture each independent RUM snapshot when the native span or OTel `startSpan`
actually starts. Builder creation is earlier and must not pin ownership. Finish
under changed context, require reverse completion and exactly-once finish/end.
A source-less start has an observed empty handoff/process owner. Keep full service
inventory to find requests created before RUM, not only session-filtered spans.

APM search uses decimal span-ID strings and hexadecimal trace IDs. Convert with
arbitrary-precision integers, never floating point. Local SpanEvent IDs use canonical
unpadded lowercase hex and root parent `0`; preserve all 128 trace bits. Retrieve
complete root trace details when search omits private RUM tags, then join exact
trace/span/parent IDs and require one matching operation/resource/service/run row.
Absent metadata remains inconclusive. Preserve optional trace flags: absent differs
from false. Indexed nanosecond duration is the exact source, not rounded detail ms.

Preserve grouped normalized resource names separately from original `http.url`.
The YAML/JSON decoder must reject object tags, aliases and duplicate keys and work
in the actual orchestrator, where browser globals may be absent. Batch independent
reads, inspect every settled result and include decode/persistence/assembly inside
the deadline. Separate index visibility, detail retrieval and host dispatch latency
from SDK overhead.

Registered witnesses require actual delegate data, metrics and completion for exact
tasks. Empty transaction metrics are diagnostic, not proof of missing callbacks.
Require B completion before releasing A without inventing cross-task metrics order.
Fence the serial message bus before task start; context publication alone does not
prove the Trace consumer received it. SDK initialization, app activation and
scenario start remain independently guarded.

A backend-only continuation needs its own frozen admission, fresh requests and the
original run/source/build/decoder identities. Preserve previous local/oracle failures;
a corrected local projection is not upload acceptance. Use
[the E05 admission](../Results/S1-E05-release-admission.json) for exact composed-
evidence limits and the original stale-reducer/opaque-ID failures.

## Captured Logs and mirrored errors

Distinguish emission, asynchronous context writes and message delivery. Record
caller ownership before logging and deliver under a different live handoff. Mirrors
use a private captured envelope that must be removed before telemetry. Explicit nil,
foreign/retired handoffs and ordinary source-less fallback are different contracts.
An unknown captured view in legacy-only mode can retain representative fallback;
use a real scene-owned peer when testing cross-scene rejection.

Compare encoded log and mirrored-RUM owners with independent view/action mapper
records. Unique synthetic phases plus complete run inventory identify Logs that
have no SDK UUID. Preserve exposed backend IDs, never fabricate omitted ones.
Require total count, complete pagination, grouped multiplicity, unique phase/owner
and raw/local agreement; reject ambiguous attribute namespaces. Query the whole RUM
session and unfiltered unique run, not a convenient owner subset.
The [Logs contract](../Results/EXP-182-log-mirror-ownership.json) owns exact scope.

## WebView and targeted mutations

For WebView, observe real UI-thread `WKScriptMessage` callbacks and forward them
unchanged. Use persistent browser-UUID/run/phase acknowledgements before navigation,
detach or rebind. Keep browser input separate from native output, which bypasses the
RUM mapper. Require actual Replay-enabled native records for container correlation,
complete-session container inventory, detached absence, private scene-key removal
and legacy correlation with a peer-negative control. Decode deflate/zlib versus gzip
correctly. Preserve source envelope fields; never infer them from container/name.
See [the WebView contract](../Results/EXP-183-webview-container-ownership.json).

For attributes/errors/timing/flags/internal metrics, use named family contracts and
nonce-bound expected inventories. Freeze independent A/B checkpoints around every
Swift/ObjC form, preserving exact typed values, absent keys, global/view/event
precedence and peer invariance. Bind payload snapshots to exact error/marker IDs
before events. For timing/loading compare local intermediate versions and final
persisted values separately: backend ingestion can collapse intermediate revisions.

Feature messages carry sender ownership through asynchronous delivery, rejecting
foreign/retired core generations; receiver handoff is not an origin. Use an accepted
independent view-update trigger when internal metrics do not emit immediately.
**FBC is Flutter-only downstream**: native fixtures prove internal/encoded ownership
and expect backend absence. Do not scale durations or change SDK behavior to force
it into native events. Flags/build aggregates remain exact. Family check inventories
and malformed-type controls live in the
[acceptance README](../../../tools/multi-scene/acceptance/README.md).

## Process, fatal and shared-vitals signals

Keep exported Core snapshots, crash-provider state, serialized plugin injection and
later report delivery separately observed. Source-less fatal/process events use one
representative; recovery thread is not scene evidence. Held snapshots retain IDs
through live context replacement.

Fatal acceptance uses clean prepare/crash, same-install recovery, then consumption
verification, each with a fresh run ID and the same binary/container. Crash only after
pre-crash guards and preparation PASS; recovery establishes different current context
before enabling the reporter. Require actual `didCrash` acknowledgement on later
launches, exact original owner and SIGABRT metadata, no returned abort trigger and
independently matched native/launcher PIDs. Launcher exit 0 can follow app crash;
process absence alone is not crash proof. Internal flush clears LaunchReport and
cannot prove there was no pending report. Preserve failed guards even if a report exists.

Drain and verify full telemetry inventory before preparation PASS/crash. A targeted
noninteractive update can expose accepted attribute mutation in the next mapper
revision; cached initial state is insufficient. Decode saved run IDs through the
encoded String and reject non-Strings. Keep native scene-ready, SDK scene snapshot
and mapper identity separate; do not manufacture a missing initial scene attribute.
For buffered launcher PID output, terminate only the fixture after terminal,
collect/reparse all output and prove independent PID agreement before advancing.
The [fatal contract](../Results/EXP-184-exported-fatal-context.json) owns exact phases.

Use real run-loop/watchdog producers for long tasks and nonfatal hangs. A controlled
memory-warning notification proves routing, not real pressure. Observe representative
and absent action before each stimulus; require mapper acknowledgement/counters
before the next boundary. Pending fatal-hang snapshots preserve owner/consent across
session changes and consume once. Deterministic restart is not watchdog termination.

For serial reactivation require ended old view, actual OS activation, fresh native
lifecycle, SDK snapshot and mapper owner before targeted work. Keep retired zero-count
views. Counter settling may retry only as explicitly admitted (the original process/
vitals contracts permit at most three fresh reads 10s apart); reject regression,
overshoot, extra rows and malformed types immediately. Do not generalize that retry.

Shared vitals separate legacy view aggregates from optional session timeseries.
Wait for actual reader samples, then stop the session before final comparison.
Preserve exact owner/field presence/integers and predeclared float tolerances.
The one-scene physical and serial variants reject each other's manifests. The
stop owner must equal the final sampled owner; slow-frame enablement requires an
actual `ViewHitchesReader`. A simulator sample cannot replace required hardware.
[EXP-186](../Results/EXP-186-shared-vitals.json) owns the serial and physical evidence.

## Profiles and Operation attachments

Join actual `rum-mobile-events.json` entries and labels through exact start Vital ID;
operation key/view are not raw attachment fields. Keep structured name/optional-key
identity, reverse completion, ongoing-operation retention and exact server-offset
nanoseconds. Profile-level RUM labels are not per-scene CPU attribution.

Operation sampling alone does not start a profile. Prove continuous profiling is
running before the first Operation and every admitted step, with the defined
foreground sampling/upload interval. Configuration presence, native timing,
installed code, full-session RUM and profile/sample/attachment joins remain separate.
Require the built-in ApplicationLaunch inventory as specified, without filtering
unexpected views or increasing timestamp tolerances.

Discover sample types and make a real retrieval: metadata can list a disabled CPU
type, while native Mach profiles expose wall-time/nanoseconds. Query complete
service/time and session inventories, each exact native start ID and the full Vital
set/name/view/session labels. Nonempty exact-Vital flamegraphs prove sampled
correlation; normalized wall time is not Operation duration.

If MCP lacks raw download, preserve the user's actual export, profile ID/provenance
and SHA-256 of attachment plus pprof. Share its exact `visualizationLink`, including
organization-switch redirects, rather than constructing a link in another org.
Recheck exact ID inventory/flamegraph before requesting another export. Never
substitute expected native entries for the downloaded file. Keep false RUM
`has_profile` flags separate from successful joins; no UI-enrichment claim follows.

Optional launch-profile presence follows independent TTID metadata: a declared
profile needs exact distinct ID/joins; explicit false without an ID requires absence
and empty launch joins. Always require the continuous profile/start IDs/samples.
Preserve extra/repeated/inconsistent-inventory controls and earlier checker verdicts.
Assemble physical acceptance only with separate source/build/install and cleanup
proof. Use the [profiling fixture](../../../tools/multi-scene/profiling-correlation/README.md)
and [physical export record](../Results/EXP-187-physical-export.json); a pure validator
or simulator mechanics pass does not satisfy that independent proof.
