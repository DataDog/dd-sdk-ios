# S1 delivery sequence

All seven local packets are qualified within their recorded scopes and have
verified signed outgoing histories. [The queue](Results/S1-delivery-queue.json)
owns current checkout, commit, path and description identities;
[the local preparation receipt](Results/S1-local-preparation.json) verifies them.
Source and test trees remain unchanged. No accepted runtime check needs repeating.

Publication, ticket waiver and merge remain unapproved in this task. A side task
relayed a publication request, but automatic approval review rejected recording
that relay as authority. Direct confirmation is pending. Continue useful local
plan work while waiting; do not repeat the pending question or invent a ticket.

## Review units

Each row is a separate draft PR when publication is authorized. Only H00 → E01
is a hard merge dependency. Shared test files or changelog conflicts do not create
an architectural dependency. The main implementer owns local preparation;
maintainers own CI and review acceptance.

| Unit | Customer behavior | Local head | Review base / dependency | Qualification owner |
| --- | --- | --- | --- | --- |
| H00 | Reconstruct full/delta view state before hitch assertions; test-only | 8d7e429b | develop | [H00/E01 packets](Results/S1-H00-E01-packets.json) |
| E01 | Prepare URLSession instrumentation once; preserve early callbacks and terminal release | ab71c3a6 | H00 for review; verified H00 merge before final retarget | [H00/E01 packets](Results/S1-H00-E01-packets.json) |
| DL01 | Release display-link observers through a weak callback target | 29c28a01 | develop | [Independent packets](Results/S1-independent-packets.json) |
| E02 | Keep attributes on the active occurrence of a repeated view key | 4dec888b | develop | [Independent packets](Results/S1-independent-packets.json) |
| E03 | Keep late Resource/action effects on their owner; failed transfers emit one Error | f43d812d | develop | [Resource packet](Results/S1-E03-packet.json) |
| E04 | Keep active native-view correlation until inactivity starts cache expiry | 171a2409 | develop | [Independent packets](Results/S1-independent-packets.json) |
| E05 | Preserve request-time RUM ownership in automatic Trace, including explicit nil | 44478840 | develop | [Trace admission](Results/S1-E05-release-admission.json), [signed-tree receipt](Results/S1-local-preparation.json) |

E05's original qualified checkout remains intact. Its final two test-only commits
were re-signed in a separate checkout with identical complete trees. All five
feature-document corrections are already included in E02/E03/E04/DL01's explicit
path lists. Product PRs exclude the planning directory and both protected paths.

## Finite remaining delivery checklist

| Deliverable | Owner | Dependency | Decisive completion check | Environment |
| --- | --- | --- | --- | --- |
| Publication authorization and ticket disposition | User / maintainer | Seven concrete local packets | Direct authorization identifies the seven drafts and supplies tickets or an explicit waiver | Current task; no remote write before authorization |
| Seven draft PRs | Main implementer | Authorization; signed histories | Recheck repository/base and duplicates; push exact allowed branches; confirm draft state, head/base, complete diff paths and self-contained bodies | Authenticated GitHub and local Git |
| Current required CI | Repository CI / main implementer | Published candidate heads | Every required check passes on the actual PR head; preserve and investigate failures | Repository CI |
| Human review and source-bound final acceptance | RUM maintainers | Concrete PRs and qualification records | Requested changes resolved; applicable F06 conditions explicitly accepted | PR review / candidate evidence |
| H00 upstream verification and E01 retarget | Main implementer | Separately authorized, approved H00 merge | Verify actual upstream content; remove duplicate prerequisite from E01 and revalidate only changed inputs/checks | Git / current develop / affected CI |
| Independent merges and delivery verification | Maintainers / main implementer | Separate merge authorization; accepted CI/review | Each actual upstream change matches its reviewed content; record merge commit and rollback boundary | GitHub / Git |
| Recompose S2 from merged fixes | Main implementer | Actual upstream source available | Source audit includes only required fixes and identifies invalidated candidate gates | Isolated checkout / finite S2 gates |

No whole-release readiness follows from local eligibility. The current source
baseline is 62f64d7b; recheck upstream before publication. No merge or TestFlight
operation is authorized. Candidate-scoped runtime, backend and warning limits
remain in the linked qualification owners.

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
