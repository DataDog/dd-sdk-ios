---
name: dd-sdk-ios:open-pr
description: Use when creating or updating a pull request in dd-sdk-ios, addressing review feedback, or handing it off for human review.
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
2. Handle each finding using the guidance below. Pass the affected local builds
   and tests before committing or pushing, then reply briefly with the change and
   relevant result and resolve the addressed feedback. Explain
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

   Re-request review only from a human after fixing their findings. Reply briefly
   with the change and relevant local result, then ask that human to review again.

## Working through feedback

Understand the reviewer's intent first. Inspect affected callers, tests and existing
patterns before editing. If a direct edit breaks something, research alternatives
that preserve the suggestion's intent before reversing it. For example, keep a
request immutable by adding its headers during construction.

If no option is clearly best, present the viable options and tradeoffs to the human
running the review loop, usually the PR author. If they cannot choose either, ask
the reviewer which option they prefer.
Keep the disputed item open while the decision is pending; silence is not a choice.
Proceed with clear fixes without adding an approval round.

After each feedback fix, run the relevant tests locally and build the affected
targets before committing or pushing, even for a one-line edit. Include test
runners and callers outside the edited directory. Syntax parsing and lint alone
do not prove code compiles or tests pass. Fix failures before publishing. For
Markdown-only changes, validate the documents, links and skill instructions and
record that no executable code changed.

Keep replies short and natural, usually one or two sentences. Answer the specific
point, say what changed and mention the relevant check. Expand when a tradeoff or
question needs explanation. Keep full logs, command lists and validation inventories
in the PR description or execution record; avoid report-style thread replies.

For example: "Moved baggage setup into request construction and kept `let`.
Runner build and all eight network tests pass."

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Wrong base branch | Use `develop` or the change's shared feature branch |
| Missing `[PROJECT-XXXX]` title prefix | Required for internal development PRs |
| Skipping review checklist items | Fill out checklist before marking PR ready |
| Assuming a ready PR assigns a human | Finish automated review, then follow the internal or external handoff path in `CONTRIBUTING.md` |
