# RUM multi-scene experiment index

Use this file to find the current status and exact detailed record for a named
experiment. Current support conclusions live in [ASSESSMENT.md](ASSESSMENT.md);
ordered work and the hardware queue live in [PLAN.md](PLAN.md). Search
[REJECTED_APPROACHES.md](REJECTED_APPROACHES.md) before revisiting an earlier
design or tooling path.

Full records through `EXP-142` are frozen in
[the historical experiment snapshot](Archive/EXPERIMENTS_THROUGH_EXP-142.md).
New full records belong in the active
[EXP-143-199 shard](Experiments/EXP-143-199.md). Do not renumber experiments.

Last updated: 2026-09-17

## Current checkpoint

Current release position: **31/66 gates closed**. All12 original safety findings
and all6 bounded responsibility reviews have repair/review evidence. EXP-176 closes
T03 at SDK `5e41d0b11` and fixture `797ab135c`:397 affected cases across396+1,
8 Objective-C checks, iOS/watchOS Release,167 probe tests,22 local expectations/
77 signals and exact backend5 Resources/4 errors/5 views across2 sessions.
All failed attempts remain preserved. EXP-177 is defined for T04 current-view
error targeting and completion delivery; T05/T06 follow. Recent identities and
attempts are in the finite gate register and active shard.

The checkpoints below preserve the earlier telemetry/navigation milestones;
they do not override this current release position.


- Last accepted public telemetry slice: `EXP-159`, targeted long-running action start/stop.
  Bounded synchronous live-view runtime passes 15/15 and exact backend ownership;
  full RUM 1,260/1,260, probe 166/166, Objective-C 8/8, Release and lint pass.
  The earlier background-interrupted attempt remains INCONCLUSIVE. Next work is
  finite release gates, early baselines, incremental review, and acceptance
  automation before any further telemetry expansion.

- Latest physical-device attempt is `EXP-157`. `EXP-156` now closes the tooling
  gate: after the earlier connection, unsigned-install, and restricted-context
  signing failures, a copied `arm64` build passed strict/deep verification,
  clean install, and launch on the wired iPad. The first `EXP-131` runtime then
  timed out before scene B or any Operation call because the scenario still
  used the unrelated legacy occurrence-source Home boundary. It emitted only
  automatic hosting-controller views. The scenario now uses the same explicit
  non-navigating Home setup already accepted for `EXP-155`; focused tests pass
  2/2 and the complete probe passes 163/163. The corrected physical run passes
  24/24 across two native scenes. Backend intake contains all eight raw steps
  and four exact reduced Operations: success/failure A→B, alpha A→A, and beta
  B→B ending before alpha. The Operation contract is accepted. Both scene
  geometries were full-screen and only B was foreground-active at completion,
  so simultaneous on-screen visibility remains a separate human-arranged Stage
  Manager/split-window row. The physical iPad is currently unavailable, so the
  unchanged hardware queue is paused rather than reinterpreted through simulator
  evidence.
- Latest runtime experiment is `EXP-158`. The generalized experimental
  `RUMViewTarget.current(in:)` keeps explicit and inferred action targets
  separate. Its serial two-native-scene run passes 9/9 while deliberately making
  B representative: explicit A owns A, explicit B owns B, and a source-A legacy
  action remains on B. Backend session
  `f67c75b2-e839-4701-a283-7e4355682b6a` confirms the same ownership across 30
  events. This accepts scene-targeted one-shot actions without approving stable
  API or changing source-less last-interacted behavior.
- Latest accepted SDK implementation, probe, and documentation checkpoint:
  `c2d1f1f9a` (`Target one-shot actions to a window scene`). Earlier SDK
  semantic-navigation checkpoint: `24cf5078a`
  (`Add observable semantic navigation adapters`). Latest migration fixture,
  harness, and probe-test checkpoint: `7da52ae6d`
  (`Expand semantic navigation probe coverage`). The signed `EXP-152` harness
  checkpoint is `0a67f3e36` (`Add native presentation dismissal probe`). The
  signed `EXP-153` harness checkpoint is `d6d813736`
  (`Exercise callback-driven semantic navigation`). The signed `EXP-154`
  scenario checkpoint is `7fd6a891a`; its accepted readiness correction is
  `f92d72909`. The signed Operation implementation, scenario, and accepted
  harness correction are `b0524bb5b`, `3e567a494`, and `eb1dd2fdc`. The signed
  inferred-Operation physical harness correction is `4695d092c`.
  Earlier
  semantic engine checkpoints remain `a84061840`, `354422d88`, `651b173c6`,
  and `47bc08eca`; the detailed ledger preserves the preceding native,
  restoration, presentation, and sibling commits.
- Documentation-refactor baseline: `5fc2099e9`
  (`Document repeated semantic route validation`).
- Frozen archive commit: `e51a83b15`.
- Latest validation: accepted explicit and capability paths each pass 42/42 with
  eight backend views, 26 actions, 26 Resources, no automatic duplicate, and
  zero errors/crashes. Accepted opaque fallback passes 5/5 and backend intake
  confirms its Detail ownership. Three additional 43/43 runs and backend
  sessions close explicit precedence, stable reconstruction, and adversarial
  source replacement. The real-reader synchronous bounce additionally passes
  17/17 locally and in backend intake without changing Detail ownership. The
  EXP-149's lifetime matrix passes 20/20. The current native probe passes
  164/164 and the affected SwiftUI test file passes 193/193. The focused
  Observation/adapter matrix passes 8/8. Exact Xcode 27 iOS Release and visionOS
  package builds succeed. Repository SwiftLint passes across 713 source and 699
  test files with zero violations. API
  verification reports only the intentionally unaccepted experimental Swift
  navigation and scene-targeted manual-view prototypes; reference baselines were
  not updated. The frozen EXP-153 runtime passes 42/42 plus its registration
  assertion; backend intake contains eight views, 13 actions, 13 Resources, one
  long task, one session, one vital, and no error or crash bucket. The EXP-154
  run then passes 25/25; backend intake contains seven views, six
  actions, six Resources, five long tasks, one session, one vital, and no error
  or crash bucket. EXP-155 adds a 3/3 focused pass, a 163/163 complete probe,
  clean lint, and a 24/24 runtime/backend pass with two scene-local Home views,
  eight raw steps, four correctly reduced Operations, and no error or crash.
  EXP-158 adds a 9/9 runtime/backend pass, an 8/8 Objective-C smoke pass, a
  successful Release simulator build, and a clean complete DatadogRUM run:
  1,255 test cases, 1,291 expanded device/configuration invocations, and zero
  failures.

Status describes the contract proved, not whether a diagnostic successfully found
a defect. Compound status preserves mixed evidence. `PREPARED` means the
driver/oracle exists but runtime acceptance is pending. `PLANNED` means the
contract is defined but implementation and driver/oracle are not yet complete.

## Current checkpoint and next experiment

`EXP-146` has accepted the shared engine, arbitrary host, explicit adapter source,
optional capability, opaque automatic fallback, runtime precedence, stable
reconstruction, adversarial capability replacement, deterministic reader bounce,
and focused disconnect fencing. Final two-window host removal is hardware-gated
after two identical simulator-system crashes before the discriminator. `EXP-147`
now accepts the realistic existing-router migration shape after source audit,
route and presentation growth, 154/154 tests, and final frozen-source backend
validation. `EXP-148` moves the generic policy into the SDK-owned iOS 27
prototype, corrects equal-route identity and pending-source authority/precedence,
passes 9/9 focused tests and 153/153 probe tests, and repeats the final 38/38
oracle against frozen SDK plus probe sources. `EXP-149` closes the deterministic
observed-source lifetime and scene matrix at 20/20: the actual SwiftUI host keeps
one subscription through reconstruction and publisher replacement, two observed
sources stay scene-local, exact disconnect releases only the disconnected source,
and an unrelated automatic subtree stays eligible. `EXP-150` then rejects the
first value-only parity candidate: a destination read during host reconstruction
cannot establish a fresh reveal before synchronous post-dismiss work. `EXP-151`
supplies the earlier signal for existing iOS 27 `@Observable` routers. Its
one-shot `.didSet` adapter rearms before the setter returns and the frozen runtime
plus backend session close the same 38-expectation oracle. Sequential/nested
mutation, reconstruction, teardown, independent-property, and background-misuse
tests are closed. `EXP-152` then proves the actual native sheet and cover
`onDismiss` callbacks run after the accepted Home mutation and use those fresh
occurrences, without creating another Home. `EXP-153` closes callback-driven
third-party parity through one custom-container boundary and the existing
publisher host, with a 42/42 local/backend run and one stable registration.
`EXP-154` closes serial two-native-scene Observation parity at 25/25 and exact
backend ownership after one deterministic duplicated-readiness harness failure.
`EXP-155` then accepts the bounded Operation `.current(in:)` engine proof at
24/24 with exact raw and reduced backend ownership after three invalid harness
attempts. `EXP-156` closes the physical tooling preflight after two disconnected
attempts, one expected unsigned-install rejection, correction of a sandbox-only
zero-identity result, and a successful verified install and launch. `EXP-157`
then records the first `EXP-131` runtime as harness-inconclusive before scene B
or any Operation call. Its corrected run passes 24/24 across two native scenes,
and backend intake proves eight raw steps plus four exact reduced Operations.
This accepts inferred cross-scene Operation attribution while retaining a human
follow-up for simultaneous on-screen visibility. `EXP-158` then generalizes the
experimental target and accepts one-shot explicit action routing: explicit A/B
actions own their requested scene, while an unchanged source-less action still
uses representative B. The 2026-09-17 current-source routing audit now defines
EXP-159 for explicit long-running action start/stop before implementation.
Proceed with that bounded simulator-capable slice while the physical iPad is
unavailable. Resume `EXP-129` and the
unchanged physical queue when hardware returns, then prepare the navigation,
Operation, and shared target shapes for API review. Interactive
dismissal/cancellation and genuine OS disconnect remain hardware rows. The
ordered acceptance contract is in
[PLAN.md](PLAN.md).

## Complete experiment ledger

| ID | Date | Status | Area | Question/result | Detailed record |
| --- | --- | --- | --- | --- | --- |
| EXP-001 | 2026-09-11 | FAIL + INCONCLUSIVE · backend | Core views | Single-window harness, payload markers, and backend queries work. Three second-window attempts ended in simulator-wide `backboardd` respawns; the second captured baseline scene B replacing still-visible A first. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `a9fab1c4-5cb6-4468-9d1a-dc0936116c46` |
| EXP-002 | 2026-09-11 | PASS · backend | Cross-surface | First fixed two-window proof: A and B views coexist; B navigation does not stop A; delayed resource/span/operation retain the intended B lifecycle. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `574be7dd-4482-48e5-b4cc-eaaa332179bd` |
| EXP-003 | 2026-09-11 | PASS · backend | Actions | Manual B action emits once instead of fanning into A; mixed UIKit/SwiftUI navigation remains scene-isolated. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `4d7dc23b-721d-4038-8c89-3b29a1c373c9` |
| EXP-004 | 2026-09-11 | PASS · backend | Cross-surface | Concurrent UIKit and SwiftUI views coexist; Session Replay uploads are accepted with no SDK crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `6a0b61d0-85a8-4915-b02e-63ab53fa13db` |
| EXP-005 | 2026-09-11 | PASS + INCONCLUSIVE · backend | SwiftUI navigation | Physical SwiftUI navigation action and destination are correct in one scene; opening B reproduces the simulator compositor crash, not an SDK crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `e7bf0f3e-2e46-4487-af4f-072cd7ba8ab8` |
| EXP-006 | 2026-09-11 | PASS · backend | Resources/Traces | Actual URLSession boundary: synchronous UIKit work and task resume can retain B; scene connection and `viewDidAppear` loading can fall to representative A. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` |
| EXP-007 | 2026-09-11 | PASS + FAIL · backend | Cross-surface | Structured requests retained B and correctly kept/dropped their action at 20/200 ms. The same run exposed the pre-fix explicit-session-stop loss of still-visible scene A. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `8a71b04b-ee69-4670-bdb1-28a6a3625662` |
| EXP-008 | 2026-09-11 | PASS · backend | Lifecycle/restoration | Explicit session stop restores both active scene branches; delayed B work remains on B after navigation. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `e03e31d3-eb19-4955-9782-1b583f37b28f` |
| EXP-009 | 2026-09-11 | PASS · backend | Resources/Traces | Three-minute causality proof: structured `Task` retains B; detached task, GCD, and timer use representative A. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `70ccd6cf-1514-4387-86ef-25cc255744c4` |
| EXP-010 | 2026-09-11 | FAIL · backend | SwiftUI navigation | SwiftUI `.onAppear` requests precede the tracked view and land on the preceding view; delayed task work is correct. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `5ebc59df-6fc1-4620-bcb2-1177d9ab3409` |
| EXP-011 | 2026-09-11 | FAIL · backend | SwiftUI navigation | `UIView.willMove(toWindow:)` remains too late for `.onAppear` and immediate `.task`; pre-correction navigation emitted a 0.79 ms duplicate Home. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `fd44bcd2-cde3-4488-a9f4-7756683d85f4` |
| EXP-012 | 2026-09-11 | FAIL · backend | SwiftUI navigation | Child-controller bridge also remains too late. It avoided synthetic/duplicate views in this run and stayed crash-free, but offered no ordering benefit and was removed. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `16e48aa6-6826-49ea-b764-6c0af6f16c0b` |
| EXP-013 | 2026-09-12 | PASS · backend | SwiftUI navigation | Scene custom trait reached SwiftUI before the hidden reader and all six Home/Detail lifecycle resources resolved to the correct view, but outer callbacks still preceded the RUM view by 35/34 ms on Home and 2/1 ms on Detail. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `68786559-42b4-4087-8e34-997e77d081c5` |
| EXP-014 | 2026-09-12 | PASS · backend | SwiftUI navigation | Adding `onChange(initial:)` reduced the callback-to-view gap to 2-3 ms for both Home and Detail. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `92326a81-441e-48b9-97b3-3db2b00bc3ab` |
| EXP-015 | 2026-09-12 | PASS · backend | SwiftUI navigation | Four synchronous custom RUM actions invoked in customer outer `.onAppear`/immediate `.task` before the view payload were all processed on the intended new Home/Detail view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `c77883d4-80fe-4730-a3ff-575221a3c262` |
| EXP-016 | 2026-09-12 | PASS · backend | Cross-surface | SwiftUI scene B navigation and delayed operation/resource work remained on B while scene C opened. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `91864fb5-cace-4f29-a348-5769bf2ffa65` |
| EXP-017 | 2026-09-12 | PASS after INVALID · backend | UIKit navigation | UIKit modal presentation/dismissal and duplicate-name A/B views remained independent. The first delayed-work switch attempt was invalidated by a stale scrolled control, which led to fixed toolbar controls in both probe UIs. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `31d0a951-095a-4a71-8c48-b6e4fb4d0af2` |
| EXP-018 | 2026-09-12 | PASS · backend | Resources/Traces | Using the fixed toolbar switch, a UIKit B trace and operation kept B Home ownership while A became active. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `76599137-09c8-4fb1-b54a-92b3c9ff04d1` |
| EXP-019 | 2026-09-12 | PASS + FAIL · backend | Cross-surface | Broad UIKit/SwiftUI teardown matrix: 18 views, 17 actions, 33 resources, 4 long tasks, zero errors/crashes, and replay available. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `972c83f7-9c13-4ea3-b5b6-d43857bb7815` |
| EXP-020 | 2026-09-12 | PASS · backend | Operations | Post-fix teardown proof. Operation key `206E691E-33AC-4BF1-8D26-E48D81315D9A` started in scene D, D closed one second later, and intake retained both raw steps on D Home view `547eb0b9-5743-47f7-ab07-c309e5b5bb29`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `c8d2aa31-127a-4d4c-a910-8e56eea5fb48` |
| EXP-021 | 2026-09-12 | FAIL · backend | SwiftUI navigation | First concurrent automatic-SwiftUI run using `DefaultSwiftUIRUMViewsPredicate`. Scene-A and scene-B taps and reactivation stayed isolated, but Home and Detail lifecycle resources landed on the preceding view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `76f40f1f-554f-4842-86a1-7bf4955b734c` |
| EXP-022 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Target-runtime automatic Home -> Detail reproduction without opening a second window. Home `.onAppear` and immediate `.task` remained on UIKit Home; Detail's three lifecycle resources and tap remained on its source navigation host. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `5c807364-100d-44b1-8d35-9d5cfd802fc5` |
| EXP-023 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Rejected `viewIsAppearing` experiment. Home `.onAppear` and immediate `.task` remained on UIKit Home; all three Detail lifecycle resources remained on the source navigation host; transient roots remained. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `13e39eae-ccc8-47a6-8125-3f52fab589b8` |
| EXP-024 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Rejected pre-base-`viewWillAppear` candidate. Home `.onAppear` and immediate `.task` used `ApplicationLaunch`; its delayed task and all three Detail lifecycle resources reused Home navigation-host view `7f2ca0fc-31fe-4902-bafb-7a7029b2758c`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `b4bbfa9a-3094-4345-b64e-bb1728bec061` |
| EXP-025 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Rejected post-base-`viewWillAppear` ordering. Home lifecycle work remained on `ApplicationLaunch`; its delayed task and all three Detail resources reused Home host `445ec932-6eb3-49bf-a25b-aff6bacbc29a`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `20462f01-45d6-4838-9102-151467c4c47f` |
| EXP-026 | 2026-09-12 | PASS · backend | SwiftUI navigation | Same-binary manual-mode control after adding the switch. Explicit tracking emitted `SwiftUI scene-A Home` before completion of its three lifecycle requests; all three backend resources use that view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `0b5749cf-e4fd-4bd5-a3e8-4789d3ee6d97` |
| EXP-027 | 2026-09-12 | FAIL · backend | SwiftUI navigation | First standalone native SwiftUI single-window control. Home `.onAppear` and immediate `.task` actions/resources used `ApplicationLaunch` `9514e96c-4cf8-4efb-a55e-35c58ba4b61e`; delayed Home plus all three Detail phases used navigation host `2810e9e8-9676-4b6b-8838-c8efb78b00ad`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `native-single-20260912171659` |
| EXP-028 | 2026-09-12 | FAIL · backend | SwiftUI navigation | First native `WindowGroup` plus `openWindow` proof. Scene A and B received distinct native sessions, but B Home `.onAppear` and immediate `.task` actions/resources used scene A Detail view `b33cbe9a-4613-4327-9e2f-a6ceadba5896`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `native-swiftui-20260912171529` |
| EXP-029 | 2026-09-12 | FAIL · source | SwiftUI navigation | Local LLDB timing/reflection inspection. Root base `viewWillAppear` had no title or children, then Home `.onAppear` ran before the navigation-controller/host callbacks. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `lldb-native-lifecycle-20260912` |
| EXP-030 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Existing explicit `.trackRUMView` control with the modifier inside each screen. Home lifecycle markers ultimately resolved correctly, but Detail `.onAppear` and immediate `.task` actions/resources used Home `4fed08f3-610f-4b6c-bea1-aff019e2e2b4`; only delayed Detail work used Detail `868d14a5-16a6-4425-84c5-338d25677f01`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-030` |
| EXP-031 | 2026-09-12 | FAIL · backend | SwiftUI navigation | Moving unchanged `.trackRUMView` outside the fully constructed screen did not establish earlier semantics. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-031` |
| EXP-032 | 2026-09-12 | PASS · backend | SwiftUI navigation | First explicit early-mount candidate. The inherited scene trait triggered the `.trackRUMView` start while the hidden platform reader was created. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-032` |
| EXP-033 | 2026-09-12 | PASS · backend | SwiftUI navigation | Three clean two-window early-mount runs. Across 72 lifecycle markers, every A/B Home/Detail on-appear, immediate-task, and delayed-task action/resource mapped once to its exact semantic view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-033` |
| EXP-034 | 2026-09-12 | PASS · backend | SwiftUI navigation | A registered but never navigated-to Detail destination produced no Detail platform lifecycle, RUM view, action, or resource. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-034` |
| EXP-035 | 2026-09-12 | PASS · backend | SwiftUI navigation | Three complete push/pop cycles produced the correct seven-occurrence RUM path: Home, Detail, Home, Detail, Home, Detail, Home, each with a distinct view UUID and strict stop-before-start ordering. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-035` |
| EXP-036 | 2026-09-12 | PASS · backend; bounded | SwiftUI navigation | An explicitly tracked but unselected tab produced neither a platform-content `onAppear` log nor a `ProbeOffscreenTabView` RUM view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-036` |
| EXP-037 | 2026-09-12 | FAIL · backend | SwiftUI navigation | A cancelled 50-point interactive back swipe emitted a false roughly half-second Home occurrence and restarted Detail although Detail stayed visible. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-037` |
| EXP-038 | 2026-09-12 | PASS · backend | SwiftUI navigation | Two clean repetitions completed the three-run bar for the final iOS-27-gated candidate. Each backend session had exactly five views, 12 lifecycle actions, and 12 lifecycle resources; every A/B Home/Detail phase mapped once to its exact UUID, with zero fallback or duplicate semantic view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-038` |
| EXP-039 | 2026-09-12 | INCONCLUSIVE · backend | SwiftUI navigation | Inconclusive construction-only stress. `ViewThatFits` rejected an oversized tracked candidate without constructing its platform reader or invoking its appearance callbacks, so it could not test construction without semantic appearance. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-039` |
| EXP-040 | 2026-09-12 | PASS · backend | Presentations | Explicit early-mount modal pass. Client and backend emitted the exact completed path `Home₁ → Sheet → Home₂`, with distinct UUIDs `0ec34c52…`, `7c8e644b…`, and `45b791dd…` despite retained Home state. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-040` |
| EXP-041 | 2026-09-13 | PASS + INCONCLUSIVE · backend | Lifecycle/restoration | Mixed immediate scene-close result. B Home started and stopped once; all six B lifecycle action/resource markers, including delayed completions after `dismissWindow`, retained B UUID `fbf4b50b…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-041` |
| EXP-042 | 2026-09-13 | PASS + INCONCLUSIVE · backend | Lifecycle/restoration | Partial restoration pass with platform-limited topology. Before intentional termination, A/B Home views and all markers were isolated. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-042` |
| EXP-043 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Public-UIKit cancellation diagnostic. At the speculative Home `onAppear`, the retained hidden reader resolved `NavigationStackHostingController<AnyView>` and a coordinator with `initiallyInteractive=true`; cancellation was not known until coordinator completion. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-043` |
| EXP-044 | 2026-09-13 | PASS · backend | SwiftUI navigation | Explicit cancellation-gate pass. A short edge swipe invoked speculative Home callbacks but emitted no Home occurrence or replacement Detail; the UI and RUM branch remained on Detail `0b3bebb8…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-044` |
| EXP-045 | 2026-09-13 | PASS · tests | SwiftUI navigation | Post-run review found that a recreated view could mount before its reader had responder ancestry, and that one scene-wide pending bucket could swallow unrelated lifecycle. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-045` |
| EXP-046 | 2026-09-13 | PASS after INVALID · backend | SwiftUI navigation | Probe-only scene-root/path prototype pass. One authoritative typed path recreated a hidden semantic tracker at each mutation. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-046` |
| EXP-047 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Rejected root-background placement. A's Home/Detail and both final Detail views were correct, but B Home `.onAppear` and immediate work used A Detail before B's hidden sibling tracker existed; only B's delayed work used B Home. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-047` |
| EXP-048 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Rejected whole-stack wrapper. B's first Home work still used A Detail, and changing the wrapper identity rebuilt the `NavigationStack`, replaying retained Home lifecycle work after each Detail start. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-048` |
| EXP-049 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Rejected stable first-child placement. It removed the whole-stack lifecycle replay and preserved one view per mutation, but B Home `.onAppear` and immediate work still used A Detail. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-049` |
| EXP-050 | 2026-09-13 | PASS · backend | SwiftUI navigation | Route-owned boundary pass. Existing explicit tracking was applied directly to each Home and typed Detail builder while the bound path recorded mutations. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-050` |
| EXP-051 | 2026-09-13 | PASS · backend | SwiftUI navigation | Route-owned occurrence/cancellation pass. The cancelled edge drag produced no path commit or RUM transition. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-051` |
| EXP-052 | 2026-09-13 | PASS · backend | SwiftUI navigation | Same-turn programmatic push/revert pass. The probe wrote `[.detail]` and then `[]`; SwiftUI exposed both binding mutations but no Detail lifecycle or RUM view, and no second Home occurrence. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-052` |
| EXP-053 | 2026-09-13 | INVALID · harness | SwiftUI navigation | Invalid harness run, retained only to prevent a false SDK conclusion. Navigation-path mode accidentally excluded the new Alternate screen from explicit tracking. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-053` |
| EXP-054 | 2026-09-13 | PASS · backend | SwiftUI navigation | Corrected materialized replacement pass. After one second on Detail, replacing `[.detail]` with `[.alternate]` produced exactly `ApplicationLaunch → Home → Detail → Alternate`, with no intermediate/restarted Home or duplicate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-054` |
| EXP-055 | 2026-09-13 | FAIL · source | SwiftUI navigation | `UIHostingSceneDelegate` is public from iOS 26 and lets an application-owned `UISceneDelegate` declare a static SwiftUI `rootScene` and receive scene lifecycle for scenes activated through its configuration/request. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-055` |
| EXP-056 | 2026-09-13 | PASS · backend | SwiftUI navigation | Concurrent materialized replacement passed for view creation: backend contains exactly `ApplicationLaunch` plus A/B `Home → Detail → Alternate`, one UUID per occurrence, with no restarted Home, replay, warning, error, or crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-056` |
| EXP-057 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Reproduced semantic occurrence failure. Replacing `[.detail(1)]` with `[.detail(2)]` committed visible Detail 2 while reusing the same destination reader. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-057` |
| EXP-058 | 2026-09-13 | PASS · backend | SwiftUI navigation | Probe-only route-identity control passed. Applying `.id(route)` around the tracked destination made `[.detail(1)] → [.detail(2)]` emit exactly launch, Home, Detail₁, Detail₂, with two distinct same-named `ProbeDetailView` UUIDs, no intermediate Home, and all nine action/resource pairs on their exact occurrence. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-058` |
| EXP-059 | 2026-09-13 | PASS · backend | SwiftUI navigation | Two-window route-identity control passed for view creation. Backend contains exactly launch plus A/B `Home → Detail₁ → Detail₂`, with distinct same-named Detail UUIDs in each scene and no intermediate Home, replay, warning, error, or crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-059` |
| EXP-060 | 2026-09-13 | PASS · tests | SwiftUI navigation | Added an internal scene-local stack-slot replacement primitive for SwiftUI occurrence rollover. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-060` |
| EXP-061 | 2026-09-13 | PASS · tests | Core views | Fixed retained-scope contamination when a navigation path returns to the same platform identity. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-061` |
| EXP-062 | 2026-09-13 | PASS · tests | SwiftUI navigation | Added dormant internal route-occurrence propagation without changing the public API or current runtime path. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-062` |
| EXP-063 | 2026-09-13 | PASS · tests | Lifecycle/restoration | Closed state/handler divergence after scene teardown. The handler already stops and removes the disconnected scene's stack; the arbiter now silently invalidates only matching SwiftUI state, fences stale callbacks until an explicit platform remount, and retains keyed generation history so generation N cannot recreate a deleted entry. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-063` |
| EXP-064 | 2026-09-13 | FAIL · source | Lifecycle/restoration | Added retained-reader update re-registration and an explicit reader-mount path after silent scene teardown. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-064` |
| EXP-065 | 2026-09-13 | PASS · tests | Lifecycle/restoration | Hardened disconnect/reconnect and observer isolation after the `EXP-064` review. Ordinary unchanged updates are deduplicated; stale initial-trait input cannot resurrect disconnected state; inactive reconnect waits for semantic appearance; cancelled remount and reader-mount/disappear races rearm correctly; source-A disconnect preserves a pending migration to B; and detached or re-registered A observers cannot bypass B's coordinator gate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-065` |
| EXP-066 | 2026-09-13 | PASS · backend | Lifecycle/restoration | Probe-only retained-reader fault-injection pass. While scene B remained foreground-active and present in `connectedScenes`, the probe posted `UIScene.didDisconnectNotification`, then updated the same retained representable witness (`0x0000000113c51880`, generation 0→1). | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-066` |
| EXP-067 | 2026-09-13 | FAIL · source | Cross-surface | Split/adaptive navigation has no semantic model beyond one callback-ordered stack per scene. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-067` |
| EXP-068 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Regular-width route-owned `NavigationSplitView` reproduced the navigation-occurrence failure. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-068` |
| EXP-069 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Regular-width automatic `NavigationSplitView` failed semantic creation and attribution. It emitted launch, a setup-only fallback, a transient host, and one final hosting-controller view—no Detail(1), Detail(2), or Placeholder view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-069` |
| EXP-070 | 2026-09-13 | PASS · backend | SwiftUI navigation | Probe-only `.id(selection)` control passed in regular-width `NavigationSplitView`: launch → Detail₁ → Detail₂ → Placeholder used four distinct UUIDs, no Sidebar/Home interval, and all three immediate action/resource pairs used their matching occurrence. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-070` |
| EXP-071 | 2026-09-13 | FAIL · backend | UIKit navigation | Isolated stock `UISplitViewController` tracking reproduced a manufactured occurrence. The platform kept the same visible Primary controller and sent it no second appearance callback, but replacing Secondary₁ with a fresh same-class Secondary₂ emitted launch → Primary₁ → Secondary₁ → Primary₂ → Secondary₂. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-071` |
| EXP-072 | 2026-09-13 | FAIL · backend | UIKit navigation | Application-subclassed `UISplitViewController` reproduced two independent false occurrences. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-072` |
| EXP-073 | 2026-09-13 | FAIL · backend | UIKit navigation | A stable secondary `UINavigationController` proves the defect also affects ordinary push/pop within a split column. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-073` |
| EXP-074 | 2026-09-13 | PASS · backend | UIKit navigation | The iOS 27 multi-scene UIKit split-column handoff candidate fixes the stock root-replacement failure. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-074` |
| EXP-075 | 2026-09-13 | PASS · backend | UIKit navigation | The same candidate fixes nested secondary push/pop. The backend path is exactly launch → Primary → Secondary₁(first) → Secondary₂ → Secondary₁(returned), with no Primary interval. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-075` |
| EXP-076 | 2026-09-13 | SKIPPED · capability | SwiftUI navigation | Blocked before uninstall or launch, so this makes no runtime claim. The route-owned split probe hardcodes Detail₁ and automatically advances to Detail₂/Placeholder; no environment input reaches its existing nil branch. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-076` |
| EXP-077 | 2026-09-13 | PASS · tests | UIKit navigation | Post-run review found that a scene-only pending lookup let an unrelated UIKit appearance expose a sibling interval, and that app/scene background flushed removal while active before suspension. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-077` |
| EXP-078 | 2026-09-13 | PASS · backend; superseded | UIKit navigation | Stock root replacement passed with the exact four-view chain and marker ownership, but the source/build timestamp raced a later no-op conditional cleanup. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-078` |
| EXP-079 | 2026-09-13 | PASS · backend | UIKit navigation | Authoritative nested push/pop rerun on the hardened candidate passed. The exact backend chain is launch → Primary → Secondary₁(first) → Secondary₂ → Secondary₁(returned), with no Primary interval. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-079` |
| EXP-080 | 2026-09-13 | PASS · backend | UIKit navigation | Final post-rebuild stock root-replacement control passed on the exact current tree. The backend chain is launch → Primary → Secondary₁ → Secondary₂, with no restarted Primary. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-080` |
| EXP-081 | 2026-09-13 | INCONCLUSIVE · simulator | UIKit navigation | Tooling/harness discrimination only. Detached install-and-run could pass environment but had no LLDB process; RunProject could debug but not pass environment. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-081` |
| EXP-082 | 2026-09-13 | PASS · backend | UIKit navigation | A real long edge swipe committed the nested pop. The exact backend path is launch → Primary → Secondary₁(first) → Secondary₂ → fresh returned Secondary₁, with no false Primary. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-082` |
| EXP-083 | 2026-09-13 | PASS · backend | UIKit navigation | A real `UIPercentDrivenInteractiveTransition` advanced a nested pop to 35 percent and cancelled it. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-083` |
| EXP-084 | 2026-09-13 | PASS · backend | UIKit navigation | The same 35-percent public-UIKit transition finished instead. RUM emitted launch → Primary → S1(first) → S2 → fresh S1(returned), with no Primary interval. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-084` |
| EXP-085 | 2026-09-13 | FAIL · source | SwiftUI navigation | No supported transparent SwiftUI navigation hook exposes both committed route identity and an early semantic destination boundary. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-085` |
| EXP-086 | 2026-09-13 | PASS + INCONCLUSIVE · backend | UIKit navigation | Two scene-owned split sequences overlapped: B's S2 push began 0.714 ms after A's pop started. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-086` |
| EXP-087 | 2026-09-13 | PASS + SKIPPED · backend/capability | SwiftUI navigation | The new initial-nil/sequence-disable split control passed its empty-detail baseline: the UI showed only Selections and backend intake contained no Detail occurrence, error, or crash. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-087` |
| EXP-088 | 2026-09-13 | PASS · tests | Actions | Public manual `addAction`/`startAction`/`stopAction` and all three `startResource` overloads now prefer the exact RUM view in a trustworthy execution-local handoff, then its scene, then the unchanged process representative. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-088` |
| EXP-089 | 2026-09-13 | INCONCLUSIVE · backend | Actions | First physical filtered-control run on the `EXP-088` implementation. The predicate rejected the probe button and emitted no automatic tap. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-089` |
| EXP-090 | 2026-09-13 | PASS · backend | SwiftUI navigation | The debug-only keyed binding created distinct Detail1 `1c759…` and Detail2 `c4f1…` RUM UUIDs while preserving one customer state token `e1c37b44…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-090` |
| EXP-091 | 2026-09-13 | PASS · backend | SwiftUI navigation | A same-turn Home → Detail → Home path write coalesced before Detail materialized. Intake contained only launch and the original Home: no Detail and no restarted Home. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-091` |
| EXP-092 | 2026-09-13 | FAIL · backend | SwiftUI navigation | The first run proved that retained Home eventually receives a fresh UUID after Detail while keeping its customer state token. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-092` |
| EXP-093 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Applying `.id` only to the hidden reader did not move returned Home creation before its outer lifecycle marker. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-093` |
| EXP-094 | 2026-09-13 | PASS · mapper | SwiftUI navigation | The path setter ran at 11:59:46.714891, Home's appearance marker at 11:59:46.719548, and the fresh Home payload at 11:59:46.731364. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-094` |
| EXP-095 | 2026-09-13 | FAIL · backend | SwiftUI navigation | First weak per-window retained-route source attempt failed. The source delivered `false`; Home2 was created later and the appearance action/resource remained on Detail. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-095` |
| EXP-096 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Rebinding the registration from both reader reconciliation callbacks still delivered `false`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-096` |
| EXP-097 | 2026-09-13 | PASS · mapper | SwiftUI navigation | Temporary debug-only eligibility labels found two live registrations: Detail rejected the Home key, while retained Home matched but had no current scene. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-097` |
| EXP-098 | 2026-09-13 | PASS · backend | SwiftUI navigation | Retaining the last concrete scene across ordinary hidden-reader detachment passed. The exact backend path was Home `96aad43e…` → Detail `06a622ff…` → fresh returned Home `8ad9240d…`; Home reused state token `749f53ae…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-098` |
| EXP-099 | 2026-09-13 | PASS · backend | SwiftUI navigation | After routing source delivery through the interactive-transition arbiter, a normal Back-button pop retained the pass: Home `24453c4e…` → Detail `8de298b6…` → fresh Home `e20f3c08…`, with the same Home state token and both immediate marker events on Home2. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-099` |
| EXP-100 | 2026-09-13 | INCONCLUSIVE · simulator | SwiftUI navigation | Both single, bounded edge drags were ignored by the simulator: Detail remained active and no path, coordinator, source, or lifecycle signal followed either gesture. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-100` |
| EXP-101 | 2026-09-13 | PASS · tests | Cross-surface | Commits `fb6b3bde7` through `251f6b8bc` close exact-view representative updates, Resource completion ownership, manual error/view/mutation routing, internal view-command handoff, and native/OpenTelemetry span-start parity. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-101` |
| EXP-102 | 2026-09-13 | PASS · backend | SwiftUI navigation | Regular-width single-scene split occurrence pass without customer `.id`. One retained Detail witness moved from Detail 1 to Detail 2 while the keyed generation advanced 1 → 2 → 3. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-102` |
| EXP-103 | 2026-09-13 | PASS + INCONCLUSIVE · backend | SwiftUI navigation | Both native scenes reached regular width and independently retained their Detail witness while advancing generation 1 → 2 → 3. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-103` |
| EXP-104 | 2026-09-13 | FAIL · backend | SwiftUI navigation | Retained split-return failure baseline. Detail₁ `2be7a2d9…` → Detail₂ `532c2db1…` → Placeholder `6334cd0c…` was correct. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-104` |
| EXP-105 | 2026-09-13 | PASS · backend | SwiftUI navigation | Fixed retained split return. The source-created returned Detail₂ UUID `761fe74b…` remained active while SwiftUI replaced the platform reader, and the replacement state adopted that identity without another start. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-105` |
| EXP-106 | 2026-09-13 | PASS · mapper | Tooling | Named-scenario harness startup proof. The valid `regression.single-scene` launch emitted its complete resolved manifest as the first structured record, then initialized Datadog and produced the expected Home/Detail payload. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-106` |
| EXP-107 | 2026-09-13 | PASS + INCONCLUSIVE · mapper | Tooling | Structured-recorder/oracle phase. Versioned JSONL keeps probe source separate from mapper-observed RUM ownership; snapshot reduction derives first-observed starts and active-to-inactive stops. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-107` |
| EXP-108 | 2026-09-13 | PASS + INCONCLUSIVE · mapper | Tooling | Exact probe scene-registry phase. Seven new tests cover logical/native identity, alias rejection, disconnect/reconnect generations, stale-handle rejection, weak windows, scene-local route/presentation/future-context state, and peer isolation; the full probe plan passes 31/31. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-108` |
| EXP-109 | 2026-09-13 | PASS · backend | SwiftUI navigation | Signal-driven Home → Detail → Home acceptance. After a clean uninstall, all three runs produced exactly one local `PASS` with 7/7 expectations and six acknowledged steps. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-109` |
| EXP-110 | 2026-09-13 | PASS · backend | SwiftUI navigation | Signal-driven stack abort and replacement acceptance. The first clean trio proved the driver and view chains, then the oracle was strengthened to require a decisive action and Resource on the final view. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-110` |
| EXP-111 | 2026-09-13 | PASS + FAIL · backend | SwiftUI navigation | Signal-driven split acceptance and automatic failure baseline. The corrected route-owned runs pass 10/10 and 13/13: Detail₁ → Detail₂ → Placeholder and Detail₁ → Detail₂₁ → Placeholder → fresh Detail₂₂ each have one distinct UUID plus an exact action/Resource pair. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-111` |
| EXP-112 | 2026-09-13 | PASS · backend | UIKit navigation | Signal-driven UIKit cancellation/completion acceptance plus a shipping structural-view fix. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-112` |
| EXP-113 | 2026-09-13 | PASS + INCONCLUSIVE · backend | Lifecycle/restoration | Exact scene-lifecycle driver acceptance. `open-window` dispatches through exact source A and waits for exact target B readiness; `close-window` dispatches through exact B and waits for B disconnect. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-113` |
| EXP-114 | 2026-09-13 | INCONCLUSIVE · simulator | Lifecycle/restoration | Exact activation-harness boundary. The first scenario version acknowledged ten exact-scene commands, but its source-labelled markers were plain public RUM calls with no SDK provenance. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-114` |
| EXP-115 | 2026-09-13 | PASS · backend | SwiftUI navigation | Target-scoped SwiftUI authority pass. Navigation-occurrence mode enabled `DefaultSwiftUIRUMViewsPredicate` at the same time as explicit route-owned tracking. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-115` |
| EXP-116 | 2026-09-13 | PASS · backend | SwiftUI navigation | Once-per-container SwiftUI integration-shape pass. A probe-only wrapper consumes one bound `NavigationStack` path and centralized route-to-RUM resolver, owns root/destination materialization, and injects the existing route-owned tracking boundary without putting metadata into Home/Detail view types. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-116` |
| EXP-117 | 2026-09-13 | INVALID · harness | Tooling | Clean-run isolation failure in the harness workflow, not an SDK-semantic failure. Both back-to-back Xcode launches passed their local oracle, but the test bundle had not been uninstalled. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-117` |
| EXP-118 | 2026-09-13 | INCONCLUSIVE · simulator | SwiftUI navigation | Prepared automatic/semantic scene-coexistence discriminator; simulator-inconclusive after two explicitly uninstalled runs because `backboardd` aborted in Metal/CoreAnimation before the terminal oracle. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-118` |
| EXP-119 | 2026-09-13 | FAIL · backend | Presentations | Exceptional explicit SwiftUI Sheet over automatic Home. The first run exposed a probe-only source label defect, fixed in `dd1b1cf34`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-119` |
| EXP-120 | 2026-09-14 | FAIL after INVALID · backend | Manual views | Existing direct keyed manual API over automatic Home fails authoritative coexistence. Attempt A never started because the scenario was omitted from a second driver allowlist; the catalog now owns that selection. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-120` |
| EXP-121 | 2026-09-14 | FAIL · backend | Manual views | First internal scene-targeted manual-stack run after `29c8cec2c`. Compose M1 remained authoritative and owned its active action/Resource, closing the `EXP-120` preemption. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-121` |
| EXP-122 | 2026-09-14 | PASS · backend | Manual views | Clean exact-scene manual-view acceptance after `b1a0fb6b8`. The oracle passes 16/16. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-122` |
| EXP-123 | 2026-09-14 | FAIL · backend | Presentations | Exact-scene Sheet lifecycle without a UI-attached suppression boundary. The semantic Sheet M1 was authoritative, but automatic discovery still emitted structural `NavigationStackHostingController` churn and a redundant automatic `ProbeSheetView` presentation-host occurrence. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-123` |
| EXP-124 | 2026-09-14 | INVALID · oracle; semantic PASS · backend | Presentations | First suppression-only presentation-boundary run. Mapper output contains exactly launch, the startup fallback, H1, semantic Sheet M1, and fresh H2; active work owns M1 and both dismiss pairs own H2, with no automatic `ProbeSheetView`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-124` |
| EXP-125 | 2026-09-14 | PASS · backend | Presentations | Clean complete-destination Sheet acceptance after `f452e9e3f` and `fad83f58f`. The oracle passes 14/14. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-125` |
| EXP-126 | 2026-09-14 | PASS after INCONCLUSIVE · backend | Presentations | Independent complete-destination `fullScreenCover` acceptance after `c70920c94`. The first Xcode interaction session expired before capture and receives no semantic or backend claim. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-126` |
| EXP-127 | 2026-09-14 | PASS after INVALID · backend | Manual views | Sibling-container authority acceptance after `45ec5656a`. Two `NavigationStack` branches mount under one outer SwiftUI host; a required ancestry assertion proves distinct left and right controller branches. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-127` |
| EXP-128 | 2026-09-14 | PASS after INCONCLUSIVE · backend | Manual views | Nested keyed-manual authority and duplicate-start acceptance. Attempt A timed out because Compose C1's exact mapper snapshot preceded the driver's `rum-view:compose#1` wait; immutable exact-view waits now search recorded evidence before subscribing. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-128` |
| EXP-129 | 2026-09-14 | INCONCLUSIVE · simulator | Manual views | Prepared exact same-key A/B isolation with reverse-order stop. The 91-test local plan proves the scenario and adversarial oracle: A/B Compose must have distinct UUIDs, exact work cannot cross scenes, stopping B cannot preempt A, and each returned Home must be fresh. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-129` |
| EXP-130 | 2026-09-14 | PASS · backend | Operations | Operation per-step navigation and duplicate-start acceptance. An explicit uninstall plus missing-container check established a clean run. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-130` |
| EXP-131 | 2026-09-14 | PREPARED · tests; hardware required | Operations | Prepared `operations.cross-scene.lifecycle`. Its exact eight-step driver starts success/failure in A and completes them in B, then starts same-name `parallel-alpha` and `parallel-beta` instances in A and B and completes beta before alpha. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-131` |
| EXP-132 | 2026-09-14 | PASS after INCONCLUSIVE · backend | Actions | Real UIKit scroll/navigation acceptance. Earlier Xcode interaction sessions expired before a gesture and are invalid tooling attempts. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-132` |
| EXP-133 | 2026-09-14 | PASS after INCONCLUSIVE · backend | Resources/Traces | Trace-only automatic URLSession owner-freezing acceptance. Attempt A reached the trace mapper with A ownership after B became representative, but the Xcode interaction session ended before a terminal result; no crash report, fatal/assertion output, or UI crash state existed, so it is tooling-incomplete rather than an SDK-crash claim. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-133` |
| EXP-134 | 2026-09-14 | PASS · backend | Resources/Traces | Independent Trace-only reverse-completion acceptance. A/Home H1 `b0bff76c…` starts request A, B/Home H1 `6c67dece…` starts request B, then B completes first while A is representative and A completes second while B is representative. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-134` |
| EXP-135 | 2026-09-15 | FAIL · backend; approved fallback classified | Actions | Ordinary SwiftUI Button → structured-task causal-boundary result. A hierarchy-derived physical tap emits exactly one automatic `tap on SwiftUI_Button` action on A/Home H1 `308f0a66…`. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-135` |
| EXP-136 | 2026-09-15 | INCONCLUSIVE · simulator | Resources/Traces | Shared/coalesced Trace-only request discriminator. One underlying task is created on A/Home; B joins it without creating or resuming another task and then should release it. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-136` |
| EXP-137 | 2026-09-15 | PASS · backend | Manual views | First customer-shaped scene-targeted Swift SPI acceptance. The probe resolves its real `UIWindowScene` and calls `startView(key:name:in:attributes:)` / `stopView(key:in:attributes:)` rather than the internal handler protocol. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-137` |
| EXP-138 | 2026-09-15 | PASS after INVALID · backend | Manual views | Customer-shaped nested-manual acceptance and harness-isolation fix. The first run passed 29/29 locally and had the correct seven-view session, but C1/P1/C2 view documents retained the preceding launch's run ID because SwiftUI restored a `WindowGroup` value outside the deleted app container. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-138` |
| EXP-139 | 2026-09-15 | PASS · backend | Presentations | Customer-shaped scene-targeted Sheet acceptance. The 14/14 oracle and backend contain H1 `8a5f8cc8…` → one semantic Sheet `83705cb0…` → fresh H2 `4fb5c337…`, with no automatic Sheet duplicate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-139` |
| EXP-140 | 2026-09-15 | PASS · backend | Presentations | Customer-shaped scene-targeted full-screen-cover acceptance. The 14/14 oracle and backend contain H1 `43326c6e…` → one semantic Cover `1d7f7dd0…` → fresh H2 `238b6fa3…`, with no automatic cover duplicate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-140` |
| EXP-141 | 2026-09-15 | PASS · backend | SwiftUI navigation | Customer-shaped complete-destination semantic API acceptance. The 38/38 oracle and backend contain seven distinct semantic occurrences H1/D1/H2/Sheet/H3/Cover/H4 plus ApplicationLaunch, with no automatic duplicate. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-141` |
| EXP-142 | 2026-09-15 | PASS after FAIL · backend; weak-oracle PASS excluded | SwiftUI navigation | Repeated equal-route acceptance through real `NavigationLink(value:)` controls. A stronger reveal-before-callback oracle exposed returned Detail work on D2 before fresh D3. | [archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md): `EXP-142` |
| EXP-143 | 2026-09-15 | PASS after FAIL, rejected candidates, and tooling-invalid retries · backend | SwiftUI navigation | Initial repeated restoration, external same/different-type replacement, rejected proposals, and canonicalized writes preserve only accepted path occurrences. The final canonical run starts Alternate before `onAppear`/immediate work, emits no speculative Detail or automatic duplicate, and passes 19/19 plus exact backend ownership. | [active record](Experiments/EXP-143-199.md#exp-143--external-semantic-router-mutations-and-restoration) |
| EXP-144 | 2026-09-16 | PASS after SDK FAIL and harness-invalid retry · backend | SwiftUI navigation | Direct Sheet → Cover → Sheet replacement emits H1/S1/F1/S2/fresh H2 with no intermediate Home or automatic duplicate. The final run passes 43/43; backend intake has the same five semantic UUIDs, 19 exact-view actions, 19 exact-view Resources, and zero errors/crashes. | [active record](Experiments/EXP-143-199.md#exp-144--semantic-presentation-replacement) |
| EXP-145 | 2026-09-16 | PASS after two INVALID harness attempts · backend | SwiftUI navigation | The actual semantic SPI preserves the `EXP-127` sibling boundary. Home commits to Detail beneath left manual authority, emits no intermediate/automatic view, and reveals one fresh Detail afterward. Final run passes 19/19; backend intake has exactly launch/Home/manual/Detail, 11 exact actions, 11 exact Resources, and zero errors/crashes. | [active record](Experiments/EXP-143-199.md#exp-145--semantic-sibling-container-isolation) |
| EXP-146 | 2026-09-16 | ENGINE/ADAPTER PASS after SDK FAIL and INVALID attempts; final removal INCONCLUSIVE · tests + backend | SwiftUI navigation/lifecycle | A container-independent engine and deterministic adapter produce exact occurrences and backend owners. Explicit/capability paths pass 42/42; precedence/reconstruction/replacement pass 43/43; opaque fallback passes 5/5; synchronous real-reader reattach passes 17/17. Focused disconnect fencing passes. Two clean final-removal attempts hit simulator `backboardd` before host removal. This is not customer-integration approval. | [active record](Experiments/EXP-143-199.md#exp-146--container-independent-semantic-navigation-host) |
| EXP-147 | 2026-09-16 | PASS after INVALID · source audit + tests + backend | SwiftUI integration | The realistic fixture has 25 routes, seven presentations, three observable routers, native/local-state and opaque arms. Customer files and all 12 navigation methods remain RUM-free; standard SwiftUI is unchanged; adding one route and one presentation adds zero RUM code; 154/154 tests pass. Final frozen-source run `exp147-router-stream-20260916T052101Z` passes 38/38 with exact backend ownership, no automatic duplicate, and zero errors/crashes. The first 38/38 run remains INVALID because source changed during it. | [active record](Experiments/EXP-143-199.md#exp-147--customer-integration-migration-cost) |
| EXP-148 | 2026-09-16 | PASS after intermediate and pre-lint pass · tests + backend | SwiftUI integration | The route-count-independent router-stream policy now lives in the iOS 27 SDK prototype rather than the fixture: one observed accepted-state stream, automatic metadata with sparse overrides, fresh equal-route occurrences, delayed authority until the first trustworthy state, and strict explicit-source precedence. Focused tests pass 9/9, the probe passes 153/153, lint is clean, and the generic Release build succeeds. Authoritative frozen-source run `exp148-sdk-observed-postlint-20260916T063742Z` passes 38/38 in backend session `c951c32e-12a7-4bc4-bc5e-bdaf2f16f8aa`, with exact eight-view and 22-bucket ownership, no automatic duplicate, and zero errors/crashes. | [active record](Experiments/EXP-143-199.md#exp-148--sdk-owned-observable-router-adapter) |
| EXP-149 | 2026-09-16 | PASS · focused tests | SwiftUI integration/lifecycle | The actual observed host subscribes once across a SwiftUI reconstruction that supplies a different publisher; the replacement remains unsubscribed. Two SDK-owned observed adapters attach to A/B independently, posted disconnect of A releases only A and rejects later A updates while B advances. Automatic suppression remains local and an unrelated subtree stays eligible. The complete semantic/observed lifetime matrix passes 20/20. | [active record](Experiments/EXP-143-199.md#exp-149--observed-source-lifetime-and-scene-isolation) |
| EXP-150 | 2026-09-16 | FAIL · mapper + backend; tests remain green | SwiftUI integration/timing | A one-boundary `currentDestination` value preserves standard SwiftUI and passes state-level parity tests, but it observes dismissal only during the next render. Frozen iPadOS 27 run `exp150-current-destination-20260916T072321Z` fails at 17/38: immediate sheet work stays on Compose and immediate cover work stays on Attachment; fresh Home starts one signal later in both cases. Backend session `2294a609-76f9-47be-a643-ab51edc5b638` confirms both wrong action/Resource owners, while settled work is correct and the app does not crash. This API shape is not an exact customer candidate. | [active record](Experiments/EXP-143-199.md#exp-150--render-time-current-destination-boundary) |
| EXP-151 | 2026-09-16 | PASS · tests + mapper + backend | SwiftUI integration/timing | An iOS 27 one-shot Observation `.didSet` adapter observes one atomically updated accepted-destination property on an existing `@Observable` router and rearms synchronously. Focused tests pass 8/8, the affected SwiftUI file passes 193/193, the probe passes 154/154, and Xcode 27 iOS Release plus visionOS package builds succeed. Post-review frozen run `exp151-observation-router-postreview-20260916T083131Z` passes 38/38; backend session `ea9adc0e-5a00-4290-9580-fb4df6bc18e7` has eight views, 11 actions, 11 Resources, no error bucket/crash, and exact fresh-Home ownership for immediate and settled sheet/cover dismissal work. Plain local `@State` remains fallback-only and the API spelling remains experimental. | [active record](Experiments/EXP-143-199.md#exp-151--one-shot-observation-router-boundary) |
| EXP-152 | 2026-09-16 | PASS · tests + mapper + backend | SwiftUI integration/timing | Harness-only characterization over the accepted Observation adapter waits for real Sheet/Cover content appearance, then records SwiftUI's actual `onDismiss` callbacks. Frozen run `exp152-native-dismiss-callbacks-20260916T094300Z` passes 38/38; each callback fires once after accepted Home state, creates no extra Home, and its immediate/settled action and Resource pairs own fresh H3/H4. Backend session `fee27d61-1eb7-4eb6-8525-7af74a53ed7e` has eight views, 11 actions, 11 Resources, and zero errors/crashes. This closes native callback characterization without replacing the stronger synchronous mutation oracle; interactive gesture dismissal remains a physical/human row. | [active record](Experiments/EXP-143-199.md#exp-152--native-swiftui-dismissal-callback-characterization) |
| EXP-153 | 2026-09-16 | PASS · tests + mapper + backend | SwiftUI integration/third-party adapters | A true custom visual container exposes synchronous accepted snapshots to one dedicated adapter, which bridges into the existing SDK-owned publisher host. No screen or navigation method changes, retroactive conformance, or new SDK API are required. Focused tests pass 7/7, the probe passes 161/161, lint and Release pass, and frozen run `exp153-third-party-callback-20260916T103122Z` passes 42/42 plus `registrations=1 active=1`. Backend session `f2d2fb24-02d6-4bd9-9df9-ee353b899e69` has eight views, 13 actions, 13 Resources, exact H1/D1/H2/Sheet/H3/Cover/H4 ownership, and zero errors/crashes. Opaque state remains fallback-only; two-native-scene runtime parity is next. | [active record](Experiments/EXP-143-199.md#exp-153--callback-driven-third-party-navigation-adapter) |
| EXP-154 | 2026-09-16 | PASS after HARNESS FAIL · tests + mapper + backend | SwiftUI integration/multi-scene | Two real native scenes independently mount per-window Observation routers and each complete H1 → D1 → fresh H2. Attempt 1 rejected a redundant readiness wait after `open-window` had already consumed B's signal; the app and partial attribution remained healthy. Corrected frozen run `exp154-observation-two-scenes-serial-fix-20260916T111921Z` passes 25/25. Backend session `a6a5afd5-8089-4996-9805-ed62fb76927d` has seven views, six actions, six Resources, exact A/B marker ownership, and zero errors/crashes. This closes serial native-scene parity, not simultaneous visibility or lifecycle acceptance. | [active record](Experiments/EXP-143-199.md#exp-154--serial-two-native-scene-observation-parity) |
| EXP-155 | 2026-09-16 | PASS after three INVALID attempts · tests + mapper + backend | Operations/API prototype | The iOS 27 `.current(in:)` SPI keeps explicit and inferred targets separate and resolves every Operation step independently. Corrected run `exp155-operation-explicit-target-serial-manual-boundaries-20260916T124918Z` passes 24/24. Backend session `bcb168fd-b5df-42ed-b416-b505a42e6e76` has eight raw steps and four reduced Operations with exact A→B success/failure, A→A alpha, B→B beta, and beta-before-alpha completion. The API shape remains experimental. | [active record](Experiments/EXP-143-199.md#exp-155--explicit-cross-scene-operation-targeting) |
| EXP-156 | 2026-09-16 | PASS · physical-device tooling | Hardware automation | Two preflights found only a disconnected local-network record. A third passed repeated wired inventories and an `arm64` build; the expected unsigned rejection exposed signing. The restricted-context zero-identity result was false: one of two login-keychain identities matches the installed device profile. A copied app passed strict/deep verification, clean install, and physical launch. | [active record](Experiments/EXP-143-199.md#exp-156--physical-ipad-automation-preflight) |
| EXP-157 | 2026-09-16 | PASS · physical Operations + backend; INCONCLUSIVE · simultaneous visibility | Operations/hardware | First signed `EXP-131` launch exposed a stale Home fixture before any Operation. With explicit per-scene Home boundaries, the physical retry passes 24/24 across two native scenes; backend contains eight raw steps and four exact reduced Operations with A→B, A→A, B→B ownership and beta-before-alpha completion. Both scenes were full-screen and A was background while B was active, so simultaneous on-screen visibility remains human-gated. | [active record](Experiments/EXP-143-199.md#exp-157--physical-inferred-operation-retry) |
| EXP-158 | 2026-09-16 | PASS · tests + mapper + backend | Actions/API prototype | The generalized iOS 27 `RUMViewTarget.current(in:)` routes one-shot actions to a requested scene while retaining independent inferred fallback. Run `exp158-sim-66f922ee-19a3-4941-b8ca-c518216e6b0d` passes 9/9: explicit A and B own their requested Home, while a source-A legacy action remains on representative B. Backend session `f67c75b2-e839-4701-a283-7e4355682b6a` confirms the same owners across 30 events. The probe passes 164/164, Objective-C smoke passes 8/8, and the full RUM suite has zero failures. Stable API and long-running actions remain open. | [active record](Experiments/EXP-143-199.md#exp-158--explicit-scene-targeted-one-shot-action) |
| EXP-159 | 2026-09-17 | PASS · tests + mapper + backend | Actions/API prototype | Targeted long-running action start/stop passes 15/15 in a bounded live-view batch, with exact backend owners, reverse completion, empty-slot isolation, and unchanged legacy fallback. The earlier background-interrupted attempt remains INCONCLUSIVE; sustained simultaneous-window use remains hardware-gated. | [active record](Experiments/EXP-143-199.md#exp-159--explicit-scene-targeted-long-running-actions) |
| EXP-160 | 2026-09-17 | MIXED · six baseline gates closed; P02/P03 fail | Early baselines | Ordinary automatic/manual/custom/NOP/26.5, dispatch and exact reentrancy pass; enabled handoff3 allocations/416bytes exceeds1/64 budget;220 retained scene entries. Legacy27 inconclusive;15 runtime unavailable. | [active record](Experiments/EXP-143-199.md#exp-160--early-compatibility-and-performance-baseline) |
| EXP-161 | 2026-09-17 | PASS · A01 | Acceptance workflow | Fully automated166tests,15/15 local,7actions/3views/0errors backend; two tooling-invalid attempts retained;24Python+3Node controls. | [active record](Experiments/EXP-143-199.md#exp-161--automated-acceptance-pipeline) |
| EXP-162 | 2026-09-17 | PASS · D01/D02 | Platform compatibility | Two failing full-target controls; watchOS RUM/macOS WebView Debug and Release pass; 70 Resource/action and 28 WebView iOS tests plus lint pass. | [active record](Experiments/EXP-143-199.md#exp-162--restore-watchos-resource-and-macos-webview-compilation) |
| EXP-163 | 2026-09-17 | PASS · D12; T02 restored | Existing-API compatibility | Three recipient metadata failures reproduced; 212 affected tests and strict source/test lint pass. Own overdue-stop attributes retained; peer metadata remains isolated. | [active record](Experiments/EXP-143-199.md#exp-163--preserve-overdue-action-stop-attributes-without-peer-leakage) |
| EXP-164 | 2026-09-17 | PASS · D09 | Controller thread compatibility | Two failing getter controls; 31 affected tests pass. Mounted fixture 19/19, zero background reads/MTC diagnostics versus control 5 reads/4 diagnostics. Tooling-invalid attempts retained. | [active record](Experiments/EXP-143-199.md#exp-164--preserve-controller-api-caller-thread-compatibility) |
| EXP-165 | PASS | D11: legacy container restored; 102 tests, 19/19 mounted bridge/Replay checks and four collector controls | [Record](Experiments/EXP-143-199.md#exp-165--preserve-legacy-nativewebview-replay-correlation) |
| EXP-166 | PASS | D04/P02: 282 tests; core-scoped consumers; full27/26.5 ABBA1 allocation/64 bytes with latency/reentrancy budgets preserved | [Record](Experiments/EXP-143-199.md#exp-166--isolate-ui-event-handoff-by-sdk-lifecycle-and-reduce-allocations) |
| EXP-167 | PASS | D05/D06: six failing controls, 198 tests/44 new cases, two native scenes 47/47 versus 20/47; old ownership and eligible peers preserved | [Record](Experiments/EXP-143-199.md#exp-167--preserve-navigation-ownership-across-session-restoration) |
| EXP-168 | PASS | D03/R02: 303 tests; 37/37 mounted checks on27/26.5; 25 leaked registrations reduced to zero, teardown restored; P03 registry budget remains open | [Record](Experiments/EXP-143-199.md#exp-168--release-keyed-swiftui-registrations-and-instrumentation) |
| EXP-169 | PASS | D07: four failing controls, 119 tests, mounted explicit/capability hosts29/29 versus19/29; automatic-before-input and immediate semantic owners | [Record](Experiments/EXP-143-199.md#exp-169--keep-automatic-tracking-until-semantic-input-is-ready) |

| EXP-170 | PASS | D08: three failing controls,314 tests and mounted51/51 versus39/51; fresh reconnect Resource/Log owners and delayed retained-host remount | [Record](Experiments/EXP-143-199.md#exp-170--accept-semantic-reconnects-only-after-a-live-attachment) |

| EXP-171 | PASS | R04: two failing no-body controls,318 tests, mounted57/57 versus43/57; first retained-reader callback owns latest input before body rebind | [Record](Experiments/EXP-143-199.md#exp-171--restore-retained-hosts-from-the-reader-without-body-reconstruction) |

| EXP-172 | PASS | P03:326 tests, three failing controls; Release ABBA27/26.5 zero retired entries/weak survivors within frozen heap limits; eight ordinary smoke runs and watchOS Release pass | [Record](Experiments/EXP-143-199.md#exp-172--retire-disconnected-scene-history-without-accepting-stale-callbacks) |
| EXP-173 | PASS | D10/R06 closed:337 tests, mounted77/77 versus55/77; accepted Binding and occurrence callbacks, rematerialization regression fixed; all four native attempts retained | [Record](Experiments/EXP-143-199.md#exp-173--commit-accepted-presentation-state-and-fence-occurrence-callbacks) |
| EXP-174 | PASS | R05 closed: three failing controls, nine new regressions and346 affected tests; monotonic synchronous generations, membership and exact two-host teardown | [Record](Experiments/EXP-143-199.md#exp-174--preserve-monotonic-reentrant-observer-delivery) |
| EXP-175 | PASS | Four failed controls repaired, seven new regressions and379 affected tests; completion/metrics stay on original owner without foreign action counts. Full T03 target/backend gate stays open | [Record](Experiments/EXP-143-199.md#exp-175--keep-resource-completion-on-its-owning-scope) |
| EXP-176 | PASS | T03 closed:397 affected/8 ObjC, iOS/watchOS Release;167 probe tests,22 local/77 signals and exact5 Resource/4 error/5 view backend owners across2 sessions, peer counters0/0; all failed attempts retained | [Record](Experiments/EXP-143-199.md#exp-176--accept-explicit-resource-starts-and-captured-completion-owners) |
| EXP-177 | PLANNED | T04: explicit current-view error targets, independent fallback and exactly-once completion; preserve T03 Resource-error owners | [Record](Experiments/EXP-143-199.md#exp-177--target-current-view-errors-without-changing-resource-owners) |

## Simulator-inconclusive and hardware-required evidence

[PLAN.md owns the executable physical-device and human-driven
queue](PLAN.md#physical-device-and-human-driven-queue). These compact locators
ensure every existing environment-bound experiment remains visible here.

| Priority | Experiments | Required capability |
| --- | --- | --- |
| P0 | `EXP-100` | Human SwiftUI edge-pop cancellation and completion |
| P0 | `EXP-081` | Human UIKit edge-pop cancel followed by completed pop |
| P0 | `EXP-086`, `EXP-103` | Stable simultaneously visible split navigation |
| P0 | `EXP-041`, `EXP-089`, `EXP-113` | B representative, visible-A work, exact B close without A disturbance |
| P0 | `EXP-114` | Real activation/focus handoff with foreground target and background peer |
| P0 | `EXP-118` | Semantic scene A coexisting with automatic scene B |
| P0 | `EXP-129` | Same manual key in A/B with reverse-order stops |
| P0 | `EXP-131` | Cross-scene Operations and distinct-key reverse completion |
| P0 | `EXP-136` | One A-created, B-joined shared Trace request |
| P0 | `EXP-146` lifetime follow-up | Actual semantic-host removal plus genuine scene disconnect/reconnect without A resurrection, duplicate stop, or B disturbance |
| P1 | `EXP-076`, `EXP-087` | Acknowledged regular/compact/regular adaptive resize |
| P1 | `EXP-042` | Concurrent two-window restoration |
| P1 | `EXP-001` | UIKit-hosted SwiftUI parity, required gate H16 |

`EXP-039` is not admitted release scope: its rejected candidate was never
constructed. F02 owns documented automatic/opaque limits; do not create another
reflection experiment without a named gate or concrete regression. The plan also
retains forward-looking hardware gates for genuine reconnect, per-scene
background/foreground, and the final iPhone Duo/iOS 27.1 release matrix.

## Detailed evidence routing

- [Active records: EXP-143-199](Experiments/EXP-143-199.md)
- [Frozen experiment history through EXP-142](Archive/EXPERIMENTS_THROUGH_EXP-142.md)
- [Archive integrity and lookup rules](Archive/README.md)
- [Rejected approaches and attempts not to repeat](REJECTED_APPROACHES.md)
- [Tooling and documentation workflow](TOOLING_RUNBOOK.md)

For `EXP-001` through `EXP-029`, the ledger locator uses a run/session token
because the frozen chronology has broad date headings. Later rows use the stable
experiment ID. One lookup here followed by one targeted search in the linked
record is sufficient; do not load the archive wholesale.
