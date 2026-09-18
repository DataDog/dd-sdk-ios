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
  signature must verify. Fresh derived artifacts must execute the complete discovered fixture inventory.
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

[F03's finite matrix](FINAL_COMPATIBILITY.md) names the final module, client and
platform cells. Freeze the approved candidate before execution; this procedure
is reusable build guidance, not proof that the matrix has passed.

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

[Platform-build evidence](Experiments/EXP-143-199.md#exp-162--restore-watchos-resource-and-macos-webview-compilation) records the isolated full-target procedure. Exclude protected project/configuration; the repository SPM helper temporarily renames the workspace, so use an isolated package where that would violate workspace safety. Compile proof does not replace runtime proof.

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

[.continue-here.md](../../.continue-here.md) is the sole restart cursor.
Use progressive disclosure and open only the evidence that owns the question.
Do not load the frozen history wholesale.

| Fact | Sole owner | Minimal update |
| --- | --- | --- |
| Approved goal, behavioral contract and non-goals | [Overview](../MULTI_SCENE_SUPPORT.md) | Change only for an approved product decision; link its affected gates. |
| Finite obligations, status, owner, dependencies, completion mode and evidence | [release-gates.json](release-gates.json) | Edit the affected gate, run the generator, update the affected assessment capability. |
| Generated checklist and counts | [PLAN](PLAN.md), [release progress](Results/release-progress.json) | Run `python3 -B tools/multi-scene/release_checklist.py --update`; never hand-copy counts elsewhere. |
| Execution priority and experiment admission | [PLAN](PLAN.md) | Preserve finite scope and dependency order; point to the cursor for current work. |
| Support conclusion and evidence limit | [Assessment](ASSESSMENT.md) | Update only affected capability/limits with direct evidence and remaining gates. |
| Current checkpoint, unfinished work and next action | [.continue-here.md](../../.continue-here.md) | Replace the cursor; do not append an experiment history or reusable session IDs. |
| Experiment definition, attempts and outcome | Owning detailed record and durable result | Preserve stable IDs, frozen sources/builds, failed/invalid attempts and negative controls; add/update one compact index row. |
| Experiment lookup | [Index](EXPERIMENTS.md) | ID, related gates, bounded outcome, decisive conclusion and exact record link; no restart instructions. |
| Reusable execution lesson | This runbook | Add the discriminator/procedure and link the detailed result rather than repeating it. |
| Customer integration and ownership guidance | [Support guide](SUPPORT_GUIDE.md) | Match the approved API and fixed T01–T15 contracts; status remains in the register. Compile final examples before supported publication. |
| Final compatibility execution contract | [Final matrix](FINAL_COMPATIBILITY.md) | Preserve finite cells and frozen source/inventory/artifact rules; record attempts separately from the procedure. |
| Review attribution and disposition | [Safety review](PRODUCTION_SAFETY_REVIEW.md), [triage](REVIEW_TRIAGE.md), [component review](COMPONENT_REVIEW.md) | Map finding to gate and repair evidence; distinguish completed review from release readiness. |
| Baseline thresholds/results and rejected lessons | [BASELINES](BASELINES.md), [REJECTED_APPROACHES](REJECTED_APPROACHES.md) | Preserve predeclared thresholds and failed results; append evidence without rewriting history. |

After a documentation update, run `python3 -B tools/multi-scene/release_checklist.py`.
It verifies register/checklist/progress agreement and the active document links
and ownership constraints. Documentation consolidation requires only these checks;
do not rerun SDK, simulator or backend acceptance merely to reorganize prose.

New full records append to the active numbered shard. When its range is full,
freeze it and start the next range without renumbering. The frozen `Archive/`
snapshots are integrity records; do not edit their relative links.
[Archive lookup rules](Archive/README.md) explain exact historical locators.
The [EXP-178 documentation checkpoint](Experiments/DOCUMENTATION_CHECKPOINT_EXP-178.md)
preserves moved historical material; it is not another restart cursor.

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

Reject a build if the selected SDK does not support the admitted deployment target. Record the exact Xcode/SDK used; an app name is not a version check.

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
4. Run the admitted affected selection and complete probe suite at its slice
   checkpoint; use full module/compatibility suites at their required gates.
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

### Physical installed-code identity

CoreDevice appDataContainer transfer does not expose the app bundle. Standalone
LLDB device commands may leave the host platform selected; command exit0 is not
proof of attachment or file retrieval. Do not suspend an acceptance launch to
work around this: the recorded preparation emitted no native records and ended
with signal9. No SDK crash or scenario verdict follows from that preparation.

The native probe and opt-in profiling fixture accept
MULTISCENE_CODE_IDENTITY_RUN_ID and MULTISCENE_CODE_IDENTITY_REVISION. Before SDK
initialization they stream SHA-256 over every installed Mach-O file and persist
Documents/<run-id>.installed-code.json. A prior receipt or malformed identity
prevents SDK initialization. Retrieve only that receipt through the app's own
appDataContainer, then compare it with the exact independently signed local app
using tools/multi-scene/acceptance/installed_code.py. Require exact run/revision,
observed process, bundle/executable, pre-SDK boundary and complete binary map;
the Debug dylib matters as well as the executable. Preserve clean-install and
source-freeze checks. This is installation evidence, never a native/backend PASS.
The nine checker tests reject18 malformed identities/inventories.

If CoreDevice remains usable while Xcode's exact destination reports preparation
errors, a generic iOS arm64 build can prepare the same hardware executable.
Record that build destination honestly; actual install/run/OS/profile evidence
must still come from the exact freshly discovered device. No simulator result
can replace physical execution.

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

[Physical signing record](Experiments/EXP-143-199.md#exp-156--physical-ipad-automation-preflight) preserves the disconnected, unsigned-install, restricted-keychain and successful install attempts. None is RUM evidence.

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

## Acceptance discriminators

### Fresh build and critical boundaries

- Every discovered test in the admitted fixture must run. A new test reported as
  `No result`/`notRun` invalidates that build's acceptance even if older tests pass.
- Prove live-view and topology prerequisites before the critical API interval.
  Backgrounding can correctly end a view/action between suspended driver steps.
  A synchronous two-live-view batch proves only its bounded serial contract.
- Preserve exact owners, counts, names, metadata, callback barriers and completion
  order. A timeout or same-name early completion cannot satisfy the oracle.
- Decode complete JSON objects from mixed OSLog/stdout at their actual prefix;
  retain the raw stream and check sequence continuity. Do not invent missing records.
- Decode mapper attributes with `AttributeValue.dd.decode`; Objective-C
  `AnyEncodable` values can fail direct Swift casts while serialization is correct.
  A backend match cannot turn a failed local oracle into a pass.
- Use repository source/test SwiftLint configurations and explicit changed-file
  lists. Configuration-free lint is not the repository gate.
- Filter `devicectl` inventories with
  `hardwareProperties.reality == physical` before reporting hardware availability.

[Detailed action discriminators](Experiments/EXP-143-199.md#exp-159--explicit-scene-targeted-long-running-actions)
and [Resource fixture lessons](Experiments/EXP-143-199.md#exp-176--accept-explicit-resource-starts-and-captured-completion-owners)
retain failed attempts and exact identities.

### Compatibility, lifetime and restoration runners

| Procedure | Required discriminators | Detailed evidence |
| --- | --- | --- |
| [Mounted WebView](../../tools/multi-scene/webview-correlation/README.md) | Frozen isolated Core/RUM/WebView/Replay builds; clean install and repeatable browser-payload acknowledgement before native mutation. Decode deflate as zlib and gzip separately. Require legacy container preservation plus peer-negative control; keep only sanitized ownership summaries. | [EXP-165](Experiments/EXP-143-199.md#exp-165--preserve-legacy-nativewebview-replay-correlation) |
| [Core-scoped handoff](../../tools/multi-scene/handoff-isolation/README.md) | Preserve baseline fixtures/thresholds, calibrated allocations and full-context nested/throwing checks. Wait for competing workloads before Release ABBA. Keep entry-snapshot/child-refresh and foreign-context third-party-callback controls; TaskLocal isolation alone is insufficient. | [EXP-166](Experiments/EXP-143-199.md#exp-166--isolate-ui-event-handoff-by-sdk-lifecycle-and-reduce-allocations) |
| [Session restoration](../../tools/multi-scene/session-restoration/README.md) | Observe readiness after actual activation with bounded retry. Read snapshots before markers can repair missing branches; verify full new-session inventory. Refresh activity in max-duration cases so inactivity cannot substitute. Posted/controlled time is not OS/backend proof. | [EXP-167](Experiments/EXP-143-199.md#exp-167--preserve-navigation-ownership-across-session-restoration) |
| [Keyed lifetime](../../tools/multi-scene/swiftui-lifetime/README.md) | Require a mounted registration/destination, then weak registration/state/instrumentation release and original method implementations after bounded drain. Keep source alive past removal. Assert OS-specific prerequisites; controller release or RSS alone is insufficient. | [EXP-168](Experiments/EXP-143-199.md#exp-168--release-keyed-swiftui-registrations-and-instrumentation) |
| [Pending authority](../../tools/multi-scene/pending-authority/README.md) | Check real automatic eligibility before first explicit/capability input, then submit immediate marker before another render. Cover absent handler/attachment with the real registry; subscription does not confer authority. | [EXP-169](Experiments/EXP-143-199.md#exp-169--keep-automatic-tracking-until-semantic-input-is-ready) |
| [Reconnect](../../tools/multi-scene/reconnect-acceptance/README.md) | Separate inherited traits from accepted reader mounts. Enable the real authority registry with a nil-returning predicate; clear/rebind the retained callback through actual SwiftUI updates. Submit markers immediately, inspect after drain, allow only known launch fallback. No repair navigation or artificial authoritative-nil handoff. | [EXP-170](Experiments/EXP-143-199.md#exp-170--accept-semantic-reconnects-only-after-a-live-attachment) |
| Retained-reader remount | Capture the real reader callback before removal, restore it before readding the same host and submit markers inside it after SDK delivery. Require zero observers before mount and no body/source reconciliation or replacement root. Missing interception is inconclusive. | [EXP-171](Experiments/EXP-143-199.md#exp-171--restore-retained-hosts-from-the-reader-without-body-reconstruction) |
| [Scene retention](../../tools/multi-scene/scene-retention/README.md) | Freeze the baseline protocol; declare initial inventory, use20 warm-up plus100+100 unique lifetimes, count every owning collection and weak survivor separately from heap. Preserve Release ABBA samples, constructor adaptations, stale callback and initial-peer controls. Async dispatch plus a bounded semaphore proves off-main initialization; synchronous dispatch may run on the caller. | [EXP-172](Experiments/EXP-143-199.md#exp-172--retire-disconnected-scene-history-without-accepting-stale-callbacks) |
| [Accepted presentations](../../tools/multi-scene/presentation-acceptance/README.md) | Mount real sheets/covers and observe native dismissal. Submit at setter return/callback before awaiting; distinguish proposal, accepted descriptor, item ID and occurrence UUID. Observation-only hooks in isolated copies retain separate archived/compiled hashes and may not mutate state. Require pre-injection stability to distinguish rematerialization from stale callback effects. | [EXP-173](Experiments/EXP-143-199.md#exp-173--commit-accepted-presentation-state-and-fence-occurrence-callbacks) |

Each linked README owns its exact required-check inventory. Preserve every
control/candidate/invalid attempt; neither a mounted logical peer nor posted
notification closes physical H08/H09/H13.

### Observer and Resource completion controls

For observer reentrancy, whichever observer receives the outer value first must
trigger nesting. This avoids Dictionary-order dependence. Assert each observer's
generations at nested return, live membership after removal and current-only
delivery to newly added observers. Apply the same oracle to initial and ordinary
publication with actual source/adapter/host objects. A simulator/backend run adds
no evidence to this synchronous in-memory contract.
[EXP-174 record](Experiments/EXP-143-199.md#exp-174--preserve-monotonic-reentrant-observer-delivery).

For late Resource completion, keep a new-session continuous action alive. An
immediately completed action cannot reveal leaked counts. Assert old Resource/error
view/session and new action Resource/error counts, including metrics, duplicates
and clock expiration. Use a fixed reference-date origin for exact nanosecond
durations; do not widen tolerances to accept activity extension.
[EXP-175 record](Experiments/EXP-143-199.md#exp-175--keep-resource-completion-on-its-owning-scope).

### Named telemetry contracts

Select the exact named contract through the optional `scenario` argument to
`connector_driver.js`; omission retains its existing action contract. Preserve
that default and all previously admitted family contracts when extending the
runner. Expected inventories must travel in nonce-bound requests. Freeze all
fixture/runner sources before build/install.

Resource/error queries cover complete sessions, including restored view run IDs;
only specifically named action queries use phase filters. For Resources, retain
original mapper occurrence/session, request-release barriers, URL/status and peer
action counters. A response-plus-error completion must yield one error and no
success event. Expected network errors remain distinct from crash acceptance.

For serial topology, capture A before actual background retirement, navigate
foreground B and confirm renewal through mapper evidence before releasing pending
work. Do not retry starts on background A or replace OS signals with artificial
foreground notifications. [Resource record](Experiments/EXP-143-199.md#exp-176--accept-explicit-resource-starts-and-captured-completion-owners).

For current-view errors, require exact payload/owner and action counters plus
exactly-once completion after scheduled writes. Consume readiness once and keep
both views live before target calls. [Error record](Experiments/EXP-143-199.md#exp-177--target-current-view-errors-without-changing-resource-owners).

For view mutations, freeze independent A/B checkpoints around every actual Swift
and Objective-C form. Test typed values, exact key absence, global/view/event
precedence and peer isolation using independent mapper and backend projections.
The detailed experiment owns its counts and status:
[attribute contract](Experiments/EXP-143-199.md#exp-178--target-view-attributes-and-removal).

For the named attribute runner, bind each typed payload snapshot to the exact
mapper error ID before its event record. JSON decoding must reject Boolean/number
coercion. Intake projection retains exact absence and only bounded synthetic
values; normalize only the declared nested key. The reusable entry point and
negative controls are in the [acceptance README](../../tools/multi-scene/acceptance/README.md#attribute-contract-exp-178t05).

For custom timing/loading, preserve ordered mapper states before each marker and
bind them to exact view/session IDs and document versions. Backend view ingestion
can collapse revisions; compare final persisted values independently and retain
intermediate overwrite evidence locally. Do not infer intermediate backend
documents from the last version. See the
[timing contract](Experiments/EXP-143-199.md#exp-179--target-custom-timing-and-loading-time).

The named timing runner binds marker assertions to the immediately preceding
mapper snapshot sequence and exact document version. Its synthetic-key projection
and malformed-duration controls are specified in the
[timing runner procedure](../../tools/multi-scene/acceptance/README.md#timing-contract-exp-179t06).

For asynchronous feature messages, distinguish the sender's captured ownership
from the receiver's current handoff. Replay messages after leaving the origin
scope and under a peer; reject foreign or invalidated core generations. Internal
metrics may not emit a snapshot immediately, so use an independently accepted
view-update trigger before each payload marker and bind the exact prior snapshot.
The bounded flag/internal oracle is in
[EXP-180](Experiments/EXP-143-199.md#exp-180--target-feature-flags-and-preserve-internal-mutation-ownership).

For the named flag/internal runner, compare typed flag replacements at every
paired checkpoint, exact sample aggregates/FBC on the owner and internal-key
absence in custom context. Reject malformed present metrics and ambiguous nested
flag representations; retain only bounded synthetic values. See the
[flag runner procedure](../../tools/multi-scene/acceptance/README.md#flaginternal-mutation-contract-exp-180t07).

Typed mapper fixtures must encode selected Encodable values and decode their
declared Codable evidence type. AttributeValue.dd.decode only casts an underlying
value; it does not construct a custom Codable enum. Test the actual projection
with primitive and Objective-C-wrapped values before accepting populated states.

When a mapper value is absent downstream, compare exact encoded JSON before
changing SDK behavior. An independent backend field-existence query distinguishes
missing indexed data from a connector projection error. Declare any diagnostic
input-scale change before execution, retain the original failed attempt and keep
the backend equality requirement; local correctness does not close a backend gate.

FBC is a Flutter-only backend metric. In a native iOS fixture, prove its internal
call-site ownership and exact encoded value locally, and expect downstream absence.
Keep flag and build-sample backend comparisons exact. Do not scale durations or
change SDK behavior to force a Flutter-only field into native backend events.


## Captured Trace acceptance

Bind native and OTel spans to their starting independent RUM snapshot, then
finish under a different live handoff after representative churn. Creating an
OTel builder does not start a span: change the handoff before startSpan and
require the start-time owner. Repeated finish/end must emit one record.

For real URLSession tasks, require every controlled loader to arrive and zero
early completion before releasing responses in the declared order. Source-less
starts require an empty handoff and an independently observed process owner.
Record exact encoded trace/span IDs without logging unrelated tags or payloads.
Inventory all spans for the synthetic run and all views for its RUM session;
compare exact correlation, operation/resource, duration and status. Span responses
use the preflighted system Ruby YAML/JSON parser; reject object tags, aliases and
duplicate keys, and freeze its source with the runner. Aggregate
counts and sampled detail queries alone cannot close the gate. Keep physical
shared-request H07 separate. The current bounded definition is
[EXP-181](Experiments/EXP-143-199.md#exp-181--accept-captured-trace-ownership-through-cross-scene-completion).


Positive APM search and trace-detail responses have different contracts. Search
uses decimal string span IDs and hexadecimal trace IDs; convert decimal strings
with arbitrary-precision integers, never floating-point numbers. Private RUM tags
may be absent from search, so retrieve each complete root trace and join exact
trace/span/parent IDs before reading its owner metadata. Require one detail record
and matching operation/resource/service/run fields; missing metadata is inconclusive.

Compare declared normalized APM operation names and preserve grouped URL resources
separately from the exact original http.url. Indexed nanosecond duration is the
comparison source; a rounded detail duration_ms is not an exact duration oracle.
Run the projection in the actual tool orchestrator as well as Node controls:
browser globals such as URL are not available there. Preserve failed attempts
before freezing a response-format correction and starting a fresh run.


Batch independent backend detail reads and inspect every settled result before
decoding. Decode bounded YAML pages in one read-only helper; only artifact creation
and bridge-response writes need escalation. Record bridge elapsed time in the
durable summary. An otherwise correct response received after the deadline cannot
retroactively pass the run. Measure the corrected read/decode path on preserved
evidence before paying for another clean installation.


Separate backend index visibility from detail retrieval cost in timing diagnostics.
A valid zero-result read can precede span visibility. Keep aggregate polling bounded,
then validate every indexed span and its exact owner; measure the detail batch
independently so query latency cannot be confused with SDK dispatch overhead.


## Captured Logs and mirrored errors

Treat emission, asynchronous context writes and message delivery as separate
boundaries. Record the caller's handoff before logging, then test delayed writes
and mirror delivery under changed context. A mirror's scene/view/action owner must
come from its private captured envelope; remove that envelope before telemetry.
Keep explicit nil, foreign/retired handoffs and ordinary source-less fallback
distinct, including the legacy off-view case. A no-peer regression for an unknown
captured view must create a scene-owned peer: an unknown view in a legacy-only app
intentionally retains representative fallback. Verify that separately, including
captured nil action, rather than treating the compatibility path as a routing defect.

For native acceptance, compare exact encoded log correlation and mirrored RUM
owners against independent view/action mapper records. Logs have no SDK log UUID
in this payload: unique synthetic phases plus the complete run inventory identify
expected entries. Preserve optional exposed backend IDs; never fabricate absent
IDs. Aggregate the full run, read all pages, independently group every selected
semantic field and require one event per exact phase/owner. Require complete
group metadata, exact raw/group/local agreement, and verify the full RUM session. Never accept only a filtered owner
subset. The bounded contract is
[EXP-182](Experiments/EXP-143-199.md#exp-182--accept-captured-logs-and-mirrored-error-ownership).


The Logs runner adds DatadogLogs source to the frozen identity and authenticates
DDSQL count plus raw Logs reads. Count the entire unique run without owner filters;
query all RUM-session actions/errors rather than named subsets. Preserve actual
backend log record IDs when exposed and reject ambiguous attribute namespaces.
The current Logs connector omits IDs even when explicitly requested. Its absence
must not weaken duplicate detection: the full count, unique phases, grouped
multiplicity and raw/local agreement are all mandatory. Preserve an inconclusive
attempt when changing this evidence contract; acceptance requires a fresh run. When a probe
project mutation resets the active Xcode scheme, switch to the intended scheme and
confirm its discovered test inventory before running. A scheme-selection failure
does not constitute an executed test or native scenario.

## WebView container acceptance

Require actual Replay-enabled native view records before checking browser container
IDs. Observe each real WKScriptMessage on its UI-thread callback and forward it to
the original SDK handler without changing routing. Use persistent acknowledgements
keyed by exact browser UUID/run/phase; wait before navigation, detach or rebind.
Record attachment and timestamp guards before emission. Keep browser input evidence
distinct from encoded output: WebViewEventReceiver bypasses the native RUM mapper.
Use complete-session backend inventory to verify each container ID and exact
absence for an unowned detached WebView. Include a spoofed private scene input and
require its removal from output. The bounded matrix is
[EXP-183](Experiments/EXP-143-199.md#exp-183--accept-native-webview-container-ownership).

The T10 driver now accepts the named WebView scenario and requires at least184
probe tests in its fresh build. Operational controls pass160 Python/38 Node tests.
Whole-session rows must preserve exact application/session replacement, five
container UUIDs, detached absence, payload counts/version and private-key absence.
The projection accepts nested or flattened fields but rejects ambiguous duplicates
and preserves malformed types for the oracle to reject. Fresh runs freeze all
WebViewTracking and SessionReplay source along with the fixture and oracle.

Detailed RUM search puts source in attributes.source, outside attributes.custom.
Preserve that envelope field before projecting the custom payload. If both shapes
provide conflicting source values, reject them. Missing source cannot be derived
from expected phase/name/container. EXP-183 attempt A retains the original failed
projection; revised projection controls pass41 tests and require a fresh run.

## Exported and fatal process context

Keep exported Core context, scene snapshots, crash-provider state, serialized
plugin injection and later report delivery as separate observed boundaries.
For source-less crashes, require the process representative once; do not infer a
scene from the thread performing recovery. A held snapshot must retain original
IDs through later context updates.

The [EXP-184 contract](Experiments/EXP-143-199.md#exp-184--accept-exported-and-fatal-process-context)
uses clean prepare/crash, same-install recovery and a consumption-verification
launch. Give each launch a fresh run identity while preserving the exact binary
and data container. Crash only after explicit pre-crash guards and a preparation
PASS. Recovery must establish a different current context before enabling the real
reporter. Require actual didCrash acknowledgement in both later launches; a quiet
timeout cannot replace report consumption. Compare all seven views/three sessions
and the one original-owner fatal error. Synthetic receiver tests remain separate
from actual process-crash evidence.

Attribute mutation alone need not emit a view event. For the pre-crash peer-update
guard, issue a targeted non-interactive timing update and observe the next mapper
revision containing the attribute before reading export/fatal state. Do not treat
the initial cached mapper event as proof that the mutation ran.

The connector scenario fatal.process-context.prepare-crash selects all three
launches automatically. Its frozen contract requires188 probe tests and44 native
expectations (24/10/10). Run IDs are generated per launch; only the first launch
uninstalls. The runner independently matches simctl/native PIDs, checks crash
termination, and queries all three sessions for seven views and exactly one fatal
error. B's injected document version must become exactly version+1 on recovery.
The existing Internal Datadog flush runs off the main actor after recording the
real launch acknowledgement; it clears LaunchReport and must never be used as
evidence that no pending crash existed. Failed phase records are retained in the
durable run summary. Build and source identities include CrashReporting sources.

A simulator launcher's exit status is not the launched application's exit status:
simctl launch --console-pty may return0 after a fatal signal. Record it as
launcher_exit. Use a nonreturning abort trigger, independently match launcher and
native PIDs, prove process disappearance after the declared boundary, and require
the real recovered report's exact original identity and SIGABRT metadata. A missing
process alone does not distinguish ordinary exit from crash. A returned trigger
or any failed guard remains FAIL even when a crash report exists; retain that
attempt and use a fresh clean install after fixing the fixture.

Disable the probe's default lifecycle Action/Resource markers for bounded fatal
acceptance. Check the complete observed telemetry inventory after draining queues
and before preparation PASS/crash; checking it only on the next process boundary
needlessly destroys an invalid preparation. Keep the later strict inventory check.


For recovery/consumption launches, simctl may buffer its PID line until the console
closes. After the native terminal record, terminate only that fixture process,
wait for the launcher, reparse all output, and then verify independent PID agreement
and every guard before advancing. Keep late failure and foreign PID controls.

Crash recovery decodes dynamic RUM attributes into type-erased Codable values.
Extract the encoded String for the whitelisted run identity; a direct String cast
can silently produce nil. Reject non-String values and compare the original run
exactly. This projection correction does not replace report provenance checks.

Initial Home mapper events can precede the native scene-ID attribute. Keep actual
scene-ready topology, the SDK's scene-indexed view snapshot and the mapper's view
UUID/logical scene as separate evidence. Require agreement before recovery, reject
a conflicting native mapper field if present, and never manufacture a missing
mapper field from expected ownership. This is serial native-scene evidence only.

Do not assume the document counter returned by RUM search equals the SDK input
revision. For fatal acceptance, copy the mapper's observed revision into the
synthetic exp184_sdk_document_version attribute and require its exact preservation.
Keep the local injected-version+1 check and all owner-specific counts. Record the
search counter separately; never substitute it for a missing SDK witness.

### Process signal acceptance

Use the real run-loop/watchdog producers for long tasks and nonfatal hangs.
A controlled UIApplication memory-warning notification proves the monitor route,
not actual pressure. Observe the representative and absent active action before
each stimulus; require exact mapper acknowledgements and view counts before the
next boundary. Pending fatal-hang tests preserve the serialized owner and prior
consent through live-session replacement and one-time consumption. Keep
deterministic restart evidence separate from actual watchdog termination.

T12 uses process-signals.representative.cross-scene-serial in the existing
acceptance.py/connector_driver.js workflow. It requires192 probe tests and46
native expectations before full-session view/error/long-task/Action/Resource/crash
queries. process-records.json is preserved in the durable summary on rejection.
Decode nested/flattened measured fields without coercion; retain absent optional
zero counters separately from malformed present values. Use source-tree-relative
paths for lint baselines so custom rules restricted to Sources remain enabled.

For serial process-signal acceptance, a peer scene can end while the other is
active. Observe its ended view, request actual OS reactivation, and join fresh
native lifecycle, SDK snapshot and mapper ownership before the next targeted
Action. Do not reuse initial view IDs or accept readiness observed before that
activation boundary. Preserve the retired view with zero counters in the complete
four-view inventory. See the EXP-185 record for the failed original fixture.

A complete count of indexed view IDs can precede their final counter updates.
For the process fixture, query view rows after individual events and allow at most
three fresh reads with10s between reads for lower integer counters to converge.
Keep exact identity/source/run checks and reject counter regression, overshoot,
malformed types or extra rows immediately. Final values must match the mapper.
Persist backend-exchanges.json before bridge and semantic validation so rejected
responses survive in the durable summary. See EXP-185 attempt B for the witness.

For shared vitals validation, separate the legacy view aggregates from optional
session timeseries. Observe each Home long enough for real samples and stop the
session before comparing final metrics. Preserve exact view identities and field
presence; keep declared floating-point serialization tolerances explicit.
A simulator sample does not close a gate requiring representative device data.
Discover current Xcode test membership; legacy vitals test files also live under
DatadogCore/Tests and are not in the RUM scheme's test inventory.


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

## Profiling correlation validation (EXP-187/T14)

Use actual ProfileAttachments from focused RUM/Profiling tests. Join profile
rum-mobile-events.json entries and labels to RUM using the exact start Vital ID;
operationKey/view are not attachment fields. Keep name/optional-key identity
structured, require reverse completion and ongoing-operation retention across
normal flushes, and preserve server-offset nanoseconds. Profile-level RUM labels
do not establish per-scene CPU attribution.

The repeatable [profiling fixture procedure](../../tools/multi-scene/profiling-correlation/README.md)
owns the opt-in build and simulator driver. Commit relevant sources first; use a
fresh output path and run UUID. It verifies source/signature, clean-install absence,
installed executable and native process identity before accepting12 assertions.
Native clock values independently reproduce exact attachment timestamps/durations,
using Swift nearest rounding with ties away from zero, not Python truncation.
Require three fixture views plus exactly one built-in ApplicationLaunch view;
all four are distinct, inactive and in one session. Do not filter unexpected
views or widen nanosecond tolerances after a failed run.
Its durable summary remains INCONCLUSIVE for T14 even when simulator mechanics
pass. The ordinary-build mode checks the acceptance implementation and scene
manifest are absent from normal Release builds.

The first frozen native attempt showed that BenchmarkTests can build with empty
client-token/application-ID substitutions. Build and clean-install success do not
prove telemetry configuration. Require the fixture's configuration check before
SDK initialization; inspect only presence/format booleans if diagnosing the built
app, and never read the protected local xcconfig. Repair existing build-setting
wiring, freeze it and use a new full attempt; preserve the original INVALID receipt.

The acceptance override includes the tracked Benchmark Runner template, then
lets Xcode resolve the existing optional Datadog.local.xcconfig include, and maps
CLIENT_TOKEN to DATADOG_CLIENT_TOKEN. Do not include the full Example chain in
-xcconfig: Base.xcconfig globally lowers the benchmark deployment settings and
breaks existing CatalogSwiftUI iOS17 APIs. Xcode performs variable/include resolution; never expand
secret values into command arguments or artifact summaries. Validate resolved
presence/application UUID in the built plist before installation.

Operation sampling does not start a standalone profile. Use continuous sampling100%
and observe actual running context before the first Operation and in each received
step; never repair that evidence after the boundary. Keep70s of foreground time
for the normal60s timer and upload. Receipt schema2 rejects disabled or late
readiness. Preserve earlier mechanics passes with stopped profiling as incomplete
profile evidence, not SDK regressions.

The validator accepts unmodified full-session RUM search/count/exhausted-page
responses and checks all12 events. Join step/aggregate view IDs to authoritative
view events because backend summaries may use URL-derived names. Backend
millisecond Operation aggregates cannot replace exact raw attachment nanoseconds.

The restored profiling MCP supports authenticated wall-time flamegraphs.
Discover actual sample types and perform a real read; type metadata alone may
list CPU even when retrieval reports that type disabled. Native Mach profiles
serialize wall-time/nanoseconds. Scope acceptance reads to the actual run and
exact Vital IDs; existing service aggregates prove connection health only.
Use the complete service/time inventory and the exact session inventory. For the
selected continuous profile, query each native start ID independently, then its
full vital-ID set, name, view and session labels. Keep the built-in launch profile
and TTID identity separate. A nonempty flamegraph filtered by exact vital_id
proves sampled correlation; normalized wall-time values are not Operation duration.

Raw rum-mobile-events.json remains a separate exact check. If MCP has no raw
download, accept the user's actual profile export: preserve original files,
record the profile ID/provenance and SHA-256 of both attachment and pprof, and
run the committed validator against the frozen native receipt and complete RUM
responses. Never substitute native expected entries for the downloaded attachment.
Keep the validation output separate from earlier attempt summaries. An exported
attachment can close that simulator component without browser authentication;
physical evidence still requires its own fresh run. RUM has_profile flags are
reported separately from exact profile/sample/attachment joins. The combined
validator's --profile-artifacts option checks the saved inventories, eight exact
joins, final labels and three flamegraphs. It rejects mismatched run/session,
absolute query windows, profile types and sample selections; see the fixture
README for the fixed artifact roles. Its summary lists unmet components while
always retaining independent physical/source/build/install proof. Do not silently
drop a false flag or infer UI enrichment from those independent joins.

The existing BenchmarkTests Profiling runner already links the module; avoid
adding a dependency to the native multi-scene probe. Freeze native counts/build/
run identity and boundary assertions before a device run. Verify a real supported
device and separate authenticated profile access. RUM connector success does not
prove profile retrieval; use the supported browser UI if no profile tool exists,
with user sign-in, without reading credentials or session storage. Physical and
backend proof remain required even if simulator/integration tests pass.

For the existing DatadogIntegrationTests Example host, an iOS27
___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption trap occurs
before XCTest connects. A successful build plus eight tests marked not-run is
invalid validation, and the returned xcresult path may not contain a bundle.
Preserve that console/summary evidence, rediscover an available iOS26.5 destination,
and run the same integration selection there. Do not alter the protected project
or reinterpret the host trap as a Profiling result. Unit controls remain valid
on their exercised iOS27 host.

### Optional launch profile in the EXP-187 inventory

Launch sampling is0 in the frozen fixture. The simulator capture contains an
incidental launch profile; the physical capture does not. Derive that inventory
from independent RUM TTID metadata: a declared profile requires its exact distinct
ID and launch/vital/view joins; explicit has_profile=false with no profile_id
requires its absence and empty launch joins. Always require exactly one continuous
profile with both start IDs and actual samples. Preserve extra/repeated/inconsistent
inventory failures. Retain the original checker verdict and separate capture and
oracle revisions when replaying immutable evidence.

A successful native receipt is not cleanup proof. If CoreDevice returns4016 and
USB no longer enumerates the phone, retain cleanup as unverified and wait for a
fresh reconnection before inspecting/terminating only that test app.


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


If Xcode MCP reports tests as not run, read its console and xcresult before
accepting any partial count. A CoreSimulator service/framework version mismatch
invalidates that attempt even if an unrelated test is shown as passed. Pin the
intended DEVELOPER_DIR and use a fresh CLI result bundle with the exact discovered
test selection; require total=passed and no skipped/not-run tests. Do not restart
all simulators or alter the user's Xcode selection to mask that preparation error.
