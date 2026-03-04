---
name: git-branch
description: Use when creating a new branch in dd-sdk-ios for a JIRA ticket or feature. Use when choosing a branch name or base branch for development work.
---

# Branching in dd-sdk-ios

## Convention

Branch names follow: `<author>/<JIRA-TICKET>/<descriptive-slug>`

- `<author>`: your GitHub username or initials
- `<JIRA-TICKET>`: project shortname + ticket number (e.g. `RUM-9999`, `FFL-123`)
- `<descriptive-slug>`: short kebab-case description

**Examples from the repo:**
- `maxep/RUM-14622/visionos-integration-test`
- `bplasovska/RUM-14563/lowercase-header-keys`
- `kelvin/RUM-13420/cache-ddtags`

## Base Branch

Always branch from `develop` (not `main` or `master`):

```bash
git checkout -b <author>/<JIRA-TICKET>/<slug> develop
```

## No JIRA Ticket?

For chores or external contributions without a ticket, use a descriptive slug only:

```bash
git checkout -b <author>/<slug> develop
```
