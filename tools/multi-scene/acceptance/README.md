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

### H04 activation-only preparation

[H04 preparation](../../../DatadogRUM/MultiSceneSupport/Results/S3-H04-activation-preparation.json)
owns the one-cell scope and remaining admission prerequisites.
`focus_activation_fixture.py` renders a separate source copy with the explicit
`windows.focus-activation-only` scenario and `physical-focus-activation-only`
profile. The original16-step activation/disconnect contract and H06 inputs remain
unchanged. The new14 steps contain four actual active/background changes, five
independent Home occurrences and four exact Action/Resource pairs.

The fixture checks complete native scene/window/key/input ownership before and
after each marker. Every intervening lifecycle/window notification invalidates
that interval, including notifications without a known fixture owner. Auxiliary
windows are inventoried rather than rejected by count. The independent Python
oracle requires the semantic terminal to end its accepted prefix. Preserve later
raw mapper/lifecycle rows separately for delivery and cleanup; they cannot supply
missing guards, work or owners. Sixteen offline controls and compiler qualification
are preparation only. Physical transport, backend publication and release/idle
cleanup must compose under review before execution. No H10, disconnect, concurrent
visibility or physical-Duo credit follows.

`focus_activation_recorder` seals the first exact semantic prefix and retains the
original tail. Complete later rows may contain ordinary updates for known Views
or native scenes; new work, errors or guards reject. Partial trailing bytes remain
pending on the same file. `focus_activation_backend` uses the existing durable
count/page transport with a fixed application/session query and interval. It checks
present owners before classifying missing expected IDs as pending, even when
incidental rows make the total large enough. Neither helper authorizes native
work, teardown or a release verdict.

### H06 Operation preparation

The [owning record](../../../DatadogRUM/MultiSceneSupport/Results/S3-human-residual-preparation.json)
tracks preparation; it does not yet admit a physical session. The original
`operations.cross-scene.lifecycle` scenario, profile and eight inferred calls stay
unchanged. `operations.cross-scene.physical-setup` observes A/B readiness, pauses
before marker4 for window arrangement, then uses fresh post-arrangement markers
before the same calls at steps6–21. Catalog selection alone cannot pass that pause.

`ProbePhysicalOperationOwners` binds distinct current A/B View IDs to independent
active Home mapper snapshots and unchanged native/input identities. Select the
current View document version, preserving old occurrences and raw IDs; mapper
delivery order is not navigation order. Re-read both direct SDK owners and full
input inventory after any wait. The app-only sampler uses session-aware
`rumContextSnapshot(for:at:)` for both native scene IDs at one sampled date. It
retains missing/partial SDK reads separately from its validated owner projection;
eight controls reject absent/aliased owners, mixed sessions and input drift.
Shared harness sources also compile in the hostless unit target, which does not
link SDK frameworks. Keep the actual Monitor adapter in app-only source.
The pure progress guard covers both setup markers and every before/after boundary
through step21. Complete local checks require20 exact Action/Resource markers and
eight ordered native calls. Generic completion never qualifies Operations.

The passive input observer installs before scene readiness and retains contact
revisions plus the full connected-scene/window inventory. Setup consumption rejects
changed input/owners and reused requests. Auxiliary windows remain recorded without
a fixed count rule. `DD_PROBE_PHYSICAL_OPERATION_CAPTURE=1` remains unarmed.

`ProbePhysicalOperationChannel` and `operation_transport.Channel` use one shared
file channel. Historical schema1 keeps its original bytes; schema2 additionally
binds the exact physical setup profile and rejects cross-mode requests. Publish
immutable hash-addressed payloads before markers, retain actual replies, and bind
run/process/profile/challenge/installed-receipt bytes. Preserve Swift numeric
encoding; Python reserialization of geometry is not an acceptance rule. Cleanup
replies never authorize teardown. Owner/input/transport controls qualify42 native
and15 host cases; the original failed test-input attempt remains separately saved.
The unarmed app pump captures SDK/recorder/SDK observations in sequence and retains
immutable stage files. Its separate context document preserves raw component bytes;
a completion receipt binds the context, original channel reply/capture and terminal
publication status. Host collection waits for that receipt first and rejects missing,
partial, foreign or late evidence. A later normal stop/expiry seals future setup
without rewriting a completed observation. Fifteen injected native capture controls
and ten host controls pass; the app compiles. Real SDK invocation and physical file
transfers remain unqualified.

Startup requires the physical-setup scenario, capture flag, pre-SDK installed-code
receipt and `DD_PROBE_PHYSICAL_OPERATION_CAPTURE_DEADLINE` (absolute Unix seconds).
The input observer installs before scene-ready. A missing receipt or partial startup
is terminal for that run. The pump keeps cleanup capture available after a request
failure until the original deadline; it never grants teardown. `CAPTURED` means bytes
were collected, not that Operations can start. The exact physical-setup profile
also requires `DD_PROBE_PHYSICAL_OPERATION_EXECUTION=1`; existing launchers leave it
unset. Its native guard consumes one host proof and the original pending input
capture, revalidates current SDK owners/input before marker4, and checks every
before/call/after boundary through step21. Marker invocation receipts let the driver
advance without imposing immediate mapper delivery. Final collection requires all
20 marker rows and eight calls, followed by a fresh continuity observation before
publishing local ownership success. The receipt names that observation cutoff.

`operation_setup.HostSetup` joins the existing channel to a challenge-bound release,
all signed Mach-O files, separate host/device process identities and actual physical
display evidence. It preserves this command's raw responses and screenshot; visual
review maps both fixture owners to distinct visible content regions. PNG dimensions
must match the screenshot response and CoreDevice display bounds in pixels. The
point scale is retained, not applied again. The host checks `proc_pidpath` against
`ps`; macOS framework Python may have a different launcher path.

Thirty-two offline entrypoint controls, one corrected real host-identity check and
saved physical-schema replay pass. Original control/host failures remain recorded.
No new native or physical transfer is qualified. The immutable host proof has no SDK
or cleanup authority: its exact capture/context and prerequisite hashes must be
consumed once by the app after revalidating current input and RUM owners. A failed
display review preserves the unarmed capture. It does not request gestures again or
authorize teardown. There is no additional screenshot freshness cutoff; the fixed
operational deadline, causal order and live state checks remain mandatory.

`HostSetup.publish()` verifies all prerequisite files again, transfers the opaque
proof/result payload before its hash marker, and permits only one publication
attempt. The native side checks both outer request identity and the exact inner
input request bytes; hash agreement alone is insufficient.

The opt-in native ledger retains app/scene/window notifications, registry changes
and SwiftUI resize revisions. Original scene/window/root objects remain retained
through the guarded interval to prevent address reuse. Any new notification,
including an auxiliary or nil object, invalidates this no-input/no-navigation
interval; stable auxiliary windows are allowed. This is a source-bound contract
for the manual SwiftUI fixture. Navigation, root replacement or another host needs
a revised contract. Eighteen injected fixture controls and six host-publication
controls pass, with cleanup/restoration verified. Independent full display evidence,
complete recorder/backend collection and the end-to-end host runner remain required
before physical qualification. Local proof publication never authorizes teardown.

`operation_completion.Completion` waits for the distinct native terminal receipt,
then pulls `Documents` once and seals the actual directory. The terminal manifest
binds every native artifact and the full observation interval, final mapper and
continuity seal. Missing, extra, changed, wrapped or substituted evidence rejects;
a native failure takes precedence. The collector preserves actual transport
responses and has no launch, input or teardown authority. Its local result leaves
display, backend and cleanup pending, and overall acceptance unqualified.
Twenty-three host controls and two affected Swift controls pass; actual Swift
fixture encoding also passes host replay. Physical directory layout needs its first
bounded qualification, with no silent per-file fallback. SDK/input/mapper doubles
do not establish physical ownership.

`operation_recorder.Recorder` joins the native snapshots to the complete recorder
prefix through its semantic terminal. It binds the original scenario bytes and
its one completion condition, preserves later mapper/lifecycle records separately,
and derives backend IDs from native owners. Partial terminal publication rereads
the same file within the original deadline; it never recopies the directory or
repeats native work. Twenty-six fabricated controls pass. Display/backend/cleanup
still remain pending.

Cleanup seals admission before input capture, cancels and awaits the scenario
driver, then stops the capture pump. Its immutable receipt binds the actual
context and original terminal bytes. `operation_transport.cleanup_response` checks
those joins without granting teardown authority. Eight host controls and thirteen
Swift controls qualify this preparation; the original empty-fixture failure and
corrected two-test result remain separate. The actual Swift receipt also passes
host replay. `operation_cleanup.Cleanup.run` now connects real operator release to fresh
stop/idle proof, exact original PID/executable checks, host-child quiescence and
task-only removal in one call. Both prior-result expectations are required; `None`
means absence. A pending driver permits one further capture under the same cutoff,
never removal. Twenty-one offline controls pass after the reviewed physical
cleanup disposition below. App/process absence stays distinct from unverified
container absence. Full display/operator integration and physical qualification
remain required.

### H06 operator prompts

`operation_operator.Operator` maps the original `operations.setup` request to the
page's `setup`/Ready label, and `operations.cleanup` to cleanup/Released. Original
request bytes remain immutable. Bind the channel challenge, run/process, device,
bundle, exact page/server receipt, request path/hash and original outer deadline.
No legacy 300-second readiness cutoff applies. The runner must independently bind
live page health and its process executable before native admission.

Only the actual page acknowledgement and matching generation transition may be
consumed. Status cannot retire pending readiness; cleanup may supersede it and
permanently prohibits returning to setup. A failed acknowledgement write consumes
the attempt; preserve the real reply and use separate cleanup. The adapter neither
runs the server nor grants SDK/teardown authority. Its 28 offline controls and
review qualify preparation only; integrated display/physical qualification remains
at the [owning record](../../../DatadogRUM/MultiSceneSupport/Results/S3-human-residual-preparation.json).

### H06 display decoder preparation

`operation_display.swift` decodes actual images and every returned video sample
with CoreImage, Vision and AVFoundation. `operation_display.py` binds the decoder
source/executable, invocation/process receipts, raw media, metadata and frame stream
in an immutable manifest. Saved consumption rechecks every reference. Geometry
uses enclosing integer pixels, retaining raw fractional bounds; PTS order uses
exact rational values. No duration matching is required.

The pixel interval requires both owner markers from START through RUN to FINAL.
Each phase advances monotonically; a temporarily undecodable phase is allowed only
between adjacent states while both owner markers remain visible. Separate actual
START/RUN/FINAL screenshots are mandatory. Post-FINAL samples remain preserved but
excluded from the claimed interval. Twenty-one controls include generated PNG,
JPEG and compressed MOV media; they grant no native or release credit.

The fixture's `ProbePhysicalOperationDisplay` installs passive marker subviews on
the exact registered windows. It rechecks native scene, window, root and generation
before each boundary. START permits arrangement; RUN freezes owner geometry in
display pixels. Publication geometry describes that observation only: host capture
must join fresh native evidence and actual pixels after arrangement.

Real physical Operation execution requires fresh `DD_PROBE_OPERATION_DISPLAY_NONCE`,
`DD_PROBE_OPERATION_DISPLAY_SOURCE_SHA256` and
`DD_PROBE_OPERATION_DISPLAY_BINARY_SHA256` values. START and RUN screenshot proofs
must be consumed before SDK dispatch. FINAL follows the native collection seal;
its screenshot and complete movie proof precede local completion. The terminal's
`displayArtifacts` map binds all ten native display records, including consumed
proofs and the final context. The collector rejects missing/changed files and
mismatched owners or causal links. Legacy unarmed output omits the map.

The native hooks pass18 focused unit controls and three actual UIKit-rendered
phase decodes. These detached-window controls do not prove physical visibility.
The terminal join and affected host consumers pass29+52 controls. The typed host
bridge passes58 offline controls and scoped review. The post-startup coordinator and display/native join pass117 host controls and
two focused fixture tests with cleanup PASS. Launcher composition and the signed
physical Debug product qualify preparation; one physical adapter qualification
remains pending at the
[preparation owner](../../../DatadogRUM/MultiSceneSupport/Results/S3-human-residual-preparation.json).
Do not enable the profile with the old host runner or infer pixel/native acceptance
from local collection alone.

`operation_display_proof.DisplayProofBridge` attaches after `HostSetup.collect()`
and before publication. Supply original native START receipt/binding bytes and the
manifest decoded from that collection's screenshot to `start()`. It publishes the
one-use START request. Supply the resulting native RUN receipt and independently
captured RUN image to `run()`, then call `HostSetup.publish()` once. Publication
appends a selected proof/result and `display-extension.json`; the original proof
and result stay immutable. Legacy publication omits the extension entirely.

After the native collection seal, `final()` joins its original observation bytes,
the FINAL receipt/screenshot and the finalized movie manifest, then publishes the
FINAL proof. Collect native completion afterward; its ten-file map must match.
The bridge never captures pixels or substitutes an older observation. A changed
artifact, failed transfer or reused phase consumes the attempt. The caller still
owns actual native pulls, screenshot/recorder lifecycle, complete backend evidence
and separate cleanup. Offline controls do not admit a human session.

### H06 capture session integration

`operation_session.Session` composes an already admitted `HostSetup`, `Operator`
and `operation_media.Media`; it does not build, install or launch. A fresh live
operator page and its process must match before capture and cleanup. Execution
ends before the original cleanup cutoff; `ExecutionDevice` applies the earlier
cutoff without changing channel identity or extending a deadline.

The native START receipt and bindings precede setup capture. After the real setup
acknowledgement, the selected recorder starts before the START screenshot. RUN
gets a separate screenshot before setup publication. FINAL follows the native
collection seal, independent screenshot and complete movie decode. The fixture
publishes the seal's exact sequenced bytes as `native-final-observation.json`
before waiting for FINAL; terminal collection checks both byte/hash identities.
`Recorder.collect()` invokes `Completion` once. Every consumed display proof must
join those same native artifacts and the decoded media.

Capture failure stops and reaps only the owned recorder. Cleanup still requires
fresh release, native idle and original result expectations; an unreaped recorder
blocks teardown. Publish the release prompt promptly, then collect backend evidence
while the app remains installed. Local mapper/terminal records and frequent upload
do not prove delivery. Freeze `backendUntil` strictly between `executionUntil` and
the final cleanup deadline; expired or missing inventory remains INVALID. After
collection, recheck recorder/operator identity and consume the actual release, then
capture fresh native idle immediately before removal. Scenario, display, backend
and cleanup outcomes stay separate. No host control qualifies the physical recorder's
SIGINT response, transfer behavior or simultaneous window visibility. A signed
physical product and one native adapter qualification remain required before a
human session.

### H06 launch preparation

`operation_launch.Launcher` verifies a separately prepared signed physical Debug
product, source/compiler evidence, decoder and helper identities. Freeze its three
UUIDs with `new_identity()` in the reviewed admission before requesting readiness.
The actual reply binds the plan, admission, identity, server, device and scenario
within the original launch cutoff; there is no five-minute readiness rule. Fresh
launch admissions also require the distinct `backendUntil` cleanup reserve.

One install and one launch supply the actual PID, installed-code receipt, startup
freshness and native challenge. Only those validated original observations may
construct the channel and return `Session`; the caller runs it once. Shared transfer
validation handles startup without creating a provisional channel.

Before any attempted launch, a failed install may be removed only after fresh
quiescence and unambiguous task-process absence. Decode file URLs and reject
conflicting bundle/executable ownership. After attempted launch without a validated
channel, preserve the app and record cleanup BLOCKED for separate safe recovery.
Offline controls and the actual host-page check qualify this composition only;
the prepared signed product still needs physical adapter qualification before
native admission. For generic physical builds, set command-local `ARCHS=arm64`:
Xcode may otherwise compile an arm64e app against arm64-only package products.
Verify actual compiler triples and all required code slices; retain the original
failed build separately.

### H06 physical adapter qualification

`operation_qualify.py --plan <prepared-product> --admission <fresh-admission>
--output <fresh-root>` qualifies one recorder/screenshot and one opaque file
roundtrip through the task app container. The reviewed admission fixes all stage
cutoffs and a fresh nonce; its sidecar prevents replay. The app is installed once
and never launched. The original root-container transfer failed on the physical
iPad, and CoreDevice reported screen recording unsupported. That path is stopped;
its INVALID verdict and successful cleanup are preserved at the
[preparation owner](../../../DatadogRUM/MultiSceneSupport/Results/S3-human-residual-preparation.json).
Do not admit a human session or repeat this mechanism from offline controls alone.

Require fresh connected/unlocked physical iPad, active display, exact signed
product/helper/decoder/Xcode identity, and initial app/process absence. Install
and verify process absence before recording. Preserve actual command returns,
decode the complete media, stop/reap the recorder and verify fresh task-process
absence before uninstall. A discovered or ambiguous task process blocks removal.
No human release receipt is fabricated. The result qualifies tools only; startup,
input, concurrent topology, SDK/backend ownership and release gates stay separate.
The launcher rejects a qualification from different Xcode bytes or device OS/build.

Actual native command responses use the bounded 1 MiB host-context parser; the
64 KiB app-channel limit is unchanged. Large process inventories retain every row,
strict JSON validation and exact raw-response/receipt joins through setup and cleanup.

### Physical recording alternatives

Audio is not acceptance evidence. Future captures must be silent; do not treat a
muted monitor-volume slider or removing an audio track afterward as disabling
capture. The inspected physical-iPad Device Hub menu has Record Screen disabled,
and QuickTime movie mode exposes no audio-off source. Keep the historical
capability below unchanged, but prepare a silent route before another recording.
The current H06 movie contract proves co-visibility between phase anchors; live
preview or anchor screenshots alone do not provide that interval evidence.

A live Device Hub preview is useful for inspection; it does not prove that a
recording finalized. The [QuickTime capability result](../../../DatadogRUM/MultiSceneSupport/Results/S3-H06-quicktime-capture.json)
qualifies one selected iPad movie through supported UI Start/Stop/Save and complete
decode. Preserve actual returned source/control observations, an absent destination,
final file hash and decoded frames; restore the original audio input afterward.
Activate the captured document before saving. Closing its last document can leave
QuickTime with no AX window; opening New Movie Recording restores the preview.
Metadata frame counts do not replace the decoder's emitted-frame inventory. This
capability does not qualify H06 startup, causal run markers or simultaneous owners.

`operation_quicktime.Recorder` supplies the receipt chain. `operation_quicktime_session`
connects it to `Session` and the explicitly selected QuickTime launch mode. The
connection is offline-reviewed preparation until its first native cell. Freeze a
fresh directory, run/device identity,
QuickTime PID/start/executable, decoder and three original cutoffs. Retain the
actual initial full AX observation and its tool-call ID. The first request checks
publication, destination absence and current wired-device identity before UI work.

For each SOURCE/START/optional CHECK/STOP/SAVE request, use supported computer
control and pass the exact returned full AX bytes to `observe()`. Use
`getAXState({disableDiffing:true})`, or `getAXStateAndScreenshot` for SOURCE and
RESTORE; a diff is insufficient. The response includes that request hash, a fresh
observation ID, the actual tool-call ID, observation time and app ID. Source
inspection records the screen/audio checkmarks seen in the image from that same
call; it is explicitly a human/model interpretation, not a fabricated disk-image
hash. The selected input is iPad Screen/Speaker at High quality; RESTORE records
the original audio selection. `fail_pending()` retains an actual tool error when
no AX observation returned, allowing separate restoration without inventing one.

`finish()` verifies the exact saved movie and completes the existing decoder under
the evidence cutoff. No frame-count metadata equality or recording-duration target
is required. Recorder restoration has its own verdict/cutoff; it cannot repair a
failed capture and does not establish app cleanup. Never substitute an older
observation, restart a failed chain or reopen an expired cutoff.

On this host, CUA exposes focused window titles/URLs but no stable macOS window
IDs. These receipts therefore cannot detect every same-title preview replacement
or a disconnect/reconnect between samples. They cannot grant H06 admission:
startup transfer, actual source-bound START/RUN/FINAL markers, RUN pixels before
SDK dispatch, FINAL after the collection seal and full task cleanup remain to be
qualified. The earlier CoreDevice recording failure stays stopped.

### QuickTime session connection

The launcher requires an explicit `QUICKTIME_CUA` recorder selection and
`H06_QUICKTIME_FIRST_CELL` admission. Its preparation record binds the scoped
review, unchanged helpers/Xcode/device, and the saved `PASS_CAPTURE_CAPABILITY_ONLY`
result, review, definition and movie. This is never `PHYSICAL_ADAPTER_QUALIFIED`.
The first cell must still qualify startup, Documents traffic, source-bound media,
Operation owners, cleanup and backend evidence. No fallback selects the stopped
CoreDevice recording path. The old root-container failure remains INVALID; a
reviewed prior Documents transfer supports testing the real channel in this cell,
without another standalone root-payload or Home qualifier.

Before installation, bind the actual current QuickTime PID, wired-iPad inventory,
full initial AX return/tool-call ID and original audio selection in the admission.
The session requests SOURCE, START, exactly one CHECK before `HostSetup.publish()`,
STOP, SAVE and independent RESTORE. Intermediate `running()` checks inspect the
frozen receipts and process; they do not require additional UI calls or claim
continuous capture. The final full movie and unchanged START/RUN/FINAL decoder
provide that display evidence. SDK initialization occurs during startup; the
native barrier gates the selected Operations afterward.

For each printed `quicktime_request`, use supported CUA controls, await the actual
return, then call `operation_quicktime_session.returned()` with that request
reference, actual tool-call ID/completion time, exact full AX bytes and the explicit
reply described above. On tool failure, supply the actual error bytes instead.
It writes immutable raw files before an atomic completion marker. Partial, late,
foreign, conflicting or reused publications reject; matching older observations
cannot replace them. Keep each returned tool observation in the transcript.

QuickTime is never killed or represented by an owned subprocess. Capture,
recorder restoration and task cleanup keep separate verdicts. An unknown, late
or failed UI call blocks overlapping restoration and task teardown; preserve the
app and perform any later restoration as a separate recovery. A timely returned
semantic/capture failure must first obtain a stopped-document observation before
restoring audio. Stop is attempted at most once under its original cutoff. A
failed Stop or expired cutoff blocks restoration and task cleanup; it never
authorizes a retry. Restoration cannot repair the original capture verdict. App cleanup still requires its own fresh release, native idle,
worker quiescence and task-only removal proof.

### H06 physical cleanup disposition

Only this physical fixture may record `OS_APP_UNINSTALL_CONTRACT` for private
app-container data after a verified task-specific OS uninstall and fresh app/
process absence. Bind the exact device, OS build, bundle, release, idle, driver
stop, child quiescence and actual teardown observations. Keep `containerAbsence`
`UNVERIFIED` and direct filesystem observation false. Keychain, shared containers,
cloud data and unqueried filesystem state are outside this disposition. Apple's
[deletion guidance](https://support.apple.com/guide/ipad/remove-or-delete-apps-ipad0aed1df8/ipados)
supports the OS contract; a generic file-list error supplies no absence proof.

H06 startup requires `DD_PROBE_OPERATION_STARTUP_NONCE` (a fresh lowercase UUID),
clean run mode, both capture flags and matching installed-code run/revision.
`ProbeOperationStartupFreshness` runs before the code receipt, recorder and SDK.
It requires absent/empty Documents and absent source-known SDK/probe roots,
rejecting links, invalid parents and read errors without deleting evidence.
`operation_setup.HostSetup` requires the actual startup receipt as `startup_raw`
and the frozen `startup_nonce`; it checks them before requesting operator input
and binds the bytes through publication. Post-initialization paths need not stay empty.

The guard's focused controls and Swift/host codec are qualified at the
[preparation owner](../../../DatadogRUM/MultiSceneSupport/Results/S3-human-residual-preparation.json).
Physical startup, display capture and the integrated adapter remain unqualified;
no H06 human admission follows from these unit checks. Old attempt verdicts stay
unchanged. Cleanup alone never grants release acceptance.

`operation_backend.Backend` connects the sealed completion/recorder to the existing
complete count/page transport and ownership check. It preserves the broad
application/session Operation inventory, actual tool returns and every failed or
pending attempt. Indexing retries keep the native-derived UTC interval and
original cutoff, with fresh transport identities; they perform no native work.
Twenty-six offline controls and review pass. Display, cleanup and overall
acceptance remain separate; this collector has no native or teardown authority.

`operation_ownership.validate` checks eight raw steps, four reduced Operations,
exact ID joins, failure reason and A/B endpoints using independently captured View,
application and service IDs. Raw steps bypass public mappers and custom source/step
context can contain completion values; use raw `view.id` and reduced endpoints.
Backend row order and strict durations are diagnostic. Native call order, physical
visibility, complete-session collection and safe cleanup remain separate requirements.

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

The isolated H04 renderer also appends `focus_activation_channel.swift` and
`focus_activation_session.swift`. They bind ARM/STOP to the pre-SDK installed-code
bytes, run, process, unique challenge and frozen operational cutoffs. ARM precedes
the first driver step; STOP seals future work and waits for the original driver
to stop plus fresh original-owner/input-idle evidence. A background peer is valid
for cleanup. A failed scenario's different activation layout can also be safely
cleaned up; it earns no H04 acceptance. Marker admission still requires the exact
active target and background peer. Native geometry bytes are retained without an
exact floating-point equality gate. `focus_activation_transport.py` returns only
protocol qualification: actual transfer/process receipts and reviewed task-only
cleanup remain mandatory. `test_focus_activation_transport.py` exercises the actual
Swift channel/idle code with synthetic adapters; it is not native device evidence.
