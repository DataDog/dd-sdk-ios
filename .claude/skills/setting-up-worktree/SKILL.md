---
name: dd-sdk-ios:setting-up-worktree
description: Use when creating a git worktree for dd-sdk-ios, starting isolated work alongside another checkout, or when a fresh worktree fails to build or test — missing DD_SDK_COMPILED_FOR_TESTING symbols, "no such module 'OpenTelemetryApi'", or missing *.local.xcconfig files.
---

# Setting Up a dd-sdk-ios Worktree

## Overview

A new worktree has only tracked files. Building and testing needs two **gitignored** inputs the main checkout already has:

| Input | Why | Without it |
|-------|-----|------------|
| `xcconfigs/Base.ci.local.xcconfig` + `Base.dev.local.xcconfig` | Sets `DD_SDK_COMPILED_FOR_TESTING` | Test targets fail to compile |
| `Carthage/Build/OpenTelemetryApi.xcframework` | `DatadogTrace` links it | `DatadogTrace` and dependents fail to build |

Reuse the main checkout's copies: setup takes ~5 seconds instead of a full `make`.

## Variables

Shell variables don't persist between agent tool calls. Re-run this at the start of **every** call — it works from the main checkout or any worktree:
```bash
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
BRANCH="maxep/RUM-1234/my-change"                  # dd-sdk-ios:git-branch: <author>/<TICKET>/<slug>, or <author>/<slug> without a ticket
WT="$(dirname "$MAIN")/dd-sdk-ios-worktrees/${BRANCH//\//-}"
```

## Steps

**1. Create the worktree** — outside the repo, from `origin/develop`:
```bash
git -C "$MAIN" fetch origin develop
git -C "$MAIN" worktree add --no-track -b "$BRANCH" "$WT" origin/develop
```
`--no-track` keeps the branch from tracking `origin/develop`; push later with `git push -u origin "$BRANCH"`.

If a harness tool already created the worktree (Claude Code uses `$MAIN/.claude/worktrees/<name>`): set `WT` to that path, add the folder to `$MAIN/.git/info/exclude` (never `.gitignore`), and continue at step 2.

**2. Local xcconfigs:**
```bash
cd "$WT" && make repo-setup     # ~2s: copies the two Base.*.local.xcconfig, runs bundle install
[ -f "$MAIN/xcconfigs/Datadog.local.xcconfig" ] && /bin/cp "$MAIN/xcconfigs/Datadog.local.xcconfig" "$WT/xcconfigs/"   # optional Example-app secrets
```

**3. Carthage build:**
```bash
cd "$WT" && mkdir -p Carthage
if [ -d "$MAIN/Carthage/Build" ] && diff -q "$MAIN/Cartfile.resolved" Cartfile.resolved; then
  /bin/cp -cR "$MAIN/Carthage/Build" Carthage/ && echo "cloned Carthage/Build"
else
  make dependencies               # downloads; needed when Cartfile.resolved differs
fi
```
`/bin/cp -c` is an APFS clone: instant, no extra disk. Use `/bin/cp` — Homebrew's GNU `cp` may shadow it in `PATH` and has no `-c`.

**4. Verify:**
```bash
cd "$WT"
for f in xcconfigs/Base.ci.local.xcconfig xcconfigs/Base.dev.local.xcconfig Carthage/Build/OpenTelemetryApi.xcframework; do
  [ -e "$f" ] && echo "ok      $f" || echo "MISSING $f"
done
git status --short                # must print nothing
```
All `ok` and an empty `git status` → ready to build and test.

**Skip** `make`, `make env-check`, `make templates`: they check or install machine-wide tools (templates go to `~/Library`) and already ran for the main checkout.
**UI integration tests** also need `MockServerAddress.local.xcconfig` and CocoaPods — `make ui-test` handles both (see `dd-sdk-ios:running-tests`).

## Xcode MCP in a Worktree

```
XcodeOpenWorkspace(path: "<WT>/Datadog.xcworkspace")   # → its own workspaceIdentifier
```
- Xcode approves access **per project folder**: a new worktree triggers a new approval. The call fails with *"Xcode is waiting for the user to approve this request"* — ask the user to approve from the Xcode MCP menu bar icon, then retry.
- Use this workspace's identifier for every call. Other skills' `<repo>` means `<WT>`.
- The main checkout's workspace can stay open: each gets its own identifier and its own active scheme/destination. In `XcodeListWorkspaces`, match by `workspacePath`.
- The first build is cold — each worktree path gets its own DerivedData.

## Cleanup

```
XcodeCloseWorkspace(workspaceIdentifier: <id>)
```
```bash
# Find this worktree's DerivedData before removing it (don't glob Datadog-*: that includes the main checkout's)
DD=$(grep -l "$WT/" ~/Library/Developer/Xcode/DerivedData/Datadog-*/info.plist 2>/dev/null | xargs -n1 dirname)
cd "$MAIN" && git worktree remove "$WT"   # refuses if there are uncommitted changes
git branch -d "$BRANCH"                   # -D if it was never merged
[ -n "$DD" ] && rm -rf $DD                # optional: reclaim DerivedData space
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Running full `make` in the worktree | Only steps 2–3 are per-checkout |
| `make dependencies` when main already has `Carthage/Build` | Clone it (step 3) |
| `cp -c` → "invalid option" | Use `/bin/cp` |
| `$MAIN` / `$WT` empty in a later tool call | Re-run the Variables block |
| Worktree inside the repo shows up as untracked | Use `../dd-sdk-ios-worktrees/`, or `.git/info/exclude` |
| Editing `.gitignore` for worktrees | `.git/info/exclude` (local only) |
| Treating the approval error as a failure | It's a pending prompt — ask the user, then retry |
| `rm -rf DerivedData/Datadog-*` | Deletes every checkout's build cache — match by `WorkspacePath` |
