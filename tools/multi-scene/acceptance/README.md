# Multi-scene acceptance workflow

This runner admits twelve finite contracts: EXP-161/A01 long-running actions,
EXP-176/T03 Resources, EXP-177/T04 errors, EXP-178/T05 attributes,
EXP-179/T06 timing/loading, EXP-180/T07 flags/internal mutations,
EXP-181/T08 Trace, EXP-182/T09 Logs/mirrors, EXP-183/T10 WebView containers,\nEXP-184/T11 fatal recovery, EXP-185/T12 process signals and EXP-186/T13 shared vitals.\nIt does not certify simultaneous
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

## Physical installed-code receipt

For a physical run, supply MULTISCENE_CODE_IDENTITY_RUN_ID and
MULTISCENE_CODE_IDENTITY_REVISION with the same fresh scenario identity. Retrieve
Documents/<run-id>.installed-code.json through the appDataContainer after a
normal launch. The receipt is created before SDK initialization and rejects a
reused file. Run acceptance/installed_code.py with --signed-app, --run-id,
--source-revision, --process-id and a fresh --output. It compares all installed
Mach-O files, including a Debug dylib, to the signed local inventory. No debugger
is needed. Keep native/backend/topology acceptance separate from this identity
check; a passing receipt alone closes no release gate.


### One-scene representative hardware sample

Use the separately frozen vitals.shared-process.single-scene-physical contract
for an ordinary iPhone. Keep the accepted serial contract and its source/capture
identities unchanged. The dedicated validate_physical_local entry point requires
one native readiness,17 expectations/eight ordered guards and exactly two final
inactive views (Home plus ApplicationLaunch). It rejects the serial manifest;
validate_local rejects the one-scene manifest. Both require the stop assertion's
owner to equal the final sampled owner and preserve exact mapper metric values.
The slow-frame configuration guard requires the actual factory to produce
ViewHitchesReader, not merely that a nonoptional factory exists.

Freeze fixture/oracle source before building. Discover the current physical
device and provisioning/signing material, verify unlock and real process/app
inventory, clean-install only the probe bundle and prove its prior absence.
Normal launch arguments are --probe-scenario followed by the exact variant ID,
--probe-run-id followed by a new run UUID, and --probe-run-mode clean. Supply the
matching installed-code receipt environment values. Compare every installed
Mach-O hash with that exact signed app and the independently observed process ID.
Keep the build/source, native records and receipt artifacts together.

Validate the native records with validate_physical_local, then query the complete
session through the same authenticated backend projections used by serial T13:
exactly two vitals_views and no peer_actions, resources, process_long_tasks,
errors or crashes. Use settled_views and validate_backend with that local result;
retain all raw exchanges, pagination/count provenance and exact integer metrics.
The original acceptance.py simulator runner intentionally accepts only the serial
T13 contract; do not pass the hardware variant to it or claim physical proof from
a pure oracle result. Independent device/build/install evidence is still required.
Verify test-app cleanup with fresh process inventory; a disconnected device is
unverified cleanup. A simulator mechanics pass checks this variant's implementation
but cannot discharge the representative-device requirement or H01–H16.


### EXP-194 native Replay coexistence

Use --scenario replay.native-recording.navigation-teardown-serial with the existing
acceptance runner and a freshly resolved iOS27 multi-window simulator. Four native
core-context checkpoints require counter growth before expansion, after B creation
and navigation, and after actual B disconnect plus A navigation. Each checkpoint
binds to independent RUM mapper ownership and live UIWindow geometry/activation.
The scenario contains no browser or injected Replay data.

The runner checks every installed Mach-O, exports native observations before the
oracle, joins the full session backend inventory, and verifies bundle/data cleanup.
Replay view bridge rows require view_id, session_id, name, run_id and has_replay.
Empty action/resource/error/crash queries still require complete query provenance.
A passed simulator slice does not close physical F05 and makes no scene-correct
Replay claim.

### Physical Replay timing

For a physical iPad that reveals A during B close, use `replay_contract.validate_physical_local`. It requires fresh A Home and an actual same-native foreground callback between the B close request and acknowledgement, old A Home stopped after actual background, B disconnect before navigation, and uninterrupted returned ownership. The simulator entrypoint retains explicit-reactivation timing. Both require the same six native/backend views and four real native record-growth checkpoints. The oracle alone never proves physical execution: retain signed build, exact device, all installed Mach-O receipts, complete backend inventory and cleanup. EXP-196 preserves the first timing rejection and requires a fresh run after the oracle freeze.

### Physical H01 precritical admission

The original same-key scenario supports `DD_PROBE_PHYSICAL_TOPOLOGY=1`. Before its first manual start it writes `Documents/<run>.physical-challenge.json` and waits at most five minutes. Arrange the two actual probe windows with native device controls. Start an independent screen recording and capture a screenshot showing both window contents. Retain the challenge, screenshot hash, capture UUID and exact run/process/native-scene/generation identities in a fresh receipt copied to `Documents/<run>.physical-admission.json`. Its capture timestamp must follow the challenge and be at most sixty seconds old. The fixture consumes it once, samples live scene attachment/visibility/lifecycle every fifty milliseconds, and guards before/after steps6–16; loss prevents subsequent mutations and produces INCONCLUSIVE.

Use `physical_same_key_contract.validate_local`, `validate_display` and `validate_backend`. The display proof must preserve the host receipt/challenge, native process identity, actual screenshot/video hashes and timings, and a review that both actual scene contents remained visible through the critical interval. Local frames, capability flags, or a terminal22/22 alone do not qualify. The backend check compares the complete session inventory to every native mapper view and Action/Resource ID, including the seven decisive pairs. The compact unit fixture explicitly contains fabricated topology and clocks; it is never physical evidence.

## Controlled app inventory preparation

`app_journey_inventory.py` supplies offline guards for the finite F08 app journeys.
It is not a scenario in the acceptance runner and grants no runtime or release
acceptance. It consumes decoded full RUM rows and query receipts. Account binding,
complete native phase capture and journey cleanup still need qualification.

The helper preserves raw IDs and available backend revisions, compares distinct
view occurrences and exact owner edges, and rejects incomplete pagination or
foreign query/session identity. Only a verified explicit SwiftUI occurrence may
normalize its process-dependent hash suffix. Browser source/service/SDK version
remain separate from native fields: a full application/session query must include
all partitions. Replay eligibility is required for a persisted container check;
active-at-dispatch ownership needs independent native evidence. Graph equality
still requires review of raw revisions and downstream non-owner values.

`app_journey_transport.py` decodes full MCP responses. Metadata `count` is the
query total even on the empty terminal page. Each page total, accumulated offsets,
exhausted pagination and an independent ungrouped COUNT must agree. Explicit or
textual truncation, stale request identity and partial captures fail closed. Preserve
raw SDK tags separately from exact compiled/installed version strings; do not
normalize build identity. Saved initial data qualifies transport, not a journey.

Run transport controls with `python3 -B -m unittest discover -s
tools/multi-scene/acceptance -p test_app_journey_transport.py`.

Run its offline controls with:

```sh
python3 -B -m unittest discover -s tools/multi-scene/acceptance -p test_app_journey_inventory.py
```

The [source oracle](../../../DatadogRUM/MultiSceneSupport/Results/S2-F08-source-oracle.json)
owns remaining capture requirements. These controls do not reopen stopped runs.


## Human-paced hosting and shared host bindings

`s2_hosting_paced_workflow.py` prepares/builds/verifies the single remaining
B-manual hosting fixture and runs its `cell` through `hosting_connector.js`
with family `hosting_paced`. The fixture exposes Push Detail, Return to Root,
Present Modal and Dismiss Modal only after exact previous lifecycle/mapper
readiness. The driver retains actual screenshot/display/readiness bytes and never
reissues a consumed prompt. App-local uptime bounds actual input; host deadlines
bound capture and publication separately. Full original hosting/backend predicates
still apply. No fold, automatic-action or physical credit follows.

`runtime_binding.py` permits an explicit host-only integration before native
admission. It preserves the original plan, helper snapshot, compiler inputs,
objects and complete app products. Only individually allowlisted acceptance
Python/JavaScript paths may change, in a new immutable helper snapshot and binding.
It rejects an already admitted/attempted root or any compiled-source change.
Completed controls and the designated review bind the exact new snapshot; the
native admission binds that review. This is build reuse, not deadline renewal or
permission to reclassify an older failed run.

The paced and WebView drivers share response publication, raw backend transport
and task-only cleanup. Evidence preservation failures do not skip app removal.
Scenario, evidence and cleanup remain separate verdicts; missing required evidence
or failed cleanup keeps overall acceptance invalid. Owning result records contain
the exact roots/receipts and remaining cells; neither entry point admits itself.


## Human Resource/Trace fold with immutable build reuse

`resource_fold_runtime.py` prepares a separate runtime root from the fold owner's
frozen inputs. `resource_fold_reuse.py` verifies original source/compiler lists,
member bytes, objects, dependencies and complete products. It does not rebuild or
rewrite the original plan, qualification, failed run or cleanup verdict.

The generated runner retains the Resource/Trace local/backend predicates and native
cleanup. Its human input bridge captures the actual returned display files and
screenshots, then samples current native ownership before releasing held work.
It proves a human-observed display transition after the prompt; it does not prove
the precise Device Hub gesture or its timestamp. No automated input worker runs.
Backend requests stream directly to the existing connector and retain their first
published clock; raw responses, validation, publication and cleanup stay bounded.
Changing COUNT/search inventories are retained as separate complete attempts and
repolled only within that original clock. The connector never deduplicates rows to
make counts pass. Malformed/truncated data and duplicate or foreign ownership still
reject; valid native behavior remains available for separate collection assessment.

Run the local `human_operator.py` page for `RUNTIME/operator`. The runner publishes
actual prompts and waiting states directly, with request-bound release controls.
Before each cell, `operator-ready-ARM-MODE.json` must bind that live page, exact plan,
device, `ARM-MODE` and fresh user readiness. Missing readiness stops before the
cell reservation. Backend/authentication preflight precedes the human invitation.

Prepare and review before execution. `verify --runtime-root PATH --plan-sha256 SHA`
checks the runtime identity. Only after live environment/authentication preflight
and operator readiness may `stage` with those arguments issue the single fixed
admission. Its SHA is required by `cell --arm A|B --mode automatic|registered
--device UUID --stage-sha256 SHA`. The generated connector serves exact RUM/APM
responses while the cell requests human input. The four ordered cells have zero
retries; the first baseline qualifies the mechanism. Missing effect, evidence or
cleanup stops this path. Original deadlines are never reopened.

For the current S2 contract, prepare with `--scope-definition` pointing to the
reviewed definition in the fold owner's `current_preparation`. This opt-in binds
the approved documentation consolidation and preserves both user-owned paths.
Its copied oracle keeps capture duration, automatic elapsed brackets and incidental
TTID duration as diagnostics. Exact registered metrics, ownership, ordering, full
inventories and actual display/scene/window proofs remain required. The request's
first `gather_started_ms` must equal the response's phase clock; transport and cleanup
deadlines remain fixed. Original helpers, attempts and verdicts are untouched.
