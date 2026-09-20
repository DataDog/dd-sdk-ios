# Request-time Trace ownership

## EXP-208 — Preserve request ownership through Trace completion

This experiment is defined for E05 on unchanged develop `62f64d7b`. The
[owning result](../Results/EXP-208-trace-ownership.json) fixes the 90-minute deadline,
13 unit selectors, three native selectors, source boundary and stop rules before
any SDK or test edits. No runtime result or eligibility is claimed yet.

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
