# URLSession QoS diagnostic

## EXP-204 — Classify the retained networking priority-inversion warning

Defined before execution. The [owning result](../Results/EXP-204-network-qos.json)
freezes one existing HeadBasedSampling selector in baseline62f64 and candidate1bd
on17.5. This is a concrete S1:F06 uncertainty from EXP-201, not a compatibility
rerun. The retained warning has no source location or stack; the test exercises
ordinary registered URLSession first resume, without deliberately repeated,
concurrent or reentrant resume.

Reuse only the inspected existing EXP-201 test/host products after exact source,
binary, toolchain, runtime and pinned-dependency verification. Run each arm once
with test-without-building, unchanged assertions and diagnostics, in fresh
processes/results. Bound the pair to20minutes/600seconds per invocation. Stop if
reuse is unavailable; no hidden rebuild, credential action or repeat-until-clean.
Preserve every warning, exact test count, available stack and cleanup result.

An occurrence in baseline establishes that the warning can predate E01, not that
it is harmless. Candidate-only occurrence needs a causal stack. A warning-free
pair means this bounded control did not reproduce it; it is not clearance of the
original suite observation. No numerical performance or sanitizer claim follows.

The initial product-root preflight stopped before tests; its receipt remains in
the owning result. After that path-only correction, baseline console records the
selected test passing once in0.041seconds and reproducing the QoS warning. The
shown stack contains TSan dispatch wrappers, CFNetwork, libdispatch and pthread;
it is incomplete and does not identify an SDK caller.

Xcode did not finalize within600seconds and was terminated under the frozen
bound. All four result readers returned64 because the result bundle had no
Info.plist. There is no accepted result inventory. Candidate never ran. The
experiment remains **INCONCLUSIVE**: the warning can occur without E01, but this
does not compare candidate behavior or clear sanitizer/performance safety. No
retry or rebuild is admitted. Source/products remain unchanged; all three cleanup
checkpoints and protected-state checks pass. Independent final audit agrees.

A separately defined follow-up applies EXP-205's proven host correction,
`-collect-test-diagnostics never`, to both unchanged arms. Source/test products,
selector, assertions and sanitizer configuration are byte-identical. Both
invocations now finalize: one test/one execution per arm passes, and all four
result readers succeed. The pair takes17.46seconds; all five cleanup checkpoints
and protected/source/product checks pass. Verbose diagnostic archives are omitted.

Both arms reproduce the QoS warning with identical15 shown stack frames: TSan
dispatch wrappers, CFNetwork, libdispatch and pthread. No shown frame belongs to
the SDK, but the displayed stack is incomplete. This resolves the paired diagnostic
as inherited recurrence; it establishes neither root cause nor harmlessness,
sanitizer safety or numerical performance. The original600second timeout remains
inconclusive as an attempt. Final S1:F06 still requires its other gates and review.
