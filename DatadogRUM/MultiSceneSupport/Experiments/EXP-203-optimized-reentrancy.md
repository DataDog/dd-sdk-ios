# Optimized URLSession reentrancy

## EXP-203 — Qualify the Release configuration for S1:P04

Defined before execution on2026-09-20. The [owning definition](../Results/EXP-203-optimized-reentrancy.json)
freezes three existing candidate tests: synchronous mutation reentry, concurrent
first resume and payload/error destruction reentry. Root owns execution on the
qualified17.5 simulator with Xcode27.1. SDK production stays1bdc9286, final
checkout925b9326; no implementation or test change is admitted.

P04 is a functional zero-defect gate. BASELINES requires zero wrong context,
duplicate dispatch, unbalanced restore, deadlock or crash; it has no numeric
budget or timed ABBA requirement. The earlier temporary P04 audit conflated it
with P01–P03. Those numeric gates and thresholds remain unchanged.

The independent source/evidence audit verified eighteen explicit EXP-199 passing
controls and exact equality of all three production and two test files at the
final candidate. Those executions used Debug. Reuse them for the covered
functional invariants; do not relabel them optimized. E01 has no scene authority
or TLS context to restore, so retain the scene contract only in its existing
reference/S2/S3 scope.

Execute the three existing selectors once in Release, verify actual -O compiler
settings and testability, and require exact discovery/execution identity with
zero failures or skips. Preserve finite existing expectations and the1800second
host bound. Reuse EXP-197's bounded original defect control; do not introduce a
new unbounded baseline recursion fixture. Preserve any failed attempt and stop
for diagnosis before retry. Keep protected files unchanged and do not use local
credentials. No performance, backend or physical-device claim follows.

The single admitted Release run passes exactly three selected tests and three
executions, each once, with no failures/skips/retries or unexpected cases.
Independent audit verifies actual -O/-enable-testing compiler jobs for SDK,
TestUtilities and tests on both built architectures; only arm64 executes.
The five source/test hashes match accepted EXP-199,1bd and925. Direct test emits
no xctestrun; the CLI selection, actual compiler/product identity and xcresult
bind the proof instead. No repeat is needed to manufacture that artifact.

S1:P04 closes. Hostless cleanup preserves the simulator's Booted state, candidate
and protected paths, with no remaining test process or installed app product.
The seven-hour caffeinate assertion stays active.

The run is not warning-free:142 build-warning lines (41 unique messages),59
duplicate ObjC classes (43 OpenTelemetry,16 KSCrash) and three Xcode SDK-version
parsing diagnostics are retained. The duplicates pair DatadogSDKTesting with
OpenTelemetryApi or DatadogCrashReporting. No direct intersection with the three
controls was found; global harmlessness is not established. The bounded F06 audit
attributes every second implementation to DatadogSDKTesting through TestUtilities.
All10 production Xcode closures, nine default SPM products,24 accepted production
builds and five accepted public-client link/load graphs exclude that test library.
The explicit development-only TestUtilities export stays outside this ordinary
client boundary. Exact graph, pair names, link inventories and binary identities
are retained by the owning result. The142 compiler-warning lines remain separate.
F06 and P01–P03 remain open; no test or build was repeated for this disposition.
