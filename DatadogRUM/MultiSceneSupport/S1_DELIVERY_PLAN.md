# S1 delivery sequence

Current delivery facts were refreshed from GitHub on September 30, 2026.
[The queue](Results/S1-delivery-queue.json) owns exact PR heads, reported CI
statuses, review observations and merge commits. Earlier packets and
[the September22 rebase receipt](Results/S1-rebase-20260922.json) retain their
historical source and validation identities; they are not the current PR inventory.

## Review units

Four units are merged: H00, DL01, E02 and E04. E01, E03 and E05 remain open.
H00's upstream prerequisite and E01's retarget to develop are complete.
Maintainers own final CI/review acceptance and merges.

| Unit / PR | Customer behavior | Observed head | Delivery state |
| --- | --- | --- | --- |
| [H00 #3214](https://github.com/DataDog/dd-sdk-ios/pull/3214) | Reconstruct full/delta view state before hitch assertions; test-only | `0deff4750` | Merged September22 |
| [E01 #3215](https://github.com/DataDog/dd-sdk-ios/pull/3215) | Prepare URLSession instrumentation once per task and SDK instance | `69c0b4017` | Open; GitHub reports mergeable; current CI failing and maintainer acceptance pending |
| [DL01 #3216](https://github.com/DataDog/dd-sdk-ios/pull/3216) | Release display-link observers through a weak callback target | `0ca7cafbc` | Merged September23 |
| [E02 #3217](https://github.com/DataDog/dd-sdk-ios/pull/3217) | Keep attributes on the active occurrence of a repeated view key | `568be6cb8` | Merged September24 |
| [E03 #3218](https://github.com/DataDog/dd-sdk-ios/pull/3218) | Keep late Resource/action effects on their owner; failed transfers emit one Error | `e3c3bde1c` | Open; reported CI green, maintainer approval observed; GitHub reports a merge conflict |
| [E04 #3219](https://github.com/DataDog/dd-sdk-ios/pull/3219) | Keep active native-view correlation until inactivity starts cache expiry | `171a24092` | Merged September22 |
| [E05 #3220](https://github.com/DataDog/dd-sdk-ios/pull/3220) | Preserve request-time RUM ownership in automatic Trace, including explicit nil | `ba03a1ba4` | Open; reported CI green; maintainer approval and conflict resolution remain |

At the observed heads, E01 has five passing and six failing reported statuses
(the five platform unit statuses plus aggregate DDCI fail). Its earlier approval
is dismissed and a changes-requested review remains in the timeline. E03 and E05
each have 22 passing reported statuses; E03 has a September28 maintainer approval.
These observations do not establish required-check completeness or permission
to merge. No CI logs were diagnosed or tests rerun for this refresh.

The [CI follow-up](Results/S1-ci-followup.json) retains earlier failures and their
attribution. Do not infer that a current CI failure repeats an older cause.
Investigate flaky CI only with clear evidence implicating changed source or tests.

## Finite remaining delivery checklist

| Deliverable | Owner | Dependency | Decisive completion check | Environment |
| --- | --- | --- | --- | --- |
| E01 current-head CI and review | Repository CI / RUM maintainers | Published replacement head | Applicable required checks and maintainer acceptance on the final head; investigate only attributable failures | Repository CI / PR review |
| E03 and E05 conflict reconciliation | SDK implementer / maintainers | Current base and published head | Preserve reviewed behavior and tests; verify final-head checks/review after resolving actual conflicts | Isolated checkout / repository CI |
| Independent final acceptance and merges | RUM maintainers | Candidate evidence; separate merge authorization | Applicable F06 accepted and actual upstream merge recorded per packet | PR review / GitHub |
| S2 integration bookkeeping | Main implementer | Intended E01 replacement and merged dependencies | Record shipping identities while preserving all original S2 built evidence and closed gates under the approved equivalence decision | Documentation / source identity records |

The register's selected-E01 qualification count is not a delivery count for all
seven units. Its F06 remains open; merged DL01/E02/E04 do not require another
release experiment. Historical source packets remain evidence for their captured
revisions, and saved local checkout paths must be reverified before use.

## E01 and S2 evidence

The [September30 user decision](../MULTI_SCENE_SUPPORT.md#e01-replacement-and-s2-evidence)
accepts the intended per-task-lock E01 replacement as functionally equivalent for
S2. Every existing S2 built result and closed gate remains valid. Replacement
alone does not admit a rebuild, retest, gate reopening or source-reconciliation
prerequisite. Historical captures keep their actual source/build identities.
Current S1 CI and maintainer acceptance remain separate.

## Preserved boundaries

- Session Replay scope is host crash safety and non-disruption to other SDK
  features. Do not test or repair captured content; prior failures remain evidence.
- Preserve the [approved failed-transfer decision](E03_RESOURCE_COMPLETION_DECISION.md):
  one owning network Error, no completed Resource, received status retained;
  successful bodies, empty HEAD/204 responses and existing manual behavior remain.
- Keep independent packets separate from deferred scene APIs, broad baggage policy
  and combined S2 work. Product PRs exclude the planning directory and protected paths.
- Re-signing and metadata edits require identity verification, not repeated native
  tests. The explicit E01/S2 equivalence decision also preserves accepted S2 evidence.
- Preserve user-owned paths and use explicit commit paths. Sign when available;
  verify signatures throughout outgoing history before a separately authorized push.

The [historical preparation plan](S1_PREPARATION_HISTORY_20260921.md) retains the
completed design/extraction narrative. The sole restart position remains
[.continue-here.md](../../.continue-here.md); this status refresh admits no native
run, CI repair, rebase, merge or push.
