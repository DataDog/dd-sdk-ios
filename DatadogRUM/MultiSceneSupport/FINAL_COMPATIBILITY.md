# Candidate compatibility matrix

Prepared procedure for F03; no final matrix execution is claimed here.
[release-gates.json](release-gates.json) owns F03's status, owner, dependencies
and closure rule. This file makes its existing checks executable and finite.
The register scopes F03 separately to S1/S2/S3. F01 approval is required only for
S3 new public scene APIs; S1/S2 keep existing API and do not wait for that package.
Each release freezes its exact candidate and affected module/platform inventory.

## Freeze and acceptance

Record the reviewed source commit, signature verification, exact production and
fixture manifests, toolchain version, package dependency revisions, deployment
minimums, configuration, architecture and freshly discovered destination for
every cell. Commit documentation/evidence separately without changing the source
identity. A compiler fix or API change requires a new candidate and revalidation
of affected cells; do not mix results from different source candidates into one
passing matrix.

The reference-branch package minimums are iOS15, tvOS15, macOS12.6, watchOS9 and visionOS1.
The S1 current-develop candidate instead declares macOS12.0 and supports seven
macOS products, including RUM and Flags. Its frozen applicability and execution
are owned by [EXP-201](Experiments/EXP-201-final-compatibility.md); preserve the
candidate manifest and Makefile rather than imposing this older reference recipe.
These are compile deployment settings, not evidence of execution on each minimum.
Per the user correction on 2026-09-18, C06 requires deployment15 compilation
and the oldest available debuggable17.x runtime sample. iOS15/16 execution is
unavailable and must be disclosed; this does not raise SDK deployment support.

All cells require a real zero exit status, readable result artifacts and the
complete selected inventory. Discover targets/tests before execution and compare
them with executed counts. Zero tests, host launch failure, a missing xcresult or
an unexpected skip is not PASS. Preserve each failed, invalid and inconclusive
attempt; attach a new attempt after a correction.

## Finite cells

The SDK implementer owns execution of all cells. RUM API reviewers own the
approved API diff; CI/toolchain and device operators supply missing environments.
S3 cells use the frozen F01 implementation. For S1/S2, F07 records each cell as
required or source-proven not applicable: M01/M04/M10 and affected-module tests
remain required; M02/M03 verify existing Swift/Objective-C APIs instead of promoting
new scene declarations; M05–M09 cover affected supported platforms/transitive
modules; M11 audits affected feature docs. No cell is omitted just because its API
is hidden. Existing experimental repair evidence is reference material, not proof
of a current-develop customer defect.

| Cell | Required environment and scope | Decisive result |
| --- | --- | --- |
| M01 / Full iOS modules | Available supported iOS simulator with a launchable test host; the ten non-Replay schemes below, complete inventories, Debug test configuration. Prefer the discovered26.5 host where27 cannot launch the legacy Example. | Every selected module test executes and passes at the candidate. Record runtime per module; an older-host result never closes legacy27/C03. |
| M02 / New iOS surface | iOS27 simulator, Debug and Release external Swift client, iOS15 deployment target with runtime guards; Swift5 and6 language modes. | Normal imports expose exactly the approved target/semantic APIs; custom conformer compiles unchanged, NOP remains safe, valid calls forward once. Compile the support guide and Publisher/Observation host call sites, including compiler>=6.4 guard. |
| M03 / Objective-C Release | iOS27 simulator, standalone Objective-C Release client using generated public headers and the approved off-main contract. | All approved selectors compile and run. Main/off-main positive and negative controls prove no SDK trap/deadlock, invalid UIKit access/retention or foreign telemetry. Debug-only exposure is insufficient. |
| M04 / iOS package | Full Datadog-Package, generic iOS destination, Debug and Release. | All selected production modules/resources emit; package minimum remains15. |
| M05 / tvOS package | Full Datadog-Package, generic tvOS destination, Debug and Release. | All selected production modules/resources emit; iOS-only APIs stay excluded and minimum remains15. |
| M06 / watchOS package | Full Datadog-Package, generic watchOS destination, Debug and Release. | All selected production modules/resources emit, including the D01 Resource path; minimum remains9. |
| M07 / visionOS package | Full Datadog-Package, generic visionOS destination, Debug and Release. | All selected production modules/resources emit and the approved iOS-only semantic surface stays excluded; minimum remains1. |
| M08 / Mac Catalyst package | Full Datadog-Package, macOS destination with Mac Catalyst variant, Debug and Release. | All selected modules emit with existing availability and package settings. |
| M09 / macOS modules | DatadogCore, DatadogLogs, DatadogTrace, DatadogCrashReporting and DatadogWebViewTracking, Debug and Release. | Complete production targets emit at minimum12.6, including D02's repaired native WebView path. Do not infer support for unlisted macOS modules. |
| M10 / Lint and API baseline | Existing repository lint/API tools with supported SDK toolchain; reviewed Swift and Objective-C baselines. | Lint succeeds, generated API changes equal the F01 approval and verification matches committed baselines. Preserve old APIs; no accidental SPI/Debug symbols appear. |
| M11 / Documentation integration | Full feature-doc workflow and existing feature-doc verification against approved source. | Tracked source coverage, every cross-feature snippet and registry agree; verification metadata refers to the audited source. F02 publishes only after its own checklist is complete. |

The repository `test-ios-all` target in [Makefile](../../Makefile) has eleven schemes.
The user-approved M01 selection excludes the Session Replay capture suite and keeps
DatadogCore, DatadogInternal, DatadogRUM, DatadogLogs, DatadogTrace,
DatadogCrashReporting, DatadogWebViewTracking, DatadogFlags, DatadogProfiling
and DatadogIntegrationTests. Reconcile these ten with the frozen Makefile.

Replay captured-content correctness is outside the release scope. Host-app crash safety and non-disruption to other SDK features remain required; no full Replay suite, content repair or inherited-fixture waiver is needed. Reuse source-matched coexistence and
other-feature evidence; admit a narrow check only for a concrete crash or disruption.
Preserve prior capture-suite failures without declaring them passed. Exclude Replay-only assertions inside the selected schemes too: slot/layout,
record-content and recording privacy/capability tests remain outside scope. Freeze
exact selector exclusions before results; these are neither passes nor OS skips.
Keep RUM/other-feature metadata and ownership coexistence tests. Each candidate
result owns its complete raw and selected inventories. This selected
matrix is not a full `make test-ios-all` result. The
[scope disposition](Results/S1-replay-scope-disposition.json) owns the amendment.

For M01, use the existing Make target with exact discovered values, for example
`make test-ios SCHEME="<listed scheme>" OS="<runtime>" DEVICE="<device>"`.
Keep Test Visibility disabled unless separately configured; credentials are not
part of result artifacts. Retain actual test/command output paths and sanitized
failure details. Selective MCP tests can diagnose failures but cannot stand in
for a required complete module inventory.

For M04–M09, the existing SPM helper defaults its configuration and temporarily
renames Datadog.xcworkspace. Run package builds in a fresh isolated extraction of
explicit committed production/private/resource/package paths, preserving the full
dependency graph and settings. Invoke equivalent xcodebuild package commands with
an explicit Debug or Release configuration there. Verify complete SwiftFileLists
and emitted modules as described in the [full-target procedure](TOOLING_RUNBOOK.md#full-target-platform-compatibility-checks).
Do not run the helper in the protected live checkout, truncate target sources,
reuse an old scratch directory, or edit build scripts.

M09 includes the Makefile's four macOS schemes plus the already repaired WebView
target. It is a regression requirement from D02, not a new public platform claim.
Include transitive Internal/private modules and original resources in every
applicable package build.

For M02/M03, create local candidate-linked clients in a new isolated fixture.
The existing remote-branch SPM smoke project requires a push; do not use that
path in this task. A successful SPI import does not prove normal public access.
Before execution, freeze the exact selector/call-site inventory and the reviewer-
approved off-main oracle. Do not remove experimental guards to make a fixture
compile before F01 approval.

## Durable result contract

Keep one sanitized matrix summary under Results with:

- Candidate and approval references, source/fixture/dependency fingerprints,
  toolchain and protected-path verification.
- For each M01–M11 cell: exact command or MCP operation, configuration, platform/
  architecture/runtime, discovered inventory, executed/passed/failed/skipped
  counts when applicable, real exit status and evidence locators/hashes.
- Every attempt and its PASS, FAIL, INVALID or INCONCLUSIVE verdict; the selected
  accepted attempt must reference unchanged candidate/fixture identities.
- API baseline diff and review disposition, lint summary, documentation checks
  and unresolved environments. Missing cells prevent F03 closure.

Only update the register and generated checklist/progress after the full F03
closure rule is met. The [restart cursor](../../.continue-here.md) exclusively
owns the current executable action.

## Boundaries that remain separate

This matrix does not replace each gate’s own evidence boundary: physical/Duo
H01–H16/F04, minimum-runtime C06, legacy-host C03, physical vitals/profiling
T13/T14 and Replay coexistence F05 retain their separately recorded status.
It does not replace F06's final independent review or the paired performance,
allocation, retained-state and reentrancy checks with unchanged
[baseline thresholds](BASELINES.md). Run performance without competing builds,
tests or profiling. Independent extraction proceeds now; S1/S2/S3 have separate
F06 freezes. Full physical-Duo F04 is S3, with optional later S2 confirmation F09.

The user supplied iOS17.5; fresh inventory confirms21F79 available and an iPad
simulator booted. Require candidate test-host execution before C06 acceptance. If a bounded genuine
attempt still cannot run17, document the approved S1/S2 runtime exception without
calling17 passed; retain deployment15 compile/link, availability audit, oldest
runnable tests and explicit unexecuted15/16/17 coverage.
