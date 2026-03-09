---
name: git-pr
description: Use when creating a pull request in dd-sdk-ios. Use when writing PR titles, PR body, or choosing the target branch.
---

# Pull Requests in dd-sdk-ios

## PR Title Format

```
[PROJECT-XXXX] Short imperative description
```

**Examples:**
- `[RUM-1234] Add baggage header merging support`
- `[FFL-213] Add Feature Flags support`
- `[RUM-14655] Fix WebView log events attaching incomplete ddTags`

## Requirements

- **Title prefix**: `[PROJECT-XXXX]` matching the JIRA ticket
- **Target branch**: `develop`
- **Always open as draft** — mark ready only when CI passes and the PR is ready for review
- All commits on the branch must be signed

## Creating via gh

The repo has a PR template at `.github/PULL_REQUEST_TEMPLATE.md`. Read it and fill in all sections:

```bash
gh pr create \
  --title "[RUM-9999] Your title here" \
  --body "<filled-in PR body following .github/PULL_REQUEST_TEMPLATE.md>" \
  --base develop \
  --draft
```

**Never add `Co-Authored-By: Claude` or any AI co-author trailer** to the PR body or commits.

## Before Opening

- [ ] `make lint` passes
- [ ] `make test-ios-all` passes
- [ ] `make api-surface-verify` passes (if public API changed)
- [ ] CHANGELOG updated (if user-facing change)

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Wrong base branch | Always `develop`, not `main` or `master` |
| Missing `[PROJECT-XXXX]` title prefix | Required for internal work |
| Skipping review checklist items | Fill out checklist before marking PR ready |
