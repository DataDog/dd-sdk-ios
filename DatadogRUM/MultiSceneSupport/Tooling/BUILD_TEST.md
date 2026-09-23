# Builds, tests and public clients

Read for an admitted build/test/API check. Use [environment preflight](ENVIRONMENT.md)
and the [common evidence contract](EVIDENCE.md); exact commands, counts, thresholds
and budgets come from the owning definition or fixture README.

## Freeze inputs before work

Bind the approved source-member dictionary and archive, SDK/fixture/runner/oracle
hashes, dependencies, compiler flags, runtime and output identities. Verify exact
path sets and bytes, not a manifest hash alone. Reject unexpected files and
symlinks. For tracked directory symlinks, check mode, Git blob and literal target
separately. Recheck source/helper identity before assertions and after execution.
Generated outputs must be explicitly inventoried outside the admitted source roots.
When copying generated projects, include module maps and their resolved umbrella
headers in that inventory. Review exact root relocation before building; never
repair dependency sources for a stale generated path. Non-compiler package/Git
state needs an explicit disposition and a build path that cannot regenerate it.

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

Preserve availability filters, skips and parameterized invocations. Discover test
identifiers before assertions with the exact intended command filters. Require all
selected methods and parents enabled, with no extra, missing or duplicate selected
ID. Intentionally unselected cases may be disabled. XCTest method filters and Swift
Testing suite filters differ; verify the resulting discovery rather than the
command text. Replay-content exclusions are neither passes nor OS skips.

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

When current sources add/remove tests, reconcile every changed method against the
frozen source before another invocation. Retain the original pre-assertion stop.
A historical suite count cannot silently omit a newer failure.

## Bounded XCTest collection

An availability annotation on an XCTest class does not prevent selector discovery
on an older runtime. Tests of a newer-only surface need a runtime setup guard that
does not rely on a redundant availability branch inside the annotated class.
Declare exact skipped IDs/reasons before execution and prove the class still runs
on its supported OS. Treat result-tree failure/skip messages as diagnostics owned
by the case or argument; preserve their raw nodes and all failure results. They do
not create extra parameter invocations or justify broad skip exclusions.

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
Never kill or exclude an unrelated process to repair a guard.

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

Use `make api-surface-verify` as the check; `make api-surface` mutates the baseline.
If its hard-coded destination is absent, retain the failed preparation and freeze
only a reviewed destination adaptation, preserving the full fixtures/dependencies,
parser/comparator and API baseline. Feature-document verified SHAs must exist in
final outgoing ancestry after a rebase/amend/squash; rerun that documentation check
before publication without repeating unchanged native evidence.

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
claiming workload or performance evidence. See the owner for current admission.
