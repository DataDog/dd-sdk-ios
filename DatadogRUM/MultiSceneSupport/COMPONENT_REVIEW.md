# Incremental multi-scene component review

Original review 2026-09-17 against `af63657f08dbecb66e7c3ae97ed53fc8f7b065b9`.
R02 was reviewed again at signed `7b77f60eb` during EXP-168. Original line ranges
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
| R04 | Ordinary/keyed modifiers and attachment/lifetime boundaries (3900–4789, 5796–6096): single-scene branch, availability fallback, declaration-owned State, generation-checked one-turn detach grace | Retained reader and reconstruction tests; `testWhenDetachedStateIsReleased_queuedFinalDetachStillRuns`, detach/reattach cancellation | BLOCKED by D08 and delayed remount coverage. D03 mounted teardown passes EXP-168; stale-trait reconnect and retained-host reattachment remain separate. |
| R05 | Transition source, observed adapter and host engine (4790–5379): stable source pinning, lazy observed authority, Observation rearm before receive, FIFO main dispatch, exact source unsubscribe | Observation synchronous/nested mutation, adapter deallocation, publisher pinning, background FIFO and exact host disconnect tests | BLOCKED by D08 and missing multi-observer reentrancy coverage described below. D07 pending authority passes EXP-169. |
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
review; P03 still needs disconnected-registry retirement, and R04 needs D08 plus
delayed retained-host remount. No extraction or final independent review is claimed.

**D07, pending semantic authority — closed in EXP-169.** Source selection and
subscription no longer activate suppression. Four real-registry controls fail on
the unchanged SDK for empty explicit/capability input, absent handler and absent
attachment; all pass when authority waits for publication prerequisites. The119
affected tests pass. Mounted explicit/capability hosts pass29/29 versus19/29,
including automatic owners before input and an action submitted immediately at
the first accepted input. Two previous tests that assumed authority without a
handler now distinguish source pinning from actual publication. D08 still owns
rejected disconnected publication; R05 still needs reentrant fan-out evidence.

**D08, disconnected host generation.** The host unconditionally records an
`ActiveOccurrence` after a void handler callback (5369), even if that handler
rejects a disconnected scene. A stale inherited trait can reach this path before
a live reader remount (6063). The subsequent generation equality guard can hide
the first accepted reconnect start. Required: put stale-trait reconciliation
between disconnect and real connection/reader mount; require exactly one fresh
UUID and correctly owned immediate telemetry. Keep physical ordering in H09.

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

**R04/R06, lifetime boundaries.** Existing tests prove synchronous reader bounce
and one-queue-turn detach cancellation. They do not prove delayed retained-host
reattachment or same-ID sheet/cover replacement ordering. H08/H09 and the R06
regression selection must cover these cases with occurrence identity; keep the
source review's hypotheses separate from reproduced results.

## Review and extraction boundary

R01/R02/R03 close only their bounded source-review obligations. R04/R05/R06 remain
blocked until the stated regressions are tested and the findings are fixed or
rejected with evidence. Keep the existing synchronous accepted-state boundary:
blindly moving reconciliation to onAppear or another task would reintroduce the
known immediate-telemetry ownership gap. Splitting the file is deferred; repairs
should be small, independently reviewable changes tied to named gates.
