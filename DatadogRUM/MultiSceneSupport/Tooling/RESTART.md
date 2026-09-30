# Handoff recovery

Use this procedure after reading the whole [cursor](../../../.continue-here.md).
It recovers context and ownership; it never admits a run or changes the selected task.
The [runbook](../TOOLING_RUNBOOK.md) owns common safeguards.

## Execution and native/build ownership

1. Verify branch, HEAD, signature and index/worktree. Preserve the cursor's protected
   paths and any additional concurrent edits. A failed signature check in a restricted
   environment is not proof of an invalid signature. Use the
   [project commit rules](DELIVERY.md#repository-and-signing-safety).
2. Read the selected preparation and its separate execution owner. Preparation's
   `native_admitted: false` means preparation grants no admission; it does not claim
   that no runner exists. The generated execution summary is a recorded observation,
   not a live process check. If a record changes during reading, reread its current
   owner and references before doing dependent work.
3. For an existing sitting, read its exact plan, admission, consumed claims,
   supervisor/driver receipts, terminal summary and cleanup evidence. Resolve paths
   from those records. Do not reuse a remembered URL, PID or tool session.
4. Correlate the recorded controller/worker PIDs with fresh process inventory,
   process start identity and the exact plan/run/output paths. An agent called
   `Root`, an unchanged PID or a reachable instruction page alone is not ownership.
   If the original controller is alive, retain its ownership and do independent work.
   Do not launch a duplicate, signal its children or compete for the build lane.
5. A resumed controller may continue only its existing unexpired admission. If the
   process ended or the clock closed, preserve the consumed attempt. Verify owned
   worker absence and task-only cleanup; record any later restoration separately.
   Do not recreate an active admission or extend a deadline to recover a session.
6. Before new execution, record the controller identity, host, exact plan/run,
   output root and supervisor/process receipts in its execution owner. Claim the
   native/build lane only after the prior controller has handed it over or is
   verified absent and its cleanup disposition is known. A side conversation is
   not a handoff. If ownership is ambiguous, continue independent preparation.

The current automatic SwiftUI family is local-mapper-only. Its access receipt uses
`LOCAL_MAPPER_ONLY_NO_AUTH_REQUIRED`; do not request Datadog login for this family.
Other families use their own declared backend preflight. Human input or an OS
authentication prompt remains a real prerequisite, never implied by old readiness.

## Recover the consequential reviewer

The stable responsibility is **rum-runtime-reviewer**: independently review exact
source/plan/controls, ownership and lifecycle invariants, source/product/helper
bindings, supported input observations, negative controls, evidence persistence,
stop/cleanup behavior and scope limits. Require disposition of actionable findings.
The reviewer is not the implementer and does not acquire native/build ownership.

`/root/c06_runtime_plan` is the historical reviewer locator and receipt identity.
Reuse that reviewer if a fresh available-agent inventory resolves it. Its absence
after a restart is not a requirement to ask the user for a new project explanation.
When delegation is authorized and available, the coordinator assigns a replacement
using this brief plus only the affected owning record, plan, diff and controls.
Preserve old reviews verbatim; never impersonate the old reviewer or change an old
review to make new source pass. If delegation is unavailable, continue independent
preparation and retain the missing-review prerequisite.

For a newly prepared automatic-coverage runtime, write `reviewer-assignment.json`
next to `runtime-plan.json` before review. Bind its SHA-256 in the new review:

```json
{
  "schema_version": 1,
  "role": "rum-runtime-reviewer",
  "plan_sha256": "<exact new plan hash>",
  "reviewer": "<actual new reviewer identity>",
  "implementer": "<actual implementer identity>",
  "coordinator": "<actual assigning controller identity>",
  "assigned_at": "<UTC timestamp>",
  "reason": "<why replacement is needed>",
  "previous_reviewer_available": false,
  "availability_evidence": "<fresh inventory observation and its location>",
  "scope": "REVIEW_ONLY_NO_NATIVE_OWNERSHIP"
}
```

The review retains its usual verdict, plan/control hashes and findings, with
`reviewer` set to the actual identity, `reviewer_role: "rum-runtime-reviewer"`, and
`reviewer_assignment: {"path": "reviewer-assignment.json", "sha256": "<hash>"}`.
The [assignment validator](../../../tools/multi-scene/acceptance/reviewer_assignment.py)
rejects changed/foreign assignments, self-review and missing availability evidence.
The automatic runtime freezes this helper with its other Python dependencies and
checks the assignment both at admission and when reusing a completed sitting.
The assignment records provenance; it is not authentication or a PASS verdict.

Frozen historical runners retain their original reviewer checks and receipts. Do
not patch their copies or rebuild products for this migration. When another family
needs a replacement reviewer, adopt the same validator in a fresh helper snapshot,
retain its exact verdict/plan/control checks, run focused controls and review the
new binding before admission. Old identity checks on historical evidence remain.

## Recover artifacts and the next executable step

Owning records bind artifacts by hash; many live under the local
`dd-sdk-ios-extractions/evidence` tree outside Git. A checkout alone does not contain
all runtime evidence, built products or dependency caches. Check the required
references before promising that a task can execute:

```bash
python3 -B tools/multi-scene/restart_artifacts.py \
  --owner DatadogRUM/MultiSceneSupport/Results/S2-coverage-remaining-preparation.json \
  --pointer /current
python3 -B tools/multi-scene/restart_artifacts.py \
  --owner DatadogRUM/MultiSceneSupport/Results/S3-H10-background-preparation.json \
  --pointer /native_session/build
```

This read-only check verifies selected file references, not their transitive
closure, binary identity or live access. It prints no artifact contents. Follow
the selected plan's own `verify` command for complete helper/source/product checks.

If an evidence tree moved, provide `--map-root OLD=NEW` to inspect its relocated
copies without editing frozen references. Matching bytes can be recovered from the
original evidence directory or its backup. Record the mapping in a new recovery
receipt and verify the full selected closure before using a fresh runtime. Never
rewrite original hashes, admissions, failed outcomes or temporary tool paths to
make a relocated run appear current.

If evidence is missing or changed, retain that result. Reconstruct source and new
preparation from the selected Git revision and checked-in renderer where possible;
new products need new identity/qualification receipts. Lost native evidence cannot
be rebuilt from prose or a synthetic replay. Continue the cursor's independent task
while an actual external artifact prerequisite is unavailable.

The selected S2 next step is described by its current execution result and the
[automatic-coverage procedure](../../../tools/multi-scene/automatic-coverage/README.md).
Reuse accepted products; a stopped mechanism needs its reviewed correction before
another invitation. H10's source preparation and compile recipe is in
[isolated backgrounding](../../../tools/multi-scene/acceptance/docs/H10.md#renderer-compile-recipe).
Neither recipe authorizes a native launch or changes a release gate.

[Implementation and offline validation](../Results/restart-recovery-20260930.json)
record the recovery changes; native qualification remains with each scenario owner.
