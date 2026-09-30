---
name: dd-sdk-ios:git-commit
description: Use when committing changes in dd-sdk-ios. Use when writing commit messages, signing commits, or staging files before a commit.
---

# Committing in dd-sdk-ios

## Requirements and project authorization

Read the active project's handoff and explicit user authorization before applying
the defaults below. Project-specific authorization may permit unsigned local
checkpoints, omit a ticket prefix, or authorize commits without another prompt.
Keep those exceptions in the project record, not in repository-wide guidance.

- **Default signing rule:** sign commits with GPG or SSH unless the user has
  authorized unsigned local work. Such authorization does not permit an unsigned
  push: every outgoing commit must be signed and verified before publication.
- **Default message prefix:** `[PROJECT-XXXX]` matching the JIRA ticket for internal
  development, unless the active project explicitly has no prefix. Never invent a ticket.

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

Use existing commit authorization. Ask for approval only when it has not already
been given for the current work; do not repeat an approval request at every checkpoint.

1. Inspect `git status --porcelain=v1` and identify the explicit task path list.
2. Inspect only those paths with `git diff -- <paths>` and
   `git diff --cached -- <paths>`. Never dump an unrestricted staged diff: unrelated
   staged files can include local credentials or user-owned work.
3. Choose the message using the active project's prefix rule.
4. Stage and commit only the explicit task paths, preserving every unrelated index entry.

## Commit Command

```bash
git add -- <explicit-task-paths>
git commit --only -S -m "<message under the project's prefix rule>" -- <explicit-task-paths>
```

The `-S` flag applies your configured GPG/SSH signature.
When unsigned local commits are authorized, use `--no-gpg-sign` instead of `-S`;
no failed signing attempt is required unless the project explicitly requires one.
Never use `git commit -a` or include unrelated staged paths.

Before an authorized push, inspect every outgoing commit, including merges. Sign
any unsigned local history and verify the rewritten outgoing range. Rewriting
already-published or shared history requires separate coordination/authorization;
do not amend the active shared branch merely to check whether signing works.

**Never add `Co-Authored-By: Claude` or any AI co-author trailer to commits in this repo.**

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Unsigned outgoing history | Local permission is not push permission; sign and verify every outgoing commit |
| Missing `[PROJECT-XXXX]` prefix | Apply the active project's explicit rule; otherwise use the repository default |
| New files missing from pbxproj | Use Xcode MCP tools — see `xcode-file-management` skill |
| Adding `Co-Authored-By: Claude` trailer | Never add AI co-author trailers in this repo |
