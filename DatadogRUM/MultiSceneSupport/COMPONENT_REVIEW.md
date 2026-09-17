# Incremental multi-scene component review

Original review 2026-09-17 against `af63657f08dbecb66e7c3ae97ed53fc8f7b065b9`.
R02 was reviewed again at signed `7b77f60eb` during EXP-168, and R04 at signed
`66d1ccb02`/`4ba7179c6` during EXP-170/171. Original line ranges
below refer to the original review; current symbol names identify the boundaries.
The 6,613-line `SwiftUIViewModifier.swift` was reviewed by responsibility before
further API expansion. This is a source review with existing regression evidence,
not final independent release sign-off or a new device run. Deferred extraction
remains in [its separate plan](DEFERRED_SINGLE_SCENE_EXTRACTION.md).

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
| R05 | Transition source, observed adapter and host engine (4790–5379): stable source pinning, lazy observed authority, Observation rearm before receive, FIFO main dispatch, exact source unsubscribe | Observation synchronous/nested mutation, adapter deallocation, publisher pinning, background FIFO and exact host disconnect tests | BLOCKED by missing multi-observer reentrancy coverage below. D07/D08 pass EXP-169/170. |
| R06 | Native semantic state/public hosts (5380–5795, 6097–6496): accepted path getter, presentation ownership, automatic metadata, explicit-over-capability precedence, unchanged standard-container integration | Rejected/canonicalized path tests, native presentation tests, host reconstruction, capability precedence and pending-observed-input tests | BLOCKED by D10. Accepted-path handling is sound in the reviewed seam; presentation writes use a different ordering. Stable API sign-off remains F01. |

Names above identify coverage in `SwiftUIViewNameExtractorTests.swift` and
`RUMViewsHandlerTests.swift`; their accepted EXP-159 suite checkpoint is 1,260/1,260.
That checkpoint was not rerun merely for this review and does not cover the gaps
below. A passing broad suite does not override a concrete untested failure path.

## Findings and remaining decisive checks

**D03 / R02, registration lifetime — closed in EXP-168.** Mounted controls on
27/26.5 retain one registration and tracking state per cycle, reaching 25, while
readers/controllers release. Instrumentation remains alive and methods remain
swizzled after SDK stop. The repair stores a bound callback on an independent
context with weak state/handler/arbiter references; neither modifier is captured.
Cancellation removes the source entry, clears metadata/callback and advances the
epoch. Rebinding cancels the old source; hidden routes keep their registrations.
Both runtime candidates pass 37/37 with zero weak survivors and three original
method implementations restored. The 303-test selection covers exact fresh
reveals, current descriptor, stale generations/epochs, peer-local suppression,
released collaborators and interactive cancel/commit. This closes R02's bounded
review; P03 still needs disconnected-registry retirement. R04's later D08 and
no-body retained-host remount evidence is recorded in EXP-170/171. No extraction or final independent review is claimed.

**D07, pending semantic authority — closed in EXP-169.** Source selection and
subscription no longer activate suppression. Four real-registry controls fail on
the unchanged SDK for empty explicit/capability input, absent handler and absent
attachment; all pass when authority waits for publication prerequisites. The119
affected tests pass. Mounted explicit/capability hosts pass29/29 versus19/29,
including automatic owners before input and an action submitted immediately at
the first accepted input. Two previous tests that assumed authority without a
handler now distinguish source pinning from actual publication. D08 still owns
rejected disconnected publication; R05 still needs reentrant fan-out evidence.

**D08, disconnected host — closed in EXP-170.**
The handler now reports accepted insertion/replacement; rejected cross-scene
replacement preserves the old owner. The host distinguishes first inherited
traits from reader mounts after teardown, and uses a new attachment generation.
Its source remains pinned within each live lifetime. Three failing controls and
314 affected tests cover early rejected reader callbacks, stale traits before/after
connection, latest input, repeated reconnects, nil prerequisites, inactive staging,
manual precedence and exact peer stop behavior. Mounted actual explicit/capability
hosts pass51/51 versus39/51; the old SDK sends immediate reconnect Resource/Log
work to Peer, while the candidate uses the fresh Home. The same retained hosting
controller is detached for200ms, then remounted after assigning a new root value;
a third unique Home occurrence and exact Resource/Log owners prove that delayed
boundary. It does not prove a retained reader callback without body reevaluation:
releaseSource clears selectedTransitions/latestSnapshot, while the reader only
reconciles attachment. That remaining R04 path is repaired and tested in EXP-171
below. EXP-168's zero-survivor/swizzle restoration evidence stays
valid. No new availability
requirement or public API was introduced; the split trait callback is within the
existing iOS27/visionOS27 host. This is not independent final review or genuine OS
ordering; H08/H09 remain open.

**R04, retained reader without body rebind — closed in EXP-171.** Two controls
reproduce loss of the latest source after final detach and scene reconnect. The
host remembers configuration weakly while detached, with no subscription or
authority. Only an accepted reader mount reobserves the latest input; a new body
with no source withdraws it. Released source/handler weak references become nil.
All318 affected tests pass, retaining D03/D08 and ordinary/keyed/arbiter coverage.
In both mounted explicit/capability variants the same controller is removed for
200ms, input changes while detached, and the captured reader callback runs with
zero source observers. It forwards SDK delivery, then submits Resource/Log work
before the framework can render. The root value is never replaced. Candidate57/57
uses a fresh Latest UUID/session; control43/57 loses it and misattributes markers.
Exact peer continuity, duplicate mount and final unsubscription checks pass.
This closes the bounded modifier/attachment review, with EXP-168 teardown and
EXP-170 trait fencing retained. H08/H09 physical ordering and final independent
release review are not inferred from it.

**D10, presentation writes.** The adapter reconciles `newItem` before writing the
customer Binding (6445–6451), unlike the path adapter, which forwards and reads
accepted state (5589–5595). A rejecting/canonicalizing setter can leave telemetry
on an unaccepted destination. Required: rejecting nil, canonicalized item,
transaction propagation, emitted setter work and exact dismissal callback tests.
Do not fix this by simply delaying all semantic commits past the critical callback.

**R05, reentrant observer fan-out.** `commit` snapshots a generation and invokes
`observers.values.forEach` synchronously (4834–4846). Existing nested-observer
coverage has one observer. Multiple observers plus a nested commit need a decisive
monotonic-generation test; a later outer callback must never regress a host that
already consumed the nested generation. This is a source-identified coverage gap,
not a reproduced SDK failure in this pass. Also cover observer removal/addition
inside delivery before closing R05.

**R06, remaining presentation lifetime boundary.** R04's no-body retained-reader
remount now passes EXP-171. Same-ID sheet/cover replacement ordering still
needs its decisive R06 regression with occurrence identity. H08/H09 genuine OS
ordering stays separate from deterministic mounted evidence.

## Review and extraction boundary

R01/R02/R03/R04 close only their bounded source-review obligations. R05/R06 remain
blocked until the stated regressions are tested and the findings are fixed or
rejected with evidence. Keep the existing synchronous accepted-state boundary:
blindly moving reconciliation to onAppear or another task would reintroduce the
known immediate-telemetry ownership gap. Splitting the file is deferred; repairs
should be small, independently reviewable changes tied to named gates.
