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
