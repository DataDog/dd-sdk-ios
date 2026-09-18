# Final multi-scene compatibility matrix

Prepared procedure for F03; no final matrix execution is claimed here.
[release-gates.json](release-gates.json) owns F03's status, owner, dependencies
and closure rule. This file makes its existing checks executable and finite.
It adds no release gates. F01 approval and the reviewed implementation must be
complete before freezing the final candidate.

## Freeze and acceptance

Record the reviewed source commit, signature verification, exact production and
fixture manifests, toolchain version, package dependency revisions, deployment
minimums, configuration, architecture and freshly discovered destination for
every cell. Commit documentation/evidence separately without changing the source
identity. A compiler fix or API change requires a new candidate and revalidation
of affected cells; do not mix results from different source candidates into one
passing matrix.

The current package minimums are iOS15, tvOS15, macOS12.6, watchOS9 and visionOS1.
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
Every cell depends on the frozen F01 implementation. Closed D01/D02/D09/D11/D12
repairs remain part of the source and regression selection.

| Cell | Required environment and scope | Decisive result |
| --- | --- | --- |
| M01 / Full iOS modules | Available supported iOS simulator with a launchable test host; the 11 schemes below, complete inventories, Debug test configuration. Prefer the discovered26.5 host where27 cannot launch the legacy Example. | Every selected module test executes and passes at the candidate. Record runtime per module; an older-host result never closes legacy27/C03. |
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

The M01 schemes come from the current `test-ios-all` target in [Makefile](../../Makefile):
DatadogCore, DatadogInternal, DatadogRUM, DatadogSessionReplay, DatadogLogs,
DatadogTrace, DatadogCrashReporting, DatadogWebViewTracking, DatadogFlags,
DatadogProfiling and DatadogIntegrationTests. Reconcile this list with the frozen
Makefile before running; a repository module change is an explicit matrix amendment.

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

This matrix cannot close physical/Duo H01–H16/F04, minimum-runtime C06, unresolved
legacy-host C03, physical vitals/profiling T13/T14 or Replay coexistence F05.
It does not replace F06's final independent review or the paired performance,
allocation, retained-state and reentrancy checks with unchanged
[baseline thresholds](BASELINES.md). Run performance without competing builds,
tests or profiling. Deferred extraction remains after freeze.
