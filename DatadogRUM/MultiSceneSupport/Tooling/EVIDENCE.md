# Evidence and acceptance contracts

Read when defining, interpreting or reusing a run. Exact inventories, thresholds,
phase deadlines and attempt limits live in the owning definition/fixture README.
This page preserves common discriminators; it does not replace those contracts.

## Measurement policy

The [project-wide rule](../../MULTI_SCENE_SUPPORT.md#measurement-and-testing-rule)
requires event attribution and View/Navigation/Action capture. Preserve recorder
costs as diagnostics; numerical timing overruns alone do not invalidate correctness.
Actual missing or inconsistent evidence, changed owners, consumed readiness and
unresolved native outcomes still block the affected claim. Timeouts remain bounded
operational safeguards, with scenario, evidence and cleanup verdicts kept separate.

## Admission and ownership

Name an existing release gate or reproduced regression, the candidate/stage, one
owner, decisive oracle, required environment, complete expected inventory, source
and helper identities, retry policy, execution/cleanup budgets and stop rules.
Freeze them before implementation/execution at the boundaries the protocol requires.
Qualify one small end-to-end path before expanding a new harness; reuse that cell
within its matrix rather than adding an identical smoke run.

One owner integrates a coupled fixture/runner/evaluator. Root owns the sole native
build/run lane. Use the designated independent reviewer for consequential SDK
concurrency/lifetime or new oracle decisions; routine host/bookkeeping corrections
need a concise changed-input record, not another design chain. No competing builds,
profiling or measurements during a timed workload. Engineering time alone does not
expire unchanged reviewed artifacts; actual execution and cleanup budgets do.

An amended input/oracle does not overwrite an earlier verdict or reset its deadline.
Preserve failures, define the changed boundary and admit only the needed continuation.
No metadata-only change, reconnection or restart requires repeating accepted tests.

## Evidence levels

| Evidence | Establishes | Does not establish |
| --- | --- | --- |
| Source/compiler audit | Reachability, platform guards, dependency or ownership shape | Executed runtime behavior |
| Deterministic SDK tests | Named routing, lifetime and reentrancy contracts under controlled inputs | Native OS ordering, visible topology or upload |
| Mounted/native receipt | Exact exercised callbacks, owners, input and installed identity | Unobserved physical ordering or backend persistence |
| Backend events/reducers | Queried complete inventories and exact persisted ownership/values | Missing local boundaries or unqueried events |
| Physical/visual proof | The recorded device, topology and native input interval | Duo hinge/scheduling parity on other hardware |

Counts, callback completion and absence of crashes alone do not prove semantic
ownership. A posted scene notification is not OS disconnect; a weak controller
check is not keyed SwiftUI registration/instrumentation teardown. Maintain separate
native, mapper, backend, reduced entity, profile and cleanup verdicts.

## S2 no-regression scope

The [S2 register contract](../release-gates.json) selects the evidence required by
that release. Exact ownership and actual native outcomes remain strict; complete
raw backend field equality and ideal callback ordering are not universal gates.
The [scope review](../Results/S2-release-gate-review-20260925.json) defines the finite
packages and preserves earlier invalid attempts. It does not amend S1/S3 contracts.

For a new S2 run, freeze a behavioral cutoff separately from delivery/collection.
Ordinary foregrounding may upload queued data afterward; capture its new occurrences
separately. Do not require immediate background upload or an inactive Session.
Missing required backend evidence leaves that obligation incomplete, without erasing
independently valid local behavior. Cleanup remains mandatory. A retrospective
assessment must name its narrower claim and original artifacts; never rewrite the
old overall verdict or synthesize a missing observation.

## Durable artifact contract

Use a new output directory and run ID. Record source revision/signature, exact
source path/hash dictionary and archive, fixture/runner/oracle manifests, dependency
and toolchain/runtime metadata, complete built/installed Mach-O map, process identity,
clean-install proof, ordered raw native receipts, critical-boundary/topology evidence,
finalized tests, raw backend exchanges with request/deadline/pagination identity,
strict semantic projection, cleanup and one compact durable summary.

The [acceptance harness](../../../tools/multi-scene/acceptance/README.md) connects
preflight, installation, source identity, scenario, backend and summary. Its named
`scenario` selection must retain the default action contract and prior families.
Expected inventories travel in nonce-bound requests. Preserve raw console/screens/
bundles locally and commit only sanitized summaries and durable artifact locators.
Do not log credentials or unrelated customer data.

Persist observed bytes before parsing, terminal-failure handling and uninstall.
Capture/persistence errors do not suppress cleanup or the original failure. Each
response binds its own request, phase and deadline. Include decode, persistence,
manifest verification and final assembly inside the budget; a late response stays
available as evidence without a PASS. Reject truncation even if counts match.
Publish a terminal transport error when validation fails, so the driver can stop
and enter cleanup promptly. Reserve cleanup time for actual tool round trips and
keep the input quiescence fence; elapsed deadlines never authorize another action.
Transfer the actual returned UI response directly. Matching prior text or checksums
do not authorize substituting another phase's observation as the current receipt.
A late terminal may establish worker quiescence for separately admitted restoration,
but cannot reopen the original cleanup or acceptance deadline.
Preflight output directories, schemas and atomic no-clobber response publication
before native execution. The runner owns decode, persistence, current native
sampling and assertions after the actual UI return. Use one bound interaction
qualification, preferably the first planned baseline cell. If it fails, stop that
path and use the prepared human session. Derive future fixed budgets from observed
latency; never renew an active or expired deadline. For the prepared WebView flow,
[the fixture contract](../../../tools/multi-scene/webview-correlation/S2/README.md)
joins app-local monotonic consumption with host-local publication by exact request/
response hashes and sequence. Preflight real atomic response publication before launch. Keep host-wall and native clocks
separate: prove causal request/response binding and native monotonic ordering, or
measure an explicit clock-offset bound. Record scenario/evidence/cleanup separately;
incomplete required evidence or cleanup leaves overall acceptance invalid.


Before backend projection/assembly, verify the live helper files against the
approved manifest, not merely hash labels in a response. Reject extra/missing files,
foreign-run payloads, symlinks, malformed types and ambiguous flattened/nested fields.
Complete JSON objects in mixed stdout/OSLog need actual prefixes and sequence checks.

For approval-gated execution, issue the short-lived admission inside the approved
process from an immutable request; an approval delay must not consume its runtime
budget. Bind fresh identities and fixed deadlines before native actions. Retain
startup stdout/stderr and an exit receipt even when no scenario summary is created.
Do not manufacture missing records or metadata from expected names/phases.

## Critical-boundary controls

Freeze positive and negative controls with the oracle. At minimum preserve the
applicable controls for stale fixtures/run IDs, consumed readiness, missing or late
critical assertions, wrong owner, wrong count, duplicate/extra event, stopped/foreign
source, incomplete pagination, malformed field and missing cleanup. A passing
count-only oracle must not replace an earlier ownership discriminator.

Prove live views and topology **before** the API interval. Capture accepted state,
request-release barriers, callbacks and completion order at the actual boundary.
Backgrounding may legitimately end a view/action between driver steps. A bounded
synchronous two-view batch establishes only that serial contract.

Mapper Home records contain exact RUM UUID plus logical scene/screen, not an
invented occurrence number. Action records use `sourceContext` and `rumContext`.
Bind markers to independently observed event/view/session IDs and the immediately
preceding mapper version/sequence. Reject early same-name completion and stale
readiness. Native/model/backend evidence must agree independently.

Public accessibility inventories can include non-view containers. Preserve actual
object identities and container edges, and require every selected target to have a
path to the source-bound owned window. Reject mixed/partial provenance, duplicate
objects, unknown parents and disconnected graphs. Connected cycles are valid when
the walk is bounded; private class names, matching titles and overlapping frames
do not establish ownership. A source-only traversal control does not prove the
actual SwiftUI graph or its observation cost.

A boundary must select its mapper and append its sequence under the same evidence
lock. A snapshot taken before asynchronous readiness work can become stale while
retaining the correct view ID. Complete SDK callbacks and main-thread observations
before that lock, and keep the latest-mapper oracle strict.

The evidence lock orders recorded rows. If event serialization precedes that lock,
a callback snapshot cannot establish mapper-entry or internal SDK command ordering.
Preserve the missing-boundary verdict and examine the actual dispatch/recording path
before attributing an SDK regression. A later correct action does not repair that
boundary, and unchanged dispatch source does not qualify an unexecuted candidate.

Decode primitive/ObjC-wrapped mapper values through the actual encoding path.
`AttributeValue.dd.decode` casts the stored value; it does not construct an arbitrary
Codable enum. Encode/decode declared evidence types when needed, test actual
projections, and reject Boolean/number coercion. Missing indexed data and connector
projection defects need separate checks against exact encoded JSON.

## Verdicts and corrections

- **PASS**: every admitted predicate passes within its boundary and budget.
- **FAIL**: the admitted semantic assertion is violated; retain raw findings.
- **INVALID**: setup, fixture, oracle or collection cannot support the intended test.
- **INCONCLUSIVE**: environment or incomplete evidence prevents the required claim.
- **SKIPPED / NOT_RUN / PREPARED**: record exactly what did not execute; no pass follows.

Keep the original label and a later reviewed classification separately. A local
oracle failure cannot be rescued by a backend match. A parser correction may
re-audit immutable saved bytes with separate provenance; missing native/upload
boundaries need a separately admitted run, not expected-value synthesis. Cleanup
and infrastructure failures do not automatically attribute an SDK defect.

Date projections must match the source operation order and integer conversion.
Bind a small exact-source reference when diagnosing rounding; do not add a time
tolerance. Recheck every remaining predicate after a parser fix: a complete row
inventory may still contain an unsettled session aggregate. Collect missing
backend evidence separately while retaining the original verdict and deadline.

A narrow representation exception must preserve original presence/type/values and
its negative controls. Examples: empty slow-frame mapper arrays may be absent
backend fields, but explicit null or a missing nonempty array is different; backend
view revisions can differ from mapper revisions but must remain positive integers.
Exact IDs, owners, values and terminal inventories remain mandatory.

## Reuse and candidate promotion

Bind reuse to the original definition, source/build/oracle hashes, complete receipts,
terminal state and scope. A changed commit ID with identical relevant bytes does
not invalidate evidence; different source composition does not inherit a full-suite,
Duo, backend or app pass. Retain accepted per-cell identities after host-only changes.
A successor may reference an immutable completed predecessor in a fresh plan. Bind
its source/products, reviewed helpers, verdicts, quiescence and restoration; never
copy a result into an unexecuted cell or mutate the consumed plan. Preserve separate
semantic failure classifications when reusing capture-mechanism qualification.

Read the authoritative register's absolute path/hash and the intended
`release_requirements.S1|S2|S3`. The experimental-reference status and an older
checkout are not the selected release qualification. Reject an authority mismatch
before changing gates. Inventory every retained SDK/auxiliary-source delta and
map each inherited invariant separately. Reopen only concrete invalidated
obligations, preserving their owner, dependency, decisive test and environment.
[EXP-216](../Results/EXP-216-s2-composition-promotion.json) illustrates this review.

An archive with historical paths is evidence, not a portable CI runner or fresh
execution authority. Gate status belongs to the register, generated progress to
PLAN, and completed narratives to their owning records. Use
[documentation maintenance](DOCUMENTATION.md) to update them once.

## Scope limits

Session Replay acceptance concerns host-app crash safety and non-disruption to other
SDK features. Captured-content correctness, full Replay capture suites and content-
fixture waivers are outside current scope; retain their historical failures.

Detailed network/per-dispatch benchmarking is optional. Object lifetime, correctness
and attribution remain required. Included new semantic SwiftUI/multi-scene code
requires representative application-visible frame rate, hitches/hangs, CPU and
memory comparison, or a reviewed source exclusion establishing non-applicability.
Historical [baseline thresholds](../BASELINES.md) remain unchanged; simulator numbers
or missing warning frames cannot establish device performance or crash freedom.


## Asynchronous fixture persistence

A reserved event sequence does not prove that its bytes reached disk. A serial
writer checkpoint must follow all earlier enqueued writes and bind the exact run,
request, final sequence, byte count and hash. Validate that durable prefix before
consuming readiness. Keep later bytes separate; a partial tail or matching older
snapshot cannot repair a missing receipt. Preserve actual callback effects and
measure observer cost before attributing an input failure to SDK code.
