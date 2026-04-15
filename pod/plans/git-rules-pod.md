# Git Workflow — Timeseries Pod Override

> These rules apply **only** during the AI Pod (Apr 13 – ~May 9, 2026) on the `feature/timeseries` branch.
> They override the global git-workflow rules for the duration of the pod.
> Once the pod ends and code moves toward `develop`, revert to the standard rules.

---

## Branching

- All work happens on `feature/timeseries` (already created).
- No new branches needed unless explicitly discussed with the team.
- Do NOT create PRs to `develop` during the pod.

---

## Commits

- **Single-line commit message**, starting with a **verb** in the imperative form.
- **No JIRA prefix** — there are no individual tickets during the pod.
- **No co-author lines** — Barbora is the sole commit author.
- Commit frequently — small, logical units of work. The agent should commit after each completed task or meaningful step.
- No description lines unless explicitly requested.

Examples:
```
add Package.swift scaffolding for DatadogTimeseries
implement TimeseriesBatcher with configurable batch size
fix CodingKeys for _dd field in TimeseriesEvent
add end-to-end verification test with UUID masking
```

---

## Pull Requests

- **No PRs during the pod.** All commits go directly to `feature/timeseries`.
- Code review happens post-pod when merging to `develop`.

---

## Agent autonomy

- The agent commits directly without asking for approval.
- The agent does NOT need to run `git status` or `git diff` before committing — just stage the relevant files and commit.
- After a successful `swift build && swift test` (or equivalent verification), the agent should commit immediately.
- Keep commits atomic: one logical change per commit.
