---
name: dd-sdk-ios:setting-up-worktree
description: Use when creating a git worktree for dd-sdk-ios, starting isolated work alongside another checkout, or when a fresh worktree fails to build or test — missing DD_SDK_COMPILED_FOR_TESTING symbols, "no such module 'OpenTelemetryApi'", or missing *.local.xcconfig files.
---

# Setting Up a dd-sdk-ios Worktree

A new worktree lacks two gitignored inputs: the local xcconfigs (test targets need them) and `Carthage/Build` (`DatadogTrace` links it). Reuse the main checkout's — setup takes seconds.

```bash
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
WT="<worktree path>"                                                       # anywhere, inside or outside the repo

# Skip these two lines if the worktree already exists (e.g. created by a harness)
git -C "$MAIN" fetch origin develop
git -C "$MAIN" worktree add --no-track -b "<branch>" "$WT" origin/develop   # branch name: dd-sdk-ios:git-branch

cd "$WT"
make repo-setup                                                            # local xcconfigs
mkdir -p Carthage && /bin/cp -cR "$MAIN/Carthage/Build" Carthage/          # APFS clone, instant
```

- Use `/bin/cp`: Homebrew's GNU `cp` may shadow it and has no `-c`.
- If `Cartfile.resolved` differs from the main checkout's, run `make dependencies` instead of the clone.
- Don't run full `make`, `env-check`, or `templates` — they're machine-wide and already done.
- If the worktree is inside the main checkout, add its folder to the file printed by `git rev-parse --path-format=absolute --git-path info/exclude` (not `.gitignore`) so it doesn't show up as untracked. Don't hardcode `.git/info/exclude`: in a linked worktree `.git` is a file.

**Xcode MCP:** `XcodeOpenWorkspace(path: "<WT>/Datadog.xcworkspace")`. Each new folder needs approval: if the call says *"Xcode is waiting for the user to approve this request"*, ask the user to approve from the Xcode MCP menu bar icon, then retry.
