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

S1 delivery follow-up is owned by the [finite release admission](../Results/S1-E05-release-admission.json).
Two registered delegate ownership cases now pass within full Integration282/282
on iOS17.5, with three genuine data/metrics/completion receipts and independent
acceptance. Eight QoS warnings remain. The qualified test-only addition is local
commit4002188a, unsigned after recorded signing timeout; production is unchanged.
The two backend mode cells stay unqualified. Replay capture tests are excluded
by the subsequent user scope decision; original results are retained. This preserves the
completed experiment's automatic comparison and its original limits.

The delivery compatibility run exposed one deterministic stale Core expectation:
it supplied request session A but expected receiver session B in baggage. Independent
review approved only that test correction, preserving the complete eleven-header
equality. Local test-only commit399b01ea (unsigned after signing timeout) passes
Core815 tests plus four predefined OS skips. The original819-case failed run remains
unchanged. The full eight-suite continuation now passes2,768 executions/five predefined
OS skips. Twelve platform builds pass144 architecture source lists and936 product
records, including Trace on macOS. Both lanes completed within their frozen deadlines;
this is not a new experiment or a production repair.

The backend delivery follow-up preserves two invalid automatic attempts. The
first stopped before Core initialization because UIApplication was still inactive
inside sceneDidBecomeActive. An activation-only correction compiled but never
launched: source inspection showed that late Core registration cannot replay
already-fired launch notifications. Moving only Core initialization into
application didFinishLaunching allows Core to observe those dates, but the next attempt stopped
on an overly narrow bootstrap-state assertion: the OS reported background there,
then active app/foreground-active scene at scenario start. Both attempts retain
exact native receipts and pass all cleanup guards; neither reached backend checks,
and registered mode never launched. These fixture failures establish no SDK defect.

The final reviewed fixture permits inactive/background bootstrap while retaining
actual active app/scene, one window, real cold/nonprewarmed TTID, all ownership
boundaries and cleanup. Compile passes with zero fixture warnings and49 preserved
SDK warning lines. Six positive/46 negative offline controls pass. It remains
NOT_RUN_BUDGET: the original automatic window could not accommodate the frozen
backend allowances, so the correction was never installed or launched. Original
deadlines and all failed/unused builds remain unchanged. The owning admission
links source, build, review, controls and stop disposition. A fresh bounded runtime
admission is required after this checkpoint; no backend or release gate closes.

The later fresh automatic admission used the exact reviewed fixture and build.
Actual cold TTID and the startup inventory passed before the scenario started;
all three requests completed. The frozen local oracle then rejected the SDK's
canonical root parent string0 because it expected sixteen zeros. Preserve its
INVALID summary and successful cleanup. Source review confirmed an oracle format
defect. An isolated correction retains full high+low trace IDs, ownership and
all original predicates; two retained native documents plus eight synthetic
positive and66 negative controls pass without a native rerun.

A separately frozen backend-only continuation stopped without retry at its first
full-session aggregate:3 rows where7 were required. No search or APM query ran,
and no backend pass is inferred. Source review shows the original assertion
exception entered cleanup before final collection and terminated the app. This
is insufficient to diagnose SDK ingestion. A new bounded automatic admission,
with fresh identity/deadlines and the corrected oracle, is the smallest decisive
continuation; it must retain the app through all backend inventories. Registered
remains unadmitted until automatic fully passes. The owning result preserves exact
artifact hashes, reviews and the original stops. No Replay test or SDK repair follows.


### S1 backend completion — 2026-09-21

The corrected automatic cell passes native/RUM/APM and cleanup: startup RUM3,
final session7/service7, client spans3/session-owned spans2. Its summary is
4a3eae2851b807f0c2a60cfaa1d4a16eedf1e3059793d921ea8f1ff9c410f41d.
Three real requests retain nil/A/B ownership and complete B, A, then unowned.

The separately admitted registered cell completed all native predicates and
inventories, but its original summary18b90e57 remains FAIL: the first session
reducer was document22 with view/action counts1/0. A later service query observed
document30 with3/2. One separately admitted session-only observation settled the
reducer but its original summaryace7bd41 remains FAIL under cross-query opaque-ID
equality. All seven search-envelope IDs differed while stable event identities
and complete client projections matched. Neither original result is relabeled.

An isolated offline correction compares reducer session ID, document version,
initial-view ID and all terminal counts, retaining complete client projections,
within-response raw/outer IDs, duplicate/page/completeness, ownership, source,
startup, native and cleanup guards. Automatic and composed registered evidence
pass; the original stale registered evidence still rejects. Existing four positive/
33 negative and new two positive/15 negative controls pass. Preserve the initial
synthetic control stop caused by aliased fixture responses. No SDK change, native
launch or backend query occurred in this correction. Resultc6bd2f03 and independent
review783b30c6 close E05-BACKEND as composed evidence. The owning
[admission record](../Results/S1-E05-release-admission.json) binds durable paths
and full hashes. Real ticket, current required CI, human review, outgoing signatures
and separately authorized delivery remain. No broader release gate closes.
