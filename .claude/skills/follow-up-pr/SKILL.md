---
name: dd-sdk-ios:follow-up-pr
description: Use when following an existing dd-sdk-ios PR through CI, review feedback and human handoff, or through merge when authorized.
---

# Follow up on a pull request

Use `gh` for GitHub operations. Read the [contribution review process](../../../CONTRIBUTING.md#review-process)
for repository policy. Use [open-pr](../open-pr/SKILL.md) to create a PR.

## Establish the scope and current state

Honor the user's requested scope, whether that is one feedback fix or ownership
through merge. Reuse authorization already given; this skill grants no additional
permission to push, contact reviewers, schedule monitoring or merge.

Confirm the PR, base branch, current head and worktree before editing. Reuse saved
work and avoid duplicating an active follow-up. Inspect CI, automatic review runs,
human reviews, conversation comments and all inline threads, including new replies
on resolved threads. Checks and approvals on an older head do not clear a new push.

## Address feedback

Understand the suggestion before editing. Inspect affected callers, tests and
existing patterns. If a direct edit breaks something, investigate alternatives
that preserve the reviewer's intent before reversing the suggestion.

If no option is clearly best, present viable options and tradeoffs to the human
running the loop, usually the PR author. If they cannot choose, ask the reviewer
which they prefer. Keep the disputed item open while the choice is pending;
silence is not a decision. Proceed with clear fixes within the authorized scope.

After each code fix, build affected targets and run relevant tests locally before
committing or pushing. Include test runners and callers outside the edited
directory. Parsing and lint alone are insufficient. Fix failures before publishing.
Use [running-tests](../running-tests/SKILL.md) to select the checks and
[build-and-diagnose](../build-and-diagnose/SKILL.md) when a build fails.
For documentation-only edits, check Markdown, links and any changed skill instructions.

Follow [git-commit](../git-commit/SKILL.md) for scoped, signed commits. Push the
validated changes, then reply and resolve addressed feedback. Explain stale,
duplicate or inapplicable findings before resolving them; never delete feedback
to clear the review. Re-request review only from a human whose findings were fixed,
with a short note about the change and relevant local result.

Keep replies natural and specific, usually one or two sentences. Answer the point,
say what changed and mention the relevant check. Expand when a question or tradeoff
needs it. Keep full logs and validation inventories in the PR body or execution
record rather than repeating them in threads.

## Automatic review and human handoff

Require green CI, including lint and code-quality checks, before leaving draft or
handing off to humans. Only approval-dependent gates such as MergeGate may remain
pending at those transitions. Marking ready starts automated review.

Wait for active automated reviews and address all received findings. Never request
automated re-reviews from any reviewer. Monitor reviews triggered by pushes; if no
new run or feedback arrives, assume no further feedback from that reviewer and
continue. A missing run is not a passed review and does not clear existing findings.

Once no automatic review is active, all received feedback is addressed and resolved,
and non-approval CI passes, follow the contribution guide's assignment path.
Datadog team members add `ready-for-human-review` and verify it is present. A team
request or GitHub ready status does not replace that label. External contributors
wait for a team member to pick up the PR. The label does not satisfy approvals.

Keep the label during routine follow-up pushes. Remove it only for significant
rework requested during human review. Reapply it after the reworked head clears
active automatic reviews, received feedback and non-approval CI.

## Monitor and finish

For ongoing ownership, reuse an existing monitor and saved state. Check frequently
while fixes, CI or automatic reviews are active, for example every five minutes.
Reduce to fifteen minutes while only humans are pending and return to frequent
checks when work resumes. Keep unchanged or non-actionable states quiet; report
meaningful changes, failures, completion or required user action.

If merge is in scope, recheck current repository rules, allowed methods, any merge
queue, required checks and approvals. Merge only the exact reviewed and tested
head, with a head guard and no admin or bypass option. Observe any queue rules.
After GitHub reports a merge, fetch the base branch and verify it contains the
intended changes. Save final evidence and stop any monitor owned by this task.
Otherwise, report the completed scope and remaining work without merging.
