---
name: dd-sdk-ios:prepare-release
description: Use when preparing a regular dd-sdk-ios release through changelog generation, version bumping, feature-doc verification, and opening the release PRs to master and develop.
---

# Prepare a release

Prepare a regular main-repo release through two draft PRs from the same branch, following the [release process](https://datadoghq.atlassian.net/wiki/spaces/CS0/pages/5957845253/Release+Process#1.-Main-repo). Hotfixes follow a separate process.

`/dd-sdk-ios:prepare-release <version> [baseline]`

Use `gh` for GitHub operations. Follow `dd-sdk-ios:git-commit` for signing and approval, using the exact release messages below. Reuse approvals already given for the same work.

## 1. Establish the release source

Start from a clean checkout, preserving unrelated work. Confirm the supplied semantic version has no `v` prefix and has not already been published. Fetch `origin/develop`, `origin/master`, and release tags. Resolve the previous published baseline for this release line using `dd-sdk-ios:generate-changelog`; ask if ambiguous.

Inspect any existing local/remote `release/<version>` branch and its PRs before creating anything. For a new release, record the fetched `origin/develop` SHA as the frozen source and branch from it:

```bash
git switch --create 'release/<version>' '<frozen source SHA>'
```

On resume, recover the original source before preparation commits and verify the existing diff, commit messages, signatures, and order. Reuse completed steps and reviewed notes without incorporating newer `develop` changes. Report mismatches before altering history.

## 2. Prepare separate signed commits

Review and stage only each step's files, then commit with `git commit -S` and these exact messages, in order:

| Step | Commit message |
|---|---|
| Version bump | `Bumped version to <version>` |
| Changelog | `Update CHANGELOG.md with version <version>` |
| Feature documentation, if changed | `Update feature docs` |

**Version:** update `__sdkVersion` in `DatadogCore/Sources/Versioning.swift`, preserving its format, and run `./tools/podspec_bump_version.sh '<version>'`. Verify every root podspec and `__sdkVersion` match. Use the helper directly because `make bump` stages the entire tree and creates its own commit.

**Changelog:** run `dd-sdk-ios:generate-changelog` with the version, baseline, and original frozen source, excluding all preparation commits. Resolve coverage gaps and `Unreleased` conflicts, then commit only `CHANGELOG.md`.

**Documentation:** first run `make feature-docs-verify`. If it passes, leave docs unchanged and skip their commit. For stale documentation, run `dd-sdk-ios:update-feature-docs`, review and commit its changes, including required registry updates, then verify again. Skip an empty commit; resolve other verification failures before pushing.

The documentation skill records the current changelog commit in `verified_against_commit`. Preserve that commit by appending the documentation commit; reverify documentation if history changes.

## 3. Review and push

Review the complete diff against both fetched targets. Check the separate commits' messages, signatures, and order, confirm version/changelog agreement, and run `git diff --check` and relevant validation. Before pushing or opening PRs, show the commits, both titles, and full bodies for approval unless already authorized.

Push `release/<version>` to `origin` without force. Use the complete PR bodies below; keep validation and changelog coverage in the handoff report.

## 4. Open or reuse both draft PRs

Check each target independently before creation:

```bash
gh pr list --repo DataDog/dd-sdk-ios --state all \
  --head 'release/<version>' --base '<master or develop>' --json number,state,title,url
```

Reuse an open PR matching head and base. Inspect and report a closed or merged match before proceeding. Create only missing PRs with `gh pr create --draft --body-file`, using temporary files containing these bodies.

**To `master`, title `Release <version>`:**

List each distinct PR referenced in the target version's finalized `CHANGELOG.md` section, one bullet per PR, sorted by number:

```markdown
### What and why?

- #<PR number>
```

**To `develop`, title `Merge release/<version> to develop`:**

```markdown
### What and why?

Merges `release/<version>` to develop;
git counterpart of <master PR URL>
```

Obtain the `master` PR URL before filling the `develop` body. Verify both PRs' head, base, title, body, and draft state. If only one creation succeeds, retain its URL and resume only the missing PR. Attach both created PRs to the current chat when supported.

## 5. Hand off

Return both PR URLs, version, frozen range, changelog coverage, verification results, and pending checks. Stop with both PRs open; merging, tagging, publishing, announcements, and dogfooding remain in the release process.
