---
name: dd-sdk-ios:update-feature-docs
description: Use when public API changes have been made to review and update all *_FEATURE.md documentation files, or to audit whether they are still accurate.
---

# update-feature-docs

Review and update the feature documentation files to match the current public API.

## When to use

- After adding or modifying a public API (configuration options, new types, new methods)
- Before opening a release PR, to make sure docs are in sync
- Any time you want to audit whether feature docs are still accurate

## What this skill covers

All `*_FEATURE.md` files in the repo. Each doc's frontmatter is the source of truth:
- `verified_against_commit` — the commit the doc was last verified against
- `tracked_files` — the public API source files whose changes should trigger a doc update

To add a new feature doc to the system, just create a `*_FEATURE.md` file with the correct frontmatter — no script changes needed.

## Steps

1. **Discover feature docs** — find all `*_FEATURE.md` files in the repo (excluding `build/` and `artifacts/`).

2. **For each doc, read its frontmatter** — extract `verified_against_commit` and `tracked_files`.
   - If `tracked_files` is missing, derive the list from the doc's "Key Files" section (every source file path it references). Treat the doc as fully out of date and proceed to step 4 — the diff in step 3 cannot be computed.
   - If `verified_against_commit` is missing, treat the doc as fully out of date and proceed to step 4 — the diff in step 3 cannot be computed.

3. **Get the diff since that commit** — run:
   ```
   git diff <verified_against_commit>..HEAD -- <tracked_files>
   ```
   If there is no diff for a doc, it is up to date — skip it.

4. **Read the current source files in full** — read each tracked source file to understand the current public API surface.

5. **Compare against the feature doc** — identify every discrepancy:
   - New configuration options or parameters missing from the doc
   - Removed or renamed options still mentioned in the doc
   - Changed defaults, behaviors, or platform availability
   - New types, enums, or feature flags not documented
   - Outdated code examples

6. **Update the feature doc** — apply all necessary changes:
   - Update the Quick Start example to reflect the current API
   - Update the Configuration Categories section
   - Update Troubleshooting if relevant
   - Fix any stale descriptions or defaults

7. **Update the frontmatter** — set:
   - `tracked_files` → if it was missing or out of date, write the list derived in step 2
   - `verified_against_commit` → current HEAD commit hash (use `git rev-parse --short=9 HEAD`)
   - `sdk_version` → current version from `DatadogCore.podspec`
   - `last_updated` → today's date (YYYY-MM-DD)

## Notes

- Only update docs for features whose tracked source files actually changed.
- Do not rewrite sections that are still accurate — only fix what is wrong or missing.
- The Quick Start example should always compile against the current API.
