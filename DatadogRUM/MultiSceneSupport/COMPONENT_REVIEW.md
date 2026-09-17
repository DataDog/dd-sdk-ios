# Incremental multi-scene component review

Original review 2026-09-17 against `af63657f08dbecb66e7c3ae97ed53fc8f7b065b9`.
R02 was reviewed again at signed `7b77f60eb` during EXP-168, and R04 at signed
`66d1ccb02`/`4ba7179c6` during EXP-170/171. R06 was reviewed again at signed
`7619eb8a2` during EXP-173, and R05 at signed `368c62a72` during EXP-174. Original line ranges
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
| R05 | Transition source, observed adapter and host engine (4790–5379): stable source pinning, lazy observed authority, Observation rearm before receive, FIFO main dispatch, exact source unsubscribe | Observation synchronous/nested mutation, adapter deallocation, publisher pinning, background FIFO and exact host disconnect tests | CLOSED in EXP-174 after three failing controls, nine new regressions and346 affected tests; initial/commit generations, nested return, add/remove and actual two-host teardown pass. |
| R06 | Native semantic state/public hosts (5380–5795, 6097–6496): accepted path getter, presentation ownership, automatic metadata, explicit-over-capability precedence, unchanged standard-container integration | Rejected/canonicalized path tests, native presentation tests, host reconstruction, capability precedence and pending-observed-input tests | CLOSED in EXP-173: accepted getter after one transaction write, occurrence-token callbacks, accepted mount authority and stable rematerialization;337 tests and native77/77. Stable API sign-off remains F01. |

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
review; P03 disconnected-registry retirement closes separately in EXP-172. R04's later D08 and
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

**D10/R06, accepted presentations — closed in EXP-173.** The actual native
Binding factory now forwards its transaction once and reads accepted state before
returning. Rejection preserves the current owner; canonicalization does not commit
the proposal. Mount/disappear closures capture an internal occurrence UUID, so
same-ID sheet→cover and A→B→A cannot revive/stop a later occurrence. Only accepted
handler publication sets started state and acquires suppression; rejected migration
preserves the old owner. Container detach and disconnect still cancel independently.
No callback is retained by the state, so boundary captures add no reverse ARC edge.
Standard container call sites, availability and metadata/default precedence remain.

The first native candidate still churned SheetAgain before old-callback injection:
SwiftUI rematerialized accepted content. The disappearance callback now reads the
current accepted Binding; unchanged accepted content keeps its occurrence, while
accepted nil balances once. A new failing unit control and the native
pre-injection stability check preserve this discriminator. All337 affected tests
pass. Native77/77 versus55/77 validates exact presentation/Home counts, peer
continuity and Resource/Log view/session IDs inside rejecting setters, immediately
after return and at actual native onDismiss. All invalid/failed attempts remain.
Opaque setter interiors still require an observed/explicit transition boundary;
no speculative proposal ownership, public API, extraction or physical ordering
claim was added. This closes the bounded R06 responsibility review.

**R05, reentrant observer fan-out — closed in EXP-174.** Three deterministic
controls reproduce `[0, 2, 1]` on nested commit, `[1, 0]` on nested initial
publication, and three callbacks after the first callback removes all observers.
Whichever observer receives the outer value first triggers the test; no dictionary
ordering assumption is involved. The single new `publish` helper snapshots IDs,
looks up live membership before each callback and stops an outer generation once
a nested commit supersedes it. The initial and ordinary publication paths share
this helper. Nested commit stays synchronous; every live observer has the newest
generation before it returns. Added observers receive current state once through
observe, and removals cancel pending delivery.

The observed adapter updates identity and rearms Observation before delivering;
actual multi-observer publisher and Observation tests preserve the latest value.
Source pinning, weak host captures, source unsubscribe and background FIFO remain
covered. Two actual host states emit distinct scene-local Latest occurrences,
keep their independent peer untouched and stop exactly those occurrences; removal
during nested delivery cannot revive a detached host. All346 affected tests and
strict source/test lint pass at signed `368c62a72`. This closes the bounded R05
review without deferring callbacks, adding API or changing event dispatch.
[Durable result](Results/EXP-174-observer-delivery.json) retains three failed
controls, all selectors and source identities. No physical/backend/final review
claim follows from this synchronous in-memory contract.

## Review and extraction boundary

All six responsibility gates close only their bounded source-review obligations.
Independent final release review and stable API sign-off remain required. Keep the existing synchronous accepted-state boundary:
blindly moving reconciliation to onAppear or another task would reintroduce the
known immediate-telemetry ownership gap. Splitting the file is deferred; repairs
should be small, independently reviewable changes tied to named gates.
