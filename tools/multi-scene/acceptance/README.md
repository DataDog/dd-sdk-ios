# Multi-scene acceptance workflow

This runner admits eight finite contracts: EXP-161/A01 long-running actions,
EXP-176/T03 Resources, EXP-177/T04 errors, EXP-178/T05 attributes,
EXP-179/T06 timing/loading, EXP-180/T07 flags/internal mutations,
EXP-181/T08 Trace and EXP-182/T09 Logs/mirrors. It does not certify simultaneous
visibility, real scene teardown, interactive gestures or hardware-only scenarios.

The Python runner records commit signature status and performs environment and
authentication preflight, a fresh probe build with all current tests and the selected contract's minimum inventory, frozen source
and binary identity, proven uninstall, clean install, scenario launch,
native-scene/mapper ownership checks, complete
backend inventory, app termination and a sanitized durable result. Unsupported
scenarios and reused output directories are rejected. No credentials are read
from local configuration or written to artifacts.

Sign commits when the agent is available. If it is unavailable, continue with
unsigned local commits using explicit paths. Local acceptance accepts unsigned
HEADs and records `UNSIGNED`; an existing signature must still verify. Signing is
required before pushing, and this runner never pushes. Frozen revision, source,
fixture and installed-build identity checks apply to both commit types.

## One invocation with the authenticated connector

Read the repository handoff/runbook first. Resolve an available iOS27 simulator
from live tooling. The driver takes an explicit repository path and simulator
UUID; the Python preflight verifies the destination again. No Xcode interaction
session is needed for this CLI-driven scenario.

From the tool orchestrator, read this trusted checkout's `connector_driver.js`
with `exec_command`, then await:

```javascript
await new Function("tools", "notify", "device", "repo", "scenario", source)(
  tools, notify, freshlyResolvedSimulatorUUID, absoluteRepositoryPath,
  "resources.explicit-start.captured-owner-cross-scene-serial"
);
```

The driver calls the installed Datadog aggregate/search tools itself and supplies
source fields to the oracle. It polls intake, paginates detailed rows and binds
each response to a fresh request nonce, exact query and request hash. It never
accepts a manually supplied PASS. Tool names are the current Datadog connector
contract; if that contract changes, revise the bridge and validate it before
claiming acceptance.

Each attempt gets a new temporary directory/run ID and a unique sanitized file
under `DatadogRUM/MultiSceneSupport/Results/acceptance/`. The temporary directory
contains raw logs, xcresult, binary identity and screenshot; these must not be
committed. The durable JSON contains counts, exact synthetic event owners,
source/build identity, stage verdicts and artifact locators. It contains neither
credentials nor raw intake bodies. Preserve INVALID/INCONCLUSIVE attempts.

The shell entry point below is useful with another bridge implementation, but it
waits for authenticated responses under `OUTPUT/bridge`; running it alone does
not complete backend acceptance:

```sh
python3 tools/multi-scene/acceptance/acceptance.py \
  --repo /absolute/checkout --device FRESH_SIMULATOR_UUID \
  --output /fresh/nonexistent/attempt \
  --durable-output /durable/sanitized/results
```

## Contract and negative controls

`scenario-contract.json` pins the complete expected fixture, including timelines,
completion conditions, driver steps and runtime options. Source hashes include
that contract and all runner files. Editing any frozen file during a run makes the
attempt invalid. The installed executable must match the fresh build hash.

Occurrence1 is the first mapper Home UUID for each logical scene. Native mapper
action envelopes do not contain a semantic occurrence field; exact UUID equality
and an independent session-only view inventory establish ownership. Seven action
IDs, final names, source native scenes, stop timestamps, durations, three view IDs
and zero error/crash events must agree locally and in Datadog. An app PASS alone
cannot override a wrong owner. Assertions must occur inside their actual critical
call interval; a later settled marker cannot replace callback-boundary evidence.

Run the operational controls without Xcode or backend access:

```sh
python3 -B -m unittest discover -s tools/multi-scene/acceptance -p 'test_*.py'
node --test tools/multi-scene/acceptance/test_connector.js
```

Controls cover stale contract/build/run IDs, missing/duplicate/reordered records,
reused readiness, native schema, wrong exact/native owners, wrong final name,
early completion, inactive prerequisites, late assertions, restored backend run
IDs, pagination/completeness, wrong stop order, yielded helper-command completion,
unsigned local commits and invalid existing signatures. The EXP-142 late-boundary
lesson is retained as a negative discriminator; that historical scenario is not claimed
as a fresh runtime acceptance by this runner.

After recording experiment dispositions, refresh gate progress with:

```sh
python3 -B tools/multi-scene/release_checklist.py --update
```

Without `--update`, the command checks required gate fields, dependencies/cycles,
telemetry completion modes, closed-gate evidence and PLAN/register agreement.

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
counts the whole unique log run with DDSQL, reads every page with actual backend
record IDs, and checks the full RUM session for three errors, two actions, three
views and no Resources/crashes. Error and log owners/actions must agree exactly;
private routing metadata must be absent. Attribute namespace ambiguity,
malformed counts and incomplete/duplicate inventories fail closed. Logs/DDSQL
tool guides must be loaded before running the connector.
