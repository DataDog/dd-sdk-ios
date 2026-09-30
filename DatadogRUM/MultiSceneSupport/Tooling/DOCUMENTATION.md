# Documentation maintenance

Read when updating a checkpoint, procedure or finding. A normal run reads the
[cursor](../../../.continue-here.md), the affected gate/result and only its needed
[runbook route](../TOOLING_RUNBOOK.md#choose-a-procedure). Do not load the frozen
experiment archive unless a specific old experiment is needed.

## One owner per fact

| Document | Owns | Keep elsewhere |
| --- | --- | --- |
| [Overview](../../MULTI_SCENE_SUPPORT.md) | Stable product contract and documentation map | Current execution state and history |
| [Navigation contract](../NAVIGATION_API.md) | Current manual-view and semantic-navigation behavior | Experiment narratives and declaration inventories |
| [Stable API review](../STABLE_API_REVIEW.md) | Canonical Swift, Objective-C and semantic declarations; API approval record | Separate inventories in Guild presentations |
| [Navigation history](../Experiments/NAVIGATION_API_HISTORY.md) | Earlier designs and original experiment observations | Present support status and execution instructions |
| [Register](../release-gates.json) | Finite deliverables, owners, dependencies, decisive tests, environments, release-specific status and proof | Duplicate manually maintained totals |
| [PLAN](../PLAN.md), [progress](../Results/release-progress.json) and [remaining work](../REMAINING_WORK.md) | Generated gate views; remaining work also joins current preparation owners | Completed experiment narratives or hand-maintained totals |
| [Assessment](../ASSESSMENT.md) | Present support conclusions and evidence limits | Detailed run counts, command failures and PR chronology |
| [Cursor](../../../.continue-here.md) | Actual unfinished work, next action, active protections and minimal reading order | Completed delivery narratives or another execution queue |
| [Experiment index](../EXPERIMENTS.md) | Compact ID/gate/status/conclusion/record lookup | Detailed outcomes and run recipes |
| Owning experiment and `Results/` record | Frozen definition, source/artifact identities, attempts, failures, controls, exact results and next bounded continuation | Copies in every active document |
| [Runbook](../TOOLING_RUNBOOK.md) and `Tooling/` | Reusable procedures and discriminators, selected by task | Run identities, expired admissions and completed results |
| [Safety](../PRODUCTION_SAFETY_REVIEW.md), [triage](../REVIEW_TRIAGE.md), [component review](../COMPONENT_REVIEW.md) | Attributable findings, decision rationale, repair evidence and review limits | Release certification or an experiment journal |
| [Delivery queue](../Results/S1-delivery-queue.json) | Per-packet preparation, publication, CI and review | Inferred release-gate closure |

A new experiment must close a named gate or investigate a reproduced regression.
Do not enlarge a telemetry row as work proceeds. Preserve each family's explicit-
target, captured-start or process-fallback completion mode in the register.

## Minimal update at a safe checkpoint

1. Record exact outcomes and artifact identities once in the owning experiment/
   result, keeping every invalid, failed, skipped and unexecuted attempt distinct.
2. Change the relevant release-specific gate only with decisive evidence. Keep
   owner, dependency, test, environment, thresholds and prior evidence limits.
3. Update the index row. Change assessment/review prose only if capability,
   attribution, disposition or an evidence limit changed; link the owner.
4. Add a reusable lesson to the appropriate procedure section, not a new
   experiment-number heading. Update the cursor only with the current next action.
5. Regenerate derived views only if their inputs changed, then run the checks below.
   Documentation-only changes do not call for SDK tests or another numbered experiment.

When interrupted, keep the cursor authoritative. A paused preparation preserves its
hashes/controls and closed deadline; another execution needs separate admission.
Do not turn a completed review into release readiness or a build into runtime proof.

## Consolidation and progressive disclosure

Before removing prose, map its constraints, failure lessons, decisions and evidence
to their canonical owners. Preserve unique original observations in a non-frozen
historical checkpoint. Keep the source revision and old-to-new section map; do not
rewrite detailed experiment shards or load frozen history wholesale.

Keep the runbook as a short router (at most 200 lines/1,800 words), the cursor at
most 85 lines/900 words, the acceptance router at most 180 lines/1,600 words,
and each procedure page at most 320 lines/3,600 words.
These caps protect reading cost; do not evade them with giant lines or code fences.
If a procedure outgrows its boundary, consolidate at a safe checkpoint and route to
an existing fixture README before adding another page. No page is a mandatory read
for every task. Link pages from their runbook or acceptance router; keep compatibility anchors
for links that cannot be updated safely.

Do not copy experiment progress paragraphs between assessment, safety review and
cursor. Review tables may share gate IDs and evidence links; the detailed narrative
still has one owner. Keep user-owned API proposal files untouched unless their edit
is explicitly part of the task.

The [migration map](../Results/documentation-migration-exp220.json) binds the source
checkpoint and each old section to a current procedure/owner. The
[historical checkpoint](../Experiments/DOCUMENTATION_CHECKPOINT_EXP-220.md) preserves
original review findings and removed observations. It is reference material, not
part of routine restart reading. Future edits update current owners.

## Documentation checks

From the repository root:

```bash
python3 -B tools/multi-scene/release_checklist.py
python3 -B -m unittest discover -s tools/multi-scene -p test_release_checklist.py
python3 -B -m unittest discover -s tools/multi-scene -p test_release_work.py
```

After a register or current preparation-owner change, run `release_checklist.py
--update` before the read-only check. It regenerates PLAN, progress and remaining
work; never hand-edit a total. The same
checker validates active links/fragments, finite experiment IDs, ownership guards,
procedure discovery/routing and entry-point size limits. Its controls must reject a
broken deep link, an orphaned procedure, entry-point growth, stale selection and
the superseded active performance requirements. It also rejects preparation
promoted to native credit and unmarked historical admission fields.

Current/history selectors are schema-versioned. Read `current` first; historical
snapshots never authorize execution. The S2 coverage owner's three historical
reader slots remain only for frozen helper compatibility and are hash-bound to its
immutable snapshot. Preserve them until those helper closures are retired. Do not
rebuild prepared products merely to migrate documentation.

For consolidation, separately verify protected paths and unchanged gate/evidence
hashes against the saved pre-edit manifest. Commit only explicit documentation and
checker paths, using [delivery/signing rules](DELIVERY.md#repository-and-signing-safety).
No build, native run, backend query, new dependency or push is implied.
