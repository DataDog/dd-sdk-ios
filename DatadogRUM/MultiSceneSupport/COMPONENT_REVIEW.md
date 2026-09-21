# Incremental multi-scene component review

**This bounded responsibility-review cycle is completed.** Current release
obligations belong to [the register](release-gates.json); this record does not
certify release readiness or direct the next experiment.

Original review 2026-09-17 against `af63657f08dbecb66e7c3ae97ed53fc8f7b065b9`.
R02 was reviewed again at signed `7b77f60eb` during EXP-168, and R04 at signed
`66d1ccb02`/`4ba7179c6` during EXP-170/171. R06 was reviewed again at signed
`7619eb8a2` during EXP-173, and R05 at signed `368c62a72` during EXP-174. Original line ranges
below refer to the original review; current symbol names identify the boundaries.
The 6,613-line `SwiftUIViewModifier.swift` was reviewed by responsibility before
further API expansion. This is a source review with existing regression evidence,
not final independent release sign-off or a new device run. Independent extraction
now proceeds under [its plan](DEFERRED_SINGLE_SCENE_EXTRACTION.md), with a generic
current-develop reproducer and separate candidate review; this completed audit
does not establish that an experimental repair affects existing customers.

The original review consulted `PRODUCTION_SAFETY_REVIEW.md` without editing it.
That document now has a tracked live disposition table at the user’s request.
Its historical reproductions are attributed to that review;
this pass independently inspected the SwiftUI source paths below. D01–D12 in the
release register preserve its finite repair/triage obligations. None closes merely
because a report exists. No production source changed during this review.

## Responsibility results

| Gate | Source boundary and inspected invariant | Existing decisive coverage | Disposition |
| --- | --- | --- | --- |
| R01 | Trait publisher/readers (1–325), tracking state and disconnect fence (1015–1580): weak notification ownership, main-thread seed, mount before change, generation-based stale callback rejection, detached versus legacy attachment | `testWhenActiveSceneDisconnects_itInvalidatesSilentlyUntilExplicitRemount`, keyed-disconnect/new-generation, latest-reader-binding and scene-migration tests in `SwiftUIViewNameExtractorTests` | Bounded reader review complete. H09 still requires genuine OS disconnect/remount. D08 covers the distinct semantic-host trait path. |
| R02 | Weak authority/occurrence registries and keyed registration (1358–2780): subtree-local suppression, exact occurrence stop, stale registration epoch rejection | Dormant/reveal, scoped suppression, exact host removal and disconnect tests | CLOSED in EXP-168 after weak callback context, explicit cancellation/rebind epoch tests, 303 affected tests and mounted release/teardown on27/26.5. |
| R03 | Deferred intent and interactive arbitration (3060–3899): scene/coordinator key, cancel rearm, pending identity check, remove pending before commit, preserve peer on disconnect | Interactive cancel/finish, concurrent keyed disconnect, pending migration and reregister-cannot-bypass-cancel tests | Bounded arbitration review complete. H11–H13 remain real recognized-gesture gates. Source observer fan-out is R05, not this arbiter. |
| R04 | Ordinary/keyed modifiers and attachment/lifetime boundaries (3900–4789, 5796–6096): single-scene branch, availability fallback, declaration-owned State, generation-checked one-turn detach grace | Retained reader and reconstruction tests; `testWhenDetachedStateIsReleased_queuedFinalDetachStillRuns`, detach/reattach cancellation | CLOSED in EXP-171: after D03/D08, no-body retained-reader controls and native first-callback57/57 versus43/57 prove fresh Latest ownership, weak configuration and teardown. H08/H09 physical ordering stays separate. |
| R05 | Transition source, observed adapter and host engine (4790–5379): stable source pinning, lazy observed authority, Observation rearm before receive, FIFO main dispatch, exact source unsubscribe | Observation synchronous/nested mutation, adapter deallocation, publisher pinning, background FIFO and exact host disconnect tests | CLOSED in EXP-174 after three failing controls, nine new regressions and346 affected tests; initial/commit generations, nested return, add/remove and actual two-host teardown pass. |
| R06 | Native semantic state/public hosts (5380–5795, 6097–6496): accepted path getter, presentation ownership, automatic metadata, explicit-over-capability precedence, unchanged standard-container integration | Rejected/canonicalized path tests, native presentation tests, host reconstruction, capability precedence and pending-observed-input tests | CLOSED in EXP-173: accepted getter after one transaction write, occurrence-token callbacks, accepted mount authority and stable rematerialization;337 tests and native77/77. Stable API sign-off remains F01. |

Names above identify coverage in `SwiftUIViewNameExtractorTests.swift` and
`RUMViewsHandlerTests.swift`; their accepted EXP-159 suite checkpoint is 1,260/1,260.
That checkpoint was not rerun merely for this review and does not by itself cover the subsequently repaired paths
below. A passing broad suite does not override a concrete untested failure path.

## Repair evidence

Detailed D03/D07/D08/R04/R05/R06 repair narratives are preserved in the
[historical checkpoint](Experiments/DOCUMENTATION_CHECKPOINT_EXP-220.md#component-repair-history).
Current original/subsequent finding dispositions belong to
[the safety table](PRODUCTION_SAFETY_REVIEW.md), with direct experiment/result links.
The table above retains the independently inspected responsibilities and limits.

## Review and extraction boundary

All six responsibility gates close only their bounded source-review obligations.
Independent final release review and stable API sign-off remain required. Keep the existing synchronous accepted-state boundary:
blindly moving reconciliation to onAppear or another task would reintroduce the
known immediate-telemetry ownership gap. Splitting the file is deferred; repairs
should be small, independently reviewable changes tied to named gates.
