# S1 delivery sequence

H00 (#3214) and E04 (#3219) were merged by external action. The five remaining
PRs were rebased onto frozen develop `dfc3ffcca`, validated and pushed with
verified signatures and exact original-head leases on September 22.
[The rebase receipt](Results/S1-rebase-20260922.json) owns the current heads,
conflict resolutions and fresh validation. [The queue](Results/S1-delivery-queue.json)
owns delivery state; earlier qualification receipts retain their original source identities.

All five source/test patches preserve their original changes. E03 combines the
upstream cache-lifetime tests and resource-ownership tests without changing either.
Fresh focused macOS validation passes 308 tests, and strict affected lint and feature
checks pass on all five heads. Current CI and human review remain. S2 keeps its
frozen source identities; this rebase does not promote a new S2 candidate.

## Review units

All seven rows have PRs; H00 and E04 are merged, and five remain open. H00 → E01
is satisfied by verified merge ancestry and identical upstream hitch content. E01
was already retargeted to develop externally. No additional stacks were introduced.
Maintainers own CI and review acceptance.

| Unit / PR | Customer behavior | Published head | Review base / dependency | Qualification owner |
| --- | --- | --- | --- | --- |
| [H00 #3214](https://github.com/DataDog/dd-sdk-ios/pull/3214) | Reconstruct full/delta view state before hitch assertions; test-only | 0deff4750 (merged) | develop | [Hitch review follow-up](Results/S1-hitch-review.json) |
| [E01 #3215](https://github.com/DataDog/dd-sdk-ios/pull/3215) | Prepare URLSession instrumentation once; preserve early callbacks and terminal release | 0ec10c36d | develop (H00 verified upstream) | [H00/E01 packets](Results/S1-H00-E01-packets.json) |
| [DL01 #3216](https://github.com/DataDog/dd-sdk-ios/pull/3216) | Release display-link observers through a weak callback target | 0ca7cafbc | develop | [Independent packets](Results/S1-independent-packets.json) |
| [E02 #3217](https://github.com/DataDog/dd-sdk-ios/pull/3217) | Keep attributes on the active occurrence of a repeated view key | 117942e7e | develop | [Independent packets](Results/S1-independent-packets.json) |
| [E03 #3218](https://github.com/DataDog/dd-sdk-ios/pull/3218) | Keep late Resource/action effects on their owner; failed transfers emit one Error | 4b9e842ba | develop | [Resource review follow-up](Results/S1-resource-completion-review.json) |
| [E04 #3219](https://github.com/DataDog/dd-sdk-ios/pull/3219) | Keep active native-view correlation until inactivity starts cache expiry | 171a24092 (merged) | develop | [Independent packets](Results/S1-independent-packets.json) |
| [E05 #3220](https://github.com/DataDog/dd-sdk-ios/pull/3220) | Preserve request-time RUM ownership in automatic Trace, including explicit nil | ba03a1ba4 | develop | [Trace admission](Results/S1-E05-release-admission.json), [signed-tree receipt](Results/S1-local-preparation.json) |

E05's original qualified checkout remains intact. Its final two test-only commits
were re-signed in a separate checkout with identical complete trees. Previously
qualified shared feature-document corrections now exist upstream; the rebased
PRs retain only their own documentation changes. Product PRs exclude the planning
directory and both protected paths.

The [CI follow-up record](Results/S1-ci-followup.json) owns the remaining failure investigations, exact assertions, environments and decisive checks. H00's two review corrections are qualified and published; the user resolved E02's feature-document finding.

## Finite remaining delivery checklist

| Deliverable | Owner | Dependency | Decisive completion check | Environment |
| --- | --- | --- | --- | --- |
| Current required CI | Repository CI / main implementer | Published candidate heads | Every required check passes on the actual PR head; preserve and investigate failures | Repository CI |
| Human review and source-bound final acceptance | RUM maintainers | Concrete PRs and qualification records | Requested changes resolved; applicable F06 conditions explicitly accepted | PR review / candidate evidence |
| H00 upstream verification and E01 rebase | Completed September 22 | H00 merged externally; E01 already based on develop | Historical boundary `8d7e429b0`; upstream hitch content identical; only E01 own commits replayed | [Rebase receipt](Results/S1-rebase-20260922.json) |
| Independent merges and delivery verification | Maintainers / main implementer | Separate merge authorization; accepted CI/review | Each actual upstream change matches its reviewed content; record merge commit and rollback boundary | GitHub / Git |
| Recompose S2 from merged fixes | Main implementer | Actual upstream source available | Source audit includes only required fixes and identifies invalidated candidate gates | Isolated checkout / finite S2 gates |

Historical qualification used `62f64d7b` and E03 reconciliation used `9a8a66c3`.
The current five PR heads use `dfc3ffcca`, including H00, E04, release 3.18.0 and
PR3196's timeseries pause fix. No duplicate pause fix was introduced. Current CI
is pending at the rebase snapshot; earlier runtime/backend evidence remains bound
to its original source. No merge or TestFlight was performed by this task.

## Preserved boundaries

- Session Replay scope is host crash safety and non-disruption to other SDK
  features. Do not test or repair captured content; prior failures remain evidence.
- Preserve the [approved failed-transfer decision](E03_RESOURCE_COMPLETION_DECISION.md):
  one owning network Error, no completed Resource, received status retained;
  successful bodies, empty HEAD/204 responses and existing manual behavior remain.
- Do not import unrelated scene APIs, broad baggage-header policy or combined S2
  work into independent packets. Keep the selected source/path inventories exact.
- Re-signing, title/body edits and metadata changes require identity verification,
  not repeated native tests. Run only missing or invalidated checks.
- Preserve both user-owned paths; commit explicit paths only. Sign when available,
  and require verified signatures throughout outgoing history before any push.

The [historical preparation plan](S1_PREPARATION_HISTORY_20260921.md) retains the
completed design/extraction narrative. The sole restart position remains
[.continue-here.md](../../.continue-here.md); the delivery plan creates no new gate.
