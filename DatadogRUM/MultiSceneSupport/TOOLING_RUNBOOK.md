# Multi-scene RUM tooling runbook

Read this document before building, running, or validating the multi-scene probe.
It records the repeatable Xcode, simulator, device-interaction, and Datadog
workflows used by the project. Product behavior and support conclusions belong in
`ASSESSMENT.md`; `EXPERIMENTS.md` indexes evidence; exact new experiment and
session identifiers belong in the active numbered shard under `Experiments/`.

Last updated: 2026-09-17

## Purpose

The harness must distinguish an SDK defect from stale application state, an
incorrect launch, an expired interaction session, unsupported simulator behavior,
or incomplete backend ingestion. Tooling is therefore part of the experimental
contract.

This runbook has two kinds of guidance:

- Apple Xcode MCP constraints, which the SDK project cannot change.
- Harness adaptations and operating procedures, which this project owns.

## Repeatable acceptance and release progress

The admitted one-command workflow lives in
[`tools/multi-scene/acceptance/README.md`](../../tools/multi-scene/acceptance/README.md).
EXP-161 exercises A01 with the accepted long-running-action fixture; it does not
reopen EXP-159 or claim another family/hardware topology. The connector driver
runs authenticated queries and the Python process owns every stage/verdict.

- Preflight records HEAD and signature status, current toolchain/destination and
  an actual authenticated read. Unsigned local commits are allowed; an existing
  signature must verify. Fresh derived artifacts must execute all 166 probe tests.
- Hash SDK/fixture/runner/contract sources before building; verify unchanged
  identity through backend checks and match installed executable to the build.
- Prove bundle data-container absence before installing. Generate a new run ID;
  reject existing output directories and bridge responses from another request.
- Preserve the complete fixture contract, native scene identities, live Home UUIDs,
  exact action owners/final names/counts, submission boundaries and stop ordering.
- Query views by session alone and validate every view's run ID. A query filtered
  only by the current run can hide restored stale views.
- Store one sanitized durable JSON per attempt under `Results/acceptance/`;
  raw console, screenshot, xcresult and binary files remain local artifacts.
- Keep FAIL (semantic violation), INVALID (setup/oracle/tooling) and INCONCLUSIVE
  (environment or incomplete evidence) distinct. Never edit a failed summary into
  PASS. A corrected runner needs a new complete attempt.

Native mapper Home records carry logical scene/screen plus exact RUM UUID. They
have no occurrence number; action records carry sourceContext and rumContext,
not semanticContext. Resolve occurrence1 from the first Home UUID and enforce
that identity. The initial EXP-161 validator incorrectly required the absent
field and was rejected; its raw FAIL summary remains preserved as a tooling-invalid
attempt. Negative controls now cover the real envelope without weakening ownership.
A helper `exec_command` may return a session ID even for a short filesystem read.
Collect its subsequent output before checking exit_code or parsing JSON. Keep the
long acceptance process asynchronous so the bridge can serve its requests; test
both immediate and yielded helper completion paths.

`release-gates.json` is the finite machine register. Run
`python3 -B tools/multi-scene/release_checklist.py --update` after an evidence-based
status change. This regenerates PLAN gate rows and `Results/release-progress.json`;
without `--update` it checks consistency. New experiments name an existing gate
or a reproduced regression. Finished narratives belong in the detailed record,
not the active plan.

The early baseline protocol is in [BASELINES.md](BASELINES.md); its fixture lives
under `tools/multi-scene/baselines/`. Run timed/allocated workloads without another
build, test or profiling workload. Preserve invalid instrumentation attempts and
calibrate allocation counters before using their numbers. Do not treat a posted
scene notification as real OS teardown or a weak controller check as mounted
SwiftUI host lifetime proof. Predeclared thresholds cannot be raised after results.

## Full-target platform compatibility checks

For a platform compile gate, extract explicitly named production source/private/
resource paths from the pinned Git revision into a fresh isolated package. Use
all production sources of the selected target and preserve the repository's
platform minimums, dependency graph, Swift mode, C++ mode, SPM_BUILD and resource
settings. Overlay only the declared candidate files; hash the complete manifest
before and after every build, then match it to the committed candidate.

Run the unchanged control first and retain compiler failures at the target being
repaired. Require complete Debug and Release builds for the candidate. Record
commands, real process exit status, diagnostic summaries and result-bundle paths.
Verify each architecture's SwiftFileList contains every production source and
that the expected modules were emitted; an isolated expression is insufficient.
Compiler wrapper lines can say “failed with exit code 0” around warnings: use
actual build status and artifacts, not that phrase alone, for the verdict.

EXP-162's [durable manifest](Results/EXP-162-platform-compatibility.json) records
this watchOS RUM/macOS WebView check, with focused iOS regressions. The isolated
packages exclude the protected project and local xcconfig. The repository's
SPM build helper renames the main workspace, so this experiment did not invoke
or modify it. Compile evidence does not substitute for an unavailable runtime.

For controlled-clock regressions that assert nanosecond durations, use a fixed
reference-time Date when the interval must be represented exactly. EXP-163's
first wall-clock-based discrete deadline differed by 24 ns; its corrected control
kept the same production source and isolated the actual metadata failures. Keep
both attempts and distinguish an oracle correction from a production repair.

## Controller thread compatibility

Use the [controller fixture](../../tools/multi-scene/controller-threads/README.md)
for D09's mounted-controller check. It builds pinned SDK commits in isolated
packages, verifies clean installation and exact binary/run identity, and records
all 19 named checks. Main Thread Checker must be proven loaded inside the app;
no diagnostics without that proof is insufficient. Preserve the unchanged SDK
control's diagnostic headers separately from candidate assertions. A context-
queue callback supplies the observation barrier. A logical peer discriminates
routing without claiming a second native window or physical concurrency.

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

Lifecycle evidence also has distinct scopes:

| Evidence | Proves | Does not prove |
| --- | --- | --- |
| Focused state/unit test | Internal fencing, generation cancellation, stop count, and subscription cleanup | UIKit/SwiftUI or the OS delivered the real lifecycle |
| Posted `UIScene` notification | Handler response to that notification and reconnect ordering | A scene actually disconnected |
| Captured real reader synchronously detached and reattached | The mounted reader's pending final-detach generation can be cancelled without replacing its occurrence | A later-run-loop remount or scene reconnect |
| Conditional host removal reached by the probe | Final host detach and scene-local suppression/source cleanup | OS scene disconnect unless the native disconnect signal is separately observed |
| Real scene close/disconnect on capable hardware | The full platform-to-SDK lifecycle for that topology | Reconnect/restoration unless those subsequent states are also observed |

Record the narrowest applicable claim. A simulator failure before the decisive
step is `INCONCLUSIVE`, even when focused tests cover the same internal code.

## Restart verification without rerunning accepted experiments

Read `AGENTS.md` and `.continue-here.md` first and follow the latter's ordered
reading list. Verify the actual branch, HEAD, signature status, and working tree.
A later documentation-only handoff can legitimately follow the accepted SDK
checkpoint; inspect its path list instead of treating it as implementation drift.
Do not rerun accepted tests or load the frozen archive merely to resume.

Capture each protected index entry and file metadata without printing a diff of
local configuration. Never open `xcconfigs/Datadog.local.xcconfig`. Hashing the
protected project file is allowed; inspect only metadata for the local xcconfig.
Preserve the actual initial status exactly rather than assuming an older `AM`
state. Use `git commit -S --only -- <explicit paths>` when signing is available.
Per the user's 2026-09-17 instruction, if the agent is unavailable, continue with
`git commit --no-gpg-sign --only -- <explicit paths>` instead of blocking local
work. Verify the resulting commit path list, protected index entries, metadata,
and project-file hash. Do not change global signing configuration. Before any
future authorized push, sign any unsigned local checkpoints and verify every
outgoing commit's signature; no push is authorized for the current task.
Git signature verification may need permission to create temporary signature
files even though it does not modify repository content; never substitute a raw
signature block for cryptographic verification.

Rediscover workspace IDs, schemes, and destinations with real Xcode MCP calls.
A working GUI-backed MCP connection can coexist with a stopped standalone
`mcp-server`; the standalone daemon status alone is not a failure verdict.
Re-query `simctl` and `devicectl` before choosing a destination, and keep the
physical queue paused when its iPad is unavailable.

For Datadog, rediscover the tools actually exposed in this connection. If an
identity endpoint is absent, a minimal bounded read aggregate using a fresh
nonexistent probe run discriminator can verify authenticated query access
without retrieving customer payloads or reusing an old session ID. Skill listing
alone is not authentication evidence. Record that this check proves read access,
not organization identity or experiment ingestion; deeper RUM tools are not
required for basic event aggregation. Exact current identifiers and outcomes
belong in the active experiment record, not a reusable recipe.

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

Xcode 27 can print `error: the following command failed with exit code 0` around
compiler warnings even when the build and tests succeeded. Do not classify that
string alone as a failure. Use the `xcodebuild` process exit status and the
`.xcresult` test summary as the authoritative result, then inspect actual
`testFailures` when either reports a problem.

Xcode MCP console filtering can still return the entire application transcript
when stdout is represented as one large log unit. Use a unique probe run ID and
bounded mapper/backend queries as the primary evidence extraction path; do not
paste the full transcript into project documentation.

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

The Objective-C smoke target is selected as
`DatadogCoreTests/DDRUMMonitor_apiTests`. `ObjcAPITests` is a source group, not a
test identifier; selecting it can exit before compiling the intended fixture and
is a tooling mistake rather than API evidence.

For an exact semantic-engine or adapter-author probe, create its stable transition
source with the initial committed destination before the host evaluates. This is
the low-level EXP-146 harness recipe, not the recommended normal-customer
integration. Do not wait for a descendant
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

### Customer migration-cost loop

Run the migration discriminator before treating an engine/adapter prototype as a
public customer shape. Keep two comparable fixture states: ordinary customer code
and the instrumented candidate. The fixture must include many routes, multiple
independent navigation containers, standard sheets/covers, one existing router,
one native-SwiftUI flow, and one opaque third-party-style flow.

For every candidate, record:

1. screen files modified;
2. navigation methods modified;
3. customer-owned lines added outside a dedicated adapter;
4. integrations required per independent container/router;
5. the RUM-code diff after adding one route and one presentation; and
6. whether ordinary generated SwiftUI remains valid without Datadog knowledge.

Baseline acceptance is zero screen edits, zero per-navigation-method RUM calls,
unchanged `.sheet`/`.fullScreenCover` call sites, automatic metadata, sparse
optional naming overrides, and no new RUM code for an added destination. An
exhaustive resolver is acceptable only when the application already owns or
deliberately chooses one. Opaque input must fall back to scene-aware automatic
tracking rather than force a navigation rewrite.

Keep migration evidence separate from runtime semantics. A low-level adapter can
pass the complete EXP-146 occurrence oracle and still fail customer integration
if its diff grows with routes or navigation methods. Record that outcome as an
API-shape failure, not an SDK-engine failure.

Serialize live simulator work for these arms. Build and test the exact source
checkpoint first. Sign when the configured agent is available; otherwise create
an unsigned local checkpoint and keep the complete source-hash manifest. Local
validation can proceed with that frozen identity; signatures are required before
any future authorized push. Then give one device worker sole ownership of clean
terminate/uninstall/missing-container/run boundaries. A second worker may analyze
backend intake, but it must not install, launch, or interact with the shared
simulator until the owner releases it.

Before delegating a migration runtime, record SHA-256 fingerprints for every
runtime-critical source file and declare that source frozen. Do not edit those
files while the device worker owns the run; documentation-only work is safe. The
worker must compare the same fingerprints after capture. A locally passing run
whose source changed in flight is `INVALID` and must be repeated from a new clean
boundary and run ID. `EXP-147`'s first 38/38 attempt established this rule.

When the experiment claims that policy moved into the SDK, the frozen manifest
must include the SDK implementation files as well as the probe project and the
complete probe `Sources` tree. Hashing only the fixture would allow a passing run
to validate a different SDK revision. `EXP-148` used three comparisons: before
launch, immediately after the terminal oracle, and after backend validation.

Test configured-source precedence before runtime acceptance. A delayed explicit
or observed source must not fall through to a lower-priority content capability
while waiting for its first value, and it must not suppress automatic tracking
before a trustworthy destination exists. Use a non-replaying publisher for this
test; a synchronous current-value source cannot expose the edge.

Test observed-source lifetime through an actual `UIHostingController`, not only
by calling the host-state object directly. Count subscriptions on both the
original and a replacement publisher, force the outer SwiftUI view to render
both selections, and require one original subscription plus zero replacement
subscriptions for the same host identity. Pair this with two scene-attached
observed adapters and an unrelated controller subtree: posted disconnect must
release only the exact scene source, later updates from it must emit nothing,
the peer must continue, and the unrelated subtree must remain eligible for
automatic tracking. This proves internal reconstruction and fencing; it does not
replace a genuine OS disconnect/reconnect run on hardware.

For a current-destination or Observation-based adapter, a state-level timeline
test is necessary but not sufficient. Run a real sheet and full-screen-cover
scenario that emits one action and Resource synchronously after the accepted
dismissal mutation, then another pair after settling. The fresh underlying view
must own the synchronous pair. `EXP-150` demonstrates why: all deterministic
adapter tests passed while the live host reconciled one render too late. Keep an
actual `.sheet(onDismiss:)` callback as a separate characterization when useful;
it is a weaker boundary and must not replace the synchronous mutation oracle.

`EXP-152` records the deterministic native-callback recipe. Use a separate
scenario so the accepted synchronous oracle is not rewritten. Wait for an
`onAppear` signal from the actual Sheet or cover content before programmatic
dismissal; accepted router state alone does not prove that SwiftUI mounted the
presentation, and dismissing earlier can make a missing `onDismiss` a harness
race. At callback entry, record the accepted presentation, current destination,
and mutation generation, then emit uniquely named immediate and settled
action/Resource pairs. Require exactly one appearance and callback per style,
fresh revealed-view ownership, and no extra underlying occurrence caused by the
callback. Direct presentation replacement may omit outgoing `onDismiss`
(`EXP-144`), so never use callback count as the adapter's commit signal.

Xcode 27's one-shot
`withObservationTracking(options: [.didSet],_:onChange:)` is a candidate for an
existing `@Observable` router because its callback runs during mutation after the
new value is stored. The continuous API is not interchangeable: it delivers at
the next suspension point and cannot satisfy immediate attribution. Before a
runtime claim, deterministically prove one-shot rearming, no gap across
back-to-back and nested MainActor mutations, cancellation/teardown, and a safe
background-mutation fallback. Plain local `@State` is not an `Observable` router
and remains outside that candidate's exactness claim.

For a callback-driven custom or third-party navigator, preserve the imported
container and navigation methods. Build one boundary adapter that reads the
current accepted snapshot synchronously, registers once for accepted commits,
and feeds the existing publisher host. Deterministically test equal-route
occurrence identity, cancelled versus committed transitions, atomic presentation
replacement, token teardown, and registration count. The live oracle must add
initial `onAppear` and immediate-task action/Resource pairs so it can distinguish
a correctly seeded root from a callback that begins too late. `EXP-153` records
the accepted recipe and its `registrations=1 active=1` runtime assertion. A
callback delivered only after the customer's navigation method returns needs a
separate timing experiment and cannot inherit EXP-153's exactness claim.

Observe one atomically updated accepted-state property. A projection that reads
separate route and presentation properties receives one `.didSet` for each write;
those are separate committed signals, so an intermediate combination is expected.
Do not describe that shape as an atomic router transaction. The projection must
also be stable and side-effect-free because SwiftUI pins the first adapter for a
host identity. Validate this with the focused tests for nested reentrancy,
independent-property behavior, host reconstruction, deallocation, and invalid
background mutation.

Because this source file participates in cross-platform package builds, run both
the iOS Release probe build and the Xcode 27 visionOS package build after changing
Observation availability or compiler guards:

```bash
/Applications/Xcode_27.app/Contents/Developer/usr/bin/xcodebuild \
  -project Datadog/Example/MultiSceneProbe/RUMNativeMultiSceneProbe.xcodeproj \
  -scheme RUMNativeMultiSceneProbe \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' build

make DEVELOPER_DIR=/Applications/Xcode_27.app/Contents/Developer \
  spm-build-visionos
```

The package helper temporarily renames `Datadog.xcworkspace`. If Xcode MCP loses
the workspace afterward, reopen the restored absolute workspace path and select
the `DatadogRUM` scheme before running more tests.

Run the route-growth and presentation-growth checks as explicit before/after
steps. Record which customer files changed and prove the dedicated adapter and
integration call sites retained identical hashes. A build after growth proves
source compatibility; it does not replace the final mapper/backend run.

Objective-C has no equivalent SPI import boundary. Keep an Objective-C prototype
Debug-only until API review, exercise its exact generated selectors in the
Objective-C API smoke target, and do not mistake that prototype for an approved
Release API.

Run `make api-surface-verify`, but interpret its result precisely. Do not run
`make api-surface` as a check: it rewrites the checked-in baselines. If the
generator is invoked accidentally, restore only those known generated files and
reconfirm that no user-owned baseline edit existed before the run. The current
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

`open-window` is an acknowledged harness step: it waits for and consumes the
target scene's `scene-ready` signal before completing. Do not immediately follow
it with `wait-for-scene-ready` for the same target unless the scenario explicitly
expects a second lifecycle readiness event. `EXP-154` attempt 1 proved that the
duplicate wait starts after the first signal's acknowledgement and deterministically
times out; this is a harness failure, not evidence about the SDK or simulator.

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

A clean uninstall and missing container can still leave simulator window-server
identity outside the app container. If a scenario requiring initial logical scene
A instead restores only B, the attempt is `INVALID`: do not reinterpret B as A or
attribute the missing readiness signal to the SDK. Use a fresh simulator target
or an explicit, proven window cleanup and a new run ID. EXP-155 attempt 1 records
this boundary.

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

Do not issue `DeviceInteractionSynthesize` before the terminal result merely to
inspect a fully automated run. Its accessibility capture can time out and block
the scenario or its console evidence. Capture after terminal when useful. If an
early capture already occurred, repeat once without it before blaming the
harness or SDK; EXP-155 attempts 2 and 3 used that comparison to isolate a stale
view-boundary harness independently of the capture failure.

### Physical-device connection preflight

An eligible physical destination in Xcode does not prove that the device is
usable by Xcode's interaction-session APIs. On Xcode 27 those APIs can still
return a simulator-only inventory even while the destination list contains a
paired iPad. If they reject the physical device by display name, hardware UDID,
and CoreDevice identifier, use the Xcode-independent physical path:

- build for the exact physical destination with `xcodebuild`;
- inspect, install, launch, terminate, and capture through `devicectl`;
- keep the same clean-run and evidence requirements as an interaction-session
  run.

Do not begin terminate/uninstall/install work merely because the destination is
listed as eligible. First require all of the following non-mutating checks:

1. the exact device is paired and reports a connected transport;
2. it is awake, unlocked, and remains on;
3. app inventory succeeds;
4. process inventory succeeds;
5. at least one repeated inventory call also succeeds, proving the tunnel is not
   disconnecting immediately after connection.

CoreDevice error 4000 (`device disconnected immediately after connecting`),
`Network.NWError 60` (`Operation timed out`), or a paired-but-disconnected state
fails this preflight. Stop before mutation, record an infrastructure-
inconclusive attempt, and preserve the named SDK scenario unchanged. The first
two `EXP-156` preflights record this boundary: one reached lock state before
app/process inventory failed, and the next found only a disconnected paired
record. Neither produced a clean boundary, install, launch, run ID, RUM session,
or SDK verdict. The later wired retry closed this connection gate before exposing
the separate signing prerequisite below.

When the user reports a cable connection but CoreDevice exposes only
`localNetwork`, confirm USB enumeration independently (for example,
`system_profiler SPUSBDataType -detailLevel mini`). No matching iPad means the
paired network record is not evidence of a usable cable. Ask for an unlocked
device, a data-capable cable/port, and acceptance of any trust prompt before
retrying.

Record both identifiers when they differ: the hardware UDID selects the Xcode
destination, while the CoreDevice identifier can appear in `devicectl` output.
The transport (`usb`, `local-network`, or another reported path) is evidence too;
a physically attached device can still be reached only through a flaky
local-network tunnel.

### Physical-device signing preflight

Run signing diagnostics before terminate/uninstall work. The probe project
intentionally sets `CODE_SIGNING_ALLOWED=NO` and `CODE_SIGNING_REQUIRED=NO` for
its simulator-first workflow, so a successful `iphoneos` compile can still
produce an app that no physical device can install.

1. Run `security find-identity -v -p codesigning` in the actual login-keychain
   context and require a valid Apple Development identity. A restricted worker
   or sandbox can return zero even when the user has valid identities; rerun the
   diagnostic in user context before declaring a credential prerequisite.
2. Resolve a development team through developer-local Xcode settings or command
   overrides. Do not commit a team identifier, certificate, or profile to the
   probe project.
3. Build the exact iPad destination as `arm64`. An unconstrained build can select
   `arm64e` while local Swift package products contain `arm64` modules.
4. Verify `codesign -d --verbose=4 <app>` reports a signature and verify the
   expected embedded development profile before installing.
5. Only then establish the clean device boundary and install.

If scheme-wide signing overrides leak into Swift package targets, do not keep
mutating identity and provisioning settings globally. The probe intentionally
builds unsigned, so this repository-neutral fallback is acceptable for a local
physical experiment:

1. make a fresh exact-device `arm64` unsigned build;
2. copy the `.app` to a temporary directory and leave the original untouched;
3. select an existing development profile that includes the device and embeds
   one currently valid local certificate;
4. embed that profile and derive concrete, minimal entitlements from its granted
   wildcard values for the app's actual bundle identifier;
5. inventory nested Mach-O code and sign it depth-first with the exact matching
   identity, then sign the outer bundle without relying on `--deep` to create
   signatures;
6. run strict/deep verification in user context and independently compare the
   profile team, certificate, device, and application identifier before install.

Keep this local: do not commit the team, identity, profile, or generated
entitlements, and do not alter accounts or credentials. Preserve both unsigned
and signed copies plus verification logs.

Zero valid identities is a user/environment prerequisite, not an SDK or source
failure. Do not create, import, revoke, or regenerate signing credentials without
explicit user involvement. An unsigned install rejection with CoreDevice error
3002, `ApplicationVerificationFailed`, or `0xe800801c` proves only that the
physical runtime never began. Preserve the build and install log, prove the app
and process remain absent, and keep the named scenario pending unchanged.

`EXP-156` records the concrete boundary and correction: the wired preflight and
`arm64` build pass; the unsigned probe is rejected; a restricted identity query
incorrectly reports zero; the user-context query finds two valid identities;
one matches the installed device profile; and a copied app passes strict/deep
verification, clean install, and launch. None of its build, signing, or install
evidence is RUM evidence.

`devicectl device process launch --console --log-output <path>` can bridge the
application's console to the caller while writing only launcher status to
`<path>`. Do not assume `--log-output` preserved JSONL merely because the live
tool result displayed it. Capture the caller output separately or preserve the
task-history item, then verify the standalone file before ending the run.

Keep non-navigating attribution scenarios independent from navigation-specific
view machinery. If their purpose is to discriminate Operations, Resources, or
Traces across scenes, establish explicit per-scene Home boundaries unless the
navigation integration itself is part of the question. Preserve inferred versus
explicit signal APIs and every ownership expectation; changing only the view
fixture is a harness correction, not evidence about the signal under test.

A manifest's `simultaneous-visible-windows` requirement states the scenario's
contract; it does not prove the OS actually arranged both windows. For physical
runs, record each scene's geometry and lifecycle and capture the terminal UI.
Two full-screen geometries with one scene background and only the other visible
prove real multi-scene execution but leave simultaneous visibility
inconclusive. Move that exact subcondition to a human-arranged Stage Manager or
split-window run without discarding otherwise valid cross-scene signal evidence.

Follow the live Xcode MCP instruction about delegating device interaction even
for an automated run. The delegate owns only device state and artifacts; source
editing and semantic interpretation remain with the main task.

When delegation is required, the same delegated worker must start the workspace
interaction session, install and run the app, capture artifacts, and end that
session. Interaction keys are scoped to the agent context that created them: a
worker given a parent-created key can receive `Session with that key doesn't
exist`, while immediately reusing the parent's human-readable session identifier
can still be rejected as recently used. Delegate before
`DeviceInteractionStartWorkspaceSession` and use a never-used identifier for the
worker-owned session. If this mismatch is discovered after the clean uninstall
boundary, that boundary may be retained only when logs prove that no install,
launch, interaction, or container mutation occurred afterward; otherwise repeat
the complete clean precondition.

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
| `PLANNED` | The contract is defined before implementation; driver/oracle coverage is not yet complete |
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
- [ ] For API-shape work, baseline fixture and migration-diff measurements defined.
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
- [ ] Migration-cost result recorded separately from semantic-engine correctness.
- [ ] Exact run details appended to the active numbered shard and one compact
      locator row added to `EXPERIMENTS.md`.
- [ ] Interaction session closed or confirmed automatically expired.

## EXP-159 operational discriminators

- A discovered test with `No result`/`notRun` invalidates current-build acceptance,
  even if every older test passes. EXP-159 initially returned164 passes with two
  new tests unexecuted; fresh derived data produced 166/166.
- Resolve live-view prerequisites before the action interval. Native background
  can correctly close a view/action between suspended driver steps. An API-only
  synchronous batch is valid only with both live views and unchanged exact
  completion oracle; it does not close sustained multi-window hardware gates.
- Preserve final names and stop-phase attributes, exact owner UUIDs, counts, and
  B-before-A ordering. Neither timeout nor a same-name early completion can pass.
- Current full-module CLI uses `-enableCodeCoverage NO` for the previously
  documented finalization issue; this is not a skipped test or a Release-build flag.
- Mixed OSLog/stdout lines can contain a valid probe JSON object away from the
  start of the line. Preserve raw logs and decode complete JSON objects at their
  prefix; never manufacture missing records. Check sequence continuity after
  terminal capture. EXP-159 recovered sequence 49 verbatim this way, yielding
  all sequences 1–94; the stdio-only original remains available.

## EXP-165 mounted WebView compatibility runner

`tools/multi-scene/webview-correlation/run.py --control COMMIT --candidate COMMIT
--output NEW.json` creates frozen isolated Core/RUM/WebView/Replay apps and uses
a fresh iOS 27 simulator discovery. It verifies clean install, executable/source
identity and fresh run IDs, then captures dummy-token telemetry on loopback only.
The actual WKWebView bridge waits for exact browser payload acknowledgement before
the next native ownership mutation. Acknowledgement is repeatable, not consumed.

Decode the SDK's `Content-Encoding: deflate` as zlib, as well as gzip. The first
collector attempt missed deflate and is preserved as INVALID; missing payloads
must not be reported as SDK failures. Four focused collector controls pass.
Acceptance requires all 19 checks plus a native Replay-enabled payload, a control
that specifically loses the legacy container, and a candidate that preserves it
without peer fallback. Never commit raw intake payloads; keep compact ownership
summaries and artifact hashes. See the fixture README for its exact one-window
boundary; T10 owns two-container/backend evidence.

## EXP-166 shared handoff acceptance

Use `tools/multi-scene/handoff-isolation/README.md` for the staged runner.
Freeze the explicit SDK directories and copied baseline fixture before building;
only adapt internal owner arguments/accessors. Keep original EXP-160 fixtures,
protocol and thresholds unchanged. Wait for every build/test/profile job to
finish before the complete 27/26.5 ABBA window. Diagnostic probes never close a
performance gate. Record actual calibrated count/requested bytes, full-context
nested/throwing checks, source/build identities and separate platform compiles.

A pure TaskLocal optimization changed the synchronous snapshot contract even
though isolation passed. Keep the discriminating entry-snapshot/child-refresh
control. Foreign context must not activate the legacy third-party callback;
assert that boundary separately from direct Resource ownership through completion.
The accepted runner reaches 1 allocation/64 bytes; never raise the frozen budget
or substitute retained heap for allocation churn. Closed D04/P02 does not close
retained-state, backend, minimum-runtime or physical-topology gates.


## EXP-167 native restoration acceptance

`tools/multi-scene/session-restoration/run.py` builds explicit pinned control and
candidate SDK copies, clean-installs both on a discovered iOS 27 iPad simulator,
requests a second native scene, and produces 47 named checks with source/build
identity and run-ID validation. It reuses baseline extraction helpers; it never
reads the main project or local xcconfig. The README defines six cases and exact
owner/inventory assertions. Controlled expiration times do not prove physical OS
lifecycle behavior or backend ownership.

Observe application readiness after scene activation, with a bounded retry:
the callback may precede UIApplication becoming active. The first attempt missed
this boundary and is retained as INVALID. The accepted repeat rebuilds both arms
and requires real topology before interpreting semantic failures. Read snapshots
before sending markers, and preserve exact new-session view inventories; a later
action can otherwise hide a missing restoration branch. Maximum-duration cases
must refresh activity before their deadline so they cannot pass as timeouts.


## EXP-168 mounted SwiftUI lifetime acceptance

`tools/multi-scene/swiftui-lifetime/run.py` runs frozen signed control/candidate
apps on discovered27/26.5 simulators, with fresh installations and run IDs.
Its37 checks require actual keyed registration and RUM destination before each
host removal, weak-object counts after bounded main-queue draining, and exact
restoration of three real method implementations after SDK release. The fixture
only reads method implementations; it does not replace them. Keep sources alive
past removal to prove their weak registration entries do not extend SDK lifetime.

Record availability as an oracle prerequisite. The first26.5 attempt incorrectly
required the27-only transition arbiter and remains INCONCLUSIVE; the revised
fixture requires the correct presence/absence before interpreting lifetime checks.
Do not substitute controller release or process RSS for registration/state and
instrumentation release. Mounted lifetime acceptance does not close P03's
separate disconnected-history budget or physical scene lifecycle gates.


## EXP-169 pending semantic authority

`tools/multi-scene/pending-authority/run.py` repeats the frozen explicit/capability
host comparison on a discovered iOS27 simulator. Require all29 named checks,
real native mount/authority registry, clean installation and new run IDs. Automatic
eligibility and mapper ownership must be checked before first semantic input;
the unchanged control can correctly own later semantic work while losing all
ordinary automatic work before it. Submit the immediate marker directly after
input, before waiting for another render or lifecycle callback. Record both
phases, exact occurrence IDs and duplicate/cancellation negatives.

The four unit controls also cover absent instrumentation and attachment with the
actual registry. Source selection is not authority. This acceptance does not
prove disconnected publication/reconnect (D08), reentrant fan-out (R05), registry
retirement (P03), or physical/backend/minimum-runtime gates. Local unsigned commits
remain eligible under the user's policy; outgoing history must be signed before
any separately authorized push.

## EXP-170 accepted reconnect publication

Definition is in EXP-143-199.md. Use actual handler rejection and separate inherited
traits from reader mounts; a posted lifecycle sequence is deterministic evidence
only. Capture immediate Resource/Log ownership at the accepted reader boundary,
then inspect it without submitting a repair navigation command. Freeze both arms,
prove clean installation and exact required-check inventory, and preserve invalid
attempts. Reuse source/build helpers with explicit SDK directory allowlists; never
read the protected project/configuration. Physical H09 remains separate.

For the D08 fixture, enable automatic SwiftUI instrumentation with a predicate
that returns nil so the real authority registry exists without synthetic automatic
destinations. Read scene snapshots after draining the queued commands, but submit
Resource/Log calls immediately after the reader boundary. Do not install an
artificial authoritative-nil UI handoff in an ordinary lifecycle callback. Clear
the retained reader's onMount before reconstruction and require SwiftUI's actual
update to rebind it; checking only the root value is insufficient. Allow only the
known ApplicationLaunch startup view in addition to the exact scene destinations.
Strict lint uses tools/lint/sources.swiftlint.yml and tests.swiftlint.yml, each
with an explicit changed-file list; a configuration-free run is not the repo gate.

EXP-170 accepted attempt3: run.py at tools/multi-scene/reconnect-acceptance,
control7826eabc1/candidate66d1ccb02,51 required checks; control39/51 versus
candidate51/51. The runtime inventory requires real mounted readers/registry and
callback rebinding, exact fresh view/session owners, three Home occurrences and
one unchanged logical peer. Package attempt1 and fixture attempt2 remain in the
durable result. Physical H09 cannot close from these posted lifecycle controls.

## EXP-171 retained reader boundary

The definition requires no body/source reconciliation between teardown and the
retained reader remount. Capture the actual reader callback before removal;
reinstall it immediately before readding the retained hosting controller, and
submit Resource/Log markers inside that callback after SDK delivery. Require the
callback to run before any subsequent render; missing callback interception is
inconclusive. Do not assign a new root value to repair the source before this
boundary. Unit controls must enforce the same no-rebind sequence independently.

EXP-171 accepted attempt1: control2da21c041/candidate4ba7179c6,57 required
checks; control43/57 versus candidate57/57. Both first mounted reader callbacks
run with zero source observers; the candidate reobserves and owns the immediately
submitted Resource/Log markers. The root value is never reassigned. SDK/fixture/
binary identities remain frozen. Results/EXP-171-retained-reader.json retains all
checks, exact owners,318 test selectors and test-summary hashes. R04 closes only
its bounded component review, leaving physical H08/H09 unchanged.

## EXP-172 retained scene state

Keep the BASELINES.md protocol prefix frozen. The isolated logical-cycle fixture
must declare an empty initial scene inventory, introduce20 warm-up plus100+100
unique lifetimes, and tear down every introduced scene. Count every scene-owning
collection, not only the old registry names. Preserve raw malloc-zone heap samples
separately from ownership counts. Use fresh Release27/26.5 processes in ABBA order;
P01/P02/P04 dispatch measurements are not being rerun. Verify stale callbacks cannot
recreate retired entries before treating zero counts as acceptance. Initial live
peer/late SDK initialization and main-thread inventory controls are required.


Use `tools/multi-scene/scene-retention/run.py` with explicit control/candidate
revisions and a new output path. It archives seven allowed SDK source paths,
uses unchanged baseline App/allocation helpers, and records the one empty-inventory
constructor adaptation. It performs watchOS Release compile, discovers27/26.5,
proves clean installation and executable/run/topology identity, executes complete
Release ABBA, then checks ordinary automatic/manual exact owners. The summary
retains all raw samples and failed setup attempts. Seven negative oracle tests
cover registry renaming, incomplete boundaries, weak survivors and frozen limits.
EXP-172's first native attempt passed16 launches; keep its accepted result pinned.
Do not use a synchronous global queue call to prove background initialization:
GCD may execute it on the caller. The unit fixture uses async dispatch and a
bounded semaphore to hold the main seed until the handler is released.


## EXP-173 accepted presentation boundaries

Define control and closure separately for D10 and R06. An internal behavior-neutral
Binding-factory relocation can expose the actual production closure to tests;
record failing controls before changing its order. Native evidence must mount
real sheet/cover content and deliver actual dismissal callbacks. Submit markers
at setter-return/callback boundaries before awaiting another frame, then inspect
queued events after drain. Distinguish a rejected proposal, accepted descriptor,
customer item ID and occurrence UUID. Preserve old callback closures for stale
same-ID and A→B→A controls. Opaque setter internals are not an accepted-state
observation source; exact interior work uses the existing source contract.


The EXP-173 native harness uses observation-only Debug hooks in isolated copies
of both SDK arms. Record archived source identity separately from the compiled
hooked identity. The hook exposes existing Binding and boundary callback values;
it must not mutate application or SDK state. Explicitly type the captured generic
Binding, and capture initializer function fields through local constants instead
of mutating `self`. The first invalid build is preserved. No hook enters production
source or the public API.


EXP-173 acceptance is durable in `Results/EXP-173-presentation-acceptance.json`.
Use `tools/multi-scene/presentation-acceptance/run.py` and its README for the
repeatable frozen control/candidate workflow. Attempt1 failed hook compilation;
attempts2/3 exposed real candidate occurrence churn, and attempt4 passes77/77
versus55/77. Require stability before injecting an old callback: otherwise native
content rematerialization can be misdiagnosed as a stale-callback failure. A content
onDisappear alone is not accepted dismissal; inspect the current Binding.
The eight oracle controls include before-render and restored-run rejection.
Archive and observation-hook compiled identities remain separate; logical peer
and injected callbacks cannot close physical scene-ordering gates.

## EXP-174 observer reentrancy controls

Use whichever observer receives the outer snapshot first to trigger the nested
commit, so the control is deterministic without depending on Dictionary order.
Record per-observer generation sequences and assert the latest at nested return.
Removal must affect pending delivery and newly added observers receive only the
current snapshot. Initial publication needs the same oracle as commit. Run actual
SDK source/observed-adapter/handler objects in XCTest; no physical/backend claim
is appropriate for this synchronous in-memory gate. Keep the protected project
and local configuration untouched and retain all failed controls before repair.

EXP-174 is accepted at signed `368c62a72`: three failed controls and346 passing
affected tests, with nine new regressions. The durable observer-delivery JSON
records source identity and exact selectors. Its source-review environment is
intentional; a new simulator app or backend run would not improve this synchronous
fan-out oracle. Do not rerun it merely to resume. T03 needs its own captured-start
and exact completion/backend discriminator before implementation.
