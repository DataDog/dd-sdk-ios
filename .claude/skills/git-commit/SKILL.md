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
2. Run the documentation gate on the staged changes (see below)
3. Propose the commit message following the format below
4. Ask: "Shall I commit with this message?"
5. Only run `git commit -S -m "..."` after the user confirms

## Documentation Gate

```bash
make docs-gate SNAPSHOT=index AGAINST=HEAD OPTIONAL=1
```

It checks that the staged changes introduce no broken documentation links or anchors, and that the selected designs and guides are still routed from `docs/README.md`. See [Documentation Gate](../../../docs/DEVELOPMENT.md#documentation-gate).

- **`block`**: do not commit. Show the new findings, fix them, re-stage, and run the gate again.
- **`allow` with advisories**: review the affected docs (architecture, `*_FEATURE.md`, guides) against the staged change before you propose the message. A correct doc needs no edit.
- **Skipped (runtime not installed)**: mention it in one line and continue. Never fail a commit for a missing runtime.

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
