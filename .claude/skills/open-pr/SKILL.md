---
name: dd-sdk-ios:open-pr
description: Use when creating a pull request in dd-sdk-ios. Use when writing PR titles, PR body, or choosing the target branch.
---

# Pull Requests in dd-sdk-ios

## Development PR Title Format

```
[PROJECT-XXXX] Short imperative description
```

**Examples:**
- `[RUM-1234] Add baggage header merging support`
- `[FFL-213] Add Feature Flags support`
- `[RUM-14655] Fix WebView log events attaching incomplete ddTags`

For regular release PRs, use `dd-sdk-ios:prepare-release` for titles, descriptions, and target branches.

## Requirements

- **Title prefix**: `[PROJECT-XXXX]` matching the JIRA ticket for internal development PRs
- **Target branch**: `develop` or the change's shared feature branch
- **Always open as draft** — mark ready when the diff is ready and CI is green; only approval-dependent gates may remain pending
- **Follow `CONTRIBUTING.md` for human assignment** — Datadog team members add `ready-for-human-review` after automated feedback is resolved; external contributors wait for a team member to pick up the PR
- All commits on the branch must be signed

## Creating via gh

For development PRs, read `.github/PULL_REQUEST_TEMPLATE.md` and complete its applicable sections. Changelog metadata applies to PRs targeting `develop`; a shared feature's integration PR must cover the whole feature.

Use `gh` for all GitHub operations.

When invoked from `dd-sdk-ios:prepare-release`, approval already given there for the same commits, push, title, and body satisfies the corresponding confirmations below.

**Before pushing**, show the user the commits that will be pushed and ask for confirmation:

```bash
git log origin/<target-branch>..HEAD --oneline
```

Ask: "Shall I push these commits and open the PR?" Only proceed after the user confirms.

**Before running the command**, show the user the proposed PR title and full body and ask for confirmation. Only run `gh pr create` after the user approves.

```bash
gh pr create \
  --title "[RUM-9999] Your title here" \
  --body-file "<PR body file>" \
  --base "<target-branch>" \
  --draft
```

**Never add `Co-Authored-By: Claude` or any AI co-author trailer** to the PR body or commits.

## Before Opening

- [ ] `make lint` passes
- [ ] `make test-ios-all` passes
- [ ] `make api-surface-verify` passes (if public API changed)
- [ ] Changelog metadata follows the PR template

## Automated review and human handoff

Marking the PR ready starts automated review; it is not the human-assignment signal.

1. Wait for active automated reviews to finish. Read review submissions,
   conversation comments, inline feedback and open threads; a completed review
   can still have unresolved findings.
2. Fix each accepted finding, run the relevant validation, commit and push, then
   reply with the change and evidence and resolve the addressed feedback. Explain
   stale or inapplicable findings before resolving them. Do not delete feedback
   to clear the queue.
3. Monitor reviews triggered automatically by the new push and repeat this loop
   when more feedback arrives. Never manually request another automated review,
   regardless of the reviewer. If no new run or feedback arrives from a reviewer,
   assume it has no further feedback and continue; do not wait for or request a
   missing rerun. Existing findings must still be addressed and resolved. Record
   unavailable runs without describing them as passed reviews. Required CI checks
   and human approvals still apply.
4. Once that loop is clear and CI is green, follow the human
   handoff paths in `CONTRIBUTING.md`. Approval-dependent gates such as MergeGate
   can remain pending until humans approve; do not wait for them before handoff.

   **Datadog team members:** add the label used by the daily reviewer-assignment bot:

   ```bash
   gh pr edit "<PR number>" --add-label "ready-for-human-review"
   ```

   Verify the label is present. A team review request does not replace it, and the
   label does not replace required approvals or MergeGate.

   **External contributors:** wait for a team member to pick up the PR and take
   it through human review; adding or verifying the label is not required.
5. Keep owning the PR through human feedback and merge. Poll frequently during
   automated review and fixes (for example, every five minutes), then less often
   while waiting on humans with no open feedback (for example, every fifteen
   minutes). If another push or finding reopens automated review, return to frequent
   checks and address it alongside human review, keeping the label. Remove the
   label only when human feedback requires significant rework, and reapply it
   after the reworked head clears automated review.

   Re-request review only from a human after fixing their findings. Reply with
   the changes and validation evidence, then ask that human to review again.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Wrong base branch | Use `develop` or the change's shared feature branch |
| Missing `[PROJECT-XXXX]` title prefix | Required for internal development PRs |
| Skipping review checklist items | Fill out checklist before marking PR ready |
| Assuming a ready PR assigns a human | Finish automated review, then follow the internal or external handoff path in `CONTRIBUTING.md` |
