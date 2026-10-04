# S2/S3 execution improvements — 4 October 2026

Status: implementation resumed by the user on 4 October. Current P1–P5 state and decisive evidence are owned by [implementation progress](Results/execution-improvements-20261004.json).

This document preserves the five proposals reviewed in the side conversation and converts them into bounded implementation tasks. It does not change any release verdict or qualify an SDK build.

## User direction and checkpoint handoff

The user explicitly requested:
1. Save these proposals and their implementation plans for the main session.
2. Ask the main session to finish its current task, perform a safe checkpoint, and pause.
3. On the user's manual restart, continue with implementation of this improvement plan.

This later direction authorizes the described P1–P5 work on manual resume; do not ask again for approval of the same bounded work. Material additions, new product decisions, or acceptance changes beyond these proposals still require the user's review. Public API approval and physical-Duo release acceptance remain separate.

The main session owns its live cursor and Git checkpoint. The side conversation adds only this file; it must not edit the cursor, stage other work, interrupt native workers, or change SDK repositories.

At the next safe checkpoint, the main session must:
- Finish only the finite task already in progress and its necessary evidence preservation/cleanup. Do not start a new platform, SDK slice, experiment, or human session merely to continue the old queue.
- Preserve original verdicts and any separate restoration; record unfinished review honestly rather than expanding work to make it pass.
- Record current source repositories, branches, HEADs, signatures, dirty paths, and actual worker/device ownership.
- Add this document to the restart reading order in .continue-here.md. Make P1 the next selected task on manual resume; the former platform/PR6 queue becomes backlog to reconcile under P1/P5.
- Include this file and the narrow checkpoint updates in explicit path-limited commits. Preserve all user-owned files, sign when available, retain the authorized local unsigned fallback, and never push.
- Pause after the checkpoint. A heartbeat or a message reporting this handoff is not the user's manual resume.

## Where the SDK work exists

Verified on 4 October 2026:

| Repository | Branch | Verified HEAD | Role |
| --- | --- | --- | --- |
| /Users/valentin.pertuisot/work/dd-sdk-ios | valpertui/multiple-windows-scenes | f4faf99c76ae6a1534cae11949ee52dc57dbb8ff at handoff inspection; main session remains active until its checkpoint | Main plan, evidence records and historical project branch |
| /Users/valentin.pertuisot/work/dd-sdk-ios-extractions/evidence/rum-continue-20261003-fp13e2hd/worktree | valpertui/s3-handoff-activation | e1b6d5e5af36bbbad48ee74dccf7675f86376b9a | Current rebuilt, feature-flagged S3 SDK source |

At the original handoff, the SDK directory was a separate Git repository with its own .git directory, and its commit objects were absent from the main repository. On 4 October, the user explicitly requested linking it to the main checkout. It is now a registered worktree on `valpertui/s3-handoff-activation`; its history is visible from the main repository. Both detached fixture worktrees were registered with their files and indices preserved. The original Git metadata and verification receipt are retained under `rum-continue-20261003-fp13e2hd/git-link-main-20261004-cycle1/`. This metadata linkage did not merge branches or resume execution. The [delivery inventory](Results/git-delivery-worktree-inventory.json) also records the four earlier S3 source branches, now linked at the user’s request, and the already-linked S2 source. Create future PR-source checkouts with `git worktree add` from the main repository.

The audited SDK range is 2d3de2170248c386a5e7f7de4477ecd703e0c504..e1b6d5e5af36bbbad48ee74dccf7675f86376b9a:

| Commit | Paris commit time | SDK work |
| --- | --- | --- |
| 06e87120c | 3 October 06:59 | Private monitor scene snapshots and target routing |
| 8cd7793d3 | 3 October 09:28 | Private scene-owned view handling |
| 4dea98a95 | 3 October 13:38 | Scene handoff activation and feature registration |
| 1d2846f71 | 3 October 15:30 | Core ownership within synchronous execution |
| aefa2f108 | 3 October 16:57 | Core ownership across asynchronous operations |
| 7ef091c48 | 3 October 18:18 | Callback ownership across task/main-thread boundaries |
| b19953812 | 4 October 02:54 | Scene ownership for automatic UIKit actions |
| e1b6d5e5a | 4 October 06:13 | Continuous scroll ownership across navigation |

The net range changes 22 production files (+2733/-195 lines) and 10 test files (+4324/-8 lines). This is implementation evidence, not a completion percentage or release qualification.

Read-only inspection:

```sh
git -C /Users/valentin.pertuisot/work/dd-sdk-ios-extractions/evidence/rum-continue-20261003-fp13e2hd/worktree log --oneline 2d3de2170248c386a5e7f7de4477ecd703e0c504..e1b6d5e5af36bbbad48ee74dccf7675f86376b9a
git -C /Users/valentin.pertuisot/work/dd-sdk-ios-extractions/evidence/rum-continue-20261003-fp13e2hd/worktree diff --stat 2d3de2170248c386a5e7f7de4477ecd703e0c504 e1b6d5e5af36bbbad48ee74dccf7675f86376b9a
```

P1 must keep this source-location map visible. The explicitly requested local linkage is complete; do not merge, relocate, delete or publish the SDK worktree merely to improve visibility. Preserve the actual source before any separately reviewed promotion.

## Assessment baseline

Audit window: approximately 2 October 15:20 to 4 October 15:20 Paris time.

- S2: 21 of 27 required gates closed; six remain open. No gate status changed in the window.
- S3: 47 of 73 required gates closed; 21 open, four environment-blocked, one review-blocked. No gate status changed. Historical closed evidence does not automatically qualify the rebuilt flagged source.
- S3 gained the eight substantive SDK commits above. PR4/PR5 private components and substantial PR6 components qualify; PR4/PR5 exclusive-Off obligations and later delivery work remain.
- The main branch range f797dd182054726138556a38a4f6757d88676fca..5b1d7f5986c12cc68bbc020287a580fb3c330acb contains 48 commits: 47 documentation/results-only, one also changing the reporting tool. Source work occurred in the separate repository.
- S2 remains three delivery items: one SwiftUI split candidate for C09/C10/H14; one UIKit transition candidate against the accepted physical baseline for H11/H13; F06 final review.
- The latest SwiftUI candidate stopped before app launch because supported Start missed its cutoff. The actual tool service recorded zero invocations. The replacement prearmed service has offline review, not native composition qualification.
- Two macOS build commands succeeded in about 38 seconds combined. Evidence parsing rejected legitimate compiler output; saved-output corrections and independent review qualified the component without rebuilding.
- These observations establish orchestration problems and real source progress. They do not prove a time-waste percentage or a newly reproduced SDK regression.

Owning records:
- [Remaining work](REMAINING_WORK.md)
- [Release register](release-gates.json)
- [S3 delivery progress](Results/S3-F12-delivery-progress.json)
- [Current PR6 owner](Results/S3-PR6-action-preparation.json)
- [Stopped SwiftUI candidate](Results/S2-swiftui-split-candidate-20261003.json)
- [Reviewed prearmed service](Results/S2-prearmed-owner-preparation-20261003.json)
- [Physical UIKit continuation](Results/S2-H11-H13-local-continuation.json)

## Execution sequence and scope limits

1. Implement P1 first.
2. Finish P2 for the two remaining S2 paths, then offer the smallest needed session only after actual readiness. The user still supplies fresh availability; approval of this plan is not a gesture, unlock, login or device-readiness acknowledgement.
3. Complete each remaining S2 behavioral item and F06 when its evidence is sufficient. Do not make S2 wait for S3 implementation or a broad tooling rewrite.
4. Advance P3 and useful P5 work when human prerequisites are unavailable. Apply P4 at normal checkpoints instead of making it a separate migration campaign.
5. Preserve accepted source-matched suites and scenarios. No repeat experiment without a missing existing gate assertion, a changed consequential mechanism, or a reproduced regression.

Retain exact event attribution, View/Navigation/Action capture, scene/window binding, source/product/run identity, evidence integrity, lifecycle/lifetime safety, and task-only cleanup. No retrospective deadline extension, fabricated observation, silent verdict rewrite or automatic conversion of missing evidence to PASS.

Strict timing/performance campaigns, optional networking benchmarks, unrelated CI flakes, general split/tab tracking redesign and Session Replay content correctness remain excluded. Required compile/platform compatibility and concrete Off footprint/lifetime checks remain legitimate. API review and physical-Duo release acceptance remain explicit external boundaries.

## P1 — Make the remaining work executable and prevent scope expansion

Owner: main implementer; user reviews material acceptance/product changes.
Dependency: none.
Status: implemented; validation and independent review are recorded in the owning implementation progress.

Scope:
- release-gates.json and owning result records.
- Results/S3-F12-delivery-progress.json.
- Existing tools/multi-scene/release_checklist.py and release_work.py only where generation needs correction.
- Generated PLAN.md/REMAINING_WORK.md and the restart cursor, preserving hand-authored sections.

Steps:
1. Reconcile each open item with its current owner and accepted evidence. Record the exact missing assertion, required source, reusable evidence, smallest next action, owner, dependency and environment.
2. Resolve S2 to the three delivery items above. Reuse closed UIKit, Resource/Trace, WebView, app, hosting and SwiftUI-transition evidence. No expanded device/build cross-product.
3. Expose existing PR1–13 progress under F12 using distinct implementation, component, Off and integration states. Do not change F12 to CLOSED because several components pass.
4. Classify obligations as release-blocking, required before merging the affected slice, or optional diagnostics. Reconcile leftover performance wording with the approved measurement rule. Preserve concrete ownership-state/lock/allocation/lifetime requirements; do not introduce a timing campaign.
5. Audit stale environment labels and source applicability. A currently available simulator does not automatically close a gate; reused historical evidence must retain its actual source and limitations.
6. Add a concise source-location map to active progress: repository, branch, HEAD, release/slice, evidence scope and promotion status. This makes isolated SDK work discoverable.
7. Require each newly selected task to name its existing gate or necessary dependency, expected new evidence and finite exit. Disallow open-ended preparation sequences.
8. Regenerate derived views once after the reconciliation and review any acceptance changes before relying on them.

Validation:
- Focused existing generator/consistency tests plus controls for contradictory states, stale source references and missing required fields.
- Verify hand-authored PLAN decisions remain intact.
- No native run, build, SDK edit or release closure merely to implement P1.

Exit:
Every unfinished item has one unambiguous next action; S2 has no added campaign; implementation progress and release readiness are reported separately.

## P2 — Qualify the full human-session path before requesting human time

Owner: harness implementer and designated independent reviewer.
Dependency: P1 acceptance boundaries.
Status: composition implemented and reviewed; the single automatic qualification stopped before tool dispatch. The path remains stopped; no human invitation is qualified.

Scope:
- Existing automatic-coverage human_rum_only_runtime.py, human_supported_readiness/continuation and foreground capture/finalization paths as needed.
- Exact currently reviewed prearmed owner service from its owning record.
- Existing interactive-transitions physical_setup/runtime/capture/cleanup path, limited to the missing UIKit candidate.
- No wholesale runner replacement and no changes to accepted historical bindings.

Steps:
1. Inventory which corrections already exist. Reuse reviewed prearmed Start/End, request lineage, quiescence, terminal anchor and saved finalizer pieces; change only actual composition gaps.
2. Prove that the real supported tool can start, return and persist observations, end, seal readable evidence and clean up. Offline controls alone cannot establish this.
3. Separate preparation, operator readiness and actual scenario execution. Waiting for a page or user reply must not consume the scenario allowance. Keep finite operation/cleanup bounds issued for their operation; never extend an expired attempt. Any idle overall reservation must be clearly operational, not an SDK timing assertion.
4. Resolve device/orientation/window/build readiness before invitation. Apply the already-reviewed physical orientation preparation before the first gesture.
5. Seal terminal local evidence before uninstall. Grade the saved terminal inventory and matching receipts; do not read a removed app's live Documents during finalization.
6. Preserve scenario, evidence and cleanup verdicts independently. Required missing evidence or cleanup still prevents overall acceptance. Keep original failures and separate restoration immutable.
7. Provide one canonical prepared route for each remaining S2 candidate. Reuse baselines and accepted cells; do not replace an ownership oracle with input-proof heuristics.
8. After qualification, invite the user only for the selected residual cell. Human input is never a debugging dependency for unqualified bootstrap code.

Validation:
- Focused negative controls: delayed/stale/duplicate readiness, consumed responses, wrong request/run/window, missing Start, missing terminal rows, publication failure, teardown ordering and interrupted input.
- One bounded automatic native qualification for the changed mechanism, with no user gestures. Use an already-planned cell's automatic bootstrap when it can establish the same complete contract.
- Reuse qualification when relevant source/tool/schema bindings remain unchanged; do not create a rehearsal before every sitting.

Exit:
A complete capture-to-grading/cleanup path works before the next invitation. The SwiftUI candidate can supply C09/C10/H14 and the physical UIKit candidate can supply H11/H13, subject to actual semantic results.

Failure policy:
If the mechanism fails its one native qualification, stop that automated path. Preserve the concrete discriminator and use the documented supported alternative; do not begin another equivalent diagnostic sequence or consume human time.

## P3 — Reuse a small build/test qualification path

Owner: tooling implementer and designated reviewer.
Dependency: P1; independent of human availability.
Status: implemented and qualified by the required visionOS build and independent actual-output review; accepted macOS output also passes saved replay. Compilation credit only.

Scope:
- Existing build/test orchestration and actual-output consumers used by current PR6 platform work.
- Start with the next unconsumed platform check after the checkpoint.
- Do not migrate every frozen helper or historical experiment.

Steps:
1. Extract the stable execution/capture/cleanup behavior into one reviewed mechanism parameterized by source, target, platform, command and outputs. Keep platform-specific interpretation small.
2. Use actual saved successful output as positive parser fixtures. Do not invent framework layouts or require an incidental printed flag where authoritative equivalent evidence proves the contract.
3. Preserve exact source/compiler/target/product/result identity. Normalize only supported aliases or documented representation differences; never normalize different deployment targets, architectures or owners into equality.
4. Report all independently detectable saved-output problems in one offline pass, then correct and replay the capture without native repetition.
5. Keep command success separate from evidence completeness. A parser stop is not an SDK compilation failure.
6. Rebuild only when required evidence was never captured, inputs changed, or a reproduced compiler/runtime defect requires a rerun.
7. Reuse current source freezes and accepted artifacts. Validate current changed bindings at meaningful admission/publication boundaries instead of inventing another full proof format.

Validation:
- Actual saved macOS output passes.
- Wrong source, platform, target, product, missing required input/object, failed command and incomplete publication fail.
- Harmless supported compiler spelling/forwarded-argument differences pass.
- The next required platform build supplies the native check; no extra demonstration build.
- Any genuine platform deployment-floor difference remains explicit and cannot be dismissed as formatting.

Exit:
The next supported platform runs through parameters and a bounded adapter, without a new bespoke controller/proof/review chain. Existing build scripts may be changed only within this approved scope, with focused verification.

## P4 — Review consequential changes and reduce repeated administration

Owner: main implementer and designated reviewer.
Dependency: P1; apply during ordinary checkpoints.
Status: implemented and reviewed for bounded platform parameter-only eligibility. This grants no new native authority or deadline extension.

Scope:
- Existing reviewer assignment/manifest validation.
- Owning result publication and derived progress views.
- No mass documentation migration.

Steps:
1. Define consequential changes requiring independent review: SDK behavior, ownership/lifetime, swizzling, acceptance assertions, command/device scope, process control and cleanup.
2. For unchanged reviewed execution code, validate new run parameters against an approved schema and allowed scope. A timestamp/output directory alone does not require a new design review.
3. Bind approval to code and policy identity. Expanded effects, changed source interpretation or weaker assertions invalidate eligibility and require review.
4. Give one complete review packet: consequential diff, contract, real positive evidence, focused negative controls, native plan and limitations. Request a consolidated finding set.
5. When a reviewed positive case fails because its fixture was unrealistic, repair the fixture/review method, not only the individual receipt.
6. Write facts once to their owner. Generate summaries at meaningful checkpoints; retain history without repeating its narrative in every active instruction.
7. Report gates closed, delivery units completed, invalid attempts and the exact next blocker. Include repository/branch/HEAD whenever SDK source work occurred outside the main checkout.
8. Preserve meaningful safe checkpoints and explicit path commits; do not replace them with a growing chain of commits for unchanged preparation.

Validation:
- SDK/oracle/lifecycle/cleanup changes invalidate previous eligibility.
- Permitted parameter-only changes retain eligibility.
- Wrong scope or source cannot borrow an older review.
- Derived status agrees with owner state and distinguishes preparation, native qualification and release acceptance.

Exit:
Routine runs reuse reviewed machinery while consequential changes retain independent scrutiny. No new reviewer-policy automation may silently approve a broader task.

## P5 — Complete S3 through finished slices and bounded qualification

Owner: SDK implementer and independent reviewer; API reviewers own F01.
Dependency: P1; P3/P4 help execution but must not become an indefinite prerequisite.
Status: PR4/PR5 exclusive-Off fixture implemented in linked verification copies; native comparison and final review remain.

Scope:
- Existing PR1–13 rebuilt feature-flag delivery chain and its tests.
- Existing product decisions and exclusions.
- No public API promotion, new dependencies, networking wire change, push, or physical-Duo equivalence claim granted by this plan.

Steps:
1. Finish the identified PR4/PR5 exclusive-Off obligations and define one finite PR6 exit packet. Preserve accepted source-matched suites and component results.
2. In that packet, cover actual automatic-input integration, genuine attached ownership, relevant construction/failure safety, required platform/minimum-compiler boundaries and remaining Off contract. Explicitly separate optional performance campaigns.
3. End each slice with implementation, affected tests, Off evidence, independent review and an updated delivery status. Do not accumulate several implemented slices with unowned qualification debt.
4. Proceed PR7→PR8 through a concrete ownership path: work starts under A, B becomes current, completion/downstream telemetry keeps the captured A owner. Apply the fixed family contracts to Trace/Logs/Flags/WebView without changing wire policy.
5. Proceed PR11→PR12 through SwiftUI navigation, semantic hosts and scene lifetime. Retain source ownership at the exact final candidate rather than testing a superseded prototype extensively.
6. Complete PR9's representative crash/watchdog context and PR10's Operations/Profiling contracts when their declared dependencies are ready. Use separate file ownership only if authorized and without competing native lanes.
7. PR13 public Swift/Objective-C promotion remains dependent on F01 approval. Continue authorized private/internal implementation meanwhile.
8. Select tests from changed behavior and platforms. Preserve required per-PR checks for the shipped stack; batch unchanged full-suite/platform obligations only after explicitly reconciling the policy under P1.
9. Run final native S3 acceptance against the frozen rebuilt flagged source; historical prototype results remain references, not automatic current-head credit.

Validation:
Each slice demonstrates the declared On behavior, agreed Off behavior, lifetime/crash safety and relevant compatibility. Final integration joins the slices. Public API approval and physical Duo F04 remain explicit external release prerequisites.

Exit:
Completed delivery units advance F12/F13; private component progress is visible without pretending it closes S3 release gates.

## Completion reporting

For each P1–P5 checkpoint report:
- What changed and why it affects an existing release gate.
- Exact source repository/branch/HEAD, changed task paths and review.
- Decisive validation performed; identify replay, native run and backend query separately.
- Gates or delivery units actually completed.
- Remaining blocker and smallest next task.

Do not add another experiment solely to execute these process improvements. Record them under this plan and the existing owning gate/result unless a new reproduced regression requires a separate experiment.

