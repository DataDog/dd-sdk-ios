# Multi-scene RUM tooling runbook

Read this document before building, running, or validating the multi-scene probe.
It records the repeatable Xcode, simulator, device-interaction, and Datadog
workflows used by the project. Product behavior and support conclusions belong in
`ASSESSMENT.md`; `EXPERIMENTS.md` indexes evidence; exact new experiment and
session identifiers belong in the active numbered shard under `Experiments/`.

Last updated: 2026-09-20

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

## Execution ownership and checkpointing

One owner carries a tightly coupled experiment through fixture, runner, evaluator
and integration. Root owns EXP-198/202 integration and execution. Reuse completed
work; use one independent reviewer for consequential SDK concurrency/lifetime and
new measurement/oracle decisions. Routine host or bookkeeping fixes use a concise
changed-input record, without another serial design/admission chain. Parallel work
must be independently useful to the release and must not compete for the host.

Prove a small real end-to-end path before expanding a new harness. EXP-202 defines
its first B-automatic acceptance cell as that qualification before execution; reuse
its exact evidence within the four-cell matrix, without an identical fifth smoke. Engineering
timeboxes prompt scope decisions and do not expire unchanged reviewed artifacts.
Actual build/run/cleanup budgets remain fixed and enforced. Preserve failed runs,
update each fact at its existing owner, and batch derived documents at checkpoints.
Report required candidate gates, qualified SDK defects, blocker age and next action.

The user scope correction on2026-09-20 defers EXP-198 and any replacement mandatory
network performance campaign. The optional source/evidence archive is preserved
in [NETWORK_BENCHMARK_FOLLOWUP.md](NETWORK_BENCHMARK_FOLLOWUP.md). Continue network
correctness, Resource/Trace ownership and object lifetime. Required benchmarking
covers application-visible frame rate, hitches/hangs, CPU and memory impact of
included new semantic SwiftUI/multi-scene changes only; freeze one representative
before/after workload and criteria before collecting it. Historical numeric limits
remain unchanged in old evidence but are not current release blockers.

## Isolated URLSession backend acceptance

EXP-202 owns the ordinary E01 Resource/Trace fixture and strict oracle. Freeze
all helper/oracle hashes as well as the complete source-member dictionary and
source archive; check the exact archived file set before and after execution.
An observed helper hash alone is insufficient: require the approved manifest
fingerprint before native actions and every backend projection/assembly.

A server-generated session row is additional to the client inventory. Validate
its type, reducer marker and exact owner separately; reducer-origin views still
need every client check. Late data cannot satisfy an earlier release boundary.

Retain raw MCP payloads and exact decimal/128-bit identities. Reject explicit
truncation or truncation messages for aggregate, search and trace detail results,
even when the returned count matches. Absence of the optional trace-detail flag
remains distinguishable from a returned false. Startup and final RUM collection
retain115seconds and125second host waits; native readiness remains120seconds.
The separately defined final-span phase runs only after local assertions and allows
600seconds for polling/pages/details,610seconds at the host, under the reviewed
final-ingestion-window definition. Older300/310second failures remain invalid. Each response binds
its phase and own deadline; late raw bytes survive without successful publication.
The span lower bound is10: six client exports and four traced Resource-derived
spans. Lower-bound ingestion counts never
replace the mandatory strict missing/extra/duplicate/owner oracle. A single MCP
call can itself exceed the boundary: retain its late bytes and timing, allow native
cleanup to finish, and diagnose transport outside a live run. A later fast query
does not retroactively satisfy release readiness or justify an automatic retry.

Fetch trace details concurrently and retain all fulfilled replies in one helper
invocation. A failed sibling still leaves its successful siblings' raw evidence,
but prevents publication. Include persistence, decode, manifest verification and
assembly in the phase deadline; MCP completion alone is insufficient. A recorded
helper dispatch delay is host evidence, not SDK latency. Never extend a live run.

Backend view document versions remain positive exact integers but may differ from
local mapper versions; report both and compare every other projected terminal field.
Client spans require the current mapper run tag. RUM-derived spans may lack it only
when origin, exact Resource trace/span key, unique service, application/session/view,
URL, parent, duration, method and status all match. Require the complete derived
Resource key set; do not count an NSError row as a Resource span. The SDK network
error category is `Network`, while its source is `network`.

For registered duration checks, reconstruct native Date values from their exact
IEEE Double bit patterns. Match the SDK's subtraction/multiplication then nearest
integer rounding with ties away from zero, including phase offsets; Python int()
truncation and Python round() tie behavior differ. Keep exact equality and ±1ns
negative controls. Reject nonfinite/reversed/out-of-range fixture evidence explicitly
instead of accepting a tolerance. A corrected diagnostic cannot replace missing
backend acceptance; unchanged automatic artifacts may be reused only with their
original hashes and reviewed source-level independence.

When reusing accepted cells across a host-only correction, audit each with its own
original definition, helper manifest, oracle and amendment. Bind new definition
and progress hashes, exact ordered cell inventory and summary hashes; require the
terminal completion state before auditing. Preserve baseline observation labels.
Keep byte-verified synthetic receipts and helpers outside temporary storage, with a
compact committed report linking archive/manifest/review hashes. An evidence archive
retains historical paths; future execution still needs fresh environment discovery,
configuration and run identities. Do not present an archive as a portable CI runner.

Cleanup runs after attempted boot/install, including failures before successful
installation. Preserve command returns/exceptions and verify container/process
absence plus exact stable runtime/device binding. Retain raw inventories; only
observed usage/size telemetry may change (lastBootedAt/lastUsedAt/dataPathSize/
logPathSize and runtime lastUsage), not device type, paths, availability or state.

The user explicitly approved Datadog.local.xcconfig use for EXP-202 and other
needed work on September20. This supersedes the earlier protected-file read
prohibition and resolves the recorded automatic-review rejection. Placeholder
compilation and offline review are already complete. Apply the reviewed credential
patch and freeze the complete helper/source identity before the authorized build;
verify current Datadog query access before execution. Preserve the config and its
index entry exactly. A placeholder build must fail before any native action.
The user clarified that client tokens and RUM application IDs are shipped client
configuration: use is approved; exclude values from public commits to avoid
unwanted ingestion into internal organizations. Avoid unnecessary value logging. The
[owning result](Results/EXP-202-urlsession-backend.json) retains the authorization
and earlier rejected attempt; no repeated permission question is needed.

Preserve observed native receipt bytes before JSON parsing or terminal-failure
handling, and retain remaining current-run snapshots before uninstall. Cleanup
must still execute if capture fails; keep both the primary failure and capture
errors. Ignore other-run receipts and reject symlinks. Keep full runtime inventories
on disk and return a bounded projection with artifact path/hash/byte count; increasing
a tool output cap is not a durable transport fix. EXP-202's first native attempt
exposed both gaps and receives no acceptance credit.

In EXP-202 on actual17.5, sceneDidBecomeActive arrived with one UIWindow while
UIApplication.applicationState was still inactive. Treat the callback as a signal
to check readiness, not proof of application-wide active state. The fixture must
observe public application activation and the intended active scene before its
unchanged topology guard and SDK setup. Preserve this native observation separately
from source hypotheses or behavior claimed on other runtimes.

S1:P04 is a functional reentrancy gate, separate from numeric P01–P03. EXP-203
reuses accepted Debug controls and qualifies only three existing selectors in
Release. Require actual -O compiler jobs and ENABLE_TESTABILITY=YES; exact test
identities matter, and a Debug result is not an optimized result.

When reusing an existing test binary for a bounded diagnostic, select its host
by the actual `.app` ancestor, verify complete source/product fingerprints, and
retain the exact existing diagnostic configuration. A console test PASS cannot
replace a finalized result inventory. If Xcode exceeds the declared bound after
the test returns, retain any observed warning separately, record the reader
failure, clean up, and stop before the next arm. EXP-204 demonstrates this limit;
no automatic retry, hidden rebuild or diagnostic suppression is permitted.
A separately defined `-collect-test-diagnostics never` pair may reuse unchanged
products after source/configuration checks. Preserve console/runtime warnings and
finalized test inventories; omitted verbose archives do not clear the warnings.
EXP-204 finalizes both arms with identical displayed stacks after this correction.

For native terminal lifetime checks, first witness a live preparation/interception,
then require release after delivery and removal of test-owned handlers. Inspect
interceptions on their owning queue, invalidate/drain the session and leave the
autorelease scope before requiring weak task release. Cancellation during mutation
must preserve its error and admit no transport; feature teardown must release its
own witnesses. EXP-199 adds only the missing failure/cancellation combinations.

A test receipt must bind exact source hashes before and after its actual run.
A mixed handoff of edited validator code and an older passing receipt receives no
qualified credit. Numeric controls must independently exceed median,p95,operation
and byte limits; a joint overrun can mask a missing companion comparison. EXP-198's
initial25-control receipt and independent review preserve these discriminators.
The source-backed baseline second-resume correction adds four controls: duplicate
mutation is expected, duplicate SDK start is rejected. Reuse unchanged binaries and
qualified native prerequisites through their original plan/run identities and raw
bytes, with explicit provenance and revalidation. Never relabel a prior stopped
measurement or copy qualification summaries into a new plan.
The fourth host attempt truthfully stopped at its then-enforced preparation
deadline. Under the revised workflow, reuse byte-identical reviewed source and
controls through a concise execution record; engineering time alone does not
invalidate them. Build, runtime and cleanup deadlines still fail closed.

Process guards must recognize actual XCTest runners and known SDK fixtures. A broad
`Runner` suffix also matches macOS `BackgroundShortcutRunner`, causing a prelaunch
false positive. Retain checks for xctest/XCTRunner, `-Runner` test apps, test bundles,
known Example hosts and competing builds/profiles. A guard correction cannot
retroactively make the stopped slot valid or reset an existing matrix deadline.

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

## Bounded native XCTest result collection

[EXP-205](Results/EXP-205-view-occurrence-isolation.json) distinguishes completed
test console output from a finalized, readable xcresult. Xcode's failure collector
can start `simctl diagnose --timeout=600` after the host exits; a whole-run cap of
600 seconds then expires before result finalization. A passive owned-process
sample can identify this wait without changing the run.

For a separately admitted expected-failure comparison, the documented
`-collect-test-diagnostics never` option may be applied symmetrically to both arms.
It omits verbose diagnostics, including sysdiagnoses and log archives; preserve
sanitizer configuration, assertions, console/runtime warnings, exact result
inventories and original deadlines. Record the omitted archives as a limitation.
Do not accept console-only results, silently extend deadlines or discard prior
attempts. A diagnostic child may have its own process group: verify its exact
identity and experiment output path before cleanup, then prove it has exited.

Read actual helper declarations before adapting tests. `takeSingle()` in
`RUMSessionMatcher.swift` is constrained to session arrays; event arrays use an
explicit exact-count assertion plus `try XCTUnwrap(array.first)`. Keep full and
delta event tests aligned, and identify owners by actual view UUIDs.

EXP-207 adds reusable fixture checks. Verify mock factories and access levels against
actual declarations; use the repository test lint configuration. Complete asynchronous
feature-context reads before asserting readiness or advancing a fake clock. The core
interceptor returns cumulative event inventories: separate incidental launch records
from the exact workload, assert each phase's count, and use raw JSON matching for
intentionally sparse browser payloads. Do not decode them as complete native models.

XCTest summary failures may contain one entry per failing test. Count assertion
messages and verify their source locations in the detailed test tree and console.
Normalize `/var` and `/private/var` paths when checking build bindings, while retaining
original paths and content hashes. A reader correction does not authorize rerunning
accepted tests or weakening their assertions.

Gate execution on a successfully written and verified freeze, rather than merely
a source-review message. Run dependent preparation and execution commands with
checked exits; preserve a preflight stop even when no build process was created.
For Trace compatibility, preserve the returned-context assertion as well as header
bytes: adding only baggage cannot establish ownership of the injected trace carrier.

Before freezing native request fixtures, assert the complete serialized span
inventory before checking operation names. Require distinct live view/action owners
before starting held requests. Protocol release markers are not URLSession completion
receipts: capture the real callback body/status/error and exact callback count. Fence
cleanup against late protocol starts and release pending protocol ownership.

For request-time Trace ownership, enable Trace URLSession tracking while leaving
RUM resource auto-tracking disabled. RUM-origin requests suppress the local Trace
span and cannot exercise its completion writer. Inspect actual outgoing headers
and serialized span ownership separately. Distinguish a present nil RUM value,
an unavailable NetworkContext and a completion with no captured entry; none is
permission to change sampling. [EXP-208](Results/EXP-208-trace-ownership.json)
records the bounded control inventory.

## Independent S1 delivery packets

The [delivery queue](Results/S1-delivery-queue.json) owns per-PR state, while the
register retains candidate qualification. At a safe checkpoint, create separate
delivery checkouts from freshly verified develop or the established H00 stack.
Copy only the recorded immutable paths and verify the complete resulting Git tree
against the qualified source. This permits metadata/signature reconstitution without
rerunning accepted tests. [H00/E01](Results/S1-H00-E01-packets.json) demonstrates that
check and excludes the equivalent hitch commit from E01's review delta.

Preserve leading whitespace when parsing `git status --porcelain`; trimming it
changes status/path columns. The first packet preflight stopped before creating a
worktree when this check rejected the unchanged E03 reproducer paths. The corrected
parser and invalid preparation record remain in the packet artifact directory.

For publication, require direct task authorization and verify every outgoing
commit signature, exact head/base, complete diff allowlist and concise body.
Check the live develop commit and duplicate branches/PRs first. Publish exact
allowed refs without force or incidental tags, then read back each draft's head,
base, commit list, paths and body. Preserve the local qualification identity if
upstream has advanced; source conflicts require a separate reconciliation and
invalidated-check inventory. The [seven-draft receipt](Results/S1-publication.json)
records this check; E03's newer Resource-cache conflict is still open.

Keep real-ticket metadata, full repository iOS/CI coverage, human review, publication
and verified merge separate. Affected-suite F03 evidence is not a `make test-ios-all`
result. Use one explicit missing/invalidated-check inventory per candidate, and carry
forward original skips, warnings and source limits. No packet authorizes a push.

The [independent packets](Results/S1-independent-packets.json) preserve source/test
identity while adding their own changelog/docs and signed history. Reconstructed
feature-document verification SHAs must resolve in the final outgoing ancestry;
refresh metadata after ticketed rewrites rather than carrying an unreachable
source pointer. Require both xcresult summary and test-tree reader commands to
succeed, persist their receipts immediately, and reject missing/failed readers
even if SQLite is parseable. DL01's pre-run review caught and closed that gap with
six negative controls before execution. Keep machine-readable Xcode discovery
stdout separate from stderr diagnostics; its initial mixed-stream attempt stopped
before any platform build and remains preserved. E02's later guard rejects an incomplete individual architecture even if the union is complete, and rejects extra or symlinked exported sources. Its two positive/eight negative controls precede the twelve passing cells. Keep build-host exclusivity and process cleanup distinct from native runtime coverage. DL01's corrected twelve build cells now pass; compilation is distinct from native platform runtime. Persist source lists, emitted modules and product hashes at completion. An implicit package build can select an exported native workspace instead; freeze the explicit package-only archive paths and verify all affected source bytes. Preserve a wrong-container discovery stop before any build.

For a complete suite with no prior exact executable inventory, separate discovery
from assertion execution. Verify the full enabled target, inspect parameter inputs
and OS skip branches, then freeze identifiers and per-case run counts before the
test result exists. Static Swift/Objective-C method counts are not executable
counts. When a test target includes Clang sources, match its project build-phase membership against target-scoped CompileC records and require every emitted object before assertion admission; a Swift-only inventory is incomplete for mixed targets. Retain default single execution: Xcode rejects `-test-iterations 1`. A
runner-option correction gets a fresh attempt and keeps its original deadline.

Package pins and checkout revisions do not bind extracted SPM binary artifacts.
Freeze the checksum-verified archive and every extracted file/symlink; require the
exact tree before Xcode, after each phase and after cleanup. Permit only the
archive's legitimate relative symlinks, and reject missing metadata, binaries,
modules/signatures, extra or changed files, substitutions and escaping targets.
E01's preserved WebView build failure executed zero tests because the shared test
artifact lost its regular files. Recovery used the existing exact 2.7.8 archive in
an isolated cache; ten negative controls exercise the real guard before a launch
sentinel. Keep the original deadline and failed result, and do not repeat accepted
suites. A passing Git/pin check alone must never qualify this prerequisite.

Resolve compiled test membership from the project build phase, including shared
files outside the module's Tests directory. Inspect Swift Testing argument arrays
and availability attributes as well as XCTSkip calls. An iOS-inapplicable,
source-declared watchOS case may receive a separately reviewed applicability
record after an omitted skip policy is detected; preserve the original rejection
and admission. Name every covered iOS assertion and excluded platform case. Never
convert an assertion failure into an allowed skip or claim the excluded platform.

Derive hosted-app cleanup from the target's TEST_HOST and resolved bundle identity,
not a stage label or module name. Replay and Integration use the Example host;
Logs, Trace, CrashReporting, Internal, WebViewTracking, Flags and Profiling targets
in this source do not. Require uninstall/absence before a hosted phase and
terminate/uninstall/absence afterward. Preserve any earlier hostless misclassification
as a cleanup limitation. Freeze the exact host policy with project/source identity.

Check the host lifecycle against both build SDK and runtime before selecting a
simulator. An unchanged legacy Example host built with SDK27 cannot supply a27
Replay/Integration control; the OS requires scene adoption. A matching Makefile
device name alone is insufficient. The iPhone26.5 replacement in EXP214 retains
unchanged source and its original deadline. Xcode may print TEST SUCCEEDED and
exit0 for enumeration that contains a host-launch error: require nonempty exact
inventory and reject the JSON errors field before admitting assertions.

For E03, the [approved completion decision](E03_RESOURCE_COMPLETION_DECISION.md)
defines failed required-body transfers as Error1/Resource0, retaining received
status. Freeze callback and serialized-event controls before implementation.
Preserve all original EXP206 bodies, including its historical manual ninth
sequence and both100ms expiry controls. An automatic-only filter cannot claim
the unannotated foreign-owner regressions fixed. No empty-byte heuristic,
synthetic-only native claim or undocumented manual contract amendment is allowed.

Before holding an HTTP body, prove Foundation has actually delivered response and
initial data while completion is still absent. EXP214's SDK-off controls required
nosniff and one initial byte for that fixture. A zero-byte failure instead fences
server header write and verifies response plus error at EOF. Record bytes before
and after release; mutate state before fulfilling readiness. Confine test/server/
delegate state to a verified queue. Preserve invalid aggregate runs and reuse only
individually audited cases whose exercised behavior is unchanged. Account for the
specific sampled SDK debug telemetry separately from public event counts; reject
unexpected telemetry rather than accepting arbitrary extra event families.

An inherited telemetry exception requires baseline/current source attribution,
independent review, exact case/message/status/identity and bounded multiplicity.
Keep the rejected audit and raw records, write a separately named classified
audit, and test wrong-case/message/identity/duplicate mutations. Do not suppress
SDK telemetry or infer complete session-metadata correctness. EXP214 applies this
to an existing stopped-session precondition diagnostic without rerunning XCTest.
Inspect the actual expiration calculation before treating a private timestamp
write as an action-duration defect. In EXP214, deadlines use actionStartTime;
lastActivityTime has no reader and metrics do not change counters. Reuse the
qualified expiry control instead of adding an unsupported repair or run.

## Session Replay acceptance scope

The user's2026-09-21 clarification excludes testing and repairing captured content.
Do not run the full Replay capture suite, continue private scroll-pocket/topology
diagnostics, or require a content-fixture repair/waiver before release. Preserve
prior FAIL/INVALID artifacts without relabeling them PASS. Only SDK-caused host-app
crashes and disruption to other SDK features justify a narrowly scoped check.
Reuse exact-source coexistence and affected-feature evidence. The
[scope disposition](Results/S1-replay-scope-disposition.json) records applicability;
[the compatibility matrix](FINAL_COMPATIBILITY.md) selects ten non-Replay schemes.
Do not call that selection a full `make test-ios-all` result.

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

## Reuse evidence across release stages

An unchanged candidate may reuse an accepted finite invariant after an exact source
and dependency audit, as in [EXP-209](Results/EXP-209-s2-source-audit.json). Enumerate
the full tracked delta and every source blob; distinguish SDK module files from
auxiliary test/tool sources. A symbol search alone does not establish exclusion.
Keep each original runtime, build, oracle, diagnostic and cleanup identity. If a
later head adds tests only, describe the earlier complete matrix plus the separately
qualified tests as composed evidence, never a new full rerun. Reuse must match the
whole gate: task lifetime cannot stand in for view/cache lifetime, and a completed
backend workflow is not automatically a portable CI or Duo acceptance runner.

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
Bound signing attempts using a dedicated process group. On timeout, stop only
that attempt and its signing children before the authorized unsigned fallback.
A lock left by an interrupted attempt may be removed only after checking its
identity, absence of owning processes/handles, unchanged HEAD and protected state;
never remove an unrelated active lock.
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
responses. Share the exact MCP visualizationLink, including its organization-switch
redirect; do not reconstruct a shorter profiling URL that can select another
organization. If the user cannot find the profile, recheck the exact ID inventory
and flamegraph before asking for another capture. Never substitute native expected
entries for the downloaded attachment.
Keep the validation output separate from earlier attempt summaries. An exported
attachment can close that simulator component without browser authentication;
physical evidence still requires its own fresh run. RUM has_profile flags are
reported separately from exact profile/sample/attachment joins. The combined
validator's --profile-artifacts option checks the saved inventories, eight exact
joins, final labels and three flamegraphs. It rejects mismatched run/session,
absolute query windows, profile types and sample selections; see the fixture
README for the fixed artifact roles. Its summary lists unmet components while
always retaining independent physical/source/build/install proof. Do not silently
drop a false flag or infer UI enrichment from those independent joins. For a
physical export, assemble the final gate verdict only after matching the separate
physical source/build/installed-code and cleanup records; retain the pure validator's
independent-proof requirement unchanged. [The accepted physical export](Results/EXP-187-physical-export.json)
records that composition without repeating the native run.

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


After reconnecting, distinguish the earlier fixture process from a new run:
resolve its installed bundle URL and compare fresh process inventory. A matching
PID must also equal the recorded run PID; if it differs, verify the new process
identity before termination. After termination, require a fresh inventory with
no process at that exact bundle path. Record absence even when no termination is
needed. Add a separately timestamped cleanup proof and artifact hashes to the
durable result; preserve the original failed attempt and raw capture summary.
If transport drops after successful native/backend checks, preserve those
components and request cleanup only; never repeat a passing capture merely
to stop its process. A raw RUM exhausted page can contain empty JSON_DATA rather
than literal []; keep its count/provenance and require no additional rows.


## Legacy runtime readiness after a platform trap

For C03, test a newly available runtime with the frozen original control before
rebuilding the complete paired matrix. Verify source/fixture/binary identity and
an absent scene manifest, then use a fresh run, clean installation and installed
hash. A platform-startup failure requires a new bundle/PID/time/UUID-matched crash;
never attach a historical report merely because its symbol matches. Stop the
bounded readiness slice if the control cannot reach the decisive fixture result.
A passing readiness check alone does not close C03. Preserve the original matrix,
thresholds and actual OS lifecycle oracle; [EXP-188](Experiments/EXP-143-199.md#exp-188--check-legacy-lifecycle-readiness-on-ios-272)
owns the conditional full-matrix admission and cleanup requirements.

Apple crash capture timestamps may contain a space before a numeric timezone,
for example `2026-09-18 21:59:01.7739 +0200`. Accept that observed syntax with
`datetime.strptime(value, "%Y-%m-%d %H:%M:%S.%f %z")` after the ISO parser, while
requiring an aware timestamp and the exact original launch interval. Keep the
failed collector summary unchanged; record any recovered analysis separately
with source-report hashes and unchanged bundle/PID/UUID checks. EXP-188 recovered
its saved report this way without rerunning the app.

For legacy hosts, record **build SDK and runtime separately**. [Apple requires
scene adoption](https://developer.apple.com/documentation/uikit/transitioning-to-the-uikit-scene-based-life-cycle)
for apps built with SDK27 on27. A newer runtime alone does not make that host a
valid legacy control. Use a genuine installed earlier SDK for the existing-app
contract, recording compiler/build/SDK/minimum-deployment identity. Never patch
Mach-O SDK versions or suppress the platform check. EXP-189 preserves the original
semantic assertions and runs only C03's finite compatibility cells.

The C03 command is `python3 -B tools/multi-scene/baselines/legacy_compatibility.py`.
It refuses uncommitted runner/fixture/definition inputs or another active build,
creates fresh archives and outputs, and builds only the baseline until readiness
passes. Navigation/mapper code is unchanged; the C03-only projection omits unused internal
performance code in both arms. Added lifecycle receipts are
observations of actual notifications. Ready ownership is checked before the
background command, background is observed before foreground, and both receipts
are retained. Fourteen oracle-control methods pass before native execution.
Actual compiler output owns toolchain identity when app plist metadata differs.

An unrelated historical performance fixture can stop a compatibility-only build
after the SDK compiles if internal API shapes have changed. Preserve that failed
attempt. Exclude only the unused workload in both arms before comparing the new
source identities; do not patch the current SDK to satisfy an out-of-scope fixture.
EXP-189 records this preparation failure and the justified common-fixture rebuild.

For minimum-runtime preflight, distinguish deployment targets from device and
simulator support. [Apple's table](https://developer.apple.com/xcode/system-requirements)
lists15 support for26.6 and17+ for27. Verify actual toolchain/host, request only the
required15.0 runtime into fresh output and retain catalog/download/import/boot
outcomes. Do not substitute a later runtime or alter its metadata. EXP-190 requires
a separate frozen native matrix after qualification; neither catalog availability
nor boot closes C06.

EXP-190's official exact15.0 requests return70 for both universal and arm64, with
no file exported. A support-table entry does not establish present catalog access.
Record that specific limit without claiming permanent runtime incompatibility.
Use older Xcode's xcdevice inventory as well as CoreDevice for older iOS devices;
exclude virtual CoreDevice entries by their reality field. Resume only when the
required runtime/device/host or catalog availability changes.

## Xcode 27.1-only Duo and runnable minimum

The user's Duo27.1 simulator is available only through Xcode27.1. Verify
xcode-select -p and xcodebuild -version, then pin DEVELOPER_DIR explicitly for
all build, simctl and device operations. Current discovery verified
/Applications/Xcode_27.1.app/Contents/Developer, Xcode27.1/27A9269 and
runtime27.1/24A94401. Rediscover IDs each execution. Existing MCP bridges/services
can remain bound to27.0 after the default changes; their run-destination SDK is
an independent check. Do not launch Duo through an old bridge.

Preserve the simulator's prior boot state and isolate only the probe bundle.
Duo device identity alone does not establish simultaneous windows: require actual
native activation, geometry and visible evidence through the critical boundary.
[EXP-191](Results/EXP-191-duo-same-key.json) owns the first bounded qualification.

Current debugging starts at17 per the user correction. Keep SDK deployment15
and existing compile evidence. Qualify the oldest available17.x environment for
C06's finite matrix, record its exact patch and disclose unavailable15/16 runtime
coverage. EXP-190's failed15.0 requests remain historical; do not repeat them or
present compilation/17 execution as an iOS15 runtime pass.

At a restart between build and launch, retain the source manifest, test summary
and every built Mach-O hash. Rediscover current tooling/device IDs, revalidate the
retained build against those artifacts, and use a fresh native run/output identity.
Do not repeat passing tests solely to reconnect MCP. EXP-191 display preflight
found the second Duo display inactive; device type alone cannot replace verifying
the open-display arrangement and simultaneous native scene topology.

Fresh post-restart MCP now reports SDK27.1 and eligible Duo destinations, matching
CLI27.1. Check that agreement on each new connection. Use Device Hub's observed
pose controls for opening/closing/folding; neither device type nor a click alone
proves the display transition. Capture devicectl display readback and app geometry.
Apple restricts new Duo windows to the inner display; qualify it before an
overlap scenario. EXP-192's finite routing preserves each original native and
backend discriminator and records unexpressible simulator boundaries explicitly.

For timed Duo input qualification, the isolated RUMNativeMultiSceneProbeDuoUI
scheme preserves screenshot and accessibility attachments. UI-test apps can
enable DD_PROBE_CAPTURE_JSONL=1; the probe then writes
Library/Application Support/ProbeAcceptance/probe.jsonl in its own container,
reset once at process launch. Export it before uninstall and verify the manifest,
fresh run ID and contiguous sequence. This fixture file contains the same JSONL
as stdout; its existence is not an acceptance verdict. A tool reporting a tap,
drag or scene-close request is insufficient without the expected native effect.

When the Duo UI collector does not finalize, preserve native JSONL and the
bounded testmanagerd/runner unified log before cleanup. Record actual synthesized
touch coordinates against display orientation; a requested orientation is not
readback. The UI calibration also writes checkpoints, PNGs and app hierarchy to
its runner container's Documents/DuoInput. Export them before uninstall, bind them
to the fresh run ID, and never treat partial xcresult output as a pass. Limit an
equivalent failing input path to two attempts and continue independent checks.

On the tested Duo27.1 runtime, appResize is supported: error24004 from an initial
info request means no active session, not unsupported capability. Hold start
until the sweep finishes; record requested display size separately from native
window bounds (900×700 display yielded900×675 app). End only the owned session.
Use devicectl's explicitly selected active-display unique ID for screenshots:
XCUIScreen.main produced black outer-display images while the inner display was
active. Neither AX tree presence nor a returned drag establishes visible pairing.

Before adaptive ownership acceptance, verify the native selection binding
publishes accepted state before immediate work and recorded path changes. Geometry
callbacks can update a stale registry later and must not repair a missed boundary
retroactively. The original EXP-192 failure is retained before EXP-193 correction.

EXP-193 uses adaptive_split_contract.py with a fixed14-phase sequence. Record
the request sequence before each pose/resize, wait for matching fresh native
geometry, then deliver the visible marker. Preserve the geometry receipt and
post-resource sequence in phases.json; stale or post-marker geometry is rejected.
The selected-state model commit must precede immediate work. Acceptance joins
all50 work event IDs to exact backend owners plus the complete view inventory.

Explicit lifecycle markers are custom actions. An automatic tap can inherit
marker attributes when the custom action flushes it; names/phases alone do not
identify the declared work. Join action.type=custom and exact event IDs. Preserve
automatic actions separately. A phase cannot begin unless the prior resource and
end receipt were verified; run dependent shell steps with fail-fast semantics.

For the measured Duo27.1 resize limitation, use separate fresh pose and resize
runs. The resize fixture observes native geometry and checks the current UIWindow
presentation and scene route before recording a guard and emitting work. Join
each guard to its earlier geometry receipt and exact custom Action/Resource.
Do not require uninterrupted ownership across ending appResize: the measured
cleanup path backgrounds the scene. Export before that boundary. A black
Resizable capture prevents visible-layout claims even when geometry is valid.

EXP-190’s corrected17.x qualification records all five stable historical Apple
catalog versions as unavailable through27.1 downloadPlatform;26.6 also rejects
17.0. Direct catalog presence/HTML response is not a usable runtime. Do not
repeat unchanged requests or patch metadata. Resume from accessible official
content or an eligible test host/device.

If the Mac locks before a delivered native control, preserve the incomplete run
and request unlock asynchronously. Export and clean the owned app before its
run/session becomes stale. Preserve the frozen build and passing tests; recheck
source/installed identity and use a new run ID after unlock.

Adaptive materialization is an observation, not a route commit. The generic probe
recordDestination helper writes `[screen]`; using it for an accepted empty split
route corrupts the topology evidence. Keep the route owned by accepted state and
record materialization without changing it. Select geometry receipts only from
scene-ready/lifecycle/geometry signals: a later assertion that copies geometry is
not the receipt acknowledged by the live resize guard.

After simulator reboot, get_app_container can return a stale registration whose
bundle/data paths no longer exist. Preserve exit code and path-existence evidence,
uninstall only the known task probe, and require failed app/data lookup before
fresh installation. Installed-code hashing remains required after install.

For F05 Replay coexistence, reuse existing probe dependency/configuration rather
than adding a feature dependency. The live `hasReplay` context is only an enablement
precondition. Require increasing native Replay records before scene expansion and
after navigation/teardown, observed native scene identities/activation states,
exact RUM owner inventory and verified no-crash completion/cleanup. WebView bridge
records alone do not prove the native recorder ran. Keep scene-correct Replay
outside the approved scope and report serial simulator topology explicitly; final
F05 acceptance still requires the stated physical multi-window environment.

The guarded XCTest resize prefix can run while desktop interaction is unavailable.
Its fresh runner Documents/DuoInput/active-run.json identifies a UUID-specific
control directory. Admit marker1 only after initial geometry, Detail selection
only after marker1's complete pair, and marker2 only after accepted selection.
Keep XCTest alive until exact native/backend acceptance is exported; then release
finish and end only the owned resize process. Source/build/app/runner identities
and cleanup must agree. This path qualifies native buttons, not inner-display
system pairing or physical gestures.

Datadog detailed results expose probe attributes under context.probe. Project them
to the oracle's flat probe.* keys without supplying missing values. A count0 query
can contain an empty JSON_DATA body; preserve its zero count as an empty inventory.
Never relax exact event IDs, full view inventory or error checks to repair a parser.


For native edge gestures, admit input only after actual compact geometry and the
expected active RUM destination, not merely application launch. A compact split
can hide Primary before viewDidAppear; native-only fixture installation may use
the attached split container, while leaving other scenarios' readiness unchanged.
Observe the actual interactive transition coordinator. Delivered short/long drags
with no began/resolved callbacks are inconclusive, even when XCTest passes.
After the two equivalent Q5 failures, stop retries and preserve the unexecuted
SwiftUI/presentation prerequisite. Export native and runner artifacts before
removing both apps and verifying app/data absence.


EXP-194 uses the existing acceptance runner's finite Replay scenario. Baseline and
growth observations carry actual core counters, exact representative/scene RUM
identity and live native scene geometry. Run before opening B, after B creation and
navigation, and after acknowledged OS disconnect plus A navigation. The native
UIView stimulus creates recorder input under default privacy; do not inject
records or use a browser bridge. The serial oracle requires complete six-view inventory,
zero errors/crashes and clean removal. Physical F05 remains a separate requirement.


Scene-ready means attached, not necessarily foreground-active. EXP-194 waits for
the actual UIWindowScene activation before its counter baseline; a sleep or later
record cannot repair early admission. Disable the probe's generic lifecycle
markers for this finite recorder-only workload so undeclared Action/Resource
noise remains a failing discriminator.


For this serial Replay workload, A backgrounds while B is foreground. A's fresh
Home on reactivation is required only with observed background, old Home stop and
the actual activation boundary before Detail. Unexplained duplicates still fail.
Keep the app alive through backend verification; immediate failure cleanup can
remove buffered events before upload. Native-only proof must remain partial.

Replay acceptance can reuse a prior successful native build with --reuse-frozen-build.
It compares every native source/build input, toolchain and complete Mach-O inventory,
then re-reads the existing XCTest result. Oracle-only changes retain separate source
provenance. Fresh installation/run identity and all native/backend checks still run.


EXP-194 now accepts the serial iPad27.0 slice with four native recording boundaries,
complete six-view backend identity, zero stray work/errors/crashes and full cleanup.
Reuse those results within their source/oracle boundary. Physical F05 still needs
an actual multi-window device; ordinary single-window hardware and Duo simulator
geometry cannot substitute for it.

For the current MCP pose probe, session creation succeeds but the returned
workflow requires a device-interaction skill absent from the available/local
catalogs; Xcode resource/template discovery returns Unexpected response type.
End the owned session without sending unsupported interactions, restore the
prior simulator state and retain the pending desktop-unlock dependency. This is
a bounded workflow limitation, not a platform capability result. Retry only when
desktop access or the supported interaction workflow changes.

EXP-193 pose input uses testAdaptivePoseSequence with a fresh runner UUID and
unique run-bound marker/selection command files. Admit every marker after native
geometry, accepted route and completed materialization evidence. A sidebar
overlay can leave detail text discoverable while Clear selection is not hittable;
dismiss the observed overlay through native input and require the button hittable.
Do not treat element existence as input readiness. Preserve the original failed
run, then rebuild the changed UI fixture and use a fresh run. Keep the app alive
through exact42-work/seven-view backend verification before releasing finish.
Direct active-display captures remain necessary when Device Hub shows black.

When the desktop locks, preserve and clean any partial UI run, keep a single
pending unlock request and immediately continue work that needs no desktop.
Review F02 ownership guidance against source/evidence or prepare F03 inventories
within their existing scope. F01 still gates API promotion, publishing and the
final candidate; do not infer approval or repeat accepted tests to fill the wait.

## Automatic-only compatibility comparisons

EXP-195 keeps UIKit views/actions and SwiftUI views/actions separate. Default
public predicates and unchanged app sources are the subject; semantic hosts,
manual RUM calls and custom marker actions cannot substitute for automatic
coverage. Qualify actual native input and geometry independently of RUM output.
Use genuine old/new build SDKs, record installed binary identities and retain
existing limitations when comparing names, counts, occurrences and owners.
A Duo27.1 versus regular27.0 delta retains an OS-patch confound; same-device
old/new build pairs isolate rebuild changes. No mapper-only result is a backend
claim. The fixed matrix and failure classifications live in the owning result.

The EXP-195 calibration exposed two important discriminators: terminate-only
collection may lose an otherwise pending final automatic action, so end with
a qualified real background boundary; a SwiftUI switch element can be found
and tapped without changing value, so require both its native callback and
value change. Preserve either failure as collector/input evidence, not SDK loss.


For UIKit, do not reuse the SwiftUI trailing-label switch coordinate: the native
stretched switch's clickable content differs. Follow a compact split's actual
initial column and native Back control before assuming its sidebar is visible.
A repeated scroll must still move content; reverse the direction when Row0 is
already offscreen. These are collector changes, not app layout fixes.

`automatic-coverage/pose.py before --attempt PATH --pose open|close|reopen`
freezes the waiting run's geometry/display precondition. After real Device Hub
input, `ack` requires changed native geometry, unchanged scene identity and a
fresh active-display readback before writing a single-use run-bound receipt.
The offline oracle checks those same records. A click, stale geometry, late
assertion or inactive display cannot qualify a fold. Preserve each collector
revision in a separate attempt. Prior qualified cells may be compared only when
app fixture and all archived SDK source fingerprints match; keep their original
build/installed identities and disclose the collector-only change.


The first automatic-only Duo XCTest Home attempt loses app/runner finalization
and emits no native background receipt. Preserve its XPC log and incomplete
result; successful preceding folds do not qualify the full cell. The Duo collector
now waits for actual Device Hub Home, then `pose.py home-ack` admits only the
fresh native background event before completing.49 oracle controls cover both
fold geometry/display and external Home chronology.

For this user-authorized UI session, `caffeinate -d -i -u -t 3600` keeps display
and system awake with a bounded user-active assertion. Verify the owned PID in
`pmset -g assertions`, record its deadline and terminate only that process at
completion. It does not change persistent lock settings or replace manual unlock.
Independent regular/Duo runs require separate manifests to avoid update races;
all comparisons retain per-run source and installed identities. Freeze/check the
archived source and runner binary, rather than requiring the working tree to stay
at an older collector version while another slice is prepared.

An old-built app and its XCTest collector have separate identities. When the old
runner cannot address a new display, use a frozen modern collector and rewrite
only UITargetAppPath/DependentProductPaths to the genuine old applications.
Verify both installed apps again after XCTest, plus the chosen runner inventory.
Never relabel a modern-built app as the old build. A duplicate-size native window
is not evidence of a spatial resize; preserve that distinction when evaluating
compatibility viewports. An external boundary timeout is input failure, never a
coverage verdict; preserve it and retry only that unaccepted cell with a fresh ID.

The one-window manifest-true follow-up has exactly eight SDK27 Duo cells. Prepare
copies with `automatic-coverage/manifest_variant.py`; preserve all Swift/Mach-O
content and change only the independently verified plist flag. Native runtime
multi-scene capability and the manifest declaration are separate observations.
The oracle requires one actual scene and rejects mixed-flag comparison histories.
`automatic-coverage/report.py` produces durable inventories, pose receipts,
source/build/installed metadata, hashes, differences and failed-input records.
The old375x667 compact viewport can qualify a real display transition only with
fresh native inventory and display evidence; label it unchanged compatibility
geometry, never resized. Modern duplicate windows alone are rejected.

Duo's compact UISplitViewController can expose BackButton in a floating toolbar.
The collector may follow that observed unique native identifier when the normal
nav-bar Back is absent, and must still prove the sidebar became visible. Rebuild
only isolated UI collectors via `automatic-coverage/collector_variant.py`; retain
all original application code/build identities. A test-manager delivery delay that
eventually produces the exact native callback is retained as operational evidence,
not silently dropped or reused as a performance result. Compare fold/background
view occurrence timing against independent native callbacks before classification.

For a bounded replay, keep a separate manifest/result with the same frozen app and
collector identities and reverse source order where useful. Preserve originals.
Compare same-source variability, exact foreground occurrence/action ownership and
native callback sequences before attributing generic hosting churn to an SDK change.
A sample requested during a delay may arrive near recovery: retain its actual
timestamp against the native callback. Idle app stacks and XCTest snapshot work
do not by themselves prove the cause or qualify a performance budget.


A modern XCTest runner can disappear after a real Duo display switch while the
unchanged old-built app remains alive and responsive to a separately verified tap.
That diagnostic does not qualify a full cell. EXP-195's bounded external collector
also fails its initial switch effect despite successful button input. Stop equivalent
retries at the declared limit; preserve partial native input, screenshot, source/app
identity and cleanup. Keep an unqualified collector prototype as an experiment
artifact instead of adding it to the supported acceptance path. A successful input
in one control never establishes that the remaining controls or scrolls are usable.

### Current-source automatic comparison (EXP-210)

Custom automatic-coverage runs require an explicit pre-edit definition with full
baseline/candidate revisions, frozen helpers and fixture sources, and one finite
cell inventory. A restored historical experiment label, added SDK source file,
changed definition, repeated cell or blocked old-build Duo input is rejected
before device mutation. SDK source exclusion does not establish automatic coverage.

The first current-develop regular UIKit switch failure retains synthesized event,
native JSONL, installed identities and video. The AX element spans372points, but
XCTest selected a point inside the visible switch; do not infer a center miss from
AX bounds alone. Check exported video duration against the event time: this capture
does not cover the later failed switch interval. A successful preceding button
and absent switch callback do not establish an SDK regression. Define any new input
diagnostic before execution, preserve the failed cell and keep diagnostic/native
input success distinct from semantic acceptance.
A passing SDK-disabled control alone is not SDK-causality proof: EXP-210
later also passes with SDK/actions enabled. When the planned red arm passes, stop
the differential pair before its disabled arm, retain mixed outcomes and move to
independent work. A matching source inventory or selected object-code section is
not whole-binary identity. Archive raw controls/products before cleaning owned
simulators; restored evidence paths do not restore live destination identities.

### Passive native input observations (EXP-218)

Freeze the input result before background flush. A bounded in-memory
`UIApplication.sendEvent` observer must call super exactly once and must not add
hit tests, control subclasses, layout changes or synchronous dispatch-time I/O.
Assigned touch ancestry can be absent at touch end, and a native target callback
can arrive after `sendEvent` returns. The recorded switch case demonstrates both;
pre/post dispatch snapshots alone do not establish the final native state. Keep
callback, frozen UI value, touch delivery and RUM observations separate. Do not
weaken a failed frozen oracle or run its skipped differential arm.

Xcode27.1 rejects `-test-iterations 1`; omit that option for a single execution and
verify the exact test count afterward. A rejected command can still create an
xcresult bundle: inspect its zero-test inventory, not directory existence. Preserve
command-only failures and require independent admission before a pre-launch host
correction. Use fresh output/run/device identities, unchanged build/source/oracle
and the original deadline. Native retries remain prohibited.

The [EXP-218 record](Results/EXP-218-native-input-observation.json) retains its
zero-test command rejection and the later native pass/strict-oracle rejection.
Both task simulators and app data were removed; no SDK-on/off or gate pass follows.

### Lifetime evidence and native display-link teardown (EXP-211)

Map each lifetime claim to its witness: collection removal, weak object release,
cache TTL and OS process cleanup are not interchangeable. Real CADisplayLink
retains its target; a factory mock may have different invalidate semantics.
Observe nonnil weak witnesses before dropping the intended owner, use bounded
predicate waits, and put cleanup notifications after the critical assertions.
A resign-active control distinguishes invalidation from ordinary owner teardown.
Keep exact failed tests and assertion messages; summary test failures may list
one representative message while the detailed result records several.

Fresh git worktrees lack ignored package locks. Verify and copy the qualified
Package.resolved explicitly before source freeze, then validate clean checkout
revisions and disable automatic resolution/updates. Preserve a prelaunch failure
as such; it consumes no native test but requires a recorded concrete correction.
Do not copy local client configuration unless the actual scenario needs it.

A weak teardown witness must account for legitimate pending owners. The existing
MessageBus configuration task retains its receivers for five seconds; observe
its actual delivery while the core is alive before measuring final-owner release.
Keep the original post-teardown wait and assertions. This does not qualify early
teardown. Observe the actual core/bus as well as a test proxy; proxy release alone
cannot establish their lifetime. Keep intermediate failures as diagnostic evidence.

Globals compiled into both a test target and TestUtilities are module-local.
An explicitly constructed core can use a different temporary directory from the
proxy's cleanup helper. Clean the actual fixture directory after critical
assertions; a passing test body followed by an integrity crash is an invalid run.
Compare source with the named git revision, not a neighboring experimental checkout.
Byte-identical unaffected method bodies and a narrowly proven formatting-only
source delta can justify composed evidence; never label it a fresh full-suite run.

For exact component composition, bind the historical baseline and candidate input
maps, tests, dependencies and preserved neighboring repairs before copying paths.
Run only the fixed affected combined-source slice; prior full-suite results retain
their original identity. A filename such as `final-test-lint.json` is not proof:
check its exit code, configuration and source hashes. Reject stale receipts and
run scoped lint when exact reuse cannot be established. Keep native products and
raw reused regression results in the durable evidence mirror. EXP-212 records
this composition boundary; a focused pass does not promote the release candidate.

For native host lifetime, witness real appearance and disappearance before weak
ownership checks. A synchronous XCTest wait can differ materially from an async
MainActor observation even when both callbacks occur. EXP-213 preserves four
SDK-off retained-host controls and four async releases under the same2s boundary;
qualify the fixture first, and keep diagnostic execution separate from SDK-on
acceptance. An application's deliberate last-view restoration owner is distinct
from native host retention: advance or witness that owner before requiring the
old RUM scope to deallocate. Never clear SDK state before the critical assertion.
A compound wait failure cannot identify which conjunct failed; inspect the
separate assertions. Count test executions and per-test cycles separately.

### EXP-196 unattended physical iPad execution

Use the connected, authorized physical device and a bounded task-owned `caffeinate -d -i -u -t 14400` assertion; record command/PID/start/deadline, renew if needed and stop only that owned process. Device auto-lock is disabled by the user. Physical scene/gesture acceptance still requires native evidence before critical mutations.

When an existing valid Apple Development identity lacks a cached profile for the authorized test device, Xcode automatic provisioning with command-only team overrides can register the test device and obtain its profile. Use `CODE_SIGN_IDENTITY=Apple Development` with automatic signing; a certificate hash conflicts with that mode. Verify the actual selected signing certificate is one of the preflight identities. Compare a wildcard profile grant against the concrete signed app entitlement, exact device membership and expiry; do not require the profile wildcard itself to equal the app identifier. `codesign -d --extract-certificates=<temporary-prefix>` extracts the public certificate for comparison. Keep profiles/team overrides local and never read the protected local xcconfig.

The first physical F05 run observed A Home/foreground during B close before explicit reactivation. Preserve that original strict rejection. The separately defined `validate_physical_local` requires that exact close-triggered interval; the existing simulator oracle retains its earlier explicit-reactivation contract. Six focused oracle tests pass, including fourteen new boundary/identity controls. No native test rerun is needed for an oracle-only repair when every frozen native input and signed/installed Mach-O still matches.

Check the physical iPad’s actual multitasking mode before overlap runs. Full Screen Apps can keep two registered scenes while showing only one; no receipt may admit that topology. Ask once before a temporary system-preference change and continue independent full-screen cases while approval is pending. Preserve precritical attempts and restore the original preference after approved tests.

A physical background scene may not disconnect after SwiftUI dismissWindow. Preserve that attempt; the fixture-only `DD_PROBE_PHYSICAL_SCENE_DESTRUCTION=1` path requests UIKit destruction of the exact connected registered session. A request is not success: require the native disconnect after the request, before final peer work, and exact unchanged peer RUM ownership. Never post lifecycle notifications or replace the final marker with an earlier one.

Physical `devicectl device capture screen-record` can return unsupported despite screenshot/control availability. Qualify the actual recording call before admitting critical overlap work. Preserve precritical failures; native activation alone does not prove display visibility. Both background-close paths also need an observer that survives the relevant view lifetime; a missing view-local callback alone cannot establish platform refusal.

Before replaying older occurrence fixtures, verify their source actually accepts and reconciles the current destination. An empty occurrence source is deliberately fenced by the SDK. H05/H07 are migrated through the existing semantic container under EXP-196, retaining exact original assertions and H05 automatic-only B. Trace evidence must decode encoded IDs/start/duration with `ProbeTraceWireIdentity`; rounded Date/Double projections cannot establish an exact wire join.

A physical launch may return before its pre-SDK installed-code receipt becomes copyable. Poll that exact run/PID file for a bounded interval, retaining each failed copy; never relaunch or accept a different process to hide the race. Validate external frozen step strings against `ProbeStep.swift` before running: URLSession step raw values contain `url-session`, not `urlsession`. A contract mismatch stays invalid and any correction requires a newly frozen clean run.

APM direct Trace retrieval can precede searchable span indexing; preserve the initial zero count and later complete count/search instead of changing the query. MCP start timestamps showed nearest-millisecond projection rather than truncation. The H07 checker uses integer arithmetic for that observed representation and explicitly leaves backend submillisecond start unverified; exact raw duration and all ownership/trace IDs remain mandatory. Boundary controls reject adjacent milliseconds and unexpected precision. Poll the initial JSONL file as well as the pre-SDK receipt within a bounded interval, retaining failures and the original PID.

H14 uses an opt-in physical resize profile (`DD_PROBE_PHYSICAL_ADAPTIVE_RESIZE=1`) with actual1194x834 regular →592x834 compact →1194x834 regular geometry; the accepted Duo profile is unchanged. Native geometry and the live registered window must agree before each resize marker. Capture actual Window-menu input and phase boundaries, then require exact whole-session ownership before closing the physical gate.

The H14 physical path is qualified: Window > Move and Resize > Left gives592x834 compact; Window > Enter Full Screen returns1194x834 regular. Freeze each request sequence before input and require fresh native geometry/live guard before its marker. Count all backend events: automatic tap events can inherit the most recent marker attributes, so join by exact event ID/type and keep those taps in the complete inventory separately from the14 custom-marker work events.

H04 process-lifetime observation is diagnostic only: installation before scene creation does not manufacture lifecycle evidence. EXP-196 receives no disconnect in either observer; do not retry equivalent background-close requests or replace them with posted notifications. H11 remote gestures qualify only with actual interactive coordinator begin/completion on the same native scene; freeze the pre-input sequence and screenshot, retain unsuccessful drags, and exclude deterministic transition controls.

For physical XCTest input, override only the task build to deployment27.0; the existing Duo scheme remains27.1 in source. The runner must receive PHYSICAL_PROBE_RUN_ID and PHYSICAL_PROBE_REVISION before launch. Freeze and verify the installed receipt and actual secondary2 mapper owner before writing the run-bound gesture control. Set xctestrun SystemAttachmentLifetime/UserAttachmentLifetime to keepAlways using the documented Xcode contract; verify an exported video exists and covers the boundary before admitting H01. [Apple UI automation recording guidance](https://developer.apple.com/videos/play/wwdc2025/344/) supports keeping videos for successful runs but does not prove this device produced one.

Physical XCTest capture is now verified after the one-time iPadOS UI Automation passcode prompt: generated PreferredScreenCaptureFormat=screenRecording plus keepAlways exports an actual MP4 through xcresulttool export attachments. Keep copy-command JSON output paths distinct from copied checkpoint JSON. In the iPad split fixture, the navigation AX frame extends behind the visible320-point primary; derive the touch edge from the visible region and recheck both frames before input. A passing UI collector is never semantic or ownership acceptance by itself.

H01 physical acceptance now combines the unchanged22-expectation oracle,23 native topology guards, fresh screenshot/nonce admission, complete backend inventory and real XCTest video. Review every decoded frame around the critical boundary with both attachment and creation-time alignment margins. Inspect the MP4 display matrix: this recording reports minus45 degrees while stored pixels are correctly oriented; use ffmpeg -noautorotate for review only and retain original video bytes/hash. A video proves observed display continuity, not unrecorded sub-frame visibility. The bounded corrected H11 edge touch still produces no interactive callback; stop equivalent retries and keep collector success distinct from gesture acceptance.


### Release-specific execution after the EXP-196 checkpoint

The register now qualifies S1/S2/S3 separately. Preserve reference evidence and
never relabel it as acceptance of a new extraction. Regenerate PLAN and progress
with release_checklist.py --update, then run the checker again without --update;
qualified release dependency IDs prevent reference/candidate status confusion.
Keep historical experiment narratives in their owning records.

Use a clean isolated checkout from remotely verified current develop for each
admitted extraction; record the actual remote SHA even when SSH fetch is blocked
and an authenticated read-only GitHub API query proves the same locally available
object. Do not copy the original checkout's protected local configuration. Prove
red on that baseline, then green on the narrow fix. Inspect upstream platform
behavior before extracting older source. F07 freezes included/excluded symbols,
transitive dependencies and affected validation; runtime flags do not prove an
excluded implementation is absent from the shipped artifact.

Only one host controller runs builds/devices. Use the new available iOS17.5 iPad
for C06 actual test-host execution and retain its user-owned boot state; do not
repeat obsolete failed download probes. Availability does not close compatibility.
S1/S2 may use the approved runtime exception only after a genuine bounded runtime
failure, with explicit deployment15 compile/link, availability and oldest runnable
coverage; no exception is currently applied.

EXP-196 is safely checkpointed. The original Full Screen Apps preference is
restored and screenshot-verified, test app/runner and process are absent, and the
exact task-owned caffeinate assertion was stopped. Its durable cleanup receipt
belongs to the EXP-196 result. Future device work requires fresh preflight and
new control/run identities; do not reuse its old PID or temporary outputs as a
new run. Remaining physical combinations are S3, not the next automatic task.

[Human acceptance](HUMAN_ACCEPTANCE.md) owns the changed input path. Prepare and
validate the whole session before asking for gestures. The Datadog app skips RUM
bootstrap under XCTest, so normal-mode or separately authorized internal TestFlight
is required for app telemetry. Current organization cannot discover its app ID;
the user now authorizes controlled runs in the probes RUM application with a distinct
service. Freeze that isolated configuration, preserve production defaults, and
claim only the sessions actually run, with no live-customer baseline.


### EXP-197 current-develop qualification

The iOS17.5 test host executes with Xcode27.1 while retaining deployment15. The
upstream workspace needs its existing OpenTelemetry framework and the command-only
`DD_SDK_COMPILED_FOR_TESTING` define for test helpers. Preserve failed preparation
attempts separately from the actual repeated-mutation red test. Reuse dependencies
only after comparing their pinned manifests and inventory; do not copy protected
configuration. A sandbox signature check can fail because Git needs a temporary
file: an authorized `git verify-commit` establishes the signature, not the failed
sandbox status.

A proposed patch must be generated against the actual frozen base and pass
`git apply --check` in that exact checkout. An intermediate candidate is not the
base. A read-only applicable patch does not authorize applying a production change
that automatic approval review rejected; retain that decision and obtain explicit
informed approval after review. EXP-197 received that explicit approval and the
reviewed patch is applied for local testing. Preserve each failed preparation
attempt; a missing test import is not an SDK behavioral failure. A forwarding
test must drain its ServerMock requests before teardown: an initial focused pass
missed that fixture lifetime trap in the broader run. The final full Internal
run at signed464af911 passes453 tests/489 executions; preserve both predecessors.

For controlled Datadog app telemetry, use the accepted probe application and a
separate service. Follow the existing profiling runner's ephemeral Xcode include
pattern to let Xcode resolve probe settings. Never read, copy, hash or log the
protected local configuration or print resolved tokens. Inspect only safe bundle
identity and configuration-validity booleans. Normal app launch is required because
XCTest skips observability bootstrap. Preserve the original app organization
lookup result and make no live-customer traffic claim.

The bounded EXP-197 S1:C06 adapters now qualify six baseline and six candidate
cells on17.5, reusing the accepted baseline without rerunning it. Keep source projection limited to the unused internal benchmark
branch; apply it once before copying ordinary/legacy variants. `prepare` owns its
new directory, and XcodeGen runs in that generated directory. Record real
readiness/background/foreground assertion timestamps and invoke the inherited
boundary checker. Cleanup must reject command errors, prove the expected absent
container condition, and preserve the original simulator boot state. The owning
result keeps adapter hashes and the paired durable summary. Reference tooling
and candidate SDK archives have separate roots. Verify the generated project name
before invoking Xcode; a stale project name caused one retained preparation
failure before any install. Never infer S2/S3 acceptance from the S1 matrix.

EXP-198 is defined in its own protocol before fixture implementation. Its real
URLSession workload uses the unchanged performance budgets. The old allocation
collector observes only its installation thread; asynchronous coverage needs
independent all-thread calibration before measurement can qualify. Keep timing
and allocation processes separate and hold competing host workloads during ABBA.

The admitted fourth correction uses one schema-v5 contract across native fixture,
host and evaluator. Freeze source/helpers before either build; freeze a separate
execution manifest afterward with actual binary hashes. Preserve native result
bytes before parsing even failed results, and keep capture status separate from
semantic verdicts. Qualification must validate only its own controls; timing must
never install the allocation observer. Enforce the absolute qualification and
matrix deadlines, including cleanup, and reserve each launch once. The owning
result records the finite correction admission and acceptance review; offline
negative-control passes never count as native or numeric evidence.

For task-retention probes, include the warm native request in explicit weak and
autorelease boundaries. Reuse fixed weak slots after per-cycle release, store
scalar snapshots in preallocated capacity and serialize results afterward. Numeric
growth in an SDK-unbound control is not attributable to instrumentation; zero-body
and session-lifetime diagnostics narrow it without subtracting a new baseline.
Raw NSMapTable count is insufficient to distinguish bookkeeping from a retained
object: capture the final terminal value under its actual coordinator lock, drop
the native task, and inspect only a weak witness before count/enumeration/insertion.
Terminal callbacks can replace values, so an earlier preparation gives false nil.
Keep this reflective ownership diagnostic outside numeric performance samples.

For repaired terminal ownership, check that a live completed task retains only its
weak identity and no strong preparation value, then release the task and require
zero live weak members. Raw weak-table capacity need not become zero. Compare the
same native fixture against the pre-repair candidate; EXP-199 owns that red/green
evidence. Keep reflection outside timed/allocation samples.

Native URLSession state transitions may complete after resume/suspend returns.
Establish each state expectation immediately before its own operation, then require
the exact transition within a bounded wait. Never pre-create the second running
expectation, retry the operation, or accept a completed/canceling substitute.
Retain the independent lifecycle/header/cancellation assertions.

For registered terminal callback allocation rows, supply and drain companion metrics
before opening the measured epoch. Use one weak settlement witness per task in a
bounded window, including warm-up; overwriting a single witness proves only the
last task released. Weak-table raw slot counts remain diagnostic, while live
members and owned preparation/payload records must reach zero.

For final compatibility, independently check every architecture's source-file list,
private C/Objective-C/C++ inputs and resource bytes; a union across architectures
can hide an omission. Complete affected-module inventories include the separate
DatadogIntegrationTests target when public native networking uses the changed path.
Its Example.app host requires a launchable runtime; source-directory file counts
are not discovered test counts. Keep inherited TSAN report_bugs=0 distinct from a
clean sanitizer claim.

The current API verifier hard-codes an iPhone17Pro latest destination. If absent,
preserve the failure and freeze a temporary destination-only adaptation; keep its
full declared Tests/Fixtures graph, parser/comparator and API baseline bytes.
Feature-doc verification needs reachable prior source objects. Use authenticated
HTTPS fetch with per-command rewrite/credential settings if the SSH agent is
unavailable; never change persistent Git configuration or emit credentials.
Verification headers now identify1bdc9286c; if later rebased/amended/squashed, rerun
the feature-doc skill before any separately authorized push so the SHA is reachable.

For delta view assertions, reconstruct all target-owned full/update records in
strict documentVersion order. A missing delta field means unchanged; an explicit
empty array clears the field. Require initial full state, unique increasing
versions, final stopped state and exact final values. Preserve the original
assertion when diagnosing an inherited failure; remove all relevant payloads and
append an explicit empty final update as separate negative controls. A last-delta
nil alone cannot establish that the signal was never collected.

Detached integration worktrees also need the existing Carthage OpenTelemetryApi
binary, in addition to exact Swift-package pins. Check these before a diagnostic
build and hash reused framework inputs for both arms. Aggregate gate fields retain
reference/S3 evidence; only the relevant release_requirements entry qualifies an
isolated S1 or S2 candidate.

For native-only Resource/Trace backend fixtures, disabling periodic vitals does
not disable the first-frame app-launch TTID writer. Freeze its incidental inventory
and owner before runtime. If no public mapper exposes it, hold before Home until
an authenticated whole-session query observes the exact fresh ApplicationLaunch
TTID, then consume an identity-bound one-use host release. Native FBC is not expected.
Preserve full MCP payload strings and decimal/128-bit identities; backend detail
timestamps rounded to seconds cannot establish exact nanosecond starts. RUM rows
use opaque backend IDs distinct from semantic event UUIDs. Account for all pages
and keep startup query evidence separate from final session/service inventories.

For expected-red unit baselines, verify the exact test tree and assertion locations:
four failed test cases can contain six assertion failures. A compile failure with
zero executed tests is not a regression reproduction. Unwrap optional model values
before arithmetic; do not replace a missing value with zero or widen timing
thresholds to repair the test. Record any precise scaffold correction before a
fresh bounded invocation and retain the original source/result identities.

### EXP-208 qualification checkpoint

The [owning result](Results/EXP-208-trace-ownership.json) binds exact red, full-target
and native-pair artifacts to the committed source/test hashes. Reuse accepted
evidence by identity after checkpoint commits; a changed HEAD alone does not
invalidate unchanged qualified bytes. Preserve all preflight, compile and semantic
failures. Header-byte preservation and the returned TraceContext ownership must
both be asserted. Matched baseline/candidate runtime warnings remain diagnostics,
not automatic clearance. Signing timeout may use the user's authorized local
unsigned fallback; record it, retain explicit commit paths and never push.


Registered ownership evidence must come from delegate-only tasks with actual data,
metrics and completion callbacks. Preserve the callback attachments and exact task
IDs; a valid metrics object can have no transaction metrics, so that count is a
diagnostic rather than a required network phase. Require B's completion before
releasing A, without imposing an unsupported cross-task metrics callback order.

Full compatibility targets can contain a second test class with the same name as
an affected module's class. Identify failures by target and selector. A changed
ownership contract may require a source-reviewed fixture correction in that other
target; preserve the old failure and full header equality, then qualify the corrected
target once. An intentional expectation correction is not an inherited pass or a
flake. Use the repository's tests.swiftlint.yml for test-file linting. On macOS,
build and inventory the actual changed product: E05 requires Trace plus Internal,
whereas the RUM-only packet's macOS slice cannot establish Trace compilation.

For E05 backend ownership, freeze three logical views, two manual actions and one
actual TTID vital per mode. Current source emits no standalone application-start
action. Fold view updates by identity/version and require zero RUM Resources when
URLSession RUM tracking is disabled. Read owner context through a passive feature
scope, then fence the serial message bus before task start; context publication
alone does not prove the Trace receiver has consumed it. Full service/run span
inventory is required to find a deliberately ownerless pre-RUM request.

Generated ApplicationLaunch/TTID events precede manual probe attributes, while the
backend session reducer is server-derived. Require exact run/nonce/phase on manual
A/B events. For those generated rows, preserve absent probe fields and reject any
mismatched nonnil run/nonce; bind the rows through the unique service, actual
app/session/view/TTID identities and one-use startup exchange. Count the reducer
explicitly: E05 startup has three raw rows, final inventory seven. It is not an
application-start action. URLProtocol.stopLoading is diagnostic on normal success;
require real body/metrics/completion, session invalidation and host cleanup instead
of inventing a mandatory cancellation callback. Verify actual frozen helper,
interpretation and native-contract files in the live acceptance path; matching
hash labels inside an exchange alone cannot establish that those files are unchanged.

Keep early SDK initialization separate from scenario activation. In the E05 fixture,
sceneDidBecomeActive preceded aggregate UIApplication active state; observe both
actual states before scenario work. Core must register its launch callback before
launch/activation notifications because this candidate does not replay stored dates.
Prepare only Core during didFinishLaunching, allowing observed inactive/background
bootstrap; start Trace/tasks/RUM only after active app plus foreground-active scene.
A background bootstrap enum is not proof of a background scenario. Preserve the
real backend TTID/cold/nonprewarmed gate and fail activation timeout before tasks.
If fixture corrections consume the original runtime budget, preserve every failed
attempt and mark an unlaunched correction NOT_RUN_BUDGET. Do not extend the old
admission or reuse its IDs; checkpoint before a separately defined continuation.

For isolated Replay topology diagnostics, NSObject.safeValue is not an exception
barrier until Core installs ObjcException.rethrow. Avoid exploratory KVC on every
layer delegate: retain the complete tree but read private fields only on the exact
class already required by the original assertion. Do not initialize Core solely
to alter a passive observer. Preserve invalid observer crashes separately.

Swift Testing attachment preferredName is not the xcresult export name. Freeze
the exact base plus the observed index/UUID decoration, require exactly one match,
and retain nonce, selector, device, runtime, timestamp and content checks. A parser
correction re-audits saved bytes without rerunning a valid native arm. Generated
private Swift fixture type names can differ across builds; retain their raw
difference and source/demangled evidence instead of silently normalizing a pass.

## Local span identity and stopped-run backend continuation

Local SpanEvent IDs use canonical unpadded lowercase hexadecimal; root parent is
the string `0`. Normalize numeric low/span/high IDs for equality while retaining
all128 trace bits, and keep backend decimal decoding independent. Reject padding,
wrong numeric identity, nonzero parents and foreign ownership. Bind a corrected
oracle to immutable native bytes and preserve the original INVALID result.

A local re-audit is not backend acceptance. A separately frozen backend-only
continuation may query the exact original run with fresh request IDs and unchanged
source/build/decoder fingerprints, under a fixed deadline. Retain raw responses
before interpreting them, require complete service/session inventories, and stop
on the first missing or mismatched inventory without retry. E05's retained local
evidence passed, but its continuation stopped at3 RUM rows instead of7; original
cleanup followed the earlier local assertion failure. Review that upload boundary
before admitting any new native run. [The E05 record](Results/S1-E05-release-admission.json)
owns exact artifacts and any later disposition; no existing admission is extended.


### Selected test inventories and cross-query backend identity

Before assertions run, bind the exact selected test identifiers, not just their
count. Xcode discovery may mark every deliberately unselected case disabled;
freeze the full inventory and require only the selected methods and their parents
to be enabled. Reject extra, missing, duplicate or disabled selected IDs and require
the complete target source list. H00 preserves its original zero-assertion discovery
stop; its qualified two-case run and repository lint are owned by
[the H00 packet](Results/S1-H00-E01-packets.json).

An exact event count does not prove that a derived session reducer has settled.
Require its terminal counters and stable identity independently. A later observation
needs a separate frozen admission; retain original results and deadlines. Compare
client events across queries by stable type/event identity and full relevant payload;
compare reducers by session, document version, initial view and terminal counts.
Opaque search-envelope IDs need only bind each row to its raw response and remain
unique within that response; they are not stable cross-query event identities.
Preserve completeness, pagination and ownership negative controls. The
[E05 admission](Results/S1-E05-release-admission.json) distinguishes original FAILs
from accepted composed offline evidence. No retry or original-result overwrite is implied.


### Native ownership observation boundaries

A synchronous MainActor XCTest wait can itself change native host release. Preserve
a matched SDK-off control before attributing retention to the SDK; use actual
appearance/disappearance and condition-based async observation. Keep every original
wait limit. Start the terminal weak-release deadline at the ownership-ending call,
before serialized-event collection, so reading events cannot extend the deadline.

Account for legitimate restoration ownership through public commands: establish a
live peer and process a command while it is active before requiring the old view
to release. Require pending work, its original event owner, peer UUID/activity and
SDK presence before teardown. [EXP-215](Results/EXP-215-native-view-lifetime.json)
binds three native cases/six cycle receipts and explicit negative controls; its
result applies only to the qualified composition, not an older selected candidate.


### Source-aware candidate promotion

Bind every gate review to the authoritative register's absolute path, hash and
release-specific `gate.release_requirements.S2` (or the intended stage). An older
checkout or the top-level experimental-reference status is not interchangeable.
Reject mismatched authority before changing any gate; preserve the rejected review.

Inventory all source and tracked deltas, distinguish SDK from auxiliary Sources,
and map each retained invariant separately. Record the previous candidate freeze
as history. Source exclusions do not transfer full-suite, Duo, app or backend
passes. Reopen only the concrete invalidated obligations, with their existing
owner/dependency/decisive-test/environment, then regenerate the checklist.
[EXP-216](Results/EXP-216-s2-composition-promotion.json) owns a worked disposition;
accepted runtime checks are not repeated for this source/documentation checkpoint.


### Source-bound counts and verified exclusions

Historical suite counts can precede later committed tests. Bind the count to the
current fixture revision and require complete raw discovery before assertions.
Preserve a mismatch as a stopped admission; an inventory correction must identify
every added/removed method and must not silently omit a failure.

XCTest method and Swift Testing filters are not interchangeable. For a wholly
excluded Swift Testing suite, a suite-level filter may be required. Before running
assertions, enumerate again with the actual command filters and require exactly
the intended disabled methods, every required method enabled and unchanged raw
identities. Do not infer exclusion from the command string or selected count.
[EXP-217](Results/EXP-217-s2-compatibility.json) preserves the ignored-filter stop
and the subsequent enumeration proof. Excluded Replay-content cases count as
neither passes nor OS skips; retain other-feature ownership/coexistence checks.


For composed public clients and API checks, a manifest hash alone does not reject
extra source files. Compare exact source path sets and bytes, reject unexpected
symlinks, and retain the admitted roots separately from generated build outputs.
Bind the simulator runtime version and build as well as its device identifier.
Apply these checks before assertions; preserve earlier definitions when tightening
preflight. Metadata-only documentation changes do not justify repeated native runs.


### Reconcile a published packet with newer upstream source

Preserve the qualified checkout. Freeze the new upstream revision and exact packet
path allowlist before applying its patch to a fresh checkout. Use `--no-color
--no-ext-diff` for machine-readable patches; forced Git color can invalidate an
otherwise correct patch. Retain a rejected application as preparation evidence.

A fresh worktree may lack its ignored Package.resolved. Copy only the qualified
lockfile, verify exact checkout revisions and archive/extracted-artifact hashes,
and keep the original resolution failure. An environment correction does not
reset the experiment deadline or permit assertion retries.

Derive changed suite inventories from named upstream additions/removals before
discovery. Require every architecture's exact compiler membership before assertions,
and bind native attachments to the current device, invocation and critical boundary.
Compare public APIs against the new upstream reference, then bind feature-document
metadata to the new signed source commit. Update only the authorized draft with an
exact remote lease and read back its head, base, commits, files and concise body.
[EXP-219](Results/EXP-219-upstream-resource-integration.json) records this procedure;
its affected checks do not replace current CI or broaden older platform evidence.

## Controlled app build prerequisites

Resolve required tools before admitting builds. S2:F08 uses task-local verified
SwiftGen6.6.3, first in PATH; DD_SKIP_LOCAL_BUILD_TOOLS disables format/lint
mutation but does not disable the app script's SwiftGen installation fallback.
Require exact command resolution, frozen package pins, fresh per-arm outputs and
source/protected guards. A stopped preparation deadline is never extended; the
[owning result](Results/S2-F08-app-preparation.json) preserves its later admission.

When a tracked-file manifest intentionally hashes regular files, validate tracked
directory symlinks separately against mode, index/HEAD blob and literal link target.
Do not silently omit an unexpected path. Preserve the rejected inventory before
a reviewed guard correction; it adds no build or runtime credit.
