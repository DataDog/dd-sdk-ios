# RUM multi-scene support assessment

This file describes present support and evidence limits. The approved contract is
in [the overview](../MULTI_SCENE_SUPPORT.md). [The register](release-gates.json)
owns finite gate status, owners, dependencies, tests and environments;
[PLAN](PLAN.md) is generated. [The cursor](../../.continue-here.md) alone owns the
current execution state and next action.

The provisional S3 candidate qualifies all20 platform builds, full RUM27/17.5 and all nine other module suites. The [final Integration component](Results/EXP-227-integration-fixture-result.json) passes280/280 after fixture-only lifecycle, assertion-guard and hitch-oracle corrections; exact compiled source, eight inherited runtime warnings and cleanup qualify. SDK94842cc8 is unchanged. Original failures and separate diagnostic restoration remain preserved; the initial TTID cause is unproven. [EXP-228](Results/EXP-228-public-clients-result.json) also qualifies five existing-public-client configurations. The [current source audit](Results/S3-M10-source-audit.json) passes strict lint and retains every existing API declaration across nine modules. RUM additions remain provisional; approved baselines are unchanged. API approval, simultaneous scene ownership, approved API/documentation integration and final review remain; these results do not replace runtime/human gates.

## Release evidence boundaries

| Stage | Qualified scope | Remaining limit |
| --- | --- | --- |
| S1: existing-customer reliability | Seven independently prepared packets with source-matched evidence; publication and follow-up history live in the [delivery queue](Results/S1-delivery-queue.json). | Current-head CI, maintainer review and final delivery remain separate from local qualification. Only H00 → E01 is an established merge dependency. |
| S2: single-scene SDK27 Duo readiness | Exact E01+DL01+E04 production `c9faed81`, documentation `7604da24`. [Composition/lifetime](Results/EXP-216-s2-composition-promotion.json), [documentation](Results/S2-F02-composition-documentation.json), [compatibility](Results/EXP-217-s2-compatibility.json) and the [controlled app comparison](Results/S2-F08-candidate-comparison.json) qualify their finite scopes. | Automatic Duo coverage, interactive transitions and final-release acceptance remain open. Historical reference results below cannot certify them. |
| S3: full multi-scene support | Experimental scene/semantic behavior has the bounded reference evidence below. | Stable API/RFC, remaining physical topology/ordering and final release obligations remain. F01 proposals are not approval. |

The [S2 scope review](Results/S2-release-gate-review-20260925.json) retains actual
Duo behavior and exact required owners, while removing duplicate physical matrices,
whole-payload backend parity and immediate background delivery as universal criteria.
The latest iPad run proves only its baseline gestures; candidate comparison is still
missing. Late Home delivery is not event loss. The proposed forced-flush extension
is stopped before implementation. The separate
[saved hosting assessment](Results/S2-H16-scoped-assessment.json) closes S2:H16: both
automatic/manual pairs retain the five native outcomes and fresh RUM owners. Original
invalid attempts and the manual candidate backend gap remain; no gesture/fold claim.

S2 contains six qualified production files and excludes deferred semantic/scene
implementation. The earlier source-exclusion
assessment remains valid; the [current testing rule](../MULTI_SCENE_SUPPORT.md#measurement-and-testing-rule)
requires no strict timing or application-performance comparison.
Its compatibility evidence retains predefined OS skips, Replay-content exclusions,
Integration QoS warnings and original preparation stops. No blanket warning,
sanitizer, crash-freedom or performance clearance follows.

[The selected-source Resource/Trace navigation comparison](Results/EXP-221-s2-resource-trace.json)
now qualifies both URLSession modes on Duo: Resources retain their start owner,
manual parent and automatic completion-time Trace correlation match the baseline,
and candidate terminal views stop correctly. Both candidate modes also pass
[explicit session rollover](Results/EXP-221-session-rollover.json). Baseline repeated
resumes mutate currentRequest baggage; their observed protocol-start carriers stay
original-owned. [Fold](Results/EXP-221-duo-fold.json) now closes S2:T03/T08 with
four source-bound Closed/Open/Closed captures and complete RUM/APM ownership
checks. Both baseline modes retain their terminal-view observations; candidate
checks pass. Registered candidate persistence qualifies through a separate saved-
capture assessment after its original collection hit an attempt cap. That original
INVALID and all cleanup results remain unchanged; no gestures were repeated.
Inherited E03 action-count and E05 automatic completion-correlation limits remain.
The controlled-app obligation is qualified by F08 below; automatic view/action
tracking and physical Duo acceptance remain separate.

The current-source automatic comparison has unresolved native-input variability.
[EXP-210](Results/EXP-210-s2-automatic-coverage.json) includes SDK-on switch failures
and passing SDK-off/later action-on controls without an isolated cause.
[EXP-218](Results/EXP-218-native-input-observation.json) adds a native SDK-on pass
whose strict dispatch observer rejects its boundary; SDK-off remains unrun.
The [callback-side witness](Results/EXP-220-native-input-callback.json) now observes
successful SDK-on/off callbacks on a regular iPhone27.0, with prior setup/host stops
preserved. This does not reproduce earlier variability or establish an SDK
cause, complete automatic-tracking comparison or candidate gate closure.

The [current UIKit stack comparison](Results/S2-coverage-home-collection-20260928.json)
qualifies one of the four Duo coverage journeys: current candidate view/action
coverage matches both preserved baseline references, including the existing switch
action omission. Native input, fold geometry, Home capture and cleanup pass. The
SDK27.1 baseline remains a reviewed offline reference with its original INVALID
verdict. UIKit split SDK26.5 qualifies. The SDK27.1 split capture retains a post-Home Sidebar occurrence and incomplete terminal inventory; separate restoration passes. Different simultaneous-column layouts do not require equal event counts. Foreground ownership assessment and a candidate comparison remain, with existing split tracking limits preserved. Both SwiftUI shapes remain and C07–C10 are open. The [continuation](Results/S2-coverage-remaining-preparation.json) owns the evidence classes and revised comparison scope. The [WebView pair](Results/S2-T10-source-preparation.json) closes S2:T10: the
active native owner survives181seconds, delayed A events retain A within inactive
retention and have no container after expiry, and the detached WebView releases.
Both complete backend inventories contain9rows. Candidate scenario, evidence and
cleanup pass; original baseline late-publication and first-candidate budget failures
remain immutable. No further TTL run is needed for the controlled app smoke.

The [controlled app comparison](Results/S2-F08-candidate-comparison.json) closes
S2:F08 for signed-in Services/detail/Back, one dashboard interaction and Home/return
on Duo27.1. Both source-bound captures retain the required view/action/resource and
Browser owners, with complete independent backend inventories and successful cleanup.
The candidate's extra range-setup actions are classified separately. No new crash,
hang or navigation failure was observed. Incidental Browser totals and timing are
not parity claims. Original harness/transport INVALID verdicts remain unchanged;
separate saved-evidence assessments and paired review support this finite closure.
The app uses custom/explicit tracking, so it does not close automatic-only C07–C10.
[Semantic Duo boot failures](Results/S2-Duo-environment-readiness.json) occur before
app installation/assertions and have no established SDK cause. An equivalent retry
requires materially changed conditions and separate admission.

Physical Duo hardware is unavailable before release. S2 can use qualified Duo
simulator and relevant iPhone/iPad evidence while disclosing uncertainty; F09 owns
later confirmation and full F04 remains S3. API availability amendments stay under
[existing S3 F01/C06/F03/A02 obligations](Results/S3-api-availability-plan.json).
[EXP-225](Results/EXP-225-api-availability.json) implements ordinary deployment15
calls with SDK-selected fallback and crash-safe Objective-C background rejection.
Optimized single-scene clients qualify on17.5/27 with automatic tracking on/off.
[Current-source legacy comparisons](Results/EXP-225-legacy17-result.json) also preserve
automatic/manual navigation and actual background/foreground ownership on17.5.
This remains experimental: attributable API approval, normal public exposure,
simultaneous native same-key ownership and the complete final matrix stay open.
The [same-key native attempt](Results/EXP-225-same-key-result.json) stopped before API
work because activating B backgrounded A; it provides no SDK regression finding.
The [full-RUM continuation](Results/EXP-225-rum-suite-result.json) qualifies the
complete target on27.0 and17.5. The older run exposed XCTest invoking an iOS27-only
test class; its runtime guard now skips exactly those25 methods, which all pass
on27. With the existing routing skip,17.5 passes1,381 cases and explicitly skips26.
SDK bytes and test assertions are unchanged, original crashes remain recorded,
and both simulators are restored. Other modules and final release approval remain.

[Application-impact preparation](Results/EXP-224-application-impact.json) now binds
four signed Release clients and reviewed sampler/trace controls to that API candidate.
Physical baseline install, launch and code identity pass, but recorder attachment fails
before workload readiness. Capture is stopped; cleanup passes. There is no performance
result or SDK regression finding. This optional diagnostic is no longer a release
prerequisite under the September25 measurement rule; no further profiling run is due.

[EXP223](Results/EXP-223-interactive-transitions.json) retains ordinary-simulator
capture and a [reviewed physical UIKit baseline](Results/S2-H11-H13-local-baseline.json).
Its actual cancel/finish chains and emitted action owners qualify for local reuse;
source, installed code, durable observations and cleanup have been reverified.
The original finish mapper-order failures and backend timeout remain unchanged.
Delayed Home upload establishes no event loss. The physical UIKit candidate remains
untested; no baseline gesture repeat is required. On Duo, the [automatic SwiftUI
pair](Results/S2-H12-H13-swiftui-duo.json) matches15 View occurrences,10 actions and
all four foreground transitions. The existing-manual baseline captures12 Views and
10 actions but restarts Detail after a cancelled pop and attributes its callback to
intermediate Home; completed sheet dismissal attributes its callback to the outgoing
Sheet. These strict failures and successful cleanup remain recorded. The candidate
matches the complete manual inventory and both inherited limitations; all four native
outcomes match in both tracking modes. Independent review closes S2:H12 and qualifies
the SwiftUI portion of H13. The physical UIKit candidate remains required for H13;
no automatic-only, S3 semantic, Home or physical Duo claim follows.

## Immediate compatibility priority

The criterion is no RUM degradation when an existing app rebuilds with the iOS27
SDK and runs on Duo without adopting new RUM/navigation integration. UIKit views,
UIKit actions, SwiftUI views and SwiftUI actions remain separate C07–C10 gates.
Manual markers or semantic hosts cannot substitute for automatic-only coverage.

The following findings concern the **experimental reference in EXP-195**, not the
selected S2 composition. Its qualified regular/SDK27-Duo source pairs and bounded
split replay establish no new foreground coverage loss in the exercised apps.
Old-built versus rebuilt Duo coverage is incomplete because inner-display input
was not qualified. The [owning result](Results/EXP-195-automatic-tracking.json)
retains every cell, raw difference, build identity and failed input attempt.

| Tracking family | Current SDK27 Duo finding | Existing limitation |
| --- | --- | --- |
| UIKit views | Stack matches. Manifest-false split preserves all foreground occurrences and suppresses post-background starts. Manifest-true split also suppresses transient structural views. | One current destination per scene; sidebars are not independently modeled. |
| UIKit actions | Same exercised taps/swipes and owner names, except manifest-true reopened Detail improves from Sidebar to retained Detail ownership. | UISwitch changes remain omitted. Manifest-false reopened Detail can still belong to Sidebar. |
| SwiftUI views | Stack matches with named Detail/Sheet and generic Home. Split preserves its generic names and named Sheets; the replay matches the original baseline foreground sequence exactly. Manifest-true suppresses generic reopen/background churn. | Split does not reliably name Sidebar/Empty/Detail or create a fresh occurrence for every logical navigation. Generic fold occurrences vary even within the frozen baseline. |
| SwiftUI actions | All source pairs preserve21 taps/4 swipes and four Toggle omissions. Stack retains Detail through folds. Split replay exactly reproduces original baseline action/occurrence ownership. | Generic split owners do not provide exact semantic navigation. |


A one-window app with its multi-scene manifest enabled selects a different SDK path
from a manifest-disabled app. The reference compares those flag variants with
unchanged app/SDK binaries and one actual scene; it does not prove simultaneous
windows or a manifest-enabled old-build comparison. Generic SwiftUI fold occurrences
vary even within frozen baseline source, so names/counts alone cannot assign a
regression. Old-app input failures do not establish SDK defects or app unusability.

## Current support

The experimental branch is not release-ready. It supports independent scene view
branches and fresh committed occurrences in the exercised paths. Exact semantic
SwiftUI tracking requires trustworthy accepted-state/materialization input; ordinary
automatic discovery and opaque navigation retain the limits below. These are
reference capabilities, with candidate transfer governed by F07 and release-specific
qualification rather than assumed from this table.

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
| Process signals and context | Source-less fatal/exported context and process signals use one representative; retained snapshots stay exact. Vitals/profiling preserve process semantics and existing view association. | [fatal context](Results/EXP-184-exported-fatal-context.json), [process signals](Results/EXP-185-process-signal-routing.json), [vitals](Results/EXP-186-shared-vitals.json), [physical profiling](Results/EXP-187-physical-profile-correlation.json) | Accepted within serial and representative-hardware contracts. False RUM profile-link flags remain recorded; no per-window measurement, UI-enrichment or simultaneous-window claim. |
| Ordinary apps and supported systems | Reference automatic/manual/custom/NOP and genuine older-SDK legacy-host comparisons have bounded acceptance. Platform and caller-thread regressions have documented repairs. | [baselines](BASELINES.md), [safety dispositions](PRODUCTION_SAFETY_REVIEW.md), [legacy build-SDK evidence](Results/EXP-189-legacy-build-sdk.json) | Deployment15 remains supported; current executable minimum coverage starts at17, with15/16 runtime coverage explicitly unexecuted. Candidate-specific C06/F03 must use their own evidence. A newer-SDK mandatory scene-adoption trap is a separate platform boundary. |
| Performance and retained state | Early reference dispatch/allocation/reentrancy/retained-state controls meet their frozen thresholds after repair. | [protocol and results](BASELINES.md), [handoff](Results/EXP-166-handoff-performance.json), [retention](Results/EXP-172-scene-retention.json) | Historical simulator microbenchmarks retain their original limits. Future sessions qualify event attribution and View/Navigation/Action capture; strict timing and application-performance campaigns are not prerequisites. |
| Session Replay | Native recording coexists through two actual scenes, navigation and teardown on physical iPad27.0. | [EXP-194 simulator](Results/EXP-194-replay-coexistence.json), [EXP-196 physical](Results/EXP-196-physical-ipad-suite.json) | F05 closed: four record-growth checkpoints, actual B disconnect, six exact backend views, zero stray Action/Resource/error/crash and verified code identities/cleanup. Original timing failure preserved; physical close-triggered return is checked separately. No simultaneous-visible, scene-correct Replay or Duo-hardware claim. |

## Limits on support claims

- No temporary public scene attribute, RUM UUID/returned view handle, new wire concept
  or split application session is approved. [Navigation decisions](NAVIGATION_API.md)
  retain automatic fallback, sparse manual escape hatches and migration limits.
- Serial scenes, logical peers and posted notifications do not prove simultaneous
  visibility or physical OS callback ordering. [Duo fidelity](DUO_SIMULATOR_ASSESSMENT.md)
  limits simulator claims even where [adaptive ownership](Results/EXP-193-adaptive-split.json)
  passes actual pose/geometry changes.
- [Physical iPad evidence](Results/EXP-196-physical-ipad-suite.json) qualifies its
  same-key simultaneous-window, settled coexistence, shared-request and adaptive
  boundaries. Unrecognized gestures and missing disconnect observations remain
  unqualified; no physical Duo or unexecuted scene combination is inferred.
- Session Replay captured-content correctness is outside scope. Host-app crash
  safety and non-disruption to other SDK features remain required. Historical
  Replay-content failures stay failures without creating a capture repair obligation.
- Follow the [project measurement rule](../MULTI_SCENE_SUPPORT.md#measurement-and-testing-rule):
  event attribution and View/Navigation/Action capture determine session acceptance.
  Strict timing is diagnostic. Preserve existing lifetime and compatibility evidence.
- Completed [safety](PRODUCTION_SAFETY_REVIEW.md) and [component](COMPONENT_REVIEW.md)
  reviews close bounded findings only. Stable API, support examples, final
  compatibility and independent delivery review remain governed by their gates.
- Counts, callback delivery and no crash do not establish ownership; native, mapper,
  backend and profile joins have distinct [evidence levels](TOOLING_RUNBOOK.md#evidence-levels).
  Current tool/runtime availability must be rediscovered when execution needs it.

Completed narratives and superseded claims are reference material in the
[non-frozen documentation checkpoint](Experiments/DOCUMENTATION_CHECKPOINT_EXP-220.md).
Open detailed evidence through the [compact index](EXPERIMENTS.md), rather than
adding run histories to this assessment.

<a id="downstream-routing-audit-for-exp-159"></a>
The older EXP-159 routing-audit link is retained for detailed experiment records;
its source discussion is in the [EXP-178 checkpoint](Experiments/DOCUMENTATION_CHECKPOINT_EXP-178.md#moved-03).
