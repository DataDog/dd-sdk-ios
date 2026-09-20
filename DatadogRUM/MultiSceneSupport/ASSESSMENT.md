# RUM multi-scene support assessment

This file describes current support and its evidence limits. The approved contract
is in [the overview](../MULTI_SCENE_SUPPORT.md); gate status, owners, dependencies
and decisive tests belong to [release-gates.json](release-gates.json) and the
generated [checklist](PLAN.md). The sole restart cursor is
[.continue-here.md](../../.continue-here.md).

## Release evidence boundaries

S1 extracts independently proven existing-customer reliability fixes. S2 targets
single-scene SDK27 Duo readiness by October 16, 2026. S3 retains full multi-scene
APIs, ownership/lifecycle and hardware acceptance. The reference results below
remain valid within their original source/environment limits; they do not certify
a newly extracted candidate. F07 must prove deferred behavior absent from each
S1/S2 shipped artifact, then F03/F06 qualify that exact candidate.

Physical Duo hardware is unavailable until after release. S2 may use qualified
simulator and relevant physical iPhone/iPad evidence, disclosing that uncertainty;
F09 provides later targeted confirmation, while full F04 remains S3. Unchanged
automatic SwiftUI naming/control limitations are outside new S2 scope. Exact API
review F01 remains attributable and pending for S3; assessment assumptions are not
approval. [Stage views](PLAN.md) own readiness.

The isolated E01 candidate1bdc9286 fixes repeated URLSession request mutation and
strong terminal-preparation retention. Its deterministic and native automatic/
registered controls preserve header, body, metrics and cleanup semantics. Debug
and optimized reentrancy checks pass. Concurrent duplicate resumes may forward
later on the preparation thread; arbitrary original-thread timing is not promised.
[Repair/ownership evidence](Results/EXP-199-terminal-task-ownership.json) and
[optimized controls](Results/EXP-203-optimized-reentrancy.json) define that scope.

Ordinary/legacy17.5 and26.5 compatibility and custom/NOP17.5/26.5/27.0 comparisons
pass on the candidate. Platform builds, compiled public clients, unchanged API
surface, feature documentation and full integration coverage qualify S1:F02/F03.
[Compatibility](Results/EXP-200-compatibility.json) and
[final matrix](Results/EXP-201-final-compatibility.json) retain exact inventories,
the corrected inherited hitch assertion and diagnostic limits.

E01 has12 of16 required gates qualified. The focused object-lifetime audit closes
S1:P03: native success/error/cancellation and feature teardown release their weak
witnesses in automatic and registered modes; the8-test follow-up passes with no
runtime warnings. Backend A01/T03/T08 and final F06 remain open. The user removed detailed network performance and any
replacement standalone network campaign from release prerequisites. The
[optional benchmark](NETWORK_BENCHMARK_FOLLOWUP.md) preserves22 valid cells, its
prelaunch host failure and unfinished continuation without a numeric verdict.
Required performance work for S2/S3 concerns application-visible frame rate,
hitches/hangs, CPU and memory impact of included semantic SwiftUI/multi-scene
changes; source exclusion can qualify non-applicability. Correctness and ownership
requirements remain unchanged.
[Backend preparation](Results/EXP-202-urlsession-backend.json) has two qualified
credential-backed Release builds and six stopped diagnostic launches, all retained.
The latest run passes native/local assertions and collects12 final RUM rows, then
stops at its original final-APM ingestion bound. Later diagnostic queries find all
six client spans and four RUM-derived spans with exact owners and values; they do
not rescue the stopped run. Actual payloads expose host assumptions about the
`Network` category, backend view document versions and absent derived-span probe
attributes. A host-only correction passes56 Python methods and12 connector cases;
independent review passes with phase-provenance hardening. One defined complete-path
diagnostic smoke is running. No SDK defect or backend
acceptance is inferred from these diagnostics.

Test-only duplicate classes are excluded from inspected shipping graphs. The
[QoS comparison](Results/EXP-204-network-qos.json) now finalizes both unchanged
arms: one test each passes and reproduces the same warning and15 shown frames.
The displayed TSan/CFNetwork/libdispatch/pthread stack has no SDK frame and remains
incomplete. This establishes recurrence without E01, not harmlessness, root cause
or sanitizer/performance clearance. The original600second timeout is retained.
Controlled Datadog app evaluation is authorized; configuration preparation and
query access alone do not establish a run.

The independent E02 candidate prevents a retained old view from absorbing a later
same-key occurrence's start or stop attributes. The narrow repair preserves
Resource/action owners and one active restored occurrence. [EXP-205](Results/EXP-205-view-occurrence-isolation.json)
qualifies eligibility with failing current-develop controls, the complete affected
RUM suite and paired public-monitor full/delta writer-JSON tests. Its own release
qualification remains open; these results neither certify backend delivery nor
change E01's selected-candidate gates.

The separate E03 investigation reproduces an existing-customer action attribution
defect on current develop: late Resource success/error changes a newer view or
session's live action counters and error_tap, despite correct Resource/error parent
IDs. [EXP-206](Results/EXP-206-resource-action-ownership.json) has four exact
baseline failures and five preservation passes. Its stateless repair is rejected
because it would erase a valid same-view response-plus-error signal. No E03
production change or release qualification is claimed.

The independent E04 candidate preserves delayed WebView correlation after a long
native visit. It retains A for the full inactivity window after navigation to B,
then expires A while retaining active B. [EXP-207](Results/EXP-207-active-view-cache.json)
qualifies the two-file repair using exact develop failures, 910 RUM cases / 946
executions and an identical three-test native bridge comparison. Session lifetime,
restoration, capacity and Replay controls pass. This is injected-message writer-JSON
evidence; backend, real browser timing, physical Duo and numerical performance are
not qualified. Lookup now takes a write lock for expiry. E04's release qualification
remains separate from the selected E01 candidate.

E05 now preserves ordinary automatic Trace request ownership through delayed or
reverse completion. [EXP-208](Results/EXP-208-trace-ownership.json) qualifies the
three-file candidate with eight exact unit failures on develop,154/154 full Trace
tests and a matched native pair: two baseline ownership failures versus3/3 passing
controls. A request started without RUM retains absent ownership after later RUM
activation. Sampling, parent propagation, caller headers and non-RUM context controls
pass. Completion consumes value-only captures before guards; this bounds lifetime
relative to existing interceptions, without immediate-unbind or measured-footprint
claims. Broader release, backend and numerical performance remain unqualified.

The first E05 candidate exposed a baggage-only write falsely claiming an SDK
TraceContext; its one-condition correction preserves emitted headers and passes the
unchanged existing assertion. Failed attempts remain recorded. Both native arms
retain the networking QoS warning, with no harmlessness or sanitizer clearance.
The [PR2683 review](Results/PR-2683-header-ownership-review.json) remains a source
review of the unmerged proposal. Its merge/fallback policy was not adopted; T08's
bounded partial/mixed-carrier follow-up remains separate.

## Immediate compatibility priority

The short-term criterion is no RUM degradation when an existing app rebuilds with
the iOS27 SDK and runs on Duo without adopting new RUM/navigation integration.
Automatic UIKit views/actions and automatic SwiftUI views/actions are four
separate S2 gates C07–C10; their eight old-build Duo cells remain unresolved.
A prepared human-assisted simulator session is now an available changed input path. [EXP-195](Results/EXP-195-automatic-tracking.json)
compares unchanged apps and preserves baseline limitations. C01’s early UIKit
view/custom-marker fixture does not prove automatic taps/scrolls; EXP-193’s
accepted-state RUMNavigationHost does not prove automatic-only SwiftUI.

All16 regular-iPhone cells, all eight original SDK27 Duo cells, all eight
manifest-enabled SDK27 Duo cells and the defined two-cell split replay qualify.
For the exercised apps rebuilt with SDK27, no new foreground view/action coverage
loss is established when comparing the current branch with the pre-scene SDK.
This is separate from the incomplete old-build-versus-rebuilt Duo comparison.

| Tracking family | Current SDK27 Duo finding | Existing limitation |
| --- | --- | --- |
| UIKit views | Stack matches. Manifest-false split preserves all foreground occurrences and suppresses post-background starts. Manifest-true split also suppresses transient structural views. | One current destination per scene; sidebars are not independently modeled. |
| UIKit actions | Same exercised taps/swipes and owner names, except manifest-true reopened Detail improves from Sidebar to retained Detail ownership. | UISwitch changes remain omitted. Manifest-false reopened Detail can still belong to Sidebar. |
| SwiftUI views | Stack matches with named Detail/Sheet and generic Home. Split preserves its generic names and named Sheets; the replay matches the original baseline foreground sequence exactly. Manifest-true suppresses generic reopen/background churn. | Split does not reliably name Sidebar/Empty/Detail or create a fresh occurrence for every logical navigation. Generic fold occurrences vary even within the frozen baseline. |
| SwiftUI actions | All source pairs preserve21 taps/4 swipes and four Toggle omissions. Stack retains Detail through folds. Split replay exactly reproduces original baseline action/occurrence ownership. | Generic split owners do not provide exact semantic navigation. |

An app with one current window and an already-enabled multiple-scene manifest
selects a different code path: RUMFeature reads the flag, not scene count. The
separate eight-cell slice changes only that independently hashed plist flag,
preserves every app/SDK binary and verifies one actual scene throughout. It does
not establish a manifest-true old-build comparison or simultaneous windows.

The genuineSDK26.5 SwiftUI app remains visibly letterboxed on the inner display,
but both old/modern collector probes fail to qualify inner input. The modern
runner disappears while its app stays alive; interruption and cleanup are retained.
The old-built UIKit probe reaches the same runner-disappearance limit. A separately
recorded Device Hub tap changes receipt3 to4 with one fresh native callback, proving
that app responds to this input. It does not qualify the failed full cell. The
bounded external collector qualifies one initial Tap but cannot produce a switch
callback or visible state change. It stops with the partial run, frozen identities
and verified cleanup preserved. No old-build Duo cell is accepted; equivalent
retries stop until the input environment materially changes. Regular source/compiler
comparisons are complete; old-build-versus-rebuilt Duo fold coverage and physical
acceptance remain incomplete.

[Regular evidence](Results/EXP-195-regular-automatic-coverage.json),
[original Duo evidence](Results/EXP-195-duo-automatic-coverage.json),
[manifest-enabled evidence](Results/EXP-195-manifest-true-coverage.json) and
[split replay](Results/EXP-195-split-replay.json) retain exact inventories, identities,
native timing and raw hashes. The [owning result](Results/EXP-195-automatic-tracking.json)
classifies every SDK27 source-pair difference without hiding the raw comparisons.
No production SDK repair has been justified by these runs.

## Current support

The branch remains experimental and is not release-ready. It supports independent
scene view branches and fresh committed navigation occurrences in the exercised
paths. Exact semantic SwiftUI tracking requires a trustworthy accepted-state or
materialization signal; opaque and ordinary automatic discovery retain their
documented limits. Serial native scenes, posted lifecycle notifications and
logical peers do not establish simultaneous-window or genuine OS lifecycle proof.

| Capability | Present conclusion | Decisive evidence | Remaining boundary |
| --- | --- | --- | --- |
| View lifecycle and restoration | Scene branches share one RUM session. Navigation resolves its previous owner before restoration; immediate and delayed session boundaries preserve eligible peers. | [EXP-167 restoration](Results/EXP-167-session-restoration.json), [EXP-176 current Resource/session owners](Results/EXP-176-resource-start.json) | Real activation, visible-peer continuity, independent backgrounding, OS reconnect and concurrent restoration: H02–H04, H09–H10, H15. |
| UIKit navigation | Exercised push/pop/modal and regular-width split paths use committed occurrences; deterministic cancellation preserves the outgoing occurrence. Structural columns are not independent RUM destinations. | [EXP-079/080 and EXP-112 records](EXPERIMENTS.md) | Native edge-pop recognition and simultaneous navigation remain H02/H11. Physical adaptive geometry H14 closes in EXP-196. |
| Exact SwiftUI navigation | Stable explicit/capability/publisher/Observation inputs support fresh routes and presentations without replacing customer navigation. Authority is local and begins only when a destination can be published. | [EXP-146–154 engine, migration and runtime records](EXPERIMENTS.md), [pending authority](Results/EXP-169-pending-authority.json) | F01 API review; H02, H05, H12–H13 simultaneous/interactive evidence; H16 UIKit-hosted parity. |
| SwiftUI presentation acceptance | Rejected/canonicalized Binding proposals follow accepted state. Occurrence tokens fence old callbacks and preserve accepted content during rematerialization. | [EXP-173 mounted presentation controls and acceptance](Results/EXP-173-presentation-acceptance.json) | Logical peers and injected callbacks do not establish physical callback ordering: H08, H09, H13. |
| SwiftUI lifetime and reconnect | Keyed registrations release instrumentation; rejected publication does not consume a reconnect generation. Retained readers restore the latest source before immediate telemetry without a body rebind. | [EXP-168 lifetime](Results/EXP-168-swiftui-lifetime.json), [EXP-170 reconnect](Results/EXP-170-reconnect-acceptance.json), [EXP-171 retained reader](Results/EXP-171-retained-reader.json) | Mounted/posted controls remain separate from genuine OS teardown/remount: H08–H09. |
| Observer delivery | Nested publication preserves monotonic generations and live membership, including initial delivery, add/remove and two-host teardown. | [EXP-174 deterministic observer regressions](Results/EXP-174-observer-delivery.json) | Bounded responsibility review only; final independent review remains F06. |
| Manual views | Experimental scene/key pairing supports independent authority, distinct-key nesting and fresh reveals of the latest underlying destination. Legacy inferred calls retain their separate pairing contract. | [EXP-122, 125–129, 137–140 records](EXPERIMENTS.md) | Physical H01 closes in EXP-196 with precritical display proof, unchanged22 assertions and exact backend owners. Reviewed Swift/Objective-C surface remains F01. |
| Actions | One-shot and continuous explicit targets select the requested live view; unavailable targets retain independent inference. Continuous stop metadata stays with its own recipient. | [EXP-158/159 records](EXPERIMENTS.md), [EXP-163 timeout metadata repair](Results/EXP-163-action-stop-attributes.json) | Stable API: F01. Source-bearing visible-window and gesture coverage: H03, H11–H13. Ordinary SwiftUI child tasks outside handoff retain process fallback. |
| Resources | Explicit starts and automatic/manual captures retain their original view/session through success, error, metrics, navigation and renewal. Foreign live actions receive no late completion counts. | [EXP-175 completion regression](Results/EXP-175-resource-completion.json), [EXP-176 mapper/backend acceptance](Results/EXP-176-resource-start.json) | Acceptance is serial native A background/B navigation and session renewal; simultaneous shared requests remain H07; stable API F01 remains separate. |
| Current-view errors | Message, Error and callback forms accept a live explicit target without changing captured Resource-error ownership. Dropped/unsampled commands complete once after scheduled writes. | [EXP-177 complete SDK, native and backend evidence](Results/EXP-177-current-view-errors.json) | Stable API F01 and physical topology remain separate. |
| View attributes/removal | Swift and Debug Objective-C target forms isolate single/batch add/remove, preserve fallback and global/view/event precedence, and do not restore ended views. Native A/B markers preserve exact typed values and absence after removal; global updates reach both views. | [EXP-178 SDK, native and backend evidence](Results/EXP-178-view-attributes.json) | T05 accepted within the serial native contract. Stable API F01 and physical topology remain separate. |
| Custom timing/loading | Swift and Debug Objective-C targets preserve fallback, repeated-name replacement, loading overwrite rules and distinct expiration policies. Eight paired mapper checkpoints prove peer invariance; backend final timing/loading values and all marker owners match exactly. | [EXP-179 SDK, native and backend evidence](Results/EXP-179-timing-loading.json) | T06 accepted within the serial native contract. Intermediate view revisions are mapper evidence; F01 and physical topology remain separate. |
| Feature flags/internal mutations | Explicit flag targets and generation-scoped Flags-bus capture preserve requested ownership. Internal metric/FBC calls retain exact, delayed, same-scene stale-view and representative behavior without leaking internal fields. Eight native paired checkpoints and exact backend flags/build aggregates pass. | [EXP-180 SDK, native and backend acceptance](Results/EXP-180-flags-internal-mutations.json) | T07 accepted within the serial native contract. FBC ownership and encoding are local proof; FBC is Flutter-only downstream and absent in the native backend. No Flutter runtime claim; stable API F01 remains separate. |
| Operations | Identity remains application-wide name/key; each step independently resolves explicit/inferred/last-proven/process context. Duplicate starts replace only the client instance without a synthetic end. | [EXP-130/155 raw and reduced evidence; EXP-157 physical serial acceptance](EXPERIMENTS.md), [contract](OPERATIONS.md) | Simultaneous visible topology H06 and stable API F01. |
| Traces | Native, OTel and automatic URLSession spans keep captured start owners through peer completion, duplicate finish/end and deferred writes. Source-less starts retain the observed process fallback; exact native/APM inventory agrees. | [EXP-181 deterministic and native/backend acceptance](Results/EXP-181-trace-start-ownership.json), [EXP-166 isolation](Results/EXP-166-handoff-isolation.json) | T08 accepted within the serial native contract. Action-bearing, nil/retired and builder timing cases have deterministic evidence; native acceptance carries empty action context. Physical shared requests H07 and stable API F01 remain separate. |
| Logs and mirrored errors | Deferred writes and reverse delivery retain exact view/action owners; the native run and complete backend inventories pass. | [EXP-182 accepted ownership evidence](Results/EXP-182-log-mirror-ownership.json) | Source-less logs use the process representative. No simultaneous-topology claim. |
| WebView bridge | Exact captured scene/date correlation, native navigation, detached omission, same-WebView rebind and peer teardown pass through two actual containers and complete backend inventory. Private scene metadata is removed. | [D11/EXP-165](Results/EXP-165-webview-correlation.json), [T10/EXP-183 acceptance](Results/EXP-183-webview-container-ownership.json) | T10 accepted within the serial controlled-payload contract. Receiver output is checked directly in backend; no Browser SDK or per-scene Replay certification. Physical F05 remains separate. |
| Process signals and context | Source-less fatal/exported context and process signals use one representative; trustworthy retained snapshots stay exact. Vitals/profiling retain process semantics and existing view association. | [Fatal/exported context](Results/EXP-184-exported-fatal-context.json), [process signals](Results/EXP-185-process-signal-routing.json), [vitals](Results/EXP-186-shared-vitals.json), [physical profiling](Results/EXP-187-physical-profile-correlation.json) | T11/T12 are closed within their cited boundaries. T13 is closed with accepted serial simulator proof plus physical native17, all3 installed hashes, exact2-view backend metrics and verified test-process cleanup. T14 is closed with physical native12, exact12-event RUM, continuous-profile start/sample joins, exact actual-export timestamps/durations and verified cleanup. The simulator export is accepted separately. False RUM profile-link flags and original failed attempts remain recorded. No per-window measurements, UI-enrichment or simultaneous-window claim. |
| Ordinary apps and supported systems | Early automatic/manual/custom/NOP workloads pass on27/26.5. watchOS/macOS and caller-thread/legacy-correlation regressions have bounded repairs. | [baseline protocol and results](BASELINES.md), [review dispositions](PRODUCTION_SAFETY_REVIEW.md), [EXP-178 older attribute integration](Results/EXP-178-view-attributes.json) | C03 closes in [EXP-189](Results/EXP-189-legacy-build-sdk.json): current/baseline SDK26.5-built legacy hosts pass16 exact navigation/actual-lifecycle cells on27.0/26.5 with full identity/cleanup. SDK27-built legacy hosts hit the mandatory Apple scene-adoption boundary; [EXP-190](Results/EXP-190-minimum-runtime.json) preserves unavailable15.0 requests. User confirms current debugging starts at17: C06 now separates deployment15 from the oldest available runnable17.x matrix and explicitly unexecuted15/16 coverage. F03 final platform/ObjC Release matrix remains required. |
| Performance and retained state | Early dispatch, allocation, reentrancy and retained-state workloads meet their original thresholds after repairs. | [frozen thresholds and numeric results](BASELINES.md), [EXP-166 paired measurements](Results/EXP-166-handoff-performance.json), [EXP-172 retention](Results/EXP-172-scene-retention.json) | Simulator microbenchmarks do not establish device-wide performance. Repeat at relevant architectural change and final freeze F06; do not raise thresholds. |
| Session Replay | Native recording coexists through two actual scenes, navigation and teardown on physical iPad27.0. | [EXP-194 simulator](Results/EXP-194-replay-coexistence.json), [EXP-196 physical](Results/EXP-196-physical-ipad-suite.json) | F05 closed: four record-growth checkpoints, actual B disconnect, six exact backend views, zero stray Action/Resource/error/crash and verified code identities/cleanup. Original timing failure preserved; physical close-triggered return is checked separately. No simultaneous-visible, scene-correct Replay or Duo-hardware claim. |

## Limits on support claims

- Automatic native SwiftUI discovery can be late for lifecycle work and can name
  structural containers. Plain render-time current-value observation and opaque
  navigation are not exact semantic sources. Keep the accepted fallback, sparse
  manual escape hatch and migration budget; see [navigation contract](NAVIGATION_API.md)
  and [rejected approaches](REJECTED_APPROACHES.md).
- Scene ownership is internal. No temporary scene attribute, public RUM UUID,
  returned view handle, new wire concept or split application session is approved.
- Counts, absence of crashes and callback delivery alone do not prove semantic
  ownership. Mapper, backend and reduced entity evidence have distinct meanings.
  [Evidence levels](TOOLING_RUNBOOK.md#evidence-levels) define the boundary.
- The completed [production safety review cycle](PRODUCTION_SAFETY_REVIEW.md) and
  [bounded component reviews](COMPONENT_REVIEW.md) do not certify release readiness.
  The [concrete stable API proposal](STABLE_API_REVIEW.md) awaits the requested
  RFC decision. The [integration guide](SUPPORT_GUIDE.md) and
  [final compatibility matrix](FINAL_COMPATIBILITY.md) are prepared drafts, not
  public API promotion or completed F02/F03 evidence. The guide's fixed15-family
  [ownership audit](Results/F02-guide-ownership-audit.json) is complete against
  unchanged source and accepted evidence; approved examples and the full feature-doc
  audit remain after F01. Supported-runtime checks,
  physical topology, Duo27.1 acceptance and final freeze remain governed by the register.
- Current availability must be rediscovered when execution needs it. Earlier
  devices, sessions and temporary artifacts are evidence locators, not instructions
  to reuse them.

Chronological conclusions and the superseded routing audit are retained in the
[documentation checkpoint](Experiments/DOCUMENTATION_CHECKPOINT_EXP-178.md).
Use the [compact index](EXPERIMENTS.md) to open only the experiment that owns a question.

The Duo27.1 simulator assessment is complete within its finite boundaries.
[EXP-192](DUO_SIMULATOR_ASSESSMENT.md) records actual display/trait and OS lifecycle
observations, plus concrete limits for concurrent visibility, disconnect and
interactive gestures. The unchanged H01 native22/22 remains inconclusive without
overlap; two pairing and two outer gesture attempts do not qualify those inputs.

[EXP-193](Results/EXP-193-adaptive-split.json) now accepts both adaptive slices:
resize5 phases/16 exact work/3 backend views and pose10 phases/42 exact work/7
backend views, zero errors and each guarded XCTest1/1. Exact semantic ownership
survives measured geometry and actual open/close; accepted selections and returns
produce distinct occurrences. Source/installed identities and full cleanup pass.
This is strong SDK ownership evidence for the observed simulator callbacks, not
physical hinge or scheduling parity. Original fixture, input, hit-target and
projection failures remain attributable. Physical/human obligations stay open.

C06's corrected17.x qualification checks all five stable versions in Apple's
historical catalog through27.1; all downloads are unavailable, as is17.0 through
26.6. The user subsequently supplied17.5(21F79), now verified installed/available with
a booted iPad simulator. No candidate matrix cell is claimed yet. The S1/S2 runtime
exception has not been used; actual tests and deployment15/availability checks
remain required.

EXP-196 closes physical F05 Replay coexistence, H05 settled semantic/automatic
coexistence and H07 shared-request captured ownership with complete native/backend
inventories and installed-code/cleanup proof. H05 retains the approved early
source-less representative fallback. H07 start precision is limited to the observed
MCP millisecond projection; exact native timing and raw backend duration remain.
No simultaneous-visibility conclusion follows from these serial cases.

H01 closes with actual tiled A/B windows visible through the original same-key
critical interval, native22/22 and all61 backend events matching11 views/46 work
IDs. Continuous physical XCTest video and90 reviewed boundary frames bind the
precritical receipt to unchanged native scene identities. H11's corrected visible-edge
finish touch still produces no native interactive callback; its13-event partial
join is exact, but neither finish nor cancel is qualified. Stop equivalent retries.
H04's independent process-lifetime witness also receives no disconnect; the latest
29-event partial inventory matches. Stop equivalent close retries; the view-local
observer alone does not explain the missing notification and no SDK defect is established. H14 now closes with measured regular–compact–regular physical resizing, unchanged
accepted selection/path/owner and a complete22-event backend match. The [owning result](Results/EXP-196-physical-ipad-suite.json)
preserves every rejection and scope limit. The SDK candidate is unchanged.

The physical EXP-196 suite is checkpointed after H01 acceptance. Full Screen Apps
is restored, both task apps/processes are absent, and the owned keep-awake process
is stopped. Remaining scene combinations move to S3; no deferred case is accepted.
The Datadog app uses manual SwiftUI views, allowlisted automatic UIKit and native/
WebView tracking in one scene. Existing XCTest paths skip RUM bootstrap, so F08
requires normal-mode app journeys alongside separate automatic fixtures; see
[the source audit](Results/Datadog-app-source-audit.json).
