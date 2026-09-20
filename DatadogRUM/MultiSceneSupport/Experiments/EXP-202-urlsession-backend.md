# Isolated URLSession backend acceptance

## EXP-202 — Qualify ordinary Resource and Trace lifecycle acceptance

Defined before implementation on2026-09-20. Closes existing S1:A01/T03/T08;
S1:F07 is already qualified. Root owns all host/backend execution. SDK production
source stays1bdc9286 versus current-develop62f64; fixture/runner changes are separate.

The [owning result](../Results/EXP-202-urlsession-backend.json) freezes the complete
source-audited contract, twelve rows, ordering, counts and negative controls.
Use four fresh Release launches on actual17.5/21F79 with Xcode27.1: A/B times
automatic/registered. Public RUM disallow configuration separates a RUM-owned host
from a Trace-owned host in each launch. Every cell has eleven real URLSession tasks
plus one public manual Resource, one Home and one Detail occurrence. The incidental native TTID vital is inventoried below; no broader
telemetry family, transport constructor or header format is admitted.

HTTP200/404/500, response-free NSError and actual response-plus-NSError preserve
current-develop semantics. An old Home Resource completes while a Detail action is
active; inherited action count1/0 stays visible. Trace URL spans retain current
completion-time Detail correlation, while their kept manual parent remains Home.
E03/E05 repairs remain separate. Repeated/completed resumes must not introduce
candidate duplicates or changed carrier identities. Existing EXP-197/199 internal
red/green evidence supplies the interception-start proof that backend counts alone
cannot establish.

Require the exact public mapper/session readiness boundary before Home starts and
the final Home Resource sentinel before navigation. Install native state waits
before suspend/resume, retain metrics-before-completion prerequisites, and observe
real task.response/error before classifying mixed results. Never invoke SDK metrics
handlers manually. Registered durations use exact source conversion of native
intervals; automatic durations fit first-resume-through-mapper plus1ms clock
precision. No latency or allocation pass follows from these semantic bounds.

The workflow binds preflight, clean install, frozen source/contract/build/installed
identity, fresh run ID, local chronology, one native window, full local inventory,
whole-session RUM and APM search/detail results, and verified cleanup. Both backend
session and independent service/time inventories remain visible. Do not hide rows
with expected-owner/run filters. Initial ApplicationLaunch may lack the public run
attribute only for its exact mapper-proven fresh view ID. Preserve128-bit trace
identity and exact span/parent values without Double conversion. Server-generated
RUM APM spans are classified separately and receive no invented cardinality claim.

Preparation is bounded to one60minute implementation pass and source/oracle review,
then at most two unqualified native prerequisite launches (automatic/registered)
before the four frozen acceptance cells. Failures stop their lane and remain in the
result; revisions need an explicit evidence-based disposition before another run.
Thresholds and expected baseline behavior cannot be relaxed to manufacture a pass.

Mutation controls reject stale source/build/run IDs, consumed readiness, late
critical assertions, missing/duplicate or wrong-identity events, owner/count and
HTTP/NSError swaps, changed trace high bits/parent/sampling, fabricated metrics,
restored backend IDs and incomplete pages. Reuse existing acceptance primitives
without running the experimental multi-scene scenario or changing its contracts.
Normal customer setup, SDK/public API, wire, privacy and dependency requirements
remain unchanged. No push or publication.

The source audit found that disabling periodic vitals leaves FirstFrameReader
active. Before any runtime, the contract therefore includes exactly one native
app-launch TTID vital (time_to_initial_display), cold/non-prewarmed, owned by the
initial ApplicationLaunch view in the fresh session. Hold before Home until the
host observes that actual vital, then consume a nonce/run/build-bound one-use
release control. Preserve the startup query alongside the final whole-session
inventories. Wrong owner, duplicate/missing vital, stale identity and late or
consumed release controls reject. This is an incidental inventory prerequisite;
it makes no broader vital or performance claim. FBC remains Flutter-only.

Pre-runtime connector qualification uses historical synthetic payloads only.
Backend RUM row IDs are opaque and differ from semantic UUIDs. Trace search
provides exact decimal duration; detail exposes rounded timestamps and optional
truncation metadata. Preserve actual representation and reject truncation without
inventing nanosecond detail starts or missing sampling fields. Arm A final Detail
state is observed across the same bounded stop boundary as B, then classified;
B must stop. No baseline phantom-active result exists before runtime.
