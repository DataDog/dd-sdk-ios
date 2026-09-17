# Incremental multi-scene component review

Reviewed 2026-09-17 against `af63657f08dbecb66e7c3ae97ed53fc8f7b065b9`.
The 6,613-line `SwiftUIViewModifier.swift` was reviewed by responsibility before
further API expansion. This is a source review with existing regression evidence,
not final independent release sign-off or a new device run. Deferred extraction
remains in [its separate plan](DEFERRED_SINGLE_SCENE_EXTRACTION.md).

The concurrent, user-owned `PRODUCTION_SAFETY_REVIEW.md` was consulted and left
unchanged/uncommitted. Its reported reproductions are attributed to that review;
this pass independently inspected the SwiftUI source paths below. D01–D12 in the
release register preserve its finite repair/triage obligations. None closes merely
because a report exists. No production source changed during this review.

## Responsibility results

| Gate | Source boundary and inspected invariant | Existing decisive coverage | Disposition |
| --- | --- | --- | --- |
| R01 | Trait publisher/readers (1–325), tracking state and disconnect fence (1015–1580): weak notification ownership, main-thread seed, mount before change, generation-based stale callback rejection, detached versus legacy attachment | `testWhenActiveSceneDisconnects_itInvalidatesSilentlyUntilExplicitRemount`, keyed-disconnect/new-generation, latest-reader-binding and scene-migration tests in `SwiftUIViewNameExtractorTests` | Bounded reader review complete. H09 still requires genuine OS disconnect/remount. D08 covers the distinct semantic-host trait path. |
| R02 | Weak authority/occurrence registries and keyed registration (1358–2780): subtree-local suppression, exact occurrence stop, stale registration epoch rejection | Dormant/reveal, scoped suppression, exact host removal and disconnect tests | BLOCKED by D03: the registry's weak references do not break the registration callback's strong capture of the modifier. |
| R03 | Deferred intent and interactive arbitration (3060–3899): scene/coordinator key, cancel rearm, pending identity check, remove pending before commit, preserve peer on disconnect | Interactive cancel/finish, concurrent keyed disconnect, pending migration and reregister-cannot-bypass-cancel tests | Bounded arbitration review complete. H11–H13 remain real recognized-gesture gates. Source observer fan-out is R05, not this arbiter. |
| R04 | Ordinary/keyed modifiers and attachment/lifetime boundaries (3900–4789, 5796–6096): single-scene branch, availability fallback, declaration-owned State, generation-checked one-turn detach grace | Retained reader and reconstruction tests; `testWhenDetachedStateIsReleased_queuedFinalDetachStillRuns`, detach/reattach cancellation | BLOCKED by D03/D08. A queued final callback can survive owner release, but that does not prove mounted keyed modifier teardown or stale-trait reconnect safety. |
| R05 | Transition source, observed adapter and host engine (4790–5379): stable source pinning, lazy observed authority, Observation rearm before receive, FIFO main dispatch, exact source unsubscribe | Observation synchronous/nested mutation, adapter deallocation, publisher pinning, background FIFO and exact host disconnect tests | BLOCKED by D07/D08 and missing multi-observer reentrancy coverage described below. |
| R06 | Native semantic state/public hosts (5380–5795, 6097–6496): accepted path getter, presentation ownership, automatic metadata, explicit-over-capability precedence, unchanged standard-container integration | Rejected/canonicalized path tests, native presentation tests, host reconstruction, capability precedence and pending-observed-input tests | BLOCKED by D10. Accepted-path handling is sound in the reviewed seam; presentation writes use a different ordering. Stable API sign-off remains F01. |

Names above identify coverage in `SwiftUIViewNameExtractorTests.swift` and
`RUMViewsHandlerTests.swift`; their accepted EXP-159 suite checkpoint is 1,260/1,260.
That checkpoint was not rerun merely for this review and does not cover the gaps
below. A passing broad suite does not override a concrete untested failure path.

## Findings and remaining decisive checks

**D03, registration lifetime.** At lines 4456 and 4698, `rebind` stores an escaping
closure that calls the modifier's `apply` and accesses its `transitionArbiter`.
The modifier owns its State registration and instrumentation; the registration
owns `process` (2621–2644). The weak source/state fields do not break this cycle.
The separate safety review reports an ARC-shape reproduction, not mounted-device
proof. Required: cancellable context without bound-modifier capture, then a real
keyed host removal and SDK release test proving weak registration/instrumentation
release and balanced unswizzling. P03 cannot close from controller-only teardown.

**D07, pending semantic authority.** `RUMSemanticNavigationHostState.reconcile`
selects a nonnil explicit source and calls `suppressionState.appear()` before
observing whether it has any current snapshot (5271–5276). An empty explicit or
capability source can therefore suppress automatic discovery without starting a
semantic occurrence. Observed input's nil-before-first-value path is different.
Required: real authority-registry tests for empty explicit/capability sources,
first accepted state, and absent instrumentation. Subscribe independently from
acquiring suppression authority.

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

R01/R03 close only their bounded source-review obligations. R02/R04/R05/R06 remain
blocked until the stated regressions are tested and the findings are fixed or
rejected with evidence. Keep the existing synchronous accepted-state boundary:
blindly moving reconciliation to onAppear or another task would reintroduce the
known immediate-telemetry ownership gap. Splitting the file is deferred; repairs
should be small, independently reviewable changes tied to named gates.
