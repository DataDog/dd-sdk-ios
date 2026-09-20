# Candidate compatibility qualification

## EXP-200 — Complete custom/NOP and iOS26.5 compatibility

Defined before fixture implementation or new runtime launches on 2026-09-20.
Owner: SDK implementer. Gates: S1:C04 and S1:C05. Dependencies: qualified
EXP-199 candidate1bdc9286 and the accepted EXP-197 baseline62f64. This closes
existing finite compatibility requirements; no production change is admitted.

Compare the same source-neutral Release fixture at deployment15 in both arms.
C04 requires the legacy-only protocol conformer to receive exactly
`add:one`, `start:two`, `stop:three`, and NOP session completion to return nil
exactly once. NOP calls must add no mapped RUM events. A real monitor positive
control before and after the NOP boundary proves the event observer is live;
observe processing barriers before asserting absence. Existing full RUM NOP and
convenience tests remain accepted evidence, not a substitute for this runtime
control. Do not import deferred target overloads or historical CANDIDATE behavior.

The finite matrix is18 cells: the two arms' six ordinary Scene/Legacy/
LegacyLifecycle modes on actual26.5 (12), plus one custom/NOP cell per arm on
17.5,26.5,27.0 (6). The12 ordinary cells reuse exact accepted binaries after
rechecking source, fixture, executable, SDK and minimum-OS identity. Compare
strict normalized view/action/Resource owners and native lifecycle notifications
against each other and the accepted17.5 oracle. SDK27.1 Scene builds and genuine
SDK26.5 Legacy/LegacyLifecycle builds remain separately identified. The custom
fixture is built with Xcode26.6/SDK26.5 for all three runtime samples.

Root is sole host controller. Fresh discovery established iPad17.5(21F79) and
iPhone18Pro27.0(24A434) Booted, and iPhone17Pro26.5(23F77) Shutdown. Record exact
runtime/device mapping again in preflight; restore each original boot state.
Every launch requires clean data absence, a new run ID, installed binary identity,
fresh terminal output, complete semantic assertions, process/data cleanup and
preserved lifecycle readiness discriminators. A failed prerequisite is not PASS.

Stop after one complete matrix or two equivalent unchanged failures. Preserve
failed attempts; a corrected fixture/runner has a new frozen identity. No
accepted17.5 ordinary cell or completed EXP-199 suite is rerun for this gate.
Keep performance measurements paused during these compatibility workloads.
The [owning result](../Results/EXP-200-compatibility.json) records identities,
commands, all18 cell verdicts, cleanup and the final bounded conclusion.

Result: all18 cells pass. Both source arms match the accepted normalized ownership
and lifecycle oracle. Custom/NOP controls pass on all three runtimes, and five
corrupted-result controls reject duplicate forwarding, missing/duplicate callbacks,
NOP telemetry and a dead observer. Every app/process/data cleanup passes; the
26.5 device returns to Shutdown and17.5/27.0 remain Booted. Protected paths are
unchanged. S1:C04/C05 close for1bdc9286; performance and release review remain open.
