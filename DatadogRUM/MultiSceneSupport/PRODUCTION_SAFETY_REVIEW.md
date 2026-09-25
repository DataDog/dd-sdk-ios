# Production safety review and dispositions

**The original review cycle is completed.** R01–R12 below map to repair gates
D01–D12, distinct from component responsibility gates R01–R06. Closure describes the
qualified reference source; it does not certify a new extraction or overall release.
[The register](release-gates.json) and [PLAN](PLAN.md) own release readiness.

Original review: 2026-09-17, branch `valpertui/multiple-windows-scenes`, head
`af63657f08dbecb66e7c3ae97ed53fc8f7b065b9`, comparison base
`92f021ba7e4a866f84a52da93ed8b63f3dc75882`. It covered a 41-file production delta
and reported nine P1 and three P2 findings. Evidence was source review plus focused
compiler/extracted-state/ARC probes, not complete SDK, mounted or physical validation.
The original hold verdict applies to that reviewed revision, before the repairs.

[Initial triage](REVIEW_TRIAGE.md) owns relevance and decisive repair boundaries.
[The historical review](Experiments/DOCUMENTATION_CHECKPOINT_EXP-220.md#original-safety-review)
preserves original wording, line locators, reproductions and exclusions. Subsequent
repair/runtime evidence is attributed in the table; original limitations remain.

## Original finding dispositions

| Finding / gate | Current disposition | Repair evidence and retained limitation |
| --- | --- | --- |
| R01 / D01: watchOS Resource compilation | CLOSED | [EXP-162](Experiments/EXP-143-199.md#exp-162--restore-watchos-resource-and-macos-webview-compilation), signed `e420528f7`: full watchOS RUM Debug/Release builds and 70 iOS Resource/action tests |
| R02 / D02: macOS WebView compilation | CLOSED | [EXP-162](Experiments/EXP-143-199.md#exp-162--restore-watchos-resource-and-macos-webview-compilation), signed `af8864528`: full macOS WebView Debug/Release builds and 28 iOS bridge tests |
| R03 / D03: keyed registration retention | CLOSED | [EXP-168](Experiments/EXP-143-199.md#exp-168--release-keyed-swiftui-registrations-and-instrumentation), signed `7b77f60eb`: 303 tests; mounted 27/26.5 checks 37/37 each, zero weak survivors and three method implementations restored after SDK stop |
| R04 / D04: named-core handoff isolation | CLOSED | [EXP-166](Experiments/EXP-143-199.md#exp-166--isolate-ui-event-handoff-by-sdk-lifecycle-and-reduce-allocations), signed `5eb3c1aac`: 282 affected tests, core/task/lifetime and all-consumer isolation; allocation1/64 and latency/reentrancy budgets pass on27/26.5 |
| R05 / D05: source-less session restoration | CLOSED | [EXP-167](Experiments/EXP-143-199.md#exp-167--preserve-navigation-ownership-across-session-restoration), signed `0aaafa7bd`: failing source-less start/identity-stop controls, 198 tests and two-native-scene 47/47 runtime acceptance |
| R06 / D06: lazy-expiration peer restoration | CLOSED | [EXP-167](Experiments/EXP-143-199.md#exp-167--preserve-navigation-ownership-across-session-restoration): controlled timeout/max-duration lifecycle boundaries, fresh peer IDs and exact action/Resource owners; background and legacy controls |
| R07 / D07: pending semantic authority | CLOSED | [EXP-169](Experiments/EXP-143-199.md#exp-169--keep-automatic-tracking-until-semantic-input-is-ready), local unsigned `a9aaf25a7`: four failing controls, 119 tests and mounted29/29; automatic eligibility before input and exact immediate semantic owners |
| R08 / D08: reconnect generation | CLOSED | [EXP-170](Experiments/EXP-143-199.md#exp-170--accept-semantic-reconnects-only-after-a-live-attachment), signed `66d1ccb02`: three failing controls,314 affected tests and mounted51/51 versus39/51; fresh reconnect Resource/Log owners, peer continuity and delayed remount. H09 still requires genuine OS ordering. |
| R09 / D09: controller caller-thread safety | CLOSED | [EXP-164](Experiments/EXP-143-199.md#exp-164--preserve-controller-api-caller-thread-compatibility) at local `a9abc092b`: 31 tests and actual mounted fixture 19/19; zero background reads/MTC diagnostics versus control 5 reads/4 diagnostics |
| R10 / D10: accepted presentation state | CLOSED | [EXP-173](Experiments/EXP-143-199.md#exp-173--commit-accepted-presentation-state-and-fence-occurrence-callbacks), signed `7619eb8a2`:337 tests; actual mounted Bindings/sheet/cover77/77 versus55/77, exact Resource/Log owners and native dismissal; all failed attempts preserved |
| R11 / D11: legacy WebView correlation | CLOSED | [EXP-165](Experiments/EXP-143-199.md#exp-165--preserve-legacy-nativewebview-replay-correlation), signed `9a1ee83a5`: 102 tests, 19/19 mounted WebView/Replay checks; legacy association restored, peers excluded |
| R12 / D12: expired action stop attributes | CLOSED | [EXP-163](Experiments/EXP-143-199.md#exp-163--preserve-overdue-action-stop-attributes-without-peer-leakage), signed `084dff4c1`: three failing recipient controls, 212 affected tests pass; own overdue-stop attributes retained without peer leakage |

## Additional and subsequent findings

| Finding / gate | Disposition | Evidence and limit |
| --- | --- | --- |
| Retained reader / R04 | Repaired; bounded review closed | [EXP-171](Results/EXP-171-retained-reader.json): no-body remount restores latest owner and weak lifetime. Genuine OS ordering remains H08/H09. |
| Stale presentation occurrence / R06 | Repaired with D10 | [EXP-173](Results/EXP-173-presentation-acceptance.json): accepted-state and occurrence-token controls; physical ordering remains separate. |
| Disconnected scene history / P03 | Repaired in reference | [EXP-172](Results/EXP-172-scene-retention.json): bounded registries/weak survivors with stale-callback controls and original thresholds. |
| Reentrant observer fan-out / R05 | Repaired; bounded review closed | [EXP-174](Results/EXP-174-observer-delivery.json): nested initial/ordinary delivery and live add/remove membership. No physical/backend claim. |
| Cross-session Resource completion / T03 | Repaired in reference | [EXP-175](Results/EXP-175-resource-completion.json) and [EXP-176](Results/EXP-176-resource-start.json): exact retained owner and foreign continuous-action counts. |
| Flags asynchronous ownership / T07 | Repaired and qualified | [EXP-180](Results/EXP-180-flags-internal-mutations.json): captured origin survives delivery; native FBC absence is expected because downstream FBC is Flutter-only. |
| Repeated request mutation and terminal retention / S1 E01 | Repaired in isolated candidate | [EXP-197](Results/EXP-197-urlsession-extraction.json) and [EXP-199](Results/EXP-199-terminal-task-ownership.json) qualify the approved repair. Concurrent duplicate resume may forward later on the preparation thread; original-thread timing is not promised. Selected-S2 [navigation](Results/EXP-221-s2-resource-trace.json) and both candidate [rollover modes](Results/EXP-221-session-rollover.json) pass. Baseline baggage mutation remains documented. [Fold](Results/EXP-221-duo-fold.json) is still invalid: the Date-corrected continuation received Closed input in time but published its receipt late. Automated fold is stopped; the original failed cleanup and separate successful restoration remain distinct. Human fold and integrated-app acceptance remain open, without an SDK regression finding. |
| Retained old-view attribute mutation / S1 E02 | Repaired in isolated candidate | [EXP-205](Results/EXP-205-view-occurrence-isolation.json): same-key occurrence isolation; source-specific qualification and delivery remain in the packet. |
| Late completion changes foreign action / S1 E03 | Repaired in isolated candidate | [EXP-214](Results/EXP-214-resource-action-design.json), [EXP-219](Results/EXP-219-upstream-resource-integration.json): approved Error1/Resource0, exact owner/counters and upstream reconciliation. Original manual controls and inherited stopped-session diagnostic remain. [Simplification review](Results/S1-resource-completion-review.json) found no safe smaller ownership design. |
| Long-lived view loses delayed WebView correlation / S1 E04 | Repaired in isolated candidate | [EXP-207](Results/EXP-207-active-view-cache.json): active lifetime and bounded expiry; [changed-edge review](Results/S1-E04-lifetime-disposition.json) adds no host/pending-Resource retention claim. Lookup takes a write lock. |
| Request-time Trace ownership / S1 E05 | Repaired in isolated candidate | [EXP-208](Results/EXP-208-trace-ownership.json), [backend admission](Results/S1-E05-release-admission.json): value-only start capture, completion guards, header/sampling preservation and exact nil/A/B ownership. Original stale-reducer and opaque-ID failures remain; immediate unbind/footprint is not claimed. |

The [component review](COMPONENT_REVIEW.md) owns the bounded SwiftUI responsibility
pass. No new public API, broad extraction eligibility or final independent approval
follows from these findings. Exact counts, source hashes, attempts and PR state belong
to the linked results and [delivery queue](Results/S1-delivery-queue.json).

## Unresolved observations and review obligations

| Observation / obligation | Required disposition boundary |
| --- | --- |
| Current S2 native-input variability | [EXP-210](Results/EXP-210-s2-automatic-coverage.json) and [EXP-218](Results/EXP-218-native-input-observation.json) do not isolate an SDK cause. [EXP-220](Results/EXP-220-native-input-callback.json) observes successful baseline SDK-on/off callbacks on regular iPhone27.0, preserving setup/host stops. Earlier variability remains unattributed; no candidate/Duo acceptance follows. |
| Ordinary UIKit-hosted SwiftUI / S2 H16 | [EXP-222](Results/EXP-222-hosted-swiftui.json) qualifies three bound simulator cells. The manual candidate completes native transitions/RUM occurrences and cleanup, but lacks the Root SwiftUI callback pair around immediate push/pop. Keep its original INVALID and strict lifecycle oracle. A human-paced attachment/lifecycle discriminator and complete backend evidence remain; no automatic retry or SDK change is justified. |
| Duo environment and app acceptance | [Fresh-device boot failures](Results/S2-Duo-environment-readiness.json) remain unresolved. [Prebooted app navigation](Results/S2-F08-app-journeys.json) reaches subdomain/Back, but AXe Home has no observed effect and Xcode MCP sessions disappear before input. Scoped cleanup passes; no SDK attribution or paired acceptance follows. |
| Networking QoS / inherited test diagnostics | [EXP-204](Results/EXP-204-network-qos.json) establishes baseline recurrence with incomplete stacks, not root cause, harmlessness or sanitizer/performance clearance. Keep candidate-specific warnings in their own results. |
| Baggage versus trace-carrier policy | [PR2683 review](Results/PR-2683-header-ownership-review.json) is not qualification of that proposal or general partial/mixed-carrier policy; bounded T08 follow-up stays separate. |
| Stable API/off-main Objective-C / F01, C06, F03 | [EXP-225](Results/EXP-225-api-availability.json) qualifies nullable creation, rejection before actor/UIKit access and legacy fallback with optimized clients and source-paired17.5 journeys. The [same-key attempt](Results/EXP-225-same-key-result.json) stops before API work when UIKit backgrounds the first scene. The [full RUM suite](Results/EXP-225-rum-suite-result.json) qualifies on27/17.5 after a test-only runtime guard prevents XCTest invoking an unavailable class. All25 guarded tests still pass on27; exact17.5 skips and eight original crashes remain recorded. No production availability defect was found. F01 approval, public exposure, simultaneous same-key proof and the complete F03 matrix remain open. [EXP-226](Results/EXP-226-platform-result.json) qualifies the20 platform build cells, including private native links and resources; remaining full-module execution is defined in [EXP-227](Results/EXP-227-modules-definition.json). |
| Shared human-session capture | [EXP223](Results/EXP-223-interactive-transitions.json) retains qualified ordinary-simulator capture and the source-reviewed completion-boundary limitations; recorded mapper timing does not establish internal SDK ownership at callback time. Physical automatic selection remains stopped. The human UIKit baseline captured all gestures and Home, with cleanup PASS; backend projection stopped collection and candidate is unrun. The action-only correction passes57 offline controls and scoped review, preserving raw values and strict ownership/terminal checks. Saved Home terminal evidence is still incomplete. A same-binary follow-up navigated but did not capture its armed pop callback chain; cleanup PASS, no backend query and no SDK regression finding. The physical-only public recognizer correction captures all four callback chains. Its latest baseline still lacks final action/view delivery within the original backend window; cleanup PASS, candidate UNRUN. Fixture background lifetime is under review; no physical/backend gate closes. Original physical/Home failures and later restoration remain separate; Replay metadata is unassessed. |
| Acceptance continuity / S2 A02 | [Session preparation](Results/S2-input-session-preparation.json) now supports separate automatic-coverage pair sessions. Predecessor receipts, original clocks and cleanup remain immutable; canonical attempt claims reject duplicate or partial admissions. Offline preparation only; first native baseline remains required. |
| S3 application impact / P01 | [EXP-224](Results/EXP-224-application-impact.json) stops physical capture: both documented attachment selectors fail while the exact baseline app remains visible in CoreDevice snapshots. No workload, performance evidence or SDK attribution; original cleanup PASS, remaining cells unrun. The unsuccessful name adapter is frozen in evidence and removed from the working tree. A concrete tooling prerequisite must change before further native qualification. |
| CI flakes | [Finite CI record](Results/S1-ci-followup.json): repair only failures clearly linked to changed production or associated tests; PR3196 owns timeseries. No waiver of required CI or maintainer acceptance. |
| Provisional Core compatibility / S3 F03 | [EXP-227](Results/EXP-227-core-failure-disposition.json) qualifies full Core26.5 after correcting two test expectations and draining asynchronous initialization before the lifetime assertion. All817 eligible cases pass with3 expected skips; cleanup passes. Original27/26.5 failures remain. The unchanged UIScreen mock traps before publisher construction on27; no production defect or27 pass follows. Seven further module suites qualify; Integration's installer failure precedes assertions and establishes no SDK defect. [EXP-228](Results/EXP-228-public-clients-result.json) qualifies five existing-public-client configurations, preserving the original Objective-C fixture/schema failure. Public scene exposure and full F03 remain separate. |

Exported/fatal/process/vitals/profile validation added no established production
finding; [the assessment](ASSESSMENT.md) links those capabilities and their limits.
Fixture/oracle issues remain in their owning results, not in this SDK defect list.
Session Replay captured-content repair is outside scope; crash safety and other-
feature continuity remain required. Optional network microbenchmarks add no numeric
claim, and included new semantic/multi-scene code retains scoped application-impact
obligations. Current S2 composition/lifetime qualification is specifically bound to
[EXP-216](Results/EXP-216-s2-composition-promotion.json), not the old reference review.
