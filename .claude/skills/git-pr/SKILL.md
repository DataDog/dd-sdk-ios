---
name: git-pr
description: Use when creating a pull request in dd-sdk-ios. Use when writing PR titles, PR body, or choosing the target branch.
---

# Pull Requests in dd-sdk-ios

## Requirements

- **Title prefix**: `[PROJECT-XXXX]` matching the JIRA ticket
- **Target branch**: `develop`
- **Always open as draft** — mark ready only when CI passes and the PR is ready for review
- All commits on the branch must be signed

## Creating via gh

The repo has a PR template at `.github/PULL_REQUEST_TEMPLATE.md` with three sections: **What and why?**, **How?**, and a **Review checklist**. Write the body inline following that structure:

```bash
gh pr create \
  --title "[RUM-9999] Your title here" \
  --body "<filled-in PR body following .github/PULL_REQUEST_TEMPLATE.md>" \
  --base develop \
  --draft
```

**Never add `Co-Authored-By: Claude` or any AI co-author trailer** to the PR body or commits.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Wrong base branch | Always `develop`, not `main` or `master` |
| Missing `[PROJECT-XXXX]` title prefix | Required for internal work |
| Skipping review checklist items | Fill out checklist before marking PR ready |
| No CHANGELOG entry for user-facing changes | Add entry to `CHANGELOG.md` |
