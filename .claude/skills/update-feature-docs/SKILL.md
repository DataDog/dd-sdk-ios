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

To add a new feature doc to the system, create a `*_FEATURE.md` file following the spec in [`docs/LLM_FEATURE_DOCS_GUIDELINES.md`](../../../docs/LLM_FEATURE_DOCS_GUIDELINES.md) and modeling it on existing docs (e.g. `DatadogRUM/RUM_FEATURE.md`, `DatadogSessionReplay/SESSION_REPLAY_FEATURE.md`). Then run this skill — it will discover the new doc, audit `tracked_files` coverage, and register it in the required places. No script changes needed.

## Steps

1. **Discover feature docs** — find all `*_FEATURE.md` files in the repo (excluding `build/` and `artifacts/`).

2. **For each doc, read its frontmatter** — extract `verified_against_commit` and `tracked_files`.
   - If `tracked_files` is missing, derive the list from public API and configuration source files in the doc's "Key Files" section. Internal implementation files in "Key Files" are navigation references, not frontmatter drift triggers. Treat the doc as fully out of date and proceed to step 4 — the diff in step 3 cannot be computed.
   - If `verified_against_commit` is missing, treat the doc as fully out of date and proceed to step 4 — the diff in step 3 cannot be computed.
   - **Audit `tracked_files` coverage** against the doc's "Key Files" section. Every public API or configuration source file path referenced in "Key Files" must also appear in `tracked_files`. Cross-feature APIs belong to the feature doc that owns them. Do not add internal implementation files solely because they are listed as navigation references. This audit must happen *here*, before step 3 — otherwise drift in untracked public files is silently ignored. If any public API or configuration files are missing, add them to `tracked_files` and treat the doc as fully out of date so the newly-tracked files are inspected in step 4.

3. **Get the diff since that commit** — first ensure the tracked source files have no uncommitted changes:
   ```
   git diff HEAD -- <tracked_files>
   ```
   If this returns anything, **abort** and tell the engineer:
   > "Tracked source files have uncommitted changes. Please commit your API changes first, then re-run the skill — otherwise the diff in step 3 won't see them and I'd report the doc as up to date even though CI would fail later."

   Then run the actual drift check:
   ```
   git diff <verified_against_commit>..HEAD -- <tracked_files>
   ```
   If there is no diff for a doc, its own tracked source files are unchanged — skip steps 4–6 for that doc (no content updates needed). **Do not skip step 5b**: cross-feature drift (e.g. a RUM API change affecting Session Replay's Quick Start) won't show up in this doc's `tracked_files` diff. **Do not skip step 7**: even with no content changes, every skill invocation is a fresh verification — the frontmatter should be bumped so `verified_against_commit` points at a recently-pushed SHA rather than an older one that may not be reachable on a fresh clone. **Do not skip step 8** either — registry coverage must be checked even when every doc is fresh.

4. **Read the current source files in full** — read each tracked source file to understand the current public API surface.

5. **Compare against the feature doc** — identify every discrepancy:
   - **Configuration options** — new options missing from the doc, removed or renamed options still mentioned, changed defaults.
   - **Public methods and properties** — for each public method/property on the tracked types (e.g. `RUMMonitor.shared()`, `startView()`, `stopView()`), confirm it appears in the doc or is intentionally excluded. Flag new public methods missing from the doc.
   - **Types, enums, and feature flags** — confirm every public enum case (including `FeatureFlag` cases), nested type, and protocol is documented.
   - **Deprecated public surface** — walk every case marked `@available(*, deprecated, message:)`. Deprecated cases stay on the public API and must appear in the doc with a clear deprecation note, otherwise customers reading the doc won't know they exist or that they're being phased out.
   - **Platform support** — verify the doc's stated platform availability matches the source. Check `#if os(...)` directives and `@available(...)` annotations on tracked types; if these have changed, update the doc's Overview section.
   - **Feature interactions** — verify the "Feature Interactions" section still holds. Look for new cross-feature dependencies (e.g. a new RUM-context read in Logs source) or removed ones.
   - **Description accuracy** — for each documented option/method, compare the snippet's inline comment against the source's doc-comment. If the source description has been updated, update the doc to match.
   - **Outdated code examples** — anything in the snippets that no longer reflects the API.

5b. **Audit every code snippet for compile-readiness** — runs for every doc on every skill invocation, **even if step 3's diff was empty**. This is the only check that catches cross-feature drift (e.g. a RUM predicate change breaking Session Replay's Quick Start). For every constructor call, method call, and type reference in every code snippet (Quick Start and any inline examples):
   - Locate the corresponding `init` / `func` / `struct` / `class` / `enum` declaration **anywhere in the SDK source**, not just this doc's `tracked_files`. Snippets often reference types from other features (e.g. Session Replay's Quick Start uses `RUM.Configuration` and `DefaultSwiftUIRUMViewsPredicate` from DatadogRUM). Use the "Feature Interactions" section of each doc as a hint for which other modules may be relevant, but resolve symbols against the actual source regardless.
   - Confirm every parameter **without** a default value (`= ...`) is supplied in the snippet, with the correct label.
   - Confirm parameter labels and argument ordering match the source.
   - **Watch especially for newly-required parameters added to existing initializers.** A required parameter added to an existing `init` is the highest-risk drift — the constructor still looks "the same" at a glance, and the source diff is a one-line addition that is easy to skim past. Example regression: `DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled:)` gained the required `isLegacyDetectionEnabled` argument and the snippet was not updated, causing a compile failure customers hit.
   - Placeholder identifiers (e.g. `<client_token>`, `MyCustomViewsPredicate`, `myView`) and user-defined helpers (e.g. `scrubURL`) are illustrative and need not resolve — only **SDK** API calls must be valid.
   - If you find any mismatch, fix the snippet (this counts as a content update — proceed to step 6).

6. **Update the feature doc** — apply all necessary changes:
   - Update the Quick Start example to reflect the current API
   - Update the Configuration Categories section
   - Update Troubleshooting if relevant
   - Fix any stale descriptions or defaults

7. **Update the frontmatter** — runs on every skill invocation, **even when steps 4–6 were skipped**. A skill run is itself a verification event; bumping the frontmatter records that and keeps `verified_against_commit` pointing at a recently-pushed SHA (older SHAs may be unreachable on a fresh clone in CI). Set:
   - `tracked_files` → if it was missing or out of date, write the list derived in step 2
   - `verified_against_commit` → current HEAD commit hash (use `git rev-parse --short=9 HEAD`)
   - `sdk_version` → current version from `DatadogCore.podspec`
   - `last_updated` → today's date (YYYY-MM-DD)

8. **Update the registries** — when adding, renaming, or removing a `*_FEATURE.md` file, also update every place that hand-lists feature docs. `tools/feature-docs-verify.sh` enforces these and will fail CI otherwise:
   - **`.github/workflows/changelog-to-confluence.yaml`** — both the `paths:` filter and the `cp` block. Use the relative path **without a leading slash** (`DatadogRUM/RUM_FEATURE.md`, not `/DatadogRUM/RUM_FEATURE.md`) — leading slashes silently never match in GitHub Actions `paths:` filters. The publish filename is kebab-case derived from the module + doc (`DatadogRUM/RUM_FEATURE.md` → `dd-sdk-ios-rum-feature.md`).
   - **`AGENTS.md`** — add the doc to the file tree under "Feature-specific docs" and to the routing table ("Where to Look First").
   - **`docs/LLM_FEATURE_DOCS_GUIDELINES.md`** — add the doc to the file inventory list.

9. **Surface a reminder to the engineer** — at the end of your run, print this single-line note so it's visible right when the engineer is using the skill:
   > "Note: `verified_against_commit` was set to `<short SHA>`. If you rebase, amend, or squash commits afterward, re-run the skill before pushing so the SHA stays reachable in the final history (otherwise CI verify will fail on a fresh clone)."

## Notes

- Only update docs for features whose tracked source files actually changed.
- Do not rewrite sections that are still accurate — only fix what is wrong or missing.
- The Quick Start example should always compile against the current API.
