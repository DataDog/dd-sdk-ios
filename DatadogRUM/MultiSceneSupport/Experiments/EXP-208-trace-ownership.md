# Request-time Trace ownership

## EXP-208 — Preserve request ownership through Trace completion

This experiment is defined for E05 on unchanged develop `62f64d7b`. The
[owning result](../Results/EXP-208-trace-ownership.json) fixes the 90-minute deadline,
13 unit selectors, three native selectors, source boundary and stop rules before
any SDK or test edits. The independently accepted unit and native comparison now
qualifies bounded E05 extraction eligibility; broader release checks remain open.

Outgoing RUM baggage and serialized span ownership are separate paths. The proposed
repair captures the existing optional request-time RUM value and uses it for the
session carrier and all four serialized ownership tags. A present nil RUM value
must stay absent; an unavailable NetworkContext preserves the receiver fallback
captured at request start. Completion without a captured entry keeps legacy behavior.

Eight unit cases are predicted to fail ownership assertions on develop; five
controls preserve sampling, parent/user/account headers, cancellation and guard
behavior. Three private captured-state assertions are replaced before baseline
with their unchanged active-span/GraphQL behavior checks. The complete Trace target
is required after the conditional repair. Sampling expressions and calls remain
unchanged, including the existing receiver fallback when network RUM is nil.

The native comparison uses automatic Trace URLSession instrumentation with manual
RUM views/actions and RUM resource auto-tracking disabled. Two held requests finish
in reverse order; another starts before RUM exists and completes after RUM activation.
Both inspect serialized Trace spans and actual outgoing headers. The existing parent
span test remains the third control. RUM-resource payloads cannot substitute for this
oracle because RUM-origin requests suppress the local Trace span under review.

The [independent design review](../Results/EXP-208-design-review.json) permits three
internal Trace files only. Each value-only capture belongs to an interception already
retained by NetworkInstrumentationFeature. Completion removes the capture before any
guard and before the feature removes its owner. Guard recovery under a different
context tests that removal behavior. Unbind does not immediately release existing
interceptions; no hard capacity, allocation or performance guarantee is inferred.
No scene handoff, other extraction, public API or instrumentation lifecycle hook is
included. Candidate-specific release checks remain separate.

The first baseline invocation compiled no tests because the new active-parent
case redeclared a local variable. Its result, diagnostics and clean-up receipt
remain preserved. A reviewed method-scoped rename keeps every selector, assertion
and line number; reversing it reproduces the original frozen bytes exactly. An
intermediate rename of the wrong binding was rejected before execution.

The corrected baseline runs13 tests: exactly eight ownership cases fail at the
34 predeclared assertions and all five preservation controls pass, with no skips.
Source/dependency/oracle identity, deadline and cleanup checks pass. This is defect
reproduction, not candidate qualification; compiler and duplicate-class diagnostics
remain in the owning artifact.

The first reviewed candidate passes all13 new controls but the full Trace target
passes153/154. An existing no-overwrite test keeps every supplied propagation
header, then fails its nil TraceContext assertion: request-time RUM adds baggage,
and the inherited any-header flag mistakes that for injected trace ownership.
Native qualification stopped before any invocation. The first candidate patch,
frozen inputs and clean-up evidence are preserved. Any correction requires a
separate specific regression admission; the original deadline remains in force.

At08:39:35UTC a specific regression amendment was admitted after independent
review: an added baggage field cannot alone make `hasSetAnyHeader` true. This is
one handler condition; emitted headers, writer policies and the frozen assertions
remain unchanged. It also corrects the inherited baggage-only false-ownership
case, without admitting merging, parsing, partial-carrier continuation or completion
fallback changes. A fresh output directory reuses the exact accepted baseline;
the same154 tests must pass before either native arm. The deadline was not reset.

The exact amendment review passed at08:41UTC. The frozen amended candidate then
passed154/154 full Trace tests (zero failures/skips), including all13 new controls
and the existing caller-header assertion. Root audit verifies source, dependency,
framework, test/oracle and cleanup identities. Native preparation freezes1864
source inputs with only the three admitted Trace production differences; baseline
and candidate use identical tests. Both arms completed before the original deadline.

The native baseline matches exactly six ownership assertions in two cases; the
unchanged parent control passes. The candidate passes3/3 with exact serialized
Trace inventories, request-time owners, outgoing trace/span identities, caller
headers and completion-time non-RUM context. Independent pair review qualifies
E05 only. Both arms retain252 compiler-warning lines,59 duplicate-class lines
and the same networking QoS warning; this establishes neither harmlessness nor
sanitizer/performance clearance. App/process cleanup and protected-state checks pass.

Productionf270c375 and test checkpoint9254adbc commit exactly the qualified bytes
in the isolated branch. Both signed attempts timed out after25seconds, so the
authorized unsigned local fallback was used. The worktree is clean; nothing was
pushed. Local writer serialization is the oracle, without a separate raw-span
export, backend result, registered ownership matrix or physical-device claim.
