# Builds, tests and public clients

Read for an admitted build/test/API check. Use [environment preflight](ENVIRONMENT.md)
and the [common evidence contract](EVIDENCE.md); exact commands, counts, thresholds
and budgets come from the owning definition or fixture README.

Before native admission, compare fixture configuration values used by the oracle
with the hash-bound source contract and actual compiler inputs. Configuration
identity checks belong in preflight; a stale expected constant must not consume
human input. Preserve an original failure and any corrected saved replay separately.

## Freeze inputs before work

Bind the approved source-member dictionary and archive, SDK/fixture/runner/oracle
hashes, dependencies, compiler flags, runtime and output identities. Verify exact
path sets and bytes, not a manifest hash alone. Reject unexpected files and
symlinks. For tracked directory symlinks, check mode, Git blob and literal target
separately. Recheck source/helper identity before assertions and after execution.
Generated outputs must be explicitly inventoried outside the admitted source roots.
Parse compiler flags as argv; accept exact joined/separate defines. Inventory target
version C separately, binding source/object/link bytes and the object variant from
actual compiler sanitizer flags. A read-only verifier stop preserves native results
for reviewed reclassification; it does not justify repeating accepted tests.
When copying generated projects, include module maps and their resolved umbrella
headers in that inventory. Review exact root relocation before building; never
repair dependency sources for a stale generated path. Non-compiler package/Git
state needs an explicit disposition and a build path that cannot regenerate it. Bind the checkout's compiler floor separately from the installed compiler, language mode and deployment target. Before availability-sensitive forwarding, check the minimum-version public declaration and typecheck the actor-sensitive shape without linking. Retain deprecations; newer-interface/probe evidence cannot replace minimum-compiler or deployed-runtime qualification.

Use fresh per-arm output directories. When reusing a binary, retain its original
build, source, configuration and complete product fingerprint. Freeze every Mach-O,
including the Debug dylib; a launcher stub hash alone cannot distinguish static-SDK
arms. Bind final linker search paths and resolved SDK archives. Reclassify a saved
artifact offline when possible rather than rebuilding to repair its classifier.

The repository's SPM helper can rename the workspace. Use an isolated package for
checks that would disturb protected workspace state. Do not modify build scripts
or dependency pins to repair an unrelated preparation failure.

The [ordinary API client](../../../tools/multi-scene/api-availability/README.md)
qualifies unguarded deployment15 calls, runtime-selected fallback and Objective-C
background rejection. Its optimized validation flag does not approve normal public
exposure. Disable unrelated automatic instrumentation in a focused API oracle,
and derive automatic view names from the predicate's actual source contract.

## Full-target platform compatibility checks

Derive membership from the frozen Xcode target's source phase, including shared
Swift and private C/Objective-C/C++ inputs, resources and generated sources. A
`Tests/` glob or source-directory count is not a target or test inventory. For each
architecture, compare its own compiler source list, emitted modules/objects and
product metadata; a union can conceal a missing architecture-specific file. Bind
actual SwiftPM target directories (which may end in `-t.build`) to exact module
list basenames. Xcode's prebuilt XCTest runner has its own SDK/deployment metadata:
verify it against the selected Xcode template and executable architecture slice,
then check the app and compiled test bundle against their intended build settings.

Inventory the actual changed modules on each platform. RUM-only macOS builds do
not prove Trace/Internal compilation. Include the separate Integration target when
public networking reaches the changed code. Verify the actual `TEST_HOST` and app
bundle, then use a launchable host/runtime pair. Build success followed by not-run
tests, a legacy-host startup trap or a nonexistent result bundle is not execution.

An isolated checkout may lack the ignored test configuration. Bind the standard
`DD_SDK_COMPILED_FOR_TESTING` condition from `tools/repo-setup/Base.ci.xcconfig.src`
when existing test-only helpers require it; do not expose them in shipping builds.
For a scheme that builds only for testing, query `-showBuildSettings` with the
explicit `test` action and selected destination. The installed Xcode manual states
that this metadata option does not build. Verify actual target host/loader settings;
a hostless override is suitable only after reviewing the selected fixture contract.
Discovery exit0 is insufficient: returned errors must be empty and every selected
case must appear. The [PR3 owner](../Results/S3-PR3-routing-preparation.json) retains
the original missing-condition, legacy-host and metadata-action stops; its hostless
path remains unqualified until actual discovery and case results are accepted.

The [finite package runner](../../../tools/multi-scene/compatibility/README.md)
verifies copied Git object-store isolation and each private compiled object's
actual link-list and final product membership. Preserve diagnostics preceding
Xcode JSON; qualify only the exact observed schema against its original command
receipt. Reuse a complete saved listing instead of repeating native discovery.

Preserve availability filters, skips and parameterized invocations. Discover test
identifiers before assertions with the exact intended command filters. Require all
selected methods and parents enabled, with no extra, missing or duplicate selected
ID. Intentionally unselected cases may be disabled. XCTest method filters and Swift
Testing suite filters differ; verify the resulting discovery rather than the
command text. Replay-content exclusions are neither passes nor OS skips.

Reconcile logical test cases and expanded parameter invocations separately. Xcode's
summary can count parents while per-device counts include their argument results.
Require exact source-declared argument tuples, each ordinary result once, and both
count models consistent with failures/skips. Duplicate, foreign or missing rows
still fail. The [PR5 owner](../Results/S3-PR5-scene-handler-preparation.json) retains
the reviewed saved-export correction; do not rerun tests for a grader repair.

Xcode test discovery can list methods excluded from the selected platform by
source conditional compilation. Reconcile a missing result with the frozen source
and final test inventory; retain the original selection and record the exact
platform exclusion. Do not count it as passed or rerun a valid suite to recover it.

If MCP package resolution fails before XCTest and cannot bind an existing verified
offline cache, preserve that build failure. Use the repository
[test skill](../../../.claude/skills/running-tests/SKILL.md) CLI fallback with exact
pins, artifact bytes, explicit cache flags and a new admission. Do not change
package requirements or extend the failed attempt.

UI-test enumeration can install and launch the test runner even when no test
method executes. Record task-bundle/container absence before enumeration, verify
any installed runner against the frozen build, then remove it and prove the clean
boundary before app execution. Treat discovery as a possible installation boundary;
an unexpected runner is a host setup finding, not SDK input.

XCTest may reinstall the app into a new bundle container. Re-query app and runner
paths after execution, verify their frozen Mach-O/Info.plist identities, then bind
observed PIDs to those paths. Keep pre-XCTest paths as preparation evidence. An
offline correction may use complete saved identity/process/result evidence while
preserving the original host failure; do not repeat a valid native arm to repair
a path classifier.

An old workspace snapshot can include documents later released from user protection.
Bind the explicit consolidation receipt and its exact original document manifest in
new inputs; retain the old snapshot and exact current checks on the remaining user
paths. For an admitted alternate runtime, distinguish CoreSimulator's device-type
display name from xcresult's model name and bind both before installation.

When current sources add/remove tests, reconcile every changed method against the
frozen source before another invocation. Retain the original pre-assertion stop.
A historical suite count cannot silently omit a newer failure.

## Bounded XCTest collection

An availability annotation on an XCTest class does not prevent selector discovery
on an older runtime. Tests of a newer-only surface need a runtime setup guard that
does not rely on a redundant availability branch inside the annotated class.
Declare exact skipped IDs/reasons before execution and prove the class still runs
on its supported OS. Treat result-tree failure/skip/runtime-warning nodes as diagnostics owned
by the case or argument; preserve their raw nodes and all failure results. They do
not create extra parameter invocations or justify broad skip exclusions. When
warning nodes are present, their message/source multiset must match the summary.
An offline decoder repair may classify saved failures; it never rewrites the run.

A lifecycle fixture may attach its shared mock window to a real scene. Observe the
actual controller/window/scene at appearance and lifecycle boundaries before
classifying a missing foreground view as an SDK regression. Process-only posts do
not exercise scene restoration. Keep test-only diagnostics opt-in, bind their
compiler condition and source uses, and join ordered records to native test cases.
No topology read off main or diagnostic subset qualifies the full suite. Preserve
a failed cleanup verdict when a later quiescence/deletion check restores the device.

Prepare source, selection, output paths and the oracle before starting Xcode.
Use the repository test skill and commands with the smallest relevant target.
The Objective-C monitor API class is `DatadogCoreTests/DDRUMMonitor_apiTests`.
Apply `-enableCodeCoverage NO` only to a test action; do not use
`-test-iterations 1` where Xcode rejects it. Verify the default actual run count.

Acceptance requires the real process exit, a finalized xcresult, its selected test
tree and all assertion failures. Wrapper messages, console PASS and summary counts
alone are insufficient. A case can contain multiple failed assertions; identify
failures by target and selector when classes share names. `No result`, `notRun`,
missing selected tests or an unexpected restarted process invalidates the claimed
complete run. Preserve the first exception before a restarted suite's later pass.

`xcresulttool get test-results` can create a derived SQLite index inside its input
bundle. Export from an exact, separately owned copy of the finalized same-run
result, and preserve the original native bundle. Bind original payload members,
returned raw bytes and the complete copy after export through final publication.
A consumer stop is separate from native failure; classify saved exports without
repeating tests. The [PR4 owner](../Results/S3-PR4-monitor-preparation.json) retains
the observed metadata effect and focused controls.

An MCP-exported xcresult can be an incomplete copy even when its test list is complete. Preserve it; use the actual same-run console path to locate and separately retain the finalized original. Verify its exact selected test tree, device and diagnostics without rerunning tests.

Keep XCTest asynchronous while host bridges serve requests. Collect both immediate
and yielded helper completion before inspecting exit status or parsing output.
Store the complete transcript durably even if a tool filter returns too much text;
return a bounded projection plus path/hash/byte count.

A collector/finalization timeout does not authorize an equivalent retry. Preserve
console, partial bundle, runner/testmanagerd evidence and exact configuration,
then clean up within the original budget. A separately admitted
`-collect-test-diagnostics never` pair may reuse unchanged products with matching
configuration and symmetric treatment; it must still retain warnings and finalized
inventories. Missing verbose archives do not clear sanitizer/runtime diagnostics.

A diagnostic child can own another process group. Identify it by the exact
experiment/app/output path before termination, reap it and prove absence. Process
guards should match actual XCTest/test bundles, known SDK hosts and competing
build/profile workloads; a broad `Runner` suffix also matches unrelated system apps.
Never kill or exclude an unrelated process to repair a guard. An owned simulator's
`launchd_sim` is its control daemon, not an XCTest worker. Bind the observed
executable and owned bootstrap path; a UDID substring alone cannot classify a worker.

Include process-inventory latency in the fixed cleanup reservation and retain the
actual rows or partial timeout output. An empty reaped group needs one inventory.
If quiescence is unproven, defer simulator teardown. Read a failed run's result
bundle only after timely quiescence and fresh bundle ownership are proved; this is
diagnostic collection from that attempt, never a retry or acceptance rescue.

## Assertion and warning interpretation

For expected-red controls, require executed tests with exact assertion locations.
A zero-test compile failure is preparation evidence. Preserve optional-value
failures; do not replace missing values with zero or widen time tolerances.
Repository source/test SwiftLint configurations and explicit changed-file lists
are required; configuration-free lint is not the repository gate.

Runtime warnings remain diagnostics unless an independently reviewed exception
binds the exact test, message, identifiers and multiplicity to source-proven
inherited behavior. Keep wrong-case/message/count negative controls. Preserve raw
FAIL separately from a qualified disposition. Matching baseline warnings establish
recurrence, not root cause, harmlessness, clean TSan or a performance pass.
Inherited `report_bugs=0` is not clean sanitizer evidence.

Formatted CI passes can be expected failures from early-flake detection. Inspect
unformatted job logs or xcresult and every repetition. A brief process sampler may
miss short tests: under review, PID-tagged startup logs and a single suite containing
all iterations can establish same-process execution without a rerun. Preserve the
sampler failure and exact inherited duplicate-class pairs. New pairs still fail.
[Delivery](DELIVERY.md#ci-and-review-follow-ups) limits when CI repairs are in scope.

## Public API and optimized checks

Compile public Swift/Objective-C clients against the actual shipping configuration.
Experimental Swift SPI, `@testable` tests, Debug-only ObjC selectors and Release
clients without `@testable` are separate evidence. Prototype availability does not
approve new public API. F01/F03 own nullable target construction, off-main ObjC
safety, ordinary deployment-15 calls, older-system fallback and newer exact routing.

Fixture result fields must preserve their declared JSON types. An Objective-C boxed
comparison may serialize as integer1; use explicit Boolean values for Boolean
fields. Keep the original invalid attempt and require fresh complete evidence after
a fixture correction. Passing API assertions cannot replace skipped process/code
checks at the required execution boundary.

Use `make api-surface-verify` as the check; `make api-surface` mutates the baseline.
If its hard-coded destination is absent, retain the failed preparation and freeze
only a reviewed destination adaptation, preserving the full fixtures/dependencies,
parser/comparator and API baseline. Feature-document verified SHAs must exist in
final outgoing ancestry after a rebase/amend/squash; rerun that documentation check
before publication without repeating unchanged native evidence.

When reusing accepted products for an API source audit, bind all compiler arguments,
response-file members, source/dependency bytes and emitted products. Preserve the
repository parser/formatter and record any cache-only relocation. Require exact
expected, discovered and returned documentation inventories before filtering by
language: a SourceKitten “Parsing” line precedes optional parsing and is not proof
that documentation was returned. Retain every module section and baseline diff.
SourceKit output can include SPI/Debug declarations while omitting their annotations;
it cannot establish ordinary Release exposure or approve a new API baseline.

If a host-tool test run omits its requested XML report, retain that collector failure.
A separate assessment may reuse the immutable exit/quiescence receipt and complete
raw test log only with exact case start/pass pairs, nested suite closure, counts,
no unknown/failure/skip lines and negative decoder controls. Do not rerun successful
tests solely to obtain the missing report or relabel the original attempt.

Optimized reentrancy requires actual `-O` compiler jobs and
`ENABLE_TESTABILITY=YES`, exact selectors and the admitted workload. A Debug result
is not Release evidence. Functional reentrancy and numeric performance are separate
gates. Optional network microbenchmarks stay outside release prerequisites; if
admitted, calibrate allocation visibility across all relevant threads, separate
timing/allocation processes, preserve ABBA order and stop competing workloads.
Keep original median/p95/allocation/count limits and independent overrun controls.

## Fixture-specific build notes

- Freeze normal and opt-in fixture membership; ordinary Release must exclude
  acceptance-only implementations and manifests where required.
- Source-only observation hooks retain separate archived/compiled hashes and may
  not mutate scenario state. Control/candidate constructors or an unused benchmark
  exclusion must be symmetric and documented before execution.
- For Python `runpy` helpers, resolve sibling imports before native admission.
  An import correction does not reset the deadline.
- Swift Testing attachment `preferredName` is not its exported filename. Freeze the
  observed index/UUID decoration, require one exact match, and retain nonce,
  selector, runtime, timestamp and content checks. Re-audit saved bytes for a parser
  correction. Preserve raw private-type-name differences with source evidence.
- The [legacy runner](../../../tools/multi-scene/baselines/legacy_compatibility.py)
  owns C03's readiness-first baseline build and finite paired matrix. Its actual
  lifecycle timestamps and cleanup checks cannot be replaced by posted signals.
- The [controlled app preparation](../Results/S2-F08-app-preparation.json) owns
  generated-resource, static-framework and exact source/object inventories. Build
  qualification is separate from its [journeys](../Results/S2-F08-app-journeys.json).

## Application-impact clients

[EXP-224 preparation](../../../tools/multi-scene/application-impact/README.md)
freezes identical UIKit/SwiftUI fixtures against the baseline and exact API candidate.
Unsigned Release builds qualify compiler/product identity only. Serialize metric
reads with phase boundaries and distinguish app-process CPU/hangs from global
physical-display FPS estimates/hitches. Strict offline decoder controls cannot
qualify native exported formats, installed code, recorder readiness or cleanup.

The physical runner binds runtime helpers separately when a reviewed host-only
correction leaves fixture/compiler/product bytes unchanged. Keep the original
build plan and failed attempts. CoreDevice launch options must precede the bundle
ID, after which tokens are app arguments. A clean install and matching pre-SDK
receipt cannot substitute for recorder readiness; stop failed qualification before
claiming workload or performance evidence. Bind the launched PID and executable/app
directory to the installed product, then retain one current process inventory just
before attachment. This proves point-in-time visibility only; the process can still
disappear before the recorder starts. On failed attachment, preserve the original
error and one bounded process read before cleanup. Neither snapshot can substitute
for recorder readiness or the trace's exact process lifetime. See the owner for
current admission.

## Integration lifecycle qualification

The [EXP227 fixture repair](../Results/EXP-227-integration-fixture-repair-definition.json)
uses a fresh qualification plan, controls and review bound to the exact full-target
selection. Require the four changed fixtures in both project and actual compiler
membership, with diagnostics disabled. Consumed diagnostic roots remain immutable
evidence and cannot be replayed or supply a qualification admission. During future
cleanup only, lingering ibtoold may settle within the original budget; preserve each
actual process inventory and require an empty worker set. Active builds/tests and
preflight still stop immediately.

Cross-language transport controls must preserve actual native payload bytes.
Canonical encoding may bind identity-only envelopes; do not require Python to
reserialize Swift floating-point geometry identically. The [H06 fixture contract](../../../tools/multi-scene/acceptance/README.md#h06-operation-preparation)
separates file-channel qualification from app wiring and post-setup View ownership.
