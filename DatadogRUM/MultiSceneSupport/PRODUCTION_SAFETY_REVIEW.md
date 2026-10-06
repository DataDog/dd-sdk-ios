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
| Repeated request mutation and terminal retention / S1 E01 | Repaired in isolated candidate; selected S2 T03/T08 closed | [Approved repair](Results/EXP-197-urlsession-extraction.json) and [terminal ownership](Results/EXP-199-terminal-task-ownership.json). Concurrent duplicate resume can forward later on the preparation thread; original-thread timing is not promised. [Fold](Results/EXP-221-duo-fold.json) and [app](Results/S2-F08-candidate-comparison.json) preserve baseline baggage/terminal-view observations and inherited E03/E05 limits. No whole-release or physical-Duo claim. |
| Retained old-view attribute mutation / S1 E02 | Repaired in isolated candidate | [EXP-205](Results/EXP-205-view-occurrence-isolation.json): same-key occurrence isolation; source-specific qualification and delivery remain in the packet. |
| Late completion changes foreign action / S1 E03 | Repaired in isolated candidate | [EXP-214](Results/EXP-214-resource-action-design.json), [EXP-219](Results/EXP-219-upstream-resource-integration.json): approved Error1/Resource0, exact owner/counters and upstream reconciliation. Original manual controls and inherited stopped-session diagnostic remain. [Simplification review](Results/S1-resource-completion-review.json) found no safe smaller ownership design. |
| Long-lived view loses delayed WebView correlation / S1 E04 | Repaired in isolated candidate | [EXP-207](Results/EXP-207-active-view-cache.json): active lifetime and bounded expiry; [changed-edge review](Results/S1-E04-lifetime-disposition.json) adds no host/pending-Resource retention claim. Lookup takes a write lock. |
| Request-time Trace ownership / S1 E05 | Repaired in isolated candidate | [EXP-208](Results/EXP-208-trace-ownership.json), [backend admission](Results/S1-E05-release-admission.json): value-only start capture, completion guards, header/sampling preservation and exact nil/A/B ownership. Original stale-reducer and opaque-ID failures remain; immediate unbind/footprint is not claimed. |

The [component review](COMPONENT_REVIEW.md) owns the bounded SwiftUI responsibility
pass. No new public API, broad extraction eligibility or final independent approval
follows from these findings. Exact counts, source hashes, attempts and PR state belong
to the linked results and [delivery queue](Results/S1-delivery-queue.json).

## Unresolved observations and review obligations

| Observation / obligation | Disposition and evidence limit |
| --- | --- |
| S2 automatic capture | [Coverage owner](Results/S2-coverage-remaining-preparation.json) preserves accepted UIKit evidence, four SwiftUI cells and the distinct saved split reference. Original candidate failure and separate restoration remain immutable. [Pre-armed service](Results/S2-prearmed-owner-preparation-20261003.json) now passes exact offline composition review after owned-End, request lineage, quiescence and Start-publication corrections. P2 automatic capture composition is independently qualified. The complete human workspace/Home-terminal/saved-publication/restoration preparation passes designated re-review after the circular readiness binding is corrected with9 actual-shape controls;26 earlier controls remain accepted. Fresh actual materialization/authority/readiness and native evidence remain required; C09/C10 and actual H14 fold proof remain open. |
| Ordinary hosting / S2 H16 | [Saved assessment](Results/S2-H16-scoped-assessment.json) closes ordinary hosting parity. Original manual backend gap remains; no gesture, fold or S3 semantic claim. |
| Duo/app acceptance | [F08 comparison](Results/S2-F08-candidate-comparison.json) qualifies finite app behavior and native/Browser owners. It cannot certify automatic tracking or physical Duo. [Pre-app boot failures](Results/S2-Duo-environment-readiness.json) have no established SDK cause. |
| Networking QoS | [EXP204](Results/EXP-204-network-qos.json) establishes baseline recurrence with incomplete stacks, not root cause, harmlessness or sanitizer/performance clearance. Candidate-specific warnings remain in their results. |
| Header policy | [PR2683 review](Results/PR-2683-header-ownership-review.json) does not qualify the proposal or general partial/mixed-carrier policy. |
| Provisional API / F01, C06, F03 | [Availability evidence](Results/EXP-225-api-availability.json) supports legacy fallback and off-main rejection before UIKit access; [API audit](Results/S3-M10-source-audit.json) preserves existing declarations. Actual concurrent ownership, approval/public exposure and source promotion remain. [Same-key attempt](Results/EXP-225-same-key-result.json) stopped before API work. |
| Shared human capture | [Physical baseline](Results/S2-H11-H13-local-baseline.json) is reusable. The [candidate](Results/S2-H11-H13-local-continuation.json) stopped before input because the harness compared portrait window axes with unrotated panel bounds; baseline setup was landscape. Owned scene/window/root/key checks passed, cleanup PASS; no SDK regression or gate closure follows. [Orientation readiness](Results/S2-physical-orientation-20261001.json) now passes24 offline controls and independent re-review, preserving actual returned bytes and original receipt cutoffs; actual pose/native continuation remains unqualified. [SwiftUI comparison](Results/S2-H12-H13-swiftui-duo.json) closes H12 and its H13 portion, retaining inherited manual attribution. Immediate delivery and mapper ordering are not universal criteria; forced flush stays stopped. |
| Delayed WebView ownership / S2 T10 | [Paired assessment](Results/S2-T10-source-preparation.json) closes active lifetime, inactive expiry, delayed exact owners and detached release in its finite scope. No physical-Duo/S3 claim. |
| Harness readiness / A02 | [Repair review](Results/human-harness-repair-loop-20260927.json) qualifies offline controls and saved replay. [Shared preflight](Results/shared-capture-preflight-20260930.json) resolves issued-receipt and final-admission publication gaps with 36 focused controls and independent review. The [SwiftUI reader continuation](Results/S2-accessibility-discovery-20261001.json) also passes50 owner/readiness controls and final baseline-plan review; consumed admission is checked before effects and the actual reviewer cannot own interaction. Actual pump/native/ancestry and [current sessions](Results/S2-input-session-preparation.json) remain unqualified. No product gate closes from preparation. [RUM-only alternative](Results/S2-rum-only-20261001.json) reproduces four accepted verdicts offline;32 source/stop/comparison controls and independent re-review pass. New bound plan/review required before native adoption; H14 fold proof remains separate. |
| Physical focus / S3 H04 | [Activation preparation](Results/S3-H04-activation-preparation.json) qualifies compiled product and runner controls. Actual device admission and serial foreground ownership remain; serial activation cannot prove an uninterrupted visible peer. |
| Isolated background / S3 H10 | [Preparation](Results/S3-H10-background-preparation.json) qualifies compiled app/session, host phase, marker/decoder, backend and bootstrap/cleanup components. The still-source adapter now passes31 synthetic controls and independent re-review: damaged evidence cannot block the original owned End, actual Start ownership survives publication failure, mutation rejection stays sticky, and terminal cleanup bytes are rejoined through publication. Actual supported-source capture and native/display/runtime composition remain; marker pixels prove neither whole-window usability nor lifecycle continuity. No runtime gate closes. |
| Silent physical display / S3 H06 | [Silent capture owner](Results/S3-H06-silent-capture.json) qualifies primitives only. Actual source observation/recording, first-launch startup, simultaneous topology and Operation owners remain unqualified. CoreDevice recording stays stopped; the old audio-bearing QuickTime movie cannot qualify future silent capture. [Original preparation](Results/S3-human-residual-preparation.json) links immutable failures and separate restoration. |
| Application impact / P01 | [EXP224](Results/EXP-224-application-impact.json) is a stopped optional diagnostic under the [measurement rule](../MULTI_SCENE_SUPPORT.md#measurement-and-testing-rule). No performance pass or SDK defect follows. |
| CI | [Finite follow-up](Results/S1-ci-followup.json): repair only failures linked to changed production/associated tests; PR3196 owns timeseries. Required CI and maintainer review are not waived. |
| Provisional compatibility / S3 F03 | [F03 owner](Results/S3-F03-candidate-preparation.json) preserves qualified components and runtime limits. [Core disposition](Results/EXP-227-core-failure-disposition.json) distinguishes test corrections from the pre-construction UIScreen mock trap. [Integration qualification](Results/EXP-227-integration-fixture-result.json) retains original TTID uncertainty, assertion-helper crash and separate restoration. Public exposure and whole-F03 closure remain separate. |
| Candidate foreground finalizer / S2 C09–C10 | [Foreground owner](Results/S2-foreground-finalization-20261002.json) preserves the consumed-idle correction and separate scenario/evidence/cleanup outcomes. Worker quiescence is proved. [Service review](Results/S2-prearmed-owner-preparation-20261003.json) now passes offline; failure-only owned End cannot rescue acceptance. Prior BLOCKED receipts remain; P2 automatic capture composition is qualified; the residual human/Home-terminal composition still needs review and actual candidate evidence before release credit. |
| Flagged develop mapping / S3 F11 | [Source mapping](Results/S3-F11-production-mapping.json) qualifies all 274 source/disposition/dependency assignments and the 13 delivery slices after independent full review and corrected-boundary re-review. Original BLOCKED receipts remain immutable. F11 closes source mapping only; fresh develop defaults, On-only owner activation, complete declaration boundaries and legacy Off behavior remain implementation/F12 obligations. No compiler, SDK safety or native pass follows. |
| Runtime flag / PR1–PR3 | [PR1](Results/S3-PR1-runtime-flag.json) and [PR3 owner](Results/S3-PR3-routing-preparation.json) retain qualified flag plumbing, dormant/cache/routing components and full RUM27/17.5 source-matched suites. The parent/current27 Off pair preserves all eight semantic traces and nil new state; its actual same-run coverage proves all14 selected On helpers unused. Positive detector visibility and source/control reviews remain bound. The17.5 pair also qualifies all eight comparisons with restored lanes; local PR3 Off obligations are complete. Remaining delivery slices are open. Original harness failures/restoration remain separate; no wholeF12, public API or release credit follows. |

All original failures, component reviews, counts and raw artifact identities live
in the linked owners and their history; this table is not another experiment log.
The [consolidation receipt](Results/documentation-consolidation-20260930.json)
records the preceding source checkpoint and section disposition. No unresolved
finding was closed by moving its narrative.

Exported/fatal/process/vitals/profile validation added no established production
finding; [the assessment](ASSESSMENT.md) owns capabilities and limits. Session
Replay scope is crash safety and other-feature continuity; captured-content repair
is excluded. Current S2 source/lifetime proof belongs to
[EXP216](Results/EXP-216-s2-composition-promotion.json), not the original reference review.
- [PR4 monitor targeting](Results/S3-PR4-monitor-preparation.json): private D1-D8 component qualifies44/44 on27 and17.5, with exact source/compiler/case/products evidence, separate cleanup PASS and designated final review. Local source checkpoint06e87120c uses the authorized unsigned fallback. Earlier compiler, fixture and consumer failures remain immutable; wholeF12, activation, API and hardware stay open.

- [PR5 scene handler](Results/S3-PR5-scene-handler-preparation.json): unknown/disconnected eligibility and the invented-scene factory fixture are corrected and independently re-reviewed. All64 exact components pass on27 and17.5; source/compiler/products, native results and separate original-state cleanup join. Final P5D1-P5D8 component review passes. Full-current RUM suites also qualify1041cases/1077invocations on each runtime; the reviewed count correction grades existing exports without repeating tests. Qualified source is locally checkpointed at8cd7793d3 using the authorized unsigned fallback. Concrete exclusive-Off now independently qualifies at this source; genuine OS ordering, activation, wholeF12, API and hardware remain separate. Original BLOCKED reviews and consumer stops stay immutable.

- [PR6 owner](Results/S3-PR6-action-preparation.json) retains accepted activation, scopes, callbacks, input/scroll,
  concrete Off and platform components. Four genuine attached configured methods qualify at e1. The
  [SDK-free discriminator](Results/S3-PR6-lifetime-discriminator-20261005.json) independently confirms fixture
  confounding at the immediate UI-release boundary: window/controller/scroll assertions also fail without instrumentation.
  Original instrumented/control FAIL remain; SDK Monitor/handler/proxy release and host-key restoration pass.
  Actual control evidence is COMPLETE and cleanup PASS, with task removal and original device/worker/Xcode state verified.
  No SDK retention cause, eventual UIKit release or current102d final-stack claim follows. P6R7 finite applicability
  review passes with explicit holds; real minimumSwift6.2, watch runtime/distribution and release acceptance remain open. Earlier failed admissions,
  missing-dependency stop and INVALID cleanup remain at their owning records; no equivalent control is needed.

- [P2 progress](Results/execution-improvements-20261004.json) preserves original failed routes and separate
  restoration. The ordering/dispatcher correction has28 reviewed controls. The extra one-attempt grant is now consumed:
  four actual calls completed, with terminal inventory/native idle before End, current parent/worker exit0, task-only
  cleanup and original app/device/display/Xcode restoration independently qualified. Separate saved-only grading passes
  21rows/3view owners; it does not reconstruct the missing original standalone native grade return. Exact TTY equality
  remains false with only Darwin PENDIN differing. This is automatic capture-composition credit only; residual
  human/gesture/Home/fold and physical orientation assertions remain unqualified. The [complete startup owner](Results/execution-improvements-20261004.json#p2.human_startup_blocker.canonical_startup_assembly) now binds canonical configuration and full local handshake/publication qualification, with designated review. Modeled platform reads and mocked Start grant no native readiness or behavioral credit. Root selection/readback now passes in the actual startup. Start/Install/initial Capture passed, then the app PID disappeared during Ready wait; cause is unproved. The [current stop](Results/S2-capture-continuity-20261006.json) retains original UNQUALIFIED/INCOMPLETE/INVALID and separate reviewed task/state/custody restoration. The separate autonomous shared-hook qualification now passes: same process/run/scene/window through three actual renewals, one final End and task/workspace restoration within cutoff, with independent review. The [latest human composition](Results/S2-capture-receipt-20261006.json) launched and returned two Running captures, then stopped on the parent receipt-path collision before renewal forwarding; no Ready invitation or gestures. Original invalid verdicts remain beside separate reviewed restoration. Repair per-call receipt identity and prove one complete renewal before Ready. The automatic qualification does not qualify this failed human path; no SDK, behavioral gate or lease-cause credit.

- P5 has one source-paired Monitor/legacy-factory Off fixture in linked verification
  worktrees at PR3/PR4/PR5. Transport/consumer review findings are corrected
  together and 37 focused offline controls pass with independent proposal review.
  All six cells and 36 adjacent scenario comparisons qualify with component-lane
  original-state cleanup. The baseline's original INCOMPLETE remains beside its
  independently reviewed saved-only correction. Final independent review qualifies
  concrete PR4/PR5 dispatch/read/state/lock/lifetime and exclusive-factory obligations
  through source reachability and accepted On witnesses; numeric complete-helper
  coverage, universal allocation and class size are not claimed. No suite or native
  cell is rerun.
  The owning progress records a finite seven-item PR6 exit packet. Accepted suites are preserved; no release gate or universal footprint
  claim follows from preparation.

- [PR9 owner](Results/S3-PR9-representative-preparation.json) records private source c6fbf17a and clean test-only successor102d. Twelve selected unit methods pass on27.0 and17.5, including retained owners, modeled legacy Off snapshot retention and injected-identity handler/Monitor disconnect. Saved coverage qualifies dormancy of three named On helpers with positive visibility. Eight current-source framework commands qualify four-platform compilation through independent actual-context review and verified worker retirement. MinimumSwift6.2, watch9 binary/runtime, complete Off/final-stack integration and release acceptance remain open; internal injectedOn17.5 does not establish public eligibility. Original failures and separate restorations remain immutable.

The [PR7 owner](Results/S3-PR7-consumer-preparation.json#current44_actual_execution) retains the current43 passed consumer methods and the separate complete Core test failure, with reviewed original-state cleanup and whole INVALID unchanged. The sampling fixture seeded shared state before asynchronous initialization completed; the signed, reviewed one-line test barrier keeps all assertions. The separate fresh CoreTSan build and single changed method now pass, with independently reviewed original-state restoration; the other43 were not repeated. No production regression or whole-PR7/F12 claim follows. WebView native-container acquisition and Flags Internal/React Native acquisition still require source-backed implementation within the default-Off contract; complete Off, older-system/lifetime/final-stack and release acceptance remain.
