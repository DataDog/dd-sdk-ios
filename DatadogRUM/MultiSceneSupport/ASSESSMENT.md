# RUM multi-scene support assessment

This file describes current support and its evidence limits. The approved contract
is in [the overview](../MULTI_SCENE_SUPPORT.md); gate status, owners, dependencies
and decisive tests belong to [release-gates.json](release-gates.json) and the
generated [checklist](PLAN.md). The sole restart cursor is
[.continue-here.md](../../.continue-here.md).

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
| UIKit navigation | Exercised push/pop/modal and regular-width split paths use committed occurrences; deterministic cancellation preserves the outgoing occurrence. Structural columns are not independent RUM destinations. | [EXP-079/080 and EXP-112 records](EXPERIMENTS.md) | Human edge-pop recognition, adaptive geometry and simultaneous windows: H02, H11, H14. |
| Exact SwiftUI navigation | Stable explicit/capability/publisher/Observation inputs support fresh routes and presentations without replacing customer navigation. Authority is local and begins only when a destination can be published. | [EXP-146–154 engine, migration and runtime records](EXPERIMENTS.md), [pending authority](Results/EXP-169-pending-authority.json) | F01 API review; H02, H05, H12–H13 simultaneous/interactive evidence; H16 UIKit-hosted parity. |
| SwiftUI presentation acceptance | Rejected/canonicalized Binding proposals follow accepted state. Occurrence tokens fence old callbacks and preserve accepted content during rematerialization. | [EXP-173 mounted presentation controls and acceptance](Results/EXP-173-presentation-acceptance.json) | Logical peers and injected callbacks do not establish physical callback ordering: H08, H09, H13. |
| SwiftUI lifetime and reconnect | Keyed registrations release instrumentation; rejected publication does not consume a reconnect generation. Retained readers restore the latest source before immediate telemetry without a body rebind. | [EXP-168 lifetime](Results/EXP-168-swiftui-lifetime.json), [EXP-170 reconnect](Results/EXP-170-reconnect-acceptance.json), [EXP-171 retained reader](Results/EXP-171-retained-reader.json) | Mounted/posted controls remain separate from genuine OS teardown/remount: H08–H09. |
| Observer delivery | Nested publication preserves monotonic generations and live membership, including initial delivery, add/remove and two-host teardown. | [EXP-174 deterministic observer regressions](Results/EXP-174-observer-delivery.json) | Bounded responsibility review only; final independent review remains F06. |
| Manual views | Experimental scene/key pairing supports independent authority, distinct-key nesting and fresh reveals of the latest underlying destination. Legacy inferred calls retain their separate pairing contract. | [EXP-122, 125–129, 137–140 records](EXPERIMENTS.md) | Same-key A/B reverse stop under physical topology: H01; reviewed Swift/Objective-C surface: F01. |
| Actions | One-shot and continuous explicit targets select the requested live view; unavailable targets retain independent inference. Continuous stop metadata stays with its own recipient. | [EXP-158/159 records](EXPERIMENTS.md), [EXP-163 timeout metadata repair](Results/EXP-163-action-stop-attributes.json) | Stable API: F01. Source-bearing visible-window and gesture coverage: H03, H11–H13. Ordinary SwiftUI child tasks outside handoff retain process fallback. |
| Resources | Explicit starts and automatic/manual captures retain their original view/session through success, error, metrics, navigation and renewal. Foreign live actions receive no late completion counts. | [EXP-175 completion regression](Results/EXP-175-resource-completion.json), [EXP-176 mapper/backend acceptance](Results/EXP-176-resource-start.json) | Acceptance is serial native A background/B navigation and session renewal; simultaneous shared requests remain H07, Trace coverage T08. |
| Current-view errors | Message, Error and callback forms accept a live explicit target without changing captured Resource-error ownership. Dropped/unsampled commands complete once after scheduled writes. | [EXP-177 complete SDK, native and backend evidence](Results/EXP-177-current-view-errors.json) | Stable API F01 and physical topology remain separate. |
| View attributes/removal | Swift and Debug Objective-C target forms isolate single/batch add/remove, preserve fallback and global/view/event precedence, and do not restore ended views. Native A/B markers preserve exact typed values and absence after removal; global updates reach both views. | [EXP-178 SDK, native and backend evidence](Results/EXP-178-view-attributes.json) | T05 accepted within the serial native contract. Stable API F01 and physical topology remain separate. |
| Custom timing/loading | Candidate target forms preserve independent fallback, repeated timing-name replacement and loading overwrite rules. Timing alone permits eligible expiration restoration; custom/NOP calls remain compatible. | [EXP-179 SDK checkpoint](Results/EXP-179-timing-loading.json):426 affected,11 ObjC/Core,3 integration on26.5 and iOS/watchOS Release pass | T06 remains open: the defined native/backend contract is pending. |
| Feature flags/internal mutations | Existing inferred exact-view → same-scene → representative routing has focused coverage. Internal-only fields remain internal. | [EXP-101 routing evidence](EXPERIMENTS.md#exp-101) | T07 customer-callable targets and internal call-site capture remain open. |
| Operations | Identity remains application-wide name/key; each step independently resolves explicit/inferred/last-proven/process context. Duplicate starts replace only the client instance without a synthetic end. | [EXP-130/155 raw and reduced evidence; EXP-157 physical serial acceptance](EXPERIMENTS.md), [contract](OPERATIONS.md) | Simultaneous visible topology H06 and stable API F01. |
| Traces and Logs | Existing tests and trace-only runs support captured start/emission context; named-core handoffs are isolated. Broader ownership acceptance is still required. | [EXP-133/134 Trace records](EXPERIMENTS.md), [EXP-166 all-consumer isolation](Results/EXP-166-handoff-isolation.json) | T08 native/OTel/automatic Trace, T09 Logs/mirrored errors and H07 shared-request acceptance. |
| WebView | Legacy unambiguous native container correlation is preserved without arbitrary peer fallback. Mounted Replay-enabled compatibility passes. | [EXP-165 native WebView compatibility](Results/EXP-165-webview-correlation.json) | Two actual native containers with navigation/rebind/backend ownership: T10. |
| Process signals and context | Source-less fatal/exported context, long tasks, hangs, memory warnings and profiling use documented process semantics. Process metrics must not be claimed as independent per-window measurements. | [approved contract](../MULTI_SCENE_SUPPORT.md#confirmed-product-decisions), [family completion modes](PLAN.md#telemetry-completion-contracts) | T11–T14 require their distinct controlled/runtime/backend deliverables; prior source inspection is not acceptance. |
| Ordinary apps and supported systems | Early automatic/manual/custom/NOP workloads pass on27/26.5. watchOS/macOS and caller-thread/legacy-correlation regressions have bounded repairs. | [baseline protocol and results](BASELINES.md), [review dispositions](PRODUCTION_SAFETY_REVIEW.md), [EXP-178 older attribute integration](Results/EXP-178-view-attributes.json) | C03 legacy27 host trap is inconclusive; C06 minimum15 runtime is unavailable in recorded runs; F03 final platform/ObjC Release matrix remains required. |
| Performance and retained state | Early dispatch, allocation, reentrancy and retained-state workloads meet their original thresholds after repairs. | [frozen thresholds and numeric results](BASELINES.md), [EXP-166 paired measurements](Results/EXP-166-handoff-performance.json), [EXP-172 retention](Results/EXP-172-scene-retention.json) | Simulator microbenchmarks do not establish device-wide performance. Repeat at relevant architectural change and final freeze F06; do not raise thresholds. |
| Session Replay | Exercised runs coexist without an SDK-caused crash; no scene-correct recording claim is made. | [EXP-004/019 records](EXPERIMENTS.md), [EXP-165 compatibility](Results/EXP-165-webview-correlation.json) | F05 requires physical multi-window coexistence. Full multi-scene replay remains out of scope. |

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
  Stable API approval, supported-runtime checks, physical topology, Duo27.1
  acceptance and final freeze remain governed by the register.
- Current availability must be rediscovered when execution needs it. Earlier
  devices, sessions and temporary artifacts are evidence locators, not instructions
  to reuse them.

Chronological conclusions and the superseded routing audit are retained in the
[documentation checkpoint](Experiments/DOCUMENTATION_CHECKPOINT_EXP-178.md).
Use the [compact index](EXPERIMENTS.md) to open only the experiment that owns a question.
