# Isolated URLSession candidate compatibility

## EXP-201 — Qualify affected platform packages and existing clients

Defined before new builds on 2026-09-20. Gate: S1:F03; its documentation evidence also closes S1:F02. Owner: SDK implementer.
Dependencies: S1:F07/C06 at frozen candidate1bdc9286, baseline62f64. EXP-199 owns
accepted Internal/Core/RUM/Trace full suites and strict lint; reuse them without
rerunning. The separate DatadogIntegrationTests suite also consumes the changed path; its
complete candidate inventory is required alongside the reused module suites.
Complete package builds cover every production target and transitive import.
No production, public API, wire, endpoint, dependency requirement or build-script
change is admitted. Local unsigned fallback is user-authorized; no push.

The source audit found the older reference recipe differs from current develop.
Candidate Package.swift sets macOS12.0, iOS/tvOS15, watchOS9 and visionOS1. Its
Makefile lists seven macOS products: Core, Logs, Trace, RUM, CrashReporting,
WebViewTracking and Flags. Preserve these current-develop contracts. The earlier
12.6/four-product recipe does not define candidate coverage. Make SPM helpers use
default configuration only; every required Debug/Release configuration is explicit.

Freeze these finite cells:

| Cell | Scope and decisive test | Environment |
| --- | --- | --- |
| M01 | Reuse all qualified EXP-199 Internal/Core/RUM/Trace inventories, failures and OS skips; execute the complete DatadogIntegrationTests inventory because its native network, Resource/Trace and sampling tests exercise the changed path | Actual17.5; exact1bdc9286 |
| M02 | Existing public Swift client compiles/runs in Swift5/6, Debug/Release; no SPI/testable imports; native URLSession completion/body and disabled/NOP safety | SDK27.1, deployment15, actual27.0 |
| M03 | Existing Objective-C generated-header selectors compile/run in Release; selected thread-safe controls complete exactly once | SDK27.1, deployment15, actual27.0 |
| M04–M08 | Complete original Datadog-Package production graph, Debug and Release, full emitted-module and source-file inventories | Generic iOS, tvOS, watchOS, visionOS and Mac Catalyst |
| M09 | All seven current-develop supported macOS products, Debug and Release; complete transitive modules | Native macOS, package minimum12.0 |
| M10 | Existing Swift/Objective-C API verifier against unchanged committed baselines; preserve baseline hashes | Xcode27.1 and existing verification tool |
| M11 | Existing feature-doc verification with reachable Git history; audit affected scope and keep metadata accurate | Isolated candidate checkout |

Root owns host execution. The client preparation worker owns only new temporary
source fixtures and reports exact public call inventory before execution. Archive
only explicit Package.swift and target source/private/resource/test-support paths;
preserve the original manifest, dependency requirements and resources. Test target
paths are included solely so the unmodified package graph remains valid. Never
archive the whole checkout, protected config or main Xcode project. Resolve only
existing dependencies and record their exact pins; no dependency upgrades are
applied to either checkout.

Retain real command exit codes, complete source/fixture/build identities, emitted
module/file lists, actual deployment settings and all failures. One failing cell
stops that lane for diagnosis; do not retry unchanged or call inherited baseline
failure a new SDK regression. If source/platform/toolchain differences require a
bounded baseline control, record it before execution. Documentation-only updates
do not change the candidate or require accepted test reruns.

[The owning result](../Results/EXP-201-final-compatibility.json) records cell
applicability, exact artifacts and any remaining limitation. This is compatibility
qualification; performance, backend acceptance and final release review stay open.

## Execution checkpoint, 2026-09-20

M02–M09 pass:24 platform/configuration builds and five public-client runtime
cells, with complete source/module inventories, identities and cleanup. M11
passes after auditing inherited feature-document drift and correcting Trace
suspension/background semantics. Five feature documents are committed separately
at5a570517; production/test source remains exactly1bdc9286.

The original M10 attempt failed before compilation: the verifier hard-codes
`iPhone 17 Pro,OS=latest`, which matches no installed destination. A fresh
temporary verifier copy changes only that destination to a freshly discovered
iPhone17Pro27.0 ID. Its parser/comparator, dependency pins, SDK source and committed
API baselines remain unchanged. Preserve both attempts; any further failure stops
for diagnosis, without rewriting API baselines.

Independent review found M01's separately named integration suite was omitted
from the original affected-suite statement. Before execution, add the complete
DatadogIntegrationTests inventory, especially native network instrumentation,
Resource/Trace correlation and head-based sampling. Use a fresh result bundle and
DerivedData with the original isolated workspace, actual17.5, Debug, serialized
testing and Test Visibility disabled. Stop on failure or30minute timeout; retain
all failures/skips and compare discovery with execution. This corrects an
acceptance scope gap; no SDK regression or new deliverable is inferred.

The destination-corrected verifier then required one fixture repair: include its
original Tests/Fixtures target paths as well as Sources/Package.swift. This failed
before SDK comparison and remains separate. The complete temporary graph passes
both nine-module API comparisons exactly, preserving every baseline byte and pin.
SourceKitten emits AppKit parse diagnostics for conditional macOS files on iOS;
no clean-parser-diagnostic claim is made. M10 is accepted within the full target
build and unchanged-public-source boundary.

The full integration run discovers/executes278 tests:277pass, one delta-hitch
assertion fails and zero skip. A bounded paired baseline/candidate diagnostic is
defined in the owning result before execution. It keeps the original workload
and assertion, adds only post-collection projected event-history attachments and
requires a reconstructed stopped view with positive frames. Missing-payload and
explicit-empty controls must reject. The first diagnostic's private dependency
fetch fails with zero tests; a fresh HTTPS attempt preserves exact accepted pins.
The fresh HTTPS attempt also executes zero tests because the detached worktrees
lack the existing OpenTelemetryApi binary. A third fresh attempt gives both arms
the same hashed2.5.0 framework used by the full integration run. These environment
repairs preserve source and the original assertion; all attempts remain recorded.

S1:F02 closes on the reviewed E01 changelog at c53ed48c, the five feature-document
audits at5a570517, unchanged API baselines and the five public-client runtime cells.
During preparation, duplicate resume callers may return before their native resume
continuation executes on the preparing thread. This bounded scheduling change is
recorded alongside tested early-callback ordering; no performance guarantee is
claimed. Production source remains1bdc9286; F03 and release acceptance stay open.

The paired diagnostic reproduces the original assertion failure in both arms:
full version1 has no frames; version2 contains one measured hitch; stopped
version3 omits unchanged frames. Independent reconstruction yields a stopped view
with one hitch in each arm. Six corruptions per arm reject (all frames missing,
explicit empty final delta, missing full baseline, duplicate version, mixed owner,
missing stop). Candidate XCTest logs show all four tests complete; its Xcode
process is still finalizing diagnostics, so no successful runner exit is claimed.
The owning result retains raw attachment/stdout provenance. A narrow test-only
correction is now justified, with complete integration qualification still required.
