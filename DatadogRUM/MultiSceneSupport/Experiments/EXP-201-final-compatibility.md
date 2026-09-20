# Isolated URLSession candidate compatibility

## EXP-201 — Qualify affected platform packages and existing clients

Defined before new builds on 2026-09-20. Gate: S1:F03. Owner: SDK implementer.
Dependencies: S1:F07/C06 at frozen candidate1bdc9286, baseline62f64. EXP-199 owns
accepted Internal/Core/RUM/Trace full suites and strict lint; reuse them without
rerunning. Other modules do not consume the changed network coordinator directly;
complete package builds still cover every production target and transitive import.
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
| M01 | Reuse all qualified EXP-199 Internal/Core/RUM/Trace inventories, failures and OS skips | Actual17.5; exact1bdc9286 |
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
