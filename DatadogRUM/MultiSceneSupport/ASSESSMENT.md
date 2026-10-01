# RUM multi-scene support assessment

This file owns present support conclusions and evidence limits. The
[overview](../MULTI_SCENE_SUPPORT.md) owns approved behavior; the
[register](release-gates.json) owns gate status and requirements. The generated
[remaining-work view](REMAINING_WORK.md) separates preparation from missing native
evidence. Only [the cursor](../../.continue-here.md) selects current execution.

## Release evidence boundaries

| Stage | Qualified scope | Remaining limit |
| --- | --- | --- |
| S1: existing-customer reliability | Source-matched independent packets; [delivery queue](Results/S1-delivery-queue.json). | Current-head CI, maintainer review and delivery remain separate. H00 → E01 is the established merge dependency. |
| S2: single-scene SDK27 Duo readiness | E01+DL01+E04, production `c9faed81`, documentation `7604da24`; [composition/lifetime](Results/EXP-216-s2-composition-promotion.json) and [compatibility](Results/EXP-217-s2-compatibility.json). | Two SDK27.1 SwiftUI split cells, one physical UIKit candidate comparison and final review. No semantic/scene API adoption is required. |
| S3: full multi-scene support | Provisional SDK `94842cc8`; [F03 components](Results/S3-F03-candidate-preparation.json) cover platform builds, RUM/legacy and module suites, existing-public clients and API/lint audit. | RFC/public exposure, simultaneous topology, native lifecycle ordering and final review. Preparation does not certify those gates. |

Future sessions follow the [September25 measurement rule](../MULTI_SCENE_SUPPORT.md#measurement-and-testing-rule).
Event attribution and View/Navigation/Action capture are decisive. Strict timing
and application-performance campaigns are optional; [EXP224](Results/EXP-224-application-impact.json)
remains stopped without a performance result. Compatibility preserves its original
skips, runtime warnings and Replay-content exclusions; no blanket warning,
sanitizer, crash-freedom or performance clearance follows.

## Selected S2 conclusions

| Capability | Conclusion and owning evidence | Retained limit |
| --- | --- | --- |
| Resource/Trace | [Navigation](Results/EXP-221-s2-resource-trace.json), [rollover](Results/EXP-221-session-rollover.json), [fold](Results/EXP-221-duo-fold.json) and integrated-app ownership qualify T03/T08. | Baseline repeated-resume baggage and terminal-view observations remain; E03 action counts and E05 completion-time correlation retain their inherited limits. Registered persistence was separately assessed after the original attempt-cap failure. |
| Automatic UIKit | [Stack](Results/S2-coverage-home-collection-20260928.json) and [split](Results/S2-coverage-remaining-preparation.json) close C07/C08 within actual layouts. Candidate owners match the SDK27.1 baseline; SDK26.5 rebuild differences are documented. | Switch omissions and Sidebar/Empty/reopened-Detail attribution limitations remain. Simultaneous columns do not require equal occurrence counts. SDK27.1 baselines remain offline-only; full split Home lifecycle is unqualified. |
| Automatic SwiftUI | [Stack comparison](Results/S2-swiftui-stack-candidate-20260930.json) qualifies both compiler baselines and the candidate: 17 Views, 25 automatic Actions, actual folds/Home and cleanup PASS. The candidate preserves SDK27.1 ownership; the single SDK26.5 scroll/swipe subtype difference is source-classified. Original failed captures remain separate. | Generic Home views and four toggle-action omissions remain inherited limitations. The [SDK26.5 split baseline](Results/S2-swiftui-split-20260930.json) also qualifies 17 Views/25 Actions, actual folds/Home and cleanup. C09/C10 and H14 stay open for the SDK27.1 split baseline/candidate comparison. The first SDK27.1 split attempt stopped on a persistent harness accessibility failure after unfold; separate cleanup restoration passes, with no SDK regression claim. |
| Interactive navigation/dismissal | [SwiftUI pair](Results/S2-H12-H13-swiftui-duo.json) closes H12 and qualifies its H13 portion with matching native transitions and automatic/manual inventories. | Existing-manual cancelled-pop restart/callback and outgoing-Sheet dismissal attribution remain. [Physical UIKit baseline](Results/S2-H11-H13-local-baseline.json) is reusable; [candidate](Results/S2-H11-H13-local-continuation.json) evidence is missing after a pre-input orientation check failure, cleanup PASS. [Orientation readiness](Results/S2-physical-orientation-20261001.json) passes24 offline controls/re-review before admission/install; actual physical pose and behavior remain unqualified. |
| UIKit-hosted SwiftUI | [Saved paired assessment](Results/S2-H16-scoped-assessment.json) closes H16 for ordinary hosting, native outcomes and fresh RUM owners. | Original manual candidate backend gap remains. No action, gesture, fold, physical or S3 semantic claim. |
| Native/WebView | [Paired assessment](Results/S2-T10-source-preparation.json) closes T10: active ownership, delayed A ownership before inactive expiry, no container after expiry, detached weak release and backend identities. | Original transport/budget failures remain; no physical-Duo or S3 claim. |
| Controlled app | [Paired app assessment](Results/S2-F08-candidate-comparison.json) closes F08 for Services/detail/Back, a dashboard interaction and Home/return, with native/Browser owners and cleanup. | Custom/explicit tracking does not certify automatic-only coverage. Extra setup actions and incidental totals/timing are not parity claims. |

The [S2 scope review](Results/S2-release-gate-review-20260925.json) excludes duplicate
physical matrices, whole-payload equality, immediate background delivery and
mapper-before-callback ordering as universal criteria. Late Home delivery is not
event loss; the forced-flush proposal remains stopped. Original INVALID verdicts
and successful later restorations remain separate in their owners. No accepted
baseline, gesture sequence or compatibility suite needs repetition to resume.

Earlier [input observations](Results/EXP-220-native-input-callback.json) never
isolated an SDK cause for switch/dispatch variability. The completed source-paired
UIKit comparison supplies its own evidence without explaining those diagnostics.
[Semantic Duo boot failures](Results/S2-Duo-environment-readiness.json) preceded app
assertions; an equivalent retry needs materially changed prerequisites.

## Provisional S3 conclusions

[API/legacy qualification](Results/EXP-225-api-availability.json) supports ordinary
deployment15 calls through SDK-selected fallback and crash-safe off-main Objective-C
rejection. [Current legacy comparisons](Results/EXP-225-legacy17-result.json) and
[full RUM suites](Results/EXP-225-rum-suite-result.json) retain actual runnable-system
evidence and exact availability skips. They do not approve the API or establish
simultaneous same-key owners: the [original native attempt](Results/EXP-225-same-key-result.json)
stopped before API work when A backgrounded.

[Final compatibility preparation](Results/S3-F03-candidate-preparation.json) owns
the qualified build/module/client components. The [Integration result](Results/EXP-227-integration-fixture-result.json)
qualifies fixture-only corrections without assigning an unproven cause to original
TTID failures. The [API audit](Results/S3-M10-source-audit.json) retains existing
declarations and unchanged baselines; additions remain provisional.
[Residual preparation](Results/S3-human-residual-preparation.json) distinguishes
compiled/offline capture components from actual topology and ownership evidence.

Physical Duo remains unqualified. S2 uses measured Duo-simulator and relevant
physical iPhone/iPad evidence with disclosed hardware uncertainty; F09 owns later
confirmation and full F04 remains S3. Stronger S3 peer-continuity and semantic
contracts cannot inherit S2 limitations as a pass.

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
