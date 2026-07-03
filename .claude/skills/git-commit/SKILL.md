---
name: dd-sdk-ios:git-commit
description: Use when committing changes in dd-sdk-ios. Use when writing commit messages, signing commits, or staging files before a commit.
---

# Committing in dd-sdk-ios

## Requirements

- **All commits MUST be signed** (GPG or SSH)
- **Message prefix**: `[PROJECT-XXXX]` matching the JIRA ticket (internal development only)

## Message Format

```
[RUM-9999] Short imperative description
```

**Examples:**
- `[RUM-1234] Add baggage header merging support`
- `[FFL-213] Add Feature Flags support`
- `[RUM-14655] Fix WebView log events attaching incomplete ddTags`

Third-party contributions skip the prefix.

## Before Committing

Always show the user what will be committed and get explicit approval before running `git commit`.

1. Run `git diff --staged` and show the output
2. Propose the commit message following the format below
3. Ask: "Shall I commit with this message?"
4. Only run `git commit -S -m "..."` after the user confirms

## Commit Command

```bash
git commit -S -m "[RUM-9999] Your message here"
```

The `-S` flag applies your configured GPG/SSH signature.

**Never add `Co-Authored-By: Claude` or any AI co-author trailer to commits in this repo.**

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Missing signature | Always use `-S`; check `git log --show-signature -1` |
| Missing `[PROJECT-XXXX]` prefix | Required for internal dev; skipped for third-party |
| New files missing from pbxproj | Use Xcode MCP tools — see `xcode-file-management` skill |
| Adding `Co-Authored-By: Claude` trailer | Never add AI co-author trailers in this repo |
