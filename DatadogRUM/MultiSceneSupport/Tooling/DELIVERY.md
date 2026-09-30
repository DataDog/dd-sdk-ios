# Isolated delivery and CI review

Read when preparing or reviewing an authorized packet. This procedure does not
itself authorize publication, merge, retargeting or TestFlight. The
[S1 delivery plan](../S1_DELIVERY_PLAN.md) and
[queue](../Results/S1-delivery-queue.json) own per-PR state; the register owns release
qualification. The [cursor](../../../.continue-here.md) owns current authorization.

## Preserve and qualify the packet

Keep the qualified checkout intact. Freeze the actual upstream revision and exact
production/test/document/build path allowlist, then apply only that packet to a fresh
isolated checkout. Machine patches use `--no-color --no-ext-diff`. Preserve a failed
application or dependency preparation rather than editing the qualified original.
A proposed patch must apply against the frozen base, not an intermediate candidate.

Source exclusions need exact path sets and bytes, including auxiliary Sources,
symlinks and build graph membership. Review each retained invariant; old reference
or S3 evidence is not an isolated S1/S2 acceptance certificate. Module dependency
boundaries, public API and source-matched F02/F03/F06 remain required. Do not infer
independent merge order from apparent file separation; currently only H00 → E01
is established. Actual upstream content must be checked before that rebase.

Keep reviewed production repairs separate from test readability changes. For a
rename/refactor-only change, freeze old/new identifiers and fixture literals,
compare all remaining tokens in order, preserve assertions/timing, then run strict
test lint and relevant platform syntax parsing. Unchanged behavior reuses its
source-matched runtime evidence. Test names and descriptions should explain behavior
without internal experiment or packet labels.

A smaller Resource design must preserve retained-session ownership, unknown-manual
compatibility, exact callbacks and counter isolation. A smaller diff alone is not a
safe simplification. [The Resource review](../Results/S1-resource-completion-review.json)
retains the rejected alternatives and accepted readability-only change.

## Repository and signing safety

Record porcelain/index state without stripping leading whitespace. Preserve every
user-owned dirty path, including staged additions. Use explicit individual paths for
both staging and `git commit --only`; never use blanket staging or `git commit -a`.
Do not include configuration, developer team/profile files or local artifacts.

Project authorization, updated September 30: agents may commit local checkpoints
without another approval, without a ticket or any message prefix, and without a
signature. A failed signing attempt is not required. Signing locally remains useful
when readily available. Only publication requires signatures: before a separately
authorized push, re-sign every unsigned outgoing commit and verify the entire
outgoing range, including merges. Preserve source trees and existing evidence;
re-signing does not require repeating unchanged accepted tests. Do not rewrite
published/shared history or disturb another task's checkout without coordination.
These project rules override the repository commit skill's defaults for this work.
A restricted signature check can fail because it cannot create a temporary file;
verify in the authorized user context before declaring a bad signature.

A documentation or signed-history reconstruction can reuse accepted source evidence
only after exact source/test/build identity checks. Verify feature-document source
SHAs against final outgoing ancestry; after rewriting history rerun the feature-doc
check, not unrelated accepted native tests. Do not invent tickets or co-author tags.

## Publication when authorized

Freeze the exact remote ref, expected head/base, outgoing signed commits, changed
paths and concise reviewer-facing description. Verify live state and the diff before
pushing only the authorized ref; no incidental branches/tags or unreviewed force
update. A reconciled published packet uses its exact remote lease. Read back head,
base, commits, file list and body, preserving readiness state changed externally.
Publication is separate from qualification, CI, maintainer review and merge.

If SSH transport is unavailable, inspect `git ls-remote --get-url`: inherited
`insteadOf` rules can silently redirect HTTPS. Use command-scoped exact HTTPS mapping
and the existing credential helper, never persistent config changes or credential
output. After a timed-out push, inspect the actual remote head and prove transport
process absence before deciding whether another operation is needed. Preserve any
failed post-push guard and verify the intended body/head before editing a PR.

PR descriptions state the concrete trigger, corrected behavior and useful validation
for someone who has not read project history. Keep source limits that matter to
review; link detailed evidence instead of copying experiment narratives.

## CI and review follow-ups

Before a CI repair, require clear evidence connecting the failure to changed
production code or associated tests. An unchanged upstream test failing in a PR is
insufficient. Check existing upstream fixes first; PR3196 owns the timeseries pause
correction. Do not publish a duplicate local candidate or imply its evidence tested
a different upstream source. Unattributed flakes do not justify further repairs or
tests; required current-head CI and maintainer acceptance stay unwaived.

Use exact job artifacts through authenticated Browse/Download controls, retaining
job/head/path/hash. Read unformatted logs or xcresult, not only formatted passes;
early-flake detection may mark failures expected, and restart can hide a first-process
exception. Keep counts by actual target/selector and every repetition. A fixture
correction in a second target with the same class name needs source review; it is
not an inherited pass or flake.

Scope any inherited diagnostic exception to exact source, test, message/identifier
and multiplicity, with independent negative controls. Keep raw FAIL and qualified
review separate. Matched warning stacks can demonstrate recurrence without proving
harmlessness or root cause. No missing SDK frame clears TSan or performance.

The [finite CI record](../Results/S1-ci-followup.json) owns actual failures and
links. Completed checks are reused until changed source, a new failure or an
unresolved concrete concern justifies more execution. External publication state is
time-sensitive: refresh it only when the active task needs a delivery action.
