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
- **Always open as draft** — mark ready only when CI passes and the PR is ready for review
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
- [ ] `make docs-gate SNAPSHOT=HEAD OPTIONAL=1` reports `allow` for the whole branch (compares with the merge-base of `origin/develop`; see [Documentation Gate](../../../docs/DEVELOPMENT.md#documentation-gate))
- [ ] `make test-ios-all` passes
- [ ] `make api-surface-verify` passes (if public API changed)
- [ ] Changelog metadata follows the PR template

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Wrong base branch | Use `develop` or the change's shared feature branch |
| Missing `[PROJECT-XXXX]` title prefix | Required for internal development PRs |
| Skipping review checklist items | Fill out checklist before marking PR ready |
