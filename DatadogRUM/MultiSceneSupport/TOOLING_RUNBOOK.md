# Multi-scene RUM tooling runbook

Start with [the restart cursor](../../.continue-here.md), the affected gate and its
owning record. Read the common rules below, then only the procedure needed for the
task. This entry point does not admit an experiment or resume paused execution.

The [assessment](ASSESSMENT.md) describes supported behavior. The
[register](release-gates.json) owns release obligations and evidence, and
[PLAN](PLAN.md) is its generated checklist. [Remaining work](REMAINING_WORK.md)
joins current preparation with the open gates. Exact commands, inventories, budgets,
run IDs and results belong to the owning experiment or fixture README.

## Choose a procedure

| Task | Read |
| --- | --- |
| Recover execution ownership, reviewer assignment or missing artifacts after restart | [Handoff recovery](Tooling/RESTART.md) |
| Reconnect tools; qualify Xcode/runtime/device/authentication or app configuration | [Environment and access](Tooling/ENVIRONMENT.md) |
| Freeze sources; build/test targets, collect XCTest or check public clients | [Builds and tests](Tooling/BUILD_TEST.md) |
| Install, sign a physical app, deliver native input, prove topology or clean up | [Device interaction](Tooling/DEVICE_INTERACTION.md) |
| Define an oracle, classify an attempt, retain artifacts or reuse evidence | [Evidence contracts](Tooling/EVIDENCE.md) |
| Check semantic navigation, lifetime, Resource controls or automatic-only coverage | [Scenario discriminators](Tooling/SCENARIOS.md) |
| Query RUM/APM/Logs/Profiles and join exact owners | [Backend acceptance](Tooling/BACKEND.md) |
| Extract a packet, sign, review CI or publish within authorization | [Delivery and CI](Tooling/DELIVERY.md) |
| Update a gate, checkpoint or procedure; validate documentation | [Documentation maintenance](Tooling/DOCUMENTATION.md) |

These pages are independent task references, not a new mandatory reading sequence.
Follow a linked fixture README only for its named family. Search the
[experiment index](EXPERIMENTS.md) for a specific historical result; do not load the
frozen archive to resume ordinary work.

## Common rules

Apply the [project measurement rule](../MULTI_SCENE_SUPPORT.md#measurement-and-testing-rule)
to every future session: event attribution and View/Navigation/Action capture are
the acceptance targets. Strict timing measurements are diagnostic; operational
timeouts bound work and cleanup without independently implying an SDK regression.

1. **Preserve workspace state.** Verify actual branch, HEAD/signature and index/work
   tree. The cursor lists protected paths. Use explicit individual staging and
   commit paths, never `git commit -a`. Configuration use is authorized when needed;
   preserve its bytes/index and exclude values from logs and public commits.
2. **Bind work to a finite gate.** Admit an experiment only for an existing gate or
   reproduced regression. Freeze candidate/stage, inputs, decisive assertions,
   inventory, environment, attempt limit and execution/cleanup budget before use.
3. **Keep one native/build owner.** Prepare before taking the host lane. Reuse the
   designated reviewer for consequential concurrency/lifetime/oracle changes; routine
   bookkeeping corrections do not need another design chain. Avoid competing work
   during measurements.
4. **Rediscover execution access.** A configured MCP server is not useful access.
   Verify live Xcode/workspace/destination and family-specific Datadog reads. Old IDs
   and evidence paths do not authorize a fresh run.
5. **Freeze and verify identity.** Match exact source paths/bytes, helpers/dependencies,
   compiler membership, runtime, all built/installed Mach-O files and process/run ID.
   A manifest label, launcher stub or matching count alone is insufficient.
6. **Prove boundaries before work.** Clean install requires observed container
   absence. Physical H06 has a [scoped freshness/cleanup alternative](../../tools/multi-scene/acceptance/README.md#h06-physical-cleanup-disposition)
   that must qualify before use. Native readiness, live ownership and required topology precede the
   critical API interval; later assertions cannot repair a missed boundary.
7. **Keep the oracle strict.** Require exact owners, event identities, counts,
   values, ordering and complete inventories. Preserve negative controls for stale
   state, consumed readiness, restored run IDs and late assertions. A backend match
   cannot rescue a failed local contract.
8. **Retain every attempt.** Save raw evidence before parsing/cleanup. Distinguish
   FAIL, INVALID, INCONCLUSIVE and unexecuted work. Never edit an old failure into
   PASS or silently extend a closed deadline.
9. **Reuse accepted evidence.** Check original source/build/oracle identity and
   scope. Do not rerun accepted tests merely to resume, reconnect, rename a test or
   sign identical source. Different candidates need explicit evidence mapping.
10. **Finish with cleanup and one durable summary.** Reap owned children, prove app/
    process/container absence (or the explicit physical H06 disposition) and restore
    temporarily changed state. Keep a later
    cleanup proof separate from an earlier failed receipt.

Local commits need no prefix and may be unsigned under the project's
[commit authorization](Tooling/DELIVERY.md#repository-and-signing-safety). Re-sign and verify all outgoing history before a separately
authorized push. This project does not infer publication, merge or TestFlight
permission from a completed experiment.

## Reasoning effort recommendations

Recommend effort for the next meaningful decision at task selection, a phase change,
new substantive uncertainty, or the end of a difficult investigation. Do not assess
individual tool calls or default the whole project to max/ultra.

| Effort | Phase | Next change |
| --- | --- | --- |
| Low | Settled bookkeeping, formatting and documentation | Raise for a substantive inconsistency. |
| Medium | Prepared build/test execution, evidence and routine compiler corrections | Raise for unexplained behavior or an unsettled oracle. |
| High | Bounded implementation, compatibility or regression diagnosis | Lower to Medium when decisions and assertions are settled. |
| xhigh | Cross-module ownership, asynchronous lifetime, reentrancy or consequential safety review | Lower to High for implementation or Medium for prepared execution. |

Announce the recommendation once when activated or materially changed, including
its reason and downgrade condition. Continue without waiting for acknowledgment or
a settings change. Announce downgrades too; do not repeat an unchanged recommendation
after restart. Restore phase, reason and last notice from the cursor at normal
checkpoints. If current settings are unknown, state only the recommendation; never
poll settings or change model/effort automatically. Recommend another model only
for a concrete capability need. Existing review requirements still apply.

Effort alone never blocks work. Hold only an affected action whose concrete unresolved
correctness decision prevents a defensible next step; name the decision, considered
evidence and unsafe assumption, then continue independent safe work. A slow tool,
input failure or failing test alone does not prove insufficient effort. Settings
changes replace neither evidence nor review and renew no deadline or retry authority.

## Repeatable acceptance workflow

Use [the existing harness](../../tools/multi-scene/acceptance/README.md), selecting
its named scenario and preserving prior contracts. A complete attempt connects:

1. Admitted definition, positive/negative oracle controls and source freeze.
2. Actual environment/authentication preflight and complete selected test inventory.
3. Fresh output/run identity, clean installation and installed-code proof.
4. Native scenario, accepted owners and precritical topology/readiness receipts.
5. Strict local assertions, complete backend inventory and exact ownership joins.
6. Cleanup, durable artifacts, verdict and an evidence-based gate update.

Keep the driver asynchronous while serving requests. Inspect every settled backend
response, preserve fulfilled siblings on failure and include decoding, persistence
and assembly in the phase deadline. Counts or a late response are not acceptance.
The source/build/native/backend/cleanup components keep their independent limits.

## Evidence levels

[Evidence contracts](Tooling/EVIDENCE.md#evidence-levels) distinguish source review,
deterministic tests, mounted/native behavior, backend persistence and physical
proof. Callback counts and no crash alone do not establish semantic ownership.
Posted disconnects, logical peers and serial scenes do not prove simultaneous
visibility or physical OS ordering. Simulator evidence stays within measured
[Duo fidelity limits](DUO_SIMULATOR_ASSESSMENT.md).

## Full-target platform compatibility checks

Use [the target procedure](Tooling/BUILD_TEST.md#full-target-platform-compatibility-checks):
freeze each architecture's actual compiler membership and discover exact selected
tests before assertions. Require finalized results, explicit skips/exclusions,
public-client/API evidence and source-matched warning dispositions. A directory
count, console PASS or a not-run target cannot substitute.

## Scope and stop rules

- Session Replay scope is host-app crash safety and non-disruption to other SDK
  features. Do not test or repair captured-content correctness or require a full
  Replay capture suite. Preserve historical failures without relabeling them.
- Strict timing measurements and application-performance campaigns are not release
  prerequisites. Focus sessions on event attribution and View/Navigation/Action
  capture; preserve historical [baseline evidence](BASELINES.md) without requalification.
- Current CI remains required. Repair flakes only when evidence links them to our
  changed surface or associated tests; check upstream fixes before duplicating work.
- Deployment compatibility, runnable older-system coverage, Duo simulation and
  physical acceptance are separate. A different environment cannot silently close
  the required one. FBC is Flutter-only downstream.
- Native input without the expected effect, semantic boot failure and unfinalized
  XCTest are not SDK acceptance. The user's [5 October directive](Results/attempt-policy-20261005.json)
  removes attempt caps for the authorized work. Start each retry as a fresh bounded
  run, preserve skipped arms and prior verdicts, and never extend an old deadline.
  Repaired prerequisites and consequential changes still need current evidence and review.
- When desktop/device access fails, retain and clean the partial run, request the
  missing prerequisite once and continue independent work. Caffeinate requires a
  user-authorized duration and cannot unlock an existing lock.
- On pause, release the host lane, preserve reviewed preparation and close the old
  deadline. Only the cursor states the next action; this runbook never renews it.

## Documentation reading and update workflow

[Documentation maintenance](Tooling/DOCUMENTATION.md) defines each fact's owner,
minimal checkpoint updates and checks. Update detailed results once, adjust support
or review conclusions only when they change, and regenerate derived views when
their register or preparation-owner inputs change. Completed narratives do not
belong in this router or the cursor.

Run the documentation check from the repository root:

```bash
python3 -B tools/multi-scene/release_checklist.py
```

Use `--update` when a register or current-owner change requires regeneration. The checker includes
all procedure links, router coverage, compact-entry limits and experiment-index
ownership. The [migration map](Results/documentation-migration-exp220.json) and
[non-frozen historical checkpoint](Experiments/DOCUMENTATION_CHECKPOINT_EXP-220.md)
preserve the consolidation's provenance; neither is routine restart reading.
