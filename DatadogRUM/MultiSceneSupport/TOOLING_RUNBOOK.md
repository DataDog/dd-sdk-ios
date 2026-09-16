# Multi-scene RUM tooling runbook

Read this document before building, running, or validating the multi-scene probe.
It records the repeatable Xcode, simulator, device-interaction, and Datadog
workflows used by the project. Product behavior and support conclusions belong in
`ASSESSMENT.md`; `EXPERIMENTS.md` indexes evidence; exact new experiment and
session identifiers belong in the active numbered shard under `Experiments/`.

Last updated: 2026-09-16

## Purpose

The harness must distinguish an SDK defect from stale application state, an
incorrect launch, an expired interaction session, unsupported simulator behavior,
or incomplete backend ingestion. Tooling is therefore part of the experimental
contract.

This runbook has two kinds of guidance:

- Apple Xcode MCP constraints, which the SDK project cannot change.
- Harness adaptations and operating procedures, which this project owns.

## Documentation reading and update workflow

Use progressive disclosure; do not load the frozen history wholesale.

1. To resume work, read the [canonical overview](../MULTI_SCENE_SUPPORT.md) and
   the current execution slice in [PLAN.md](PLAN.md).
2. To check current support, read [ASSESSMENT.md](ASSESSMENT.md).
3. To locate evidence, search [EXPERIMENTS.md](EXPERIMENTS.md), then open only
   the linked detailed record or targeted archive range.
4. Before designing an experiment, search the relevant section of
   [REJECTED_APPROACHES.md](REJECTED_APPROACHES.md).
5. To record an experiment, append its full record to the active numbered shard,
   add one compact index row, and update only the affected assessment rows and
   plan items. Keep attempts with different validity or outcomes distinguishable.
6. When a shard's numeric range is full, freeze it and create the next bounded
   range without renumbering any experiment.

The frozen `Archive/` snapshots are integrity records. Do not edit them to repair
relative links; use [their manifest](Archive/README.md) and targeted search.

## Evidence levels

Never use one evidence level as a substitute for another:

1. A harness assertion proves that the application reached a call site or
   lifecycle state.
2. A mapper event or captured outgoing payload proves which RUM view UUID the SDK
   assigned to an event.
3. Backend intake proves that Datadog accepted and represented the event.
4. A reduced backend entity, such as a RUM Operation, proves reducer semantics and
   may differ from the raw step documents.

A callback count, successful build, local marker, or absence of a crash is not
semantic attribution evidence.

## Xcode MCP preparation

### Select the intended Xcode

When more than one Xcode is installed, pin `DEVELOPER_DIR` or use the intended
Xcode's absolute tool path. Do not infer the selected toolchain from an application
name, and do not assume that `/Applications/Xcode.app` or a remembered
`xcode-select` value points to Xcode 27.

Before an acceptance build, record both:

```sh
xcode-select -p
xcodebuild -version
```

On the 2026-09-15 test host, `/Applications/Xcode.app` was Xcode 26.6
(`17F113`), while `/Applications/Xcode_27.app` was Xcode 27.0 (`27A266a`) and
`xcode-select` selected the latter. A Release build invoked explicitly through the
26.6 installation completed but warned that the iOS 27 deployment target was
unsupported. Treat that result as invalid evidence. The accepted build used
`/Applications/Xcode_27.app/Contents/Developer/usr/bin/xcodebuild` and the iOS
27.0 simulator SDK.

### Resolve and cache the workspace

1. Call `XcodeListWorkspaces`.
2. Resolve the SDK workspace at `Datadog.xcworkspace` for DatadogRUM tests.
3. The probe is a separate project and its scheme is not in the SDK workspace.
   If its path is absent, call `XcodeOpenWorkspace` with
   `Datadog/Example/MultiSceneProbe/RUMNativeMultiSceneProbe.xcodeproj`.
4. Cache both returned `workspaceIdentifier` values for the current Xcode
   connection. Use the SDK identifier with scheme `DatadogRUM` and the probe
   identifier with scheme `RUMNativeMultiSceneProbe`.
5. Pass the correct identifier to every workspace-aware call. A failed attempt
   to select `RUMNativeMultiSceneProbe` in the SDK workspace is a workspace
   routing mistake, not a missing scheme or project defect.
6. Resolve identifiers again if Xcode, the headless server, or either workspace
   restarts.

`workspaceIdentifier` is required in practice even where an individual tool's
schema makes it look optional. Never reuse a remembered identifier across Xcode
connections.

### Verify useful access

A listed server or successful tool discovery does not prove that tool calls work.
Verify access with a real call such as `XcodeListWorkspaces`, then list the active
scheme and run destinations. If calls reject or hang, check Xcode's external-agent
permission and headless-server state before investigating the SDK.

### Cache stable selections

For one working session, retain:

- `workspaceIdentifier`;
- active scheme;
- exact simulator or device UUID;
- disambiguated run-destination title;
- probe bundle identifier.

Re-query only when a tool reports a stale identifier, the scheme changes, or the
device topology changes.

## Xcode-provided interaction instructions

Xcode 27 packages a `device-interaction` skill, but it may not be exposed through
MCP resources. Export it before opening a device-interaction session:

```sh
xcrun agent skills export --output-dir /tmp/xcode-agent-skills
```

When the selected Xcode is not the one chosen by `xcode-select`, invoke that
Xcode's `usr/bin/agent` directly or set `DEVELOPER_DIR` first. The output directory
must be absolute. A missing directory is created automatically.

Read the exported `device-interaction/SKILL.md` before driving the device. Do this
once during preparation, not while a short-lived interaction session is open.

## Build, test, and launch workflow

### Fast test loop

1. Use `GetTestList` once and cache exact `targetName` and `testIdentifier` pairs.
2. Use `RunSomeTests` while iterating on focused harness or SDK behavior.
3. Read `fullSummaryPath`, `fullConsoleLogsPath`, and the `.xcresult` path instead
   of relying on truncated inline results.
4. Run `RunAllTests` at the slice checkpoint.
5. Run the repository's authoritative module suites, lint, build, and API checks
   at their planned release gates.

Filter build and console logs at the tool when possible. Avoid transferring or
parsing an entire Xcode log when a severity, pattern, glob, or tail limit can
isolate the evidence.

The probe scheme is `RUMNativeMultiSceneProbe`. The SDK workspace scheme is
`DatadogRUM`; `DatadogRUM iOS` is stale and exits before tests run. If a direct
Xcode 27 test invocation completes its tests but hangs while finalizing the
result bundle, rerun the unchanged selection with code coverage disabled:

```sh
/Applications/Xcode_27.app/Contents/Developer/usr/bin/xcodebuild \
  -workspace Datadog.xcworkspace \
  -scheme DatadogRUM \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -enableCodeCoverage NO \
  test
```

Use `-enableCodeCoverage NO` only with a test action. Xcode rejects that option
for a plain `build`; the accepted Release probe command omits it.

Authoritative Xcode 27 Release probe build:

```sh
/Applications/Xcode_27.app/Contents/Developer/usr/bin/xcodebuild \
  -project Datadog/Example/MultiSceneProbe/RUMNativeMultiSceneProbe.xcodeproj \
  -scheme RUMNativeMultiSceneProbe \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  build
```

Keep the explicit Xcode path. `/Applications/Xcode.app` may point at a different
major version on the same host.

This is a tooling workaround, not permission to omit the complete module run.
Use Xcode 27's `xcresulttool get test-results summary` on the resulting
`.xcresult` when raw output is truncated. Its device-level `passedTests` count
includes parameterized test runs and is the count used by this project.

For semantic restoration and router work, do not rely on sleeps or one runtime
callback order. Run `RUMSwiftUINavigationOccurrenceSourceTests` first, then the
semantic cluster (occurrence source, container lifetime, interactive arbiter,
and semantic navigation state). Its deterministic matrix must cover:

- accepted occurrence identity before descriptor reconciliation;
- donor reader mount versus non-reader trait/update callbacks;
- multiple newer and out-of-order older donor refreshes;
- detach and disappear before and after ownership transfer;
- SwiftUI state replacement and later reuse of the former state;
- scene disconnect, queued source cleanup, and both reconnect orders;
- same-scene identity transfer and cross-scene fresh remount; and
- a newer donor generation while the last proven destination is still older.

Only after that matrix passes should one clean device run validate the
platform's observed happy-path order. A device PASS followed by a deterministic
race failure is a rejected implementation attempt and must remain in the active
experiment record.

### Experimental public-API loop

Customer-shaped API experiments may use Swift SPI before normal public API
review. Import those declarations with `@_spi(Experimental)` in the probe and
compile both Debug and Release probe configurations. The Release build is the
proof that the experiment does not depend on `@testable` visibility.

An SDK test that needs both SPI and internal access uses both import attributes,
each on its own line:

```swift
@_spi(Experimental)
@testable import DatadogRUM
```

A plain `@testable` import does not expose SPI members. When asserting fresh
SwiftUI occurrences, inspect emitted transitions or commands; the tracking
state's base identity is a stable fallback and is not the generated occurrence
identity. `RUMStopViewCommand` also has no instrumentation-type field, so pair it
with its start by identity and assert the start command's type.

For an exact semantic host, create its stable transition source with the initial
committed destination before the host evaluates. Do not wait for a descendant
`.task`, probe scene reader, or diagnostic native-scene attribute before calling
`setInitialDestination`: `EXP-146` attempt A showed that this makes root
`onAppear` and immediate-task work precede the semantic view. The host resolves
the actual scene from the SDK's inherited scene trait; customer destination
metadata does not need an internal RUM UUID or native scene identifier. Add root
`onAppear` and immediate-task action/Resource ownership to the oracle so a normal
navigation-only timeline cannot conceal this ordering regression.

A complete semantic timeline does not by itself prove that SwiftUI reconstructed
the customer container or resolved its optional capability again. Add a separate
assertion whose evidence is the capability's resolution count. For the stable
arm, return the same source and require no replay or duplicate. For the
adversarial arm, return a decoy source on the second resolution, forbid its view,
and require the original source to complete the exact timeline. This separates
source-pinning evidence from an ordinary happy-path navigation pass.

Serialize live simulator work for these arms. Build and test the exact signed
revision first, then give one device worker sole ownership of clean
terminate/uninstall/missing-container/run boundaries. A second worker may analyze
backend intake, but it must not install, launch, or interact with the shared
simulator until the owner releases it.

Objective-C has no equivalent SPI import boundary. Keep an Objective-C prototype
Debug-only until API review, exercise its exact generated selectors in the
Objective-C API smoke target, and do not mistake that prototype for an approved
Release API.

Run `make api-surface-verify`, but interpret its result precisely. The current
source-based verifier includes Swift SPI and declarations excluded by `#if DEBUG`;
it therefore reports the experimental Swift and Objective-C declarations
as additions. Do not update checked-in API baselines for a prototype. Confirm
that the diff contains only the expected experimental declarations and treat any
additional difference as a failure. A stable proposal must pass the normal API
review and API-surface gate before release.

### Launch configuration

Supply scenario configuration through `DeviceInteractionInstallAndRun`:

```text
$(inherited)
--probe-scenario <scenario-id>
--probe-run-id <unique-run-id>
--probe-run-mode <clean-or-restoration>
```

Do not edit the shared Xcode scheme for an individual experiment. Preserve
scheme-provided arguments with `$(inherited)`.

Every conclusive attempt must have a unique run ID. A relaunch that intentionally
continues the same attempt may reuse its run ID only when the scenario contract
explicitly permits it.

## Clean-run precondition

For scenarios whose default run mode is `clean`:

1. Resolve the exact target-device UUID.
2. Terminate the probe if it is running.
3. Uninstall its bundle from that exact target.
4. Verify that querying the application container reports that it does not exist.
5. Start or reuse the workspace interaction session.
6. Install and launch the requested scenario.

If Xcode must start a workspace session before it reveals the target UUID, that
session may remain open while steps 2–4 run. The acceptance boundary is that the
uninstall and missing-container proof occur before `InstallAndRun`; merely opening
a device session does not contaminate application state.

Failure to establish the clean precondition invalidates the attempt. It is not an
SDK failure.

An uninstall and missing application-container proof do not guarantee that the
simulator window server discarded every value previously persisted for a SwiftUI
`WindowGroup`. The probe must normalize each restored window value to the current
launch's run ID before using it as telemetry. Preserve the original routed value
only for SwiftUI window identity and dismissal. Backend validation must still
inspect every view in the resulting session and reject a run if any semantic view
retains another run ID.

OS/window persistence restoration scenarios must use their documented
predecessor run and restored state instead of this clean sequence. A clean launch
whose router is intentionally initialized with a non-empty path, such as
`EXP-143`, is semantic-container bootstrap and still uses the clean-run
precondition.

## Device-interaction workflow

Device-interaction sessions can expire quickly. Complete all code review, skill
loading, coordinate strategy, scenario selection, and expected-result preparation
before starting one.

Use this sequence without unrelated work between calls:

1. `DeviceInteractionStartWorkspaceSession`
2. `DeviceInteractionInstallAndRun`
3. `DeviceInteractionSynthesize` with no command to capture live state
4. Read the hierarchy and confirm the expected accessibility identifier
5. `DeviceInteractionSynthesize` with the prepared interaction
6. Capture the post-interaction hierarchy, logs, and screenshots
7. Wait only as required by the scenario's observable terminal result
8. `DeviceInteractionEndSession`

The start call returns the exact interaction key. Apple currently names the key
parameter differently across its APIs:

| Call | Key parameter |
| --- | --- |
| `DeviceInteractionInstallAndRun` | `interactionSessionKey` |
| `DeviceInteractionSynthesize` | `interactSessionKey` |
| `DeviceInteractionEndSession` | `interactionSessionKey` |

Preserve the spelling from each live schema. Do not normalize the parameter name
in raw calls.

Trust the exact value returned in `interactionSessionKey`, even when it happens
to equal the human-readable session identifier rather than looking opaque. Retry
`StartWorkspaceSession` only after another call reports that returned key invalid
or expired.

### Fully automated scenarios

A signal-driven scenario that needs no external touch does not require a
`Synthesize` call merely to advance it. After the clean precondition:

1. start the workspace interaction session;
2. install and run with the exact scenario arguments;
3. read filtered console output until the terminal result or bounded timeout;
4. capture hierarchy/screenshot only when visual state is evidence for the row;
5. end the interaction session.

Follow the live Xcode MCP instruction about delegating device interaction even
for an automated run. The delegate owns only device state and artifacts; source
editing and semantic interpretation remain with the main task.

`waitForSignal` proves that a matching signal exists after the driver's current
observation cursor; it does not by itself prove that a new semantic occurrence
started after an earlier navigation boundary. A previously emitted occurrence
can satisfy a later wait when the cursor predates it. For returned destinations,
pair the wait with the ordered semantic oracle's after-index rule, or wait for an
occurrence number that cannot exist before the boundary. `EXP-143` caught a
hidden initial Home this way: the step wait reused H1, while the ordered oracle
correctly rejected the missing post-pop Home occurrence.

Do not model direct SwiftUI presentation replacement by assuming every outgoing
`.sheet` or `.fullScreenCover` modifier invokes `onDismiss`. `EXP-144` observed
that Sheet → Cover → Sheet can omit both replacement-time dismissal callbacks.
Keep a style's recorder interval continuous when its callback is omitted, and
ignore a delayed callback while that same style is current. This is a harness
lifecycle rule; the RUM oracle must still require distinct presentation view IDs.

Do not add a later `waitForSignal` for a short marker when the terminal completion
conditions already require the marker's action/Resource evidence. The marker may
arrive while the driver is evaluating an earlier step; subscribing afterward
creates a false timeout even though the SDK result is complete. The first
post-fix canonicalization attempt in `EXP-143` and `EXP-145` attempt A exposed
this race. If an explicit wait is necessary, choose a discriminator that cannot
exist before the current observation cursor.

Do not use an ordinary delayed task as the clock for an exact authority stop.
Scheduling may place it before or after the stop; either owner can be correct for
the call site's actual execution time. `EXP-145` attempt B was invalid for fixing
that callback to the manual side. Use an explicit marker before stop and another
after the newly revealed occurrence starts. Treat the unsynchronized delayed
callback as diagnostic evidence unless the driver gates its execution side.

### Coordinate and gesture rules

Always capture the current hierarchy before interacting. Use an element's reported
hit point or bounds; never guess from a screenshot. If multiple applications are
present and the hierarchy provides an `activationBundleId`, activate that bundle
before interacting with its element.

The documented commands used by this project include:

```text
t <x> <y> [duration]                     tap or hold
d <x> <y>                                double tap
t <x1> <y1> f <x2> <y2> [duration]      swipe
w <duration>                             wait
```

Example upward swipe:

```text
t 200 600 f 200 200 0.3
```

Choose both swipe endpoints inside the measured scrollable element. The duration
is part of the experiment: a deceleration scenario needs a fast gesture, while a
drag-and-drop scenario needs a slower dedicated command.

After any interaction, capture again and confirm its effect. Retry at most once
when the evidence proves that the first interaction had no effect. Do not retry a
gesture merely because the SDK result was unexpected.

`interactionCommand: "help"` is not supported and does not return command syntax.

### Expired sessions

`Session not found` before an interaction means the gesture was not performed. It
does not consume the scenario's gesture retry and is not an SDK failure.

Recover by:

1. Starting a fresh workspace interaction session.
2. Reinstalling and relaunching the same prepared scenario.
3. Capturing the live hierarchy again.
4. Recomputing or confirming coordinates from that new hierarchy.
5. Performing the prepared interaction immediately.

If an automated run's session expires before `InstallAndRun`, first prove that no
install, launch, or container mutation happened after the clean precondition. A
replacement interaction session may then reuse that clean proof. If any app
operation occurred, repeat terminate, uninstall, and missing-container checks;
do not infer a clean launch merely from the replacement session being new. Some
Xcode versions also reject immediate reuse of the expired human-readable session
name, so use a distinct replacement name and preserve both names in the tooling
record.

If `DeviceInteractionEndSession` reports that the session no longer exists after
a successful capture, record it as automatic tooling expiration. The captured
artifacts remain valid.

## Scenario interaction recipes

Every scenario requiring external interaction should declare or document:

- required capability, such as `nativeUIKitGesture`;
- assertion or signal that proves the destination is ready;
- target accessibility identifier;
- gesture type and speed requirement;
- coordinate rule based on the target bounds;
- maximum retry count;
- timeout and terminal-result condition;
- simulator, physical-device, or human requirement;
- conditions that make the run inconclusive.

The application must publish a readiness barrier before external input is
accepted. Reaching a screen name is insufficient when the interactive UIKit or
SwiftUI element has not mounted yet.

Prefer an XCTest UI or `xcui` driver for repeatable simulator interactions when it
exercises the same production gesture path. Use Xcode device interaction for
physical devices, visual inspection, and experiments requiring its device
capabilities.

## Simulator, device, and human routing

Do not repeatedly run a topology the simulator cannot express.

Classify each experiment as one of:

- simulator-capable and automated;
- simulator-capable with one real external gesture;
- physical-device required;
- human-driven physical-device required.

If the simulator cannot maintain simultaneous windows, generate an analog touch,
perform a cancellation gesture, or preserve deceleration across a transition,
record the exact limitation and put the unchanged experiment in the physical or
human rerun queue. `INCONCLUSIVE` is the correct result; `PASS` and `FAIL` are not.

The harness should continue to own deterministic setup, run IDs, assertions,
payload capture, and backend validation even when a human supplies the gesture.

## Run artifacts

Each attempt should produce one compact machine-readable summary containing:

- scenario ID and unique run ID;
- Git revision and dirty-state note;
- device UUID, model, and OS;
- clean or restoration mode;
- terminal `PASS`, `FAIL`, `INCONCLUSIVE`, or `INVALID` result;
- expectation count and failed expectation identifiers;
- RUM session ID when available;
- hierarchy, console-log, screenshot, summary, and `.xcresult` paths;
- local mapper/payload validation status;
- backend ingestion and reducer validation status;
- reason and rerun instructions for invalid or inconclusive attempts.

Exact run IDs, RUM session IDs, and artifact evidence belong in the active
numbered record under `Experiments/`. `EXPERIMENTS.md` keeps one compact locator
row; higher-level documents should cite the stable `EXP-*` identifier instead of
duplicating volatile identifiers.

## Datadog validation workflow

Use the unique probe run attribute as the primary search key. Application name and
timestamps are secondary discriminators.

RUM and APM index the probe's run identifier under different attributes:

- RUM: `@context.probe.run_id:<run-id>`;
- APM spans: `@probe.run_id:<run-id>` and the exact `@http.url` as an independent
  retry discriminator.

Do not substitute the APM form in a RUM query. For Trace-only URLSession rows,
also aggregate the exact URL in RUM and require zero matching Resource events.

For each run:

1. Find the RUM session and record concise identifying metadata.
2. Retrieve the relevant view, action, Resource, error, long-task, vital, and
   Operation documents with the run-ID query.
3. Independently query `@session.id:<session-id> @type:view`. Verify that every
   expected occurrence is present and that each semantic view document carries
   the current run ID. A run-ID aggregate alone can hide a view whose start
   attributes were contaminated by restored state.
4. Group actions and Resources by `@type`, `@view.id`, and `@view.name`. Compare
   those counts and UUIDs with the local mapper evidence; this catches a correct
   view inventory with incorrect downstream ownership.
5. For Operations, compare raw `operation_step` documents with the reduced
   Operation result.
6. Verify exact counts, occurrence IDs, start/end ownership, and the absence of
   unexpected duplicate events.
7. Check for RUM errors, crashes, or SDK telemetry that could invalidate the run.

If an exact application-name query returns nothing, retry authentication and
broaden the query before concluding that the session is absent. Account for intake
latency with bounded retries; do not poll indefinitely.

Save reusable Datadog query shapes without credentials. Never copy API keys,
authorization headers, cookies, or complete customer payloads into documentation.

## Failure classification

Use these categories consistently:

| Result | Meaning |
| --- | --- |
| `PASS` | Every required semantic expectation is proven at its declared evidence level |
| `FAIL` | The intended platform path occurred, but the SDK or backend violated the contract |
| `INCONCLUSIVE` | The environment could not exercise or distinguish the required behavior |
| `INVALID` | Setup, launch configuration, stale state, tooling, or oracle construction broke the experiment |
| `SKIPPED` | A declared capability or prerequisite made the row intentionally inapplicable |
| `PREPARED` | Driver/oracle coverage exists, but the required runtime or backend acceptance has not run |

Examples that are not SDK failures:

- wrong or omitted scenario argument;
- stale installed application;
- missing clean-install proof;
- expired interaction session before the gesture;
- gesture never reaching the intended element;
- simulator reporting no deceleration for a required deceleration experiment;
- multi-window compositor closing a scene before the decisive step;
- backend query attempted before ingestion or with expired authentication;
- oracle checking the wrong event type, count, interval, or occurrence.

When the simulator window server (`backboardd`) crashes, inspect its `.ips` and
look separately for an application `.ips`, fatal/assertion output, mapper error,
and backend RUM crash/error event. One clean retry is reasonable when the same
topology has previously worked. An identical second system-process crash before
the decisive signal moves the unchanged row to capable physical hardware; it is
not an SDK crash or semantic result.

Invalid and inconclusive attempts must still be documented so later work does not
repeat them.

## Security and repository hygiene

Never stage or commit:

- `xcconfigs/Datadog.local.xcconfig`;
- credentials or authentication material;
- captured intake request bodies or headers;
- simulator application containers;
- screenshots, hierarchy dumps, console logs, or `.xcresult` bundles;
- temporary exported Xcode skills.

Store artifacts in temporary or ignored local directories. Documentation may
record their local paths for the current handoff, but only durable, sanitized
conclusions and identifiers belong in Git.

Before committing harness or documentation work, inspect the exact staged paths
and keep unrelated project-file or local-configuration changes outside the commit.

## Known Apple Xcode MCP constraints

These are operating constraints, not SDK backlog items:

- interaction sessions may expire while preparation is still in progress;
- the session lifetime and remaining time are not exposed;
- an expired session may be reported only as `Session not found`;
- device-interaction command grammar may require exporting Xcode's packaged skill;
- `interactionCommand: "help"` does not provide that grammar;
- the interaction key parameter has inconsistent names across calls;
- workspace identifiers become stale when the workspace or Xcode service restarts;
- the advertised tool set is dynamic;
- a successful connection or tool listing does not prove the agent is authorized
  to make useful calls.

Do not create project tasks to change these Apple-owned APIs. Adapt the harness and
runbook around them.

## Pre-run checklist

- [ ] Intended Xcode selected.
- [ ] `xcode-select -p` and `xcodebuild -version` recorded for acceptance builds.
- [ ] Working Xcode MCP call completed.
- [ ] Current workspace identifier resolved.
- [ ] Scheme and exact run destination confirmed.
- [ ] Device-interaction skill exported and read when needed.
- [ ] Scenario and unique run ID chosen.
- [ ] Capability and interaction recipe reviewed.
- [ ] Expected semantic timeline and evidence levels known.
- [ ] Clean or restoration precondition established.
- [ ] Backend query discriminator prepared.
- [ ] No credentials or local artifacts are candidates for staging.

## Post-run checklist

- [ ] Terminal result captured.
- [ ] Expected interaction demonstrably occurred.
- [ ] Mapper or outgoing-payload ownership checked.
- [ ] Backend session and event ownership checked when required.
- [ ] Exact-session view inventory matches the mapper and every view has the current run ID.
- [ ] Raw and reduced Operation evidence compared when applicable.
- [ ] Crash, RUM error, and duplicate-event checks completed.
- [ ] Invalid or inconclusive tooling behavior documented.
- [ ] Physical-device or human rerun added when needed.
- [ ] Exact run details appended to the active numbered shard and one compact
      locator row added to `EXPERIMENTS.md`.
- [ ] Interaction session closed or confirmed automatically expired.
