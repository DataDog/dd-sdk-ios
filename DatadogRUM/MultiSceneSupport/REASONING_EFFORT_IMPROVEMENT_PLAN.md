# Reasoning effort usage improvement plan

Date: 7 October 2026.
Status: implemented after signed checkpoint 4a4a9b40c on 7 October 2026. This advisory policy changes no native admission or release gate.
Owner: main session, Resume multi-scene RUM work.

## Objective and requested order

Help the user choose quicker reasoning settings for routine work and increase effort when the next decision warrants it. Recommendations are advisory and must not create a new approval loop or stop otherwise executable work.

The user requested this order:

1. Finish the current bounded task and all owned cleanup. If an existing prerequisite prevents completion, record the exact blocker and reach a safe checkpoint; do not extend an active deadline or claim unfinished work complete.
2. Perform a safe checkpoint using the current project rules, preserving all user-owned and parallel work. Commit explicit task paths, sign when available and retain the authorized local unsigned fallback. Do not push.
3. Implement this improvement plan as a small documentation/workflow change.
4. Resume authorized S2/S3 work with the advisory policy active.

Do not interrupt an active native scenario to implement this plan or grow the current task merely to defer the checkpoint. Re-read the authoritative cursor at implementation time; examples below do not select a new SDK task.

## Recommendation policy

Assess effort when selecting a bounded task, changing work phase, encountering a substantive new uncertainty, or completing a difficult investigation. Classify the next meaningful decision rather than the entire experiment, PR or release. Do not assess every tool call.

| Recommended effort | Typical phase | Downgrade or escalation condition |
| --- | --- | --- |
| Low | Mechanical bookkeeping, formatting, known documentation updates and expected artifact checks | Escalate if an inconsistency requires investigation or a substantive decision. |
| Medium | Reviewed build/test execution, evidence collection, routine project membership and straightforward compiler corrections | Escalate for unexplained behavior, an unsettled oracle or a consequential implementation decision. |
| High | Bounded implementation, oracle design, compatibility analysis and concrete regression diagnosis | Return to Medium when the decision and assertions are settled and only execution remains. |
| xhigh | Cross-module ownership, asynchronous lifetime, reentrancy, semantic navigation and consequential independent safety review | Return to High for bounded implementation or Medium for prepared execution after the difficult contract is resolved. |

These are task-based recommendations, not measured guarantees of model capability. Do not default the entire project to max/ultra. Recommend a more capable model only when there is a concrete reason beyond additional effort; never change model or reasoning settings automatically under this policy. Existing designated-reviewer requirements remain unchanged.

## User-facing behavior

- Give one concise commentary notice when the recommendation changes materially, preferably before entering the new phase. Announce the current recommendation once when the policy is first activated.
- Include the recommended level, the concrete reason and the condition for returning to a lower level. Say whether work continues or one named step is blocked.
- Continue without waiting for an acknowledgment, a settings change or a permission response. An ignored recommendation does not remove existing authorization.
- Avoid repeated reminders at the same level, including after compaction or restart. A changed task with the same effort normally needs only its ordinary progress update. Clarify separately if a recommendation becomes a concrete blocker.
- Use only reliable current-session information when describing the selected model/effort. If that setting is not available, state the recommended level without claiming the current setting is too high or low. Do not add settings polling or unrelated session-log inspection.
- Announce downgrades as readily as upgrades. Tool wait time, build duration and external prerequisites do not independently justify higher effort.

Example notices:

> Medium recommended: the source decision is settled; the next phase is the prepared build and qualification. Continuing.

> xhigh recommended for the next phase: a deferred callback may outlive its scene owner. Return to Medium once the ownership correction and assertions are reviewed. Continuing the investigation.

## Narrow blocking rule

A High or xhigh recommendation alone is never a blocker. Suspend only the affected consequential action when a concrete unresolved issue prevents a safe, defensible next step. Examples include conflicting ownership interpretations that change customer behavior, inability to distinguish a proposed correction from the reproduced failure, or a lifetime/concurrency change that would require an unsupported assumption.

Name the unresolved decision, the evidence already considered and why proceeding is unsafe. Recommend higher effort where it may help, without claiming that low effort caused a failure or that a higher setting guarantees resolution. If the current setting is unknown, do not infer it. Continue independent safe work while the affected action is held; stop all work only if no safe independent task remains. Preserve existing native cleanup and interruption rules before switching attention.

An input failure, slow tool, timeout, build failure or failing test alone is not evidence of insufficient reasoning. A settings change never substitutes for required testing, evidence or review and does not renew a run deadline or authorize a retry.

## Minimal implementation

1. Add a compact project-specific section to [TOOLING_RUNBOOK.md](TOOLING_RUNBOOK.md) defining phase-based recommendations, non-blocking notices, downgrade behavior and the narrow blocking rule. Keep this reusable policy in one canonical place and respect the runbook size cap. If it must live in a procedure page, expose it through a short common-rule pointer so normal execution discovers it.
2. Add a small hand-maintained entry beside the selected work in the authoritative root cursor. Store only current phase, recommended effort, one-line reason, downgrade condition and last notified recommendation. Update it during normal safe checkpoints; do not create a commit for each notice. Leave generated execution-status blocks and shared work untouched.
3. Ensure normal restart reading reaches that policy and restores the last recommendation. Existing cursor-to-runbook routing may already suffice; add a pointer only where necessary.
4. Do not duplicate effort fields across the gate register, every result and generated PLAN. Do not change release-gate schemas, runners, frozen bindings, build scripts, SDK code or model configuration. Add no automation, polling loop, experiment, approval prompt or reviewer chain solely for this advisory feature.
5. Validate the documentation links and size limits with the existing read-only documentation checker at the safe checkpoint. Regenerate derived documents only if their actual inputs changed. No SDK tests or native run are required for this documentation-only change.
6. Commit the explicit plan/policy/cursor paths at a safe checkpoint, following project signing rules. Report where the rule lives and the first recommendation. Continue authorized project execution.

Cursor entry shape, adapted to the actual phase at implementation time:

- Phase: fixed build/test qualification.
- Recommended effort: Medium.
- Reason: source decision and selected assertions are already reviewed.
- Raise when: valid results expose an unexplained ownership/lifetime issue.
- Last notified: Medium for this phase.

For a High/xhigh phase, replace the raise condition with a concrete downgrade condition. Keep the entry short and within the cursor size limit. It is advisory state, never execution authority.

## Acceptance checks

Review these cases without launching tests or a human session:

| Case | Expected behavior |
| --- | --- |
| Start a prepared build/test phase | Recommend Medium once and continue. |
| Enter a new ownership/lifetime design decision | Recommend High or xhigh with a concrete reason; continue safe investigation without waiting. |
| Resolve that decision | Recommend the lower execution level instead of retaining xhigh indefinitely. |
| User does not switch settings | Continue authorized executable work; no repeated reminder or approval requirement. |
| Current effort is not observable | Report a recommendation without inventing the selected setting. |
| Tool is slow or a fixture fails | Diagnose the actual evidence; do not attribute the failure to reasoning effort. |
| Concrete correctness decision remains unresolved | Hold only the unsafe step, explain it and continue independent work. |
| Compaction or restart at the same phase | Restore the advisory state without restarting tests or repeating the same notice. |

Implementation is complete when the rule is discoverable in the normal main-session flow, the compact recommendation survives restart, these cases are covered by policy, and the first ordinary progress update uses it. This is workflow completion only; it closes no S2/S3 release gate.

## Implementation record

Canonical policy: [runbook recommendations](TOOLING_RUNBOOK.md#reasoning-effort-recommendations).
Restart state: [root cursor](../../.continue-here.md), beside selected work.
First notice: Low for this settled documentation/workflow change; work continued
without acknowledgment or a settings change. Current model/effort was not inferred.
The policy covers all eight acceptance cases above: prepared execution, ownership
uncertainty, downgrade, ignored advice, unknown settings, actual failure diagnosis,
scoped correctness holds and unchanged restart state. No SDK tests are needed.
Validation uses the existing documentation link/size checker; no runner, gate schema,
build script, SDK source, automation or configuration is changed.
