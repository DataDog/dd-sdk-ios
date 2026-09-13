# RUM multi-scene experiment history

Read this document when reproducing a result, checking exact run or RUM session
identifiers, reviewing rejected approaches, or continuing from a prior checkpoint.
The [assessment](ASSESSMENT.md) interprets this evidence; the
[plan](PLAN.md) decides what to run next. Start at the
[canonical overview](../MULTI_SCENE_SUPPORT.md) for the current resume point.

Last updated: 2026-09-13

## Checkpoint commit structure

The branch history and current checkpoint are intentionally split by rollback
boundary, in this order:

| Order | Commit subject | Boundary |
| --- | --- | --- |
| 1 | `Route RUM state through concurrent scenes` | Core scene/view/action/lifecycle/session/cache/operation model, plus the private execution-local handoff and focused tests |
| 2 | `Preserve scene ownership for RUM resources` | Network interception and URLSession RUM resource start/completion ownership |
| 3 | `Preserve scene ownership for logs and mirrored errors` | Log correlation and delayed log-to-RUM error routing |
| 4 | `Preserve scene ownership for trace correlation` | Manual spans, URLSession spans, propagation correlation, and completion ownership |
| 5 | `Preserve native scene ownership for WebView RUM` | Native container snapshots forwarded with WebView events |
| 6 | `Add a multi-scene RUM integration probe` | Runner scenario, multi-window scene delegate support, scheme, and project wiring |
| 7 | `Document the multi-scene support checkpoint` | This assessment, experiment ledger, rejected paths, plan review, questions, and resume instructions |
| 8 | `Bridge native scene identity into SwiftUI` | iOS 17+ custom trait publication, SwiftUI environment bridge, normal-app gating, and focused tests |
| 9 | `Preserve feature operations after scene teardown` | Last-proven source-view snapshot, teardown/navigation/legacy tests, and no live-view resurrection |
| 10 | `Add fixed multi-scene probe controls` | Fixed UIKit/SwiftUI activation and close controls used by delayed-work and teardown experiments |
| 11 | `Update the multi-scene runtime assessment` | Consolidated run/session evidence, operation failure and fix, current gaps, validation, and resume plan |
| 12 | `Add automatic SwiftUI multi-scene probe mode` | Manual/automatic probe selection and conditional explicit SwiftUI view tracking used by the transparent-tracking experiments |
| 13 | `Support cross-window RUM operation attribution` | Per-step trustworthy-view resolution, exact scene-independent identity, duplicate-start semantics, focused regressions, and A/B runtime controls |
| 14 | `Preserve exact RUM operation identity in profiling` | Exact `(name, operationKey)` correlation in continuous and app-launch Profiling, including delimiter and omitted-key collision coverage |
| 15 | `Automate SwiftUI navigation probe and document findings` | Deterministic automatic navigation, rejected early UIKit lifecycle hooks, exact-ID backend evidence, and resume guidance |
| 16 | `Add native SwiftUI multi-scene probe` | Standalone iOS 27 `WindowGroup` harness plus single-window and two-window backend baselines |
| 17 | `Consolidate multi-scene support assessment` | Reconciled verdict, experiment results, product decisions, Operations contract, and resume state before the split |
| 18 | `Split multi-scene support documentation` | Canonical overview plus assessment, plan, experiment, and Operations documents with one owner per topic |
| 19 | `Expand the native multi-scene navigation probe` | Native manual/automatic controls, stress/modal/scene-close paths, route-owned tracking, cancelled and aborted navigation, materialized replacement, split-selection, and UIKit split controls |
| 20 | `Keep repeated RUM view occurrences isolated` | Reducer identity, restored-scope boundaries, and action/resource ownership when a platform identity is reused for a later navigation occurrence |
| 21 | `Track multi-scene navigation occurrences` | iOS 27 explicit SwiftUI early mount and interactive completion, atomic occurrence replacement, retained-reader teardown/remount, and UIKit split-column reconciliation with focused regressions |
| 22 | `Add deterministic UIKit split transition controls` | Public-UIKit interactive cancel/finish controls and manual-pop hold used to validate committed navigation occurrences |
| 23 | `Add concurrent and adaptive split probe controls` | Concurrent split-window launch plus empty-selection and sequence-disable controls for overlap and resize experiments |
| 24 | `Use scene handoff for manual RUM work` | Exact-view/scene routing for manual actions and Resource starts invoked inside trustworthy UI-event context |
| 25 | `Update the multi-scene support checkpoint` | Current backend evidence, assessment, plan, rejected paths, validation, and exact resume state |
| 26 | `Add UI event handoff probe` | Predicate-filtered physical UIKit control with synchronous and post-scope manual action/Resource markers |
| 27 | `Update the multi-scene support checkpoint` | `EXP-089` backend evidence, corrected discriminator status, and exact resume state |
| 28 | `Keep exact-view actions representative` | Exact-view actions advance the compatibility representative without creating cross-scene duplicates |
| 29 | `Route resource completions to their owner` | Resource metrics, success, and failure stay with the scope selected at start |
| 30 | `Route manual errors through scene handoff` | Manual errors prefer trustworthy event-local view and scene ownership |
| 31 | `Route per-view mutations through scene handoff` | View attributes, timing, and loading-time mutations use exact or scene-local targets |
| 32 | `Scope manual views to their scene` | Manual view start/stop resolves a trustworthy scene without changing source-less compatibility |
| 33 | `Route internal view work through scene handoff` | Internal view commands carry exact event-local view and scene targets through the subscriber |
| 34 | `Add keyed SwiftUI view binding seam` | Debug-only semantic occurrence key and generation drive RUM identity without resetting customer content |
| 35 | `Add keyed SwiftUI navigation probe` | Native probe supplies route keys and generations for replacement, abort, and retained-return experiments |
| 36 | `Route OpenTelemetry spans through scene handoff` | Native and OpenTelemetry span builders share exact, scene-local, and representative start-context selection |
| 37 | `Reveal retained SwiftUI navigation occurrences` | A weak per-window route source starts a fresh retained occurrence before outer lifecycle work and uses the interactive-transition gate |
| 38 | `Add keyed SwiftUI split navigation probe` | Split selection supplies RUM-only occurrence keys and generations without replacing customer content identity |
| 39 | `Document split navigation runtime evidence` | `EXP-102`/`EXP-103`, updated assessment and plan, simulator-system-crash boundary, and the real-device/human rerun queue |
| 40 | `Preserve revealed SwiftUI view occurrences across remount` | Source-started retained routes transfer their published identity to replacement SwiftUI tracking state; split-return probe and focused regressions |
| 41 | `Document retained split return and harness plan` | `EXP-104`/`EXP-105`, updated support verdict, deterministic harness workstream, and exact resume state |
| 42 | `Introduce named multi-scene probe scenarios` | Validated 35-scenario catalog, strict legacy adapter, manifest-first fail-closed startup, generated hostless tests, and probe documentation |
| 43 | `Document named probe scenario validation` | `EXP-106` process-boundary proof, exact valid/invalid launch evidence, and refreshed resume state |
| 44 | `Record and validate multi-scene probe timelines` | Versioned JSONL recorder, mapper snapshot reduction, semantic oracle, five fixtures, and 24-test probe plan |
| 45 | `Model one RUM destination per scene` | UIKit split manifests forbid structural Primary RUM views and retain Primary lifecycle only as negative diagnostic evidence |
| 46 | `Add exact scene registry to multi-scene probe` | Main-actor logical/native scene registry, weak window ownership, lifecycle/geometry/route snapshots, disconnect fencing, and schema-version compatibility |
| 47 | `Drive probe navigation through observed signals` | Signal-driven Home → Detail → Home execution, exact scene/path/destination/RUM-occurrence waits, one terminal verdict, deferred lifecycle-fact reduction, and focused driver/oracle tests |
| 48 | `Drive deterministic SwiftUI navigation scenarios` | Signal-driven stack abort and same-/different-type replacement, exact path/destination acknowledgements, decisive action/Resource expectations, and focused driver tests |
| 49 | `Document deterministic stack scenario evidence` | `EXP-110` local/backend evidence, strengthened acceptance timelines, and refreshed handoff state |
| 50 | `Drive deterministic SwiftUI split selection` | Root-owned split selection commands, observed selection/destination waits, exact per-occurrence action/Resource checks, and asynchronous oracle ordering fixes |
| 51 | `Document signal-driven split selection evidence` | `EXP-111` local/backend evidence, automatic semantic failure control, oracle corrections, and refreshed handoff state |
| 52 | `Treat regular split primaries as structural` | iOS 27 multi-scene suppression of regular structural Primary/supplementary UIKit split columns, retained same-column reconciliation, and compatibility regressions |
| 53 | `Drive deterministic UIKit transitions` | Exact-scene begin/progress/resolve commands, coordinator-result signals, semantic UIKit names, resolved-view marker checks, and focused cancel/finish driver tests |
| 54 | `Document signal-driven UIKit transition evidence` | `EXP-112` local/backend evidence, structural-view verdict, validation snapshot, and refreshed resume state |
| 55 | `Coordinate probe scene lifecycle explicitly` | Exact source-to-target window open, exact target close, readiness/disconnect acknowledgements, peer-continuity expectations, and focused driver coverage |
| 56 | `Document exact scene lifecycle evidence` | `EXP-113` local/backend evidence, open/close lifecycle verdict, simulator-topology boundary, and refreshed resume state |
| 57 | `Drive observable scene activation transitions` | Exact registered-scene activation, latched lifecycle-state conditions, durable terminal-result logging, explicit inconclusive classification, and focused driver coverage |
| 58 | `Suppress automatic SwiftUI views in explicit subtrees` | iOS 27 multi-scene authority registry, subtree-scoped automatic-view suppression, focused coexistence regressions, and a probe configuration that enables automatic and explicit tracking together |

Rows 1-58 are committed. Row 16 is commit `e56262485`; row 17 is commit
`2fb8dd9b5`; row 18 is commit `6fa2baf24`; rows 19-21 are commits
`4ddfa9a3a`, `1eea12c27`, and `61031e16f`; rows 22-23 are commits
`77dd05c4a` and `bce1cdbd4`; row 24 is commit `7d7bc0814`, row 25 is
`adaec8bdb`, row 26 is `e124ae72c`, and row 27 is `8cb8661af`. Rows 28-37 are
`85da8fa9c`, `c657f15fd`, `149e58655`, `917bc36b3`, `798a2228a`, `79aefb836`,
`119afcac6`, `c5cf8cfaf`, `08126fedd`, and `eece6ec17` respectively. Row 38 is
`96222a6b1`; row 39 is `e2bac40da`, row 40 is `60da5316b`, row 41 is
`4010931b0`, row 42 is `6bee92ee7`, row 43 is `98fa60559`, row 44 is
`ff8750dc3`, row 45 is `acca8907f`, and row 46 is `abfb93d45`.
Row 47 is `34ba7eabf`, row 48 is `4a1311dd4`, row 49 is `9657713e2`, row 50
is `96a6208ff`, row 51 is `b1d74b8cc`, row 52 is `f4c8669c0`, and row 53 is
`df0322619`. Row 54 is `4f1bf4d55`, row 55 is `45e5999e4`, row 56 is
`a97e943df`, row 57 is `4d1783198`, and row 58 is `85d03e5ee`.

Twelve earlier signed attempts failed before writing a commit object. The last
attempt that returned signer stderr reported:

```text
error: Signing file /var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T//.git_signing_buffer_tmpm6SzCt
Couldn't sign message (signer): communication with agent failed?
Signing /var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T//.git_signing_buffer_tmpm6SzCt failed: communication with agent failed?

fatal: failed to write commit object
```

That blocker is superseded for this development branch: the user explicitly
authorized unsigned development-cycle commits and prohibited pushing them. The
exact-path commits from row 28 onward use that policy. This is local checkpoint
history, not push-ready history.

Because `xcconfigs/Datadog.local.xcconfig` already has a user-owned staged entry,
an exact `git add` is not enough: an ordinary `git commit` still commits every
pre-staged path. Use `git commit --only -- <exact paths>` or otherwise isolate the
index, and never alter that file's staged/working-tree state. The first row-58
commit accidentally included its pre-staged empty blob; it was immediately
amended out, and the exact prior `AM` state was restored. Commit `171110739` is
therefore superseded and is not part of branch history.

## Consolidated experiment ledger

The chronological notes below retain full IDs and observations. This table is the
authoritative index of runs that currently support decisions. `EXP-*` identifiers
are stable references: append new rows and never renumber existing experiments.

| Experiment | Probe run | RUM session | Runtime | What it established |
| --- | --- | --- | --- | --- |
| EXP-001 | `a9fab1c4-5cb6-4468-9d1a-dc0936116c46` | `18e48c14-7073-4353-9b85-0121b93c74e0`, `5fc61f1f-9253-4c12-9917-d1568e4ca9d5`, and `86a1a492-24db-485c-80dc-1a4a21dab1e7` | iPadOS 27 | Single-window harness, payload markers, and backend queries work. Three second-window attempts ended in simulator-wide `backboardd` respawns; the second captured baseline scene B replacing still-visible A first. |
| EXP-002 | `574be7dd-4482-48e5-b4cc-eaaa332179bd` | `59a3329e-1a21-486c-9ee5-190d111bfbf3` | iPadOS 26.5 | First fixed two-window proof: A and B views coexist; B navigation does not stop A; delayed resource/span/operation retain the intended B lifecycle. |
| EXP-003 | `4d7dc23b-721d-4038-8c89-3b29a1c373c9` | `0caa932a-7c4c-4c9d-9fb5-4acb691118f9` | iPadOS 26.5 | Manual B action emits once instead of fanning into A; mixed UIKit/SwiftUI navigation remains scene-isolated. |
| EXP-004 | `6a0b61d0-85a8-4915-b02e-63ab53fa13db` | `2b282934-aae9-4495-b7fc-797736f58735` | iPadOS 26.5 | Concurrent UIKit and SwiftUI views coexist; Session Replay uploads are accepted with no SDK crash. |
| EXP-005 | `e7bf0f3e-2e46-4487-af4f-072cd7ba8ab8` | `feb94679-4b2e-4821-8146-a531e8608672` | iPadOS 27 | Physical SwiftUI navigation action and destination are correct in one scene; opening B reproduces the simulator compositor crash, not an SDK crash. |
| EXP-006 | `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` | `5e65abff-6999-45b2-b8ca-cf199b1b13e4` | iPadOS 26.5 | Actual URLSession boundary: synchronous UIKit work and task resume can retain B; scene connection and `viewDidAppear` loading can fall to representative A. |
| EXP-007 | `8a71b04b-ee69-4670-bdb1-28a6a3625662` | `462f633d-b3fb-4fd5-83e6-bd83123187ee`, then `2df86288-72c8-43dc-ab53-7d13d70c6367` | iPadOS 26.5 | Structured requests retained B and correctly kept/dropped their action at 20/200 ms. The same run exposed the pre-fix explicit-session-stop loss of still-visible scene A. |
| EXP-008 | `e03e31d3-eb19-4955-9782-1b583f37b28f` | `29784a34-5196-4ed1-8c56-8e3337f31205` | iPadOS 26.5 | Explicit session stop restores both active scene branches; delayed B work remains on B after navigation. |
| EXP-009 | `70ccd6cf-1514-4387-86ef-25cc255744c4` | `8ea9108c-3fb3-4cdf-ae76-c429348b16b0` | iPadOS 26.5 | Three-minute causality proof: structured `Task` retains B; detached task, GCD, and timer use representative A. RUM and APM agree. |
| EXP-010 | `5ebc59df-6fc1-4620-bcb2-1177d9ab3409` | `d49d1cdf-5a6d-4787-af1e-1422ec841ea4` | iPadOS 27 | SwiftUI `.onAppear` requests precede the tracked view and land on the preceding view; delayed task work is correct. |
| EXP-011 | `fd44bcd2-cde3-4488-a9f4-7756683d85f4` | `dab21bf2-8fee-406a-bd84-81b7211e934e` | iPadOS 27 | `UIView.willMove(toWindow:)` remains too late for `.onAppear` and immediate `.task`; pre-correction navigation emitted a 0.79 ms duplicate Home. |
| EXP-012 | `16e48aa6-6826-49ea-b764-6c0af6f16c0b` | `c8c5b90c-ef71-4bbe-842a-fa22ed5587fd` | iPadOS 27 | Child-controller bridge also remains too late. It avoided synthetic/duplicate views in this run and stayed crash-free, but offered no ordering benefit and was removed. |
| EXP-013 | `68786559-42b4-4087-8e34-997e77d081c5` | `799d975d-9597-4b2e-9c4e-833835aed5de` | iPadOS 27 | Scene custom trait reached SwiftUI before the hidden reader and all six Home/Detail lifecycle resources resolved to the correct view, but outer callbacks still preceded the RUM view by 35/34 ms on Home and 2/1 ms on Detail. |
| EXP-014 | `92326a81-441e-48b9-97b3-3db2b00bc3ab` | `4bd7fa85-dda2-4712-9cce-33cb23f73a3c` | iPadOS 27 | Adding `onChange(initial:)` reduced the callback-to-view gap to 2-3 ms for both Home and Detail. It still did not invert lifecycle ordering; backend intake nevertheless preserved all six resources, the source Home navigation action, four expected views, and zero errors/crashes. |
| EXP-015 | `c77883d4-80fe-4730-a3ff-575221a3c262` | `67fdbd11-1d6a-440d-afd0-db11ff6bc6c4` | iPadOS 27 | Four synchronous custom RUM actions invoked in customer outer `.onAppear`/immediate `.task` before the view payload were all processed on the intended new Home/Detail view. Six lifecycle resources were also correct; five total actions, zero drops, zero errors/crashes. |
| EXP-016 | `91864fb5-cace-4f29-a348-5769bf2ffa65` | `02b150f8-3b2f-43fd-b032-8cac2ef91cd9` | iPadOS 26.5 | SwiftUI scene B navigation and delayed operation/resource work remained on B while scene C opened. Scene C's connection and initial lifecycle resources used the previous representative B view, confirming the source-less early-scene boundary. |
| EXP-017 | `31d0a951-095a-4a71-8c48-b6e4fb4d0af2` | `3160c14e-95d7-4a0e-a40b-204060cfae45` | iPadOS 26.5 | UIKit modal presentation/dismissal and duplicate-name A/B views remained independent. The first delayed-work switch attempt was invalidated by a stale scrolled control, which led to fixed toolbar controls in both probe UIs. |
| EXP-018 | `76599137-09c8-4fb1-b54a-92b3c9ff04d1` | `725418d9-aae5-4570-8bd0-1bad452bbb8c` | iPadOS 26.5 | Using the fixed toolbar switch, a UIKit B trace and operation kept B Home ownership while A became active. APM trace `6aa50e250000000095c6c6caacd03265` retained resource `probe-span-scene-B`. |
| EXP-019 | `972c83f7-9c13-4ea3-b5b6-d43857bb7815` | `3a8b0c3b-53e4-4426-b4b1-12e92ec715d5` | iPadOS 26.5 | Broad UIKit/SwiftUI teardown matrix: 18 views, 17 actions, 33 resources, 4 long tasks, zero errors/crashes, and replay available. Duplicate views, modals, SwiftUI scroll, delayed resources, and both UIKit/SwiftUI traces stayed scene-correct. Raw operation starts survived, but operation ends after scene closure did not, exposing the teardown gap. |
| EXP-020 | `c8d2aa31-127a-4d4c-a910-8e56eea5fb48` | `6c05508c-18fc-41df-85e8-32c573fbf37e` | iPadOS 26.5 | Post-fix teardown proof. Operation key `206E691E-33AC-4BF1-8D26-E48D81315D9A` started in scene D, D closed one second later, and intake retained both raw steps on D Home view `547eb0b9-5743-47f7-ab07-c309e5b5bb29`. The reducer produced one successful 3.15-second operation with the same start/end view. Session counts: 8 resources, 8 views, 7 actions, 3 vitals, 1 long task, 1 operation, 1 session; replay available. |
| EXP-021 | `76f40f1f-554f-4842-86a1-7bf4955b734c` | `ae9530b4-4117-4895-a1fe-7442a160e76f` | iPadOS 26.5 | First concurrent automatic-SwiftUI run using `DefaultSwiftUIRUMViewsPredicate`. Scene-A and scene-B taps and reactivation stayed isolated, but Home and Detail lifecycle resources landed on the preceding view. Each initial transition emitted a transient `RUMMultiSceneProbeSwiftUIRoot` before the final navigation-host or destination view. Closing B sent its late detached callbacks to `Background`, not scene A. Backend intake matches the console sequence; Session Replay remained available and no SDK crash was recorded. |
| EXP-022 | `5c807364-100d-44b1-8d35-9d5cfd802fc5` | `2133b271-2079-4d9c-b570-fcea81e1f062` | iPadOS 27 | Target-runtime automatic Home -> Detail reproduction without opening a second window. Home `.onAppear` and immediate `.task` remained on UIKit Home; Detail's three lifecycle resources and tap remained on its source navigation host. Both transitions then emitted transient root and final destination views. Backend: 21 events, 6 views, 8 resources, 1 action, zero errors/crashes, replay available. |
| EXP-023 | `13e39eae-ccc8-47a6-8125-3f52fab589b8` | `092c7b63-661e-4f8c-a8ff-b21b92665c96` | iPadOS 27 | Rejected `viewIsAppearing` experiment. Home `.onAppear` and immediate `.task` remained on UIKit Home; all three Detail lifecycle resources remained on the source navigation host; transient roots remained. The final Detail view started about 515 ms after `.onAppear`. Steady-state manual action/resource attribution remained correct, uploads returned 202, replay was available, and no crash occurred. The extra swizzle was removed. |
| EXP-024 | `b4bbfa9a-3094-4345-b64e-bb1728bec061` | `ae51b4e7-c88b-4413-98bb-455f93c38dd6` | iPadOS 27 | Rejected pre-base-`viewWillAppear` candidate. Home `.onAppear` and immediate `.task` used `ApplicationLaunch`; its delayed task and all three Detail lifecycle resources reused Home navigation-host view `7f2ca0fc-31fe-4902-bafb-7a7029b2758c`. Intake contains 17 events, 5 views, 7 resources, zero errors/crashes, and replay. Exact IDs disprove a destination-view fix despite the repeated host name. |
| EXP-025 | `20462f01-45d6-4838-9102-151467c4c47f` | `da12ef5f-539e-4821-afa9-c2814e63be91` | iPadOS 27 | Rejected post-base-`viewWillAppear` ordering. Home lifecycle work remained on `ApplicationLaunch`; its delayed task and all three Detail resources reused Home host `445ec932-6eb3-49bf-a25b-aff6bacbc29a`. Backend contains 16 events, 5 views, 7 resources, zero errors/crashes, and replay. The hook was removed. |
| EXP-026 | `0b5749cf-e4fd-4bd5-a3e8-4789d3ee6d97` | `cc9e9e0c-1f85-401b-9f33-ba66843b9e50` | iPadOS 26.5 | Same-binary manual-mode control after adding the switch. Explicit tracking emitted `SwiftUI scene-A Home` before completion of its three lifecycle requests; all three backend resources use that view. Twelve ingested events, zero errors/crashes, and replay available confirm the default path remains unchanged. |
| EXP-027 | `native-single-20260912171659` | `721dcd8f-c88c-44f8-be1b-99d60829da92` | iPadOS 27 | First standalone native SwiftUI single-window control. Home `.onAppear` and immediate `.task` actions/resources used `ApplicationLaunch` `9514e96c-4cf8-4efb-a55e-35c58ba4b61e`; delayed Home plus all three Detail phases used navigation host `2810e9e8-9676-4b6b-8838-c8efb78b00ad`. `ProbeHomeView` never appeared; final `ProbeDetailView` `9387c0d9-f0f2-4010-afb0-8f84e17e4275` started after the callbacks. Backend preserved all 6 actions and 6 resources across exactly those mappings, 5 views total, and zero view crashes/errors. |
| EXP-028 | `native-swiftui-20260912171529` | `ffe3a564-c484-4d2a-b1c7-1e7170d333d0` | iPadOS 27 | First native `WindowGroup` plus `openWindow` proof. Scene A and B received distinct native sessions, but B Home `.onAppear` and immediate `.task` actions/resources used scene A Detail view `b33cbe9a-4613-4327-9e2f-a6ceadba5896`. B's own navigation host `5ed90c94-ebd0-491b-bb81-24d4b846468a` appeared afterward and received delayed Home plus all Detail lifecycle work; final B Detail `c7a46015-aa45-4d4e-a280-7b6e989f469a` started later. Backend preserved the exact 12-action/12-resource mapping, 9 noisy views, and zero view crashes/errors. |
| EXP-029 | `lldb-native-lifecycle-20260912` | Not applicable | iPadOS 27 | Local LLDB timing/reflection inspection. Root base `viewWillAppear` had no title or children, then Home `.onAppear` ran before the navigation-controller/host callbacks. Detail `.onAppear` ran before both hosting-controller and base UIKit callbacks. Titles were correct only at the later host boundary. `content.list.item.type` is gone, while `elements.body.viewType` falsely exposes registered `ProbeDetailView` while Home is visible. No backend claim is attached to this experiment. |
| EXP-030 | `native-manual-single-20260912-2207` | `1535edec-4f88-4158-a926-3268744b11c0` | iPadOS 27 | Existing explicit `.trackRUMView` control with the modifier inside each screen. Home lifecycle markers ultimately resolved correctly, but Detail `.onAppear` and immediate `.task` actions/resources used Home `4fed08f3-610f-4b6c-bea1-aff019e2e2b4`; only delayed Detail work used Detail `868d14a5-16a6-4425-84c5-338d25677f01`. |
| EXP-031 | `native-outer-single-20260912-2211` | `6e3ae2b5-2b93-4545-bd29-d7b5eaa376fd` | iPadOS 27 | Moving unchanged `.trackRUMView` outside the fully constructed screen did not establish earlier semantics. Home `.onAppear`/immediate work used `ApplicationLaunch`; Detail `.onAppear`/immediate work used Home `951d3c80-42a3-4bc4-8088-88218edeee15`; delayed work alone reached Detail `26b13949-d8b4-463d-b1f7-6f37e1ac1122`. Modifier rearrangement is not the fix. |
| EXP-032 | `native-mount-single-20260912-2219` | `7f01c652-6641-4759-b0df-43c6a3b9ddf0` | iPadOS 27 | First explicit early-mount candidate. The inherited scene trait triggered the `.trackRUMView` start while the hidden platform reader was created. All 6 actions and 6 resources mapped to semantic Home `1e61f052-7bab-4bef-98c7-3ce2591060ba` or Detail `26cc1198-b336-4396-80d3-9bd13cdd22a7`, with no fallback, warning, crash, or hang. |
| EXP-033 | `native-mount-two-window-20260912-2223`, `native-mount-two-window-repeat1-20260912`, `native-mount-two-window-repeat2-20260912` | `739d9ac2-2d9e-44e0-ae72-390defae5ab5`, `ba8fbafe-f762-4203-abeb-08771ba2a02e`, `3557e5d5-d42f-450a-ac85-32c0276f7cc5` | iPadOS 27 | Three clean two-window early-mount runs. Across 72 lifecycle markers, every A/B Home/Detail on-appear, immediate-task, and delayed-task action/resource mapped once to its exact semantic view. Each run had four semantic view UUIDs plus `ApplicationLaunch`, zero fallback marker, duplicate semantic view, warning, crash, or hang. Backend aggregates match device logs. |
| EXP-034 | `native-mount-dormant-20260912` | `4f34c6e1-2637-49a4-a6c8-d42826e6104e` | iPadOS 27 | A registered but never navigated-to Detail destination produced no Detail platform lifecycle, RUM view, action, or resource. Backend contained only `ApplicationLaunch`, Home `d33ece16-e02f-498e-9241-a91bebccabd7`, and Home's six expected markers. |
| EXP-035 | `native-mount-nav-stress-20260912` | `09bead82-7639-49a1-aa78-ff9670ad1746` | iPadOS 27 | Three complete push/pop cycles produced the correct seven-occurrence RUM path: Home, Detail, Home, Detail, Home, Detail, Home, each with a distinct view UUID and strict stop-before-start ordering. Retained SwiftUI state does not collapse RUM occurrences; RUM views represent the navigation path. All emitted lifecycle and tap actions used the current occurrence. |
| EXP-036 | `native-mount-offscreen-tab-20260912` | `593feed3-6c44-4c55-9350-d1ac7fb4942d` | iPadOS 27 | An explicitly tracked but unselected tab produced neither a platform-content `onAppear` log nor a `ProbeOffscreenTabView` RUM view. Backend contained only `ApplicationLaunch` and Home `57fda015-9e7c-4d88-a975-37cccd8bf984`. This case did not preload the offscreen representable, so it is a clean result but not a general construction/visibility proof. |
| EXP-037 | `native-mount-cancelled-nav-20260912`, `explicit-cancel-baseline-20260912` | `f08c8011-1175-4715-909f-dfb3503dc33e`, `8864b6a6-da13-4201-888e-05634d2b0ddd` | iPadOS 27 | A cancelled 50-point interactive back swipe emitted a false roughly half-second Home occurrence and restarted Detail although Detail stayed visible. The early-mount candidate and the disabled-candidate control reproduced the same sequence (546 ms versus 506 ms), proving an existing explicit `.trackRUMView` cancellation gap rather than a regression from early mount. Both false occurrences reached backend intake. |
| EXP-038 | `native-mount-final-repeat3-20260912`, `native-mount-final-repeat4-20260912` | `0fa4998d-4c39-4674-ac70-8dc91702fac9`, `683e6b94-efbc-4ff3-a865-8ee46915f9d3` | iPadOS 27 | Two clean repetitions completed the three-run bar for the final iOS-27-gated candidate. Each backend session had exactly five views, 12 lifecycle actions, and 12 lifecycle resources; every A/B Home/Detail phase mapped once to its exact UUID, with zero fallback or duplicate semantic view. Both scenes ended concurrently on Detail; there was no SDK/SwiftUI warning, crash, or hang. |
| EXP-039 | `native-mount-view-that-fits-20260912` | `97ff096b-4c03-4de3-9271-2b9035f0c498` | iPadOS 27 | Inconclusive construction-only stress. `ViewThatFits` rejected an oversized tracked candidate without constructing its platform reader or invoking its appearance callbacks, so it could not test construction without semantic appearance. Backend contained only `ApplicationLaunch`, one Home occurrence, and Home's three actions/resources; all six markers used the Home UUID, with no rejected-candidate view, warning, crash, or hang. The dead stress harness was removed. |
| EXP-040 | `native-mount-sheet-20260912` | `1c500aa3-b689-468d-bf49-1eaf6b417411` | iPadOS 27 | Explicit early-mount modal pass. Client and backend emitted the exact completed path `Home₁ → Sheet → Home₂`, with distinct UUIDs `0ec34c52…`, `7c8e644b…`, and `45b791dd…` despite retained Home state. All six Sheet lifecycle markers used Sheet, and the post-dismiss action/resource used Home₂. Four total views including `ApplicationLaunch`, nine actions, seven resources, zero fallback, errors, crashes, or warnings. |
| EXP-041 | `native-mount-immediate-close-20260913` | `7d41417b-907b-42de-ac7b-6553d090b6af` | iPadOS 27 | Mixed immediate scene-close result. B Home started and stopped once; all six B lifecycle action/resource markers, including delayed completions after `dismissWindow`, retained B UUID `fbf4b50b…`. No fallback, error, crash, hang, or SDK warning occurred. Closing frontmost B returned the fullscreen simulator to SpringBoard and made A inactive; reactivating A correctly created a new lifecycle occurrence. This topology therefore did not test continuity of a simultaneously visible A window. |
| EXP-042 | `native-mount-restoration-20260913` | `e578a172-4f94-47a9-990e-8fe0b85aee79`, then `35ad014f-8f8d-4998-b3e7-f7e0fd0072e3` | iPadOS 27 | Partial restoration pass with platform-limited topology. Before intentional termination, A/B Home views and all markers were isolated. Relaunch without uninstall restored only B, retaining native scene ID `77E241EA…`; its new RUM Home occurrence received all lifecycle and manual-marker work with no fallback. A did not reconnect, so concurrent two-scene restoration remains untested. Two sessions contained five views, 11 actions, 10 resources, and zero backend errors/crashes. |
| EXP-043 | `native-transition-coordinator-probe-20260913` | `079b717d-7c5f-491c-bdd3-83316072a713` | iPadOS 27 | Public-UIKit cancellation diagnostic. At the speculative Home `onAppear`, the retained hidden reader resolved `NavigationStackHostingController<AnyView>` and a coordinator with `initiallyInteractive=true`; cancellation was not known until coordinator completion. The later reversal callback had already lost the coordinator and Detail emitted no matching SwiftUI callback. Backend preserved the erroneous `Home → Detail → false Home (0.549 s) → replacement Detail → Home` path, six views total, with no crash or warning. This positively qualifies a coordinator-completion gate for the exercised native `NavigationStack` path. |
| EXP-044 | `native-cancel-gate-candidate-20260913` | `0206043e-8479-4f42-984e-7fb5235fbfa5` | iPadOS 27 | Explicit cancellation-gate pass. A short edge swipe invoked speculative Home callbacks but emitted no Home occurrence or replacement Detail; the UI and RUM branch remained on Detail `0b3bebb8…`. A completed interactive pop then stopped Detail and started fresh Home₂ `1a995513…`, distinct from Home₁ `a81641e6…`. Backend contains exactly `ApplicationLaunch → Home₁ → Detail → Home₂`; all six initial Home/Detail lifecycle action/resource pairs use their exact source view, and the post-pop action/resource use Home₂. Four views, eight actions, seven resources, zero errors/crashes, no warning, and accepted uploads. |
| EXP-045 | `transition-gate-isolation-hardening-20260913` | No backend session; source/focused-test evidence | Xcode 27, iOS 27-gated code | Post-run review found that a recreated view could mount before its reader had responder ancestry, and that one scene-wide pending bucket could swallow unrelated lifecycle. The gate now resolves the tracked state's attached controller first, uses only the matching scene hierarchy as a provisional fallback, keys transactions by scene plus coordinator identity, revalidates ownership on real attachment, and lets unrelated or cross-scene-corrected state escape. Nineteen arbiter/provider tests pass, including retained and recreated returns, cancellation, same-scene unrelated work, two coordinators in one scene, two scenes, scene correction, disconnect, and stale completion. Full RUM passed 1,058/1,058; lint passed 713 source and 699 test files. This row adds no new runtime/backend claim. |
| EXP-046 | `native-navigation-path-occurrence-20260913-0130` | `b6b4f018-4642-4321-92c6-6ff7f8462f4b` | iPadOS 27 | Probe-only scene-root/path prototype pass. One authoritative typed path recreated a hidden semantic tracker at each mutation. The push started Detail before its lifecycle work; a cancelled edge drag neither mutated the path nor emitted a RUM transition; a completed pop logged occurrence 2 and created Home₂ `6357e2ff…`, distinct from Home₁ `c9350381…`, around Detail `4ae1e947…`. Backend contains exactly `ApplicationLaunch → Home₁ → Detail → Home₂`, seven actions, seven resources, zero errors/crashes, and the post-pop marker pair on Home₂. The first `…-0124` attempt proved push ordering but was excluded from the gesture result after its Xcode launch expired and a device-only activation relaunched without the intended environment. This validates the proposed contract boundary, not a production API. |
| EXP-047 | `native-navigation-path-two-window-20260913-0140` | `b17be708-453a-4c28-9570-e6f834ba49e7` | iPadOS 27 | Rejected root-background placement. A's Home/Detail and both final Detail views were correct, but B Home `.onAppear` and immediate work used A Detail before B's hidden sibling tracker existed; only B's delayed work used B Home. A scene-root path observer alone is not an early enough semantic boundary for a newly opened window. No duplicate view, warning, error, or crash occurred. |
| EXP-048 | `native-navigation-path-wrapper-two-window-20260913-0143` | `84abe003-f3c1-4fe5-b6a1-3282a14bd825` | iPadOS 27 | Rejected whole-stack wrapper. B's first Home work still used A Detail, and changing the wrapper identity rebuilt the `NavigationStack`, replaying retained Home lifecycle work after each Detail start. Backend had five view starts including launch, but duplicated actions/resources on the wrong Detail occurrences. |
| EXP-049 | `native-navigation-path-first-child-two-window-20260913-0146` | `12814ace-3aab-4073-976b-a143c1f6ec2c` | iPadOS 27 | Rejected stable first-child placement. It removed the whole-stack lifecycle replay and preserved one view per mutation, but B Home `.onAppear` and immediate work still used A Detail. Reordering a detached root tracker cannot establish B's semantic view before B content starts. No duplicate view, warning, error, or crash occurred. |
| EXP-050 | `native-navigation-destination-owned-two-window-20260913-0151` | `722168c6-14f1-42b7-b4e1-533ed3b7be60` | iPadOS 27 | Route-owned boundary pass. Existing explicit tracking was applied directly to each Home and typed Detail builder while the bound path recorded mutations. A/B Home and Detail each started before their three lifecycle action/resource pairs; all 12 actions and 12 resources used the exact source view. Backend contains only `ApplicationLaunch` plus the four semantic views, with zero replay, duplicate, fallback, warning, error, or crash. This validates the placement required by a future integration; it is not transparent automatic support. |
| EXP-051 | `native-navigation-destination-owned-cancel-20260913-0157` | `14e98588-7f40-488d-826d-f1ab55586b37` | iPadOS 27 | Route-owned occurrence/cancellation pass. The cancelled edge drag produced no path commit or RUM transition. The completed pop logged Home occurrence 2, stopped Detail `3853ced6…`, and started Home₂ `f2c30907…`, distinct from Home₁ `90e5e7ee…`; the final marker action/resource used Home₂. Backend contains exactly `ApplicationLaunch → Home₁ → Detail → Home₂`, with no replay, duplicate, fallback, warning, error, or crash. A diagnostic `probe.navigation_occurrence` value remained stale at 1 on retained Home₂ even though the UUID/path semantics were correct; that non-contract attribute was removed rather than used as evidence. |
| EXP-052 | `native-navigation-aborted-programmatic-20260913-021355` | `e137947b-fad1-44f3-a083-0bf9126c3a74` | iPadOS 27 | Same-turn programmatic push/revert pass. The probe wrote `[.detail]` and then `[]`; SwiftUI exposed both binding mutations but no Detail lifecycle or RUM view, and no second Home occurrence. The post-abort action `3ed8395f…` and resource `96013dae…` used original Home `ce0da61e…`. Backend contains exactly ApplicationLaunch plus one Home, four actions, four resources, zero Detail events/errors/crashes, and two accepted uploads. Binding writes are not themselves RUM navigation occurrences. |
| EXP-053 | `native-navigation-materialized-replacement-20260913-022525` | `7cf4ad27-2a7a-4ffb-9055-cfcadcd19afb` | iPadOS 27 | Invalid harness run, retained only to prevent a false SDK conclusion. Navigation-path mode accidentally excluded the new Alternate screen from explicit tracking. Home/Detail were correct, but Alternate emitted no view; its early work stayed on Detail and delayed work was rejected after Detail stopped. Backend has three views, eight actions, eight resources, no Alternate view, five no-active-view warnings, and zero errors/crashes. The omission was fixed before rerun. |
| EXP-054 | `native-navigation-materialized-replacement-20260913-022917` | `b847bf2d-a643-49fe-ba00-1992248f5b66` | iPadOS 27 | Corrected materialized replacement pass. After one second on Detail, replacing `[.detail]` with `[.alternate]` produced exactly `ApplicationLaunch → Home → Detail → Alternate`, with no intermediate/restarted Home or duplicate. Each semantic screen started before its `.onAppear` and all nine action/resource pairs used its exact UUID; Alternate start led its callback by 0.614 ms. Backend contains four views, nine actions, nine resources, zero errors/crashes, and two accepted uploads. |
| EXP-055 | `xcode27-uihosting-scene-delegate-review-20260913` | No backend session; Apple documentation and SDK interface evidence | Xcode 27 SDK | `UIHostingSceneDelegate` is public from iOS 26 and lets an application-owned `UISceneDelegate` declare a static SwiftUI `rootScene` and receive scene lifecycle for scenes activated through its configuration/request. It exposes no navigation-path or destination identity and cannot transparently wrap an existing pure-SwiftUI `WindowGroup`. It may be an explicit customer root/lifecycle option, but it does not solve semantic destination creation. No runtime claim is attached. |
| EXP-056 | `native-navigation-replacement-two-window-20260913-023302` | `e3e33d60-dce7-4681-a51c-112f5776d9db` | iPadOS 27 | Concurrent materialized replacement passed for view creation: backend contains exactly `ApplicationLaunch` plus A/B `Home → Detail → Alternate`, one UUID per occurrence, with no restarted Home, replay, warning, error, or crash. All on-appear/immediate and all B delayed markers used their route view. A Alternate's delayed source-less manual action/resource ran after B Home became process representative and therefore used B Home, matching the approved compatibility fallback rather than indicating a route/view failure. Backend: 7 views, 18 actions, 18 resources, 2 long tasks, 1 vital; three uploads returned 202. |
| EXP-057 | `native-navigation-same-type-replacement-20260913-024952` | `36a22f91-7823-4f4e-9052-891ca3e9b3a1` | iPadOS 27 | Reproduced semantic occurrence failure. Replacing `[.detail(1)]` with `[.detail(2)]` committed visible Detail 2 while reusing the same destination reader. RUM remained on the original active `ProbeDetailView` UUID with `screen=detail-1`; it emitted no Detail₂ view or lifecycle markers. Backend contains only launch, Home, Detail₁, six actions, and six resources, with zero errors/crashes and two accepted uploads. Same platform/view-modifier lifetime therefore collapses two navigation occurrences unless the integration supplies a route-occurrence identity. |
| EXP-058 | `native-navigation-same-type-route-id-20260913-030955` | `ef550604-548a-40ff-a1a1-c6050a6acbbb` | iPadOS 27 | Probe-only route-identity control passed. Applying `.id(route)` around the tracked destination made `[.detail(1)] → [.detail(2)]` emit exactly launch, Home, Detail₁, Detail₂, with two distinct same-named `ProbeDetailView` UUIDs, no intermediate Home, and all nine action/resource pairs on their exact occurrence. Backend has 25 documents, zero errors/crashes, and two accepted uploads. This proves an occurrence token is the missing input; `.id` itself is not the proposed API because it also resets customer SwiftUI state. |
| EXP-059 | `native-navigation-same-type-route-id-two-window-20260913-031734` | `6ade87bd-4d78-462e-ab47-2ee5a54f910d` | iPadOS 27 | Two-window route-identity control passed for view creation. Backend contains exactly launch plus A/B `Home → Detail₁ → Detail₂`, with distinct same-named Detail UUIDs in each scene and no intermediate Home, replay, warning, error, or crash. All route-owned early work and all B delayed work used the exact occurrence. A Detail₂'s delayed source-less manual pair used B Home after B became representative, matching compatibility policy. Backend: 7 views, 18 actions, 18 resources, 2 long tasks, 1 vital; three uploads returned 202. |
| EXP-060 | `swiftui-atomic-occurrence-replacement-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Added an internal scene-local stack-slot replacement primitive for SwiftUI occurrence rollover. An active replacement stops Detail₁ and starts Detail₂ without exposing Home; a covered or backgrounded slot changes silently and starts the replacement only when revealed/resumed. Missing or cross-scene old occurrences fail closed instead of materializing stale work. Same-name identities and A/B isolation are covered. All 43 `RUMViewsHandlerTests` passed; two strengthened unwind/state assertions passed separately. This primitive is not wired to a public occurrence key, so it adds no runtime/backend support claim. |
| EXP-061 | `retained-view-occurrence-isolation-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Fixed retained-scope contamination when a navigation path returns to the same platform identity. `Home₁ → Detail → Home₂` still creates three backend UUIDs, but inactive Home₁ now ignores later same-identity view start/stop commands while continuing to receive its exactly targeted pending Resource completion. The fix also marks transferred/restored scopes as having an established start boundary, so a later same-identity start leaves exactly one active occurrence. Regressions cover same-session and cross-session pending work plus restoration: focused 3/3, all 75 `RUMSessionScopeTests`, and all 27 `RUMApplicationScopeTests` passed. Active duplicate-start and stop behavior remains unchanged. |
| EXP-062 | `swiftui-route-occurrence-state-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Added dormant internal route-occurrence propagation without changing the public API or current runtime path. An opaque non-serialized key, binding generation, and immutable descriptor now drive fresh keyed command identities, atomic same-scene replacement, stop/start scene migration, detached-key handling, and stale-generation rejection while legacy lifecycle identities remain stable. The interactive arbiter reduces multiple candidates to the final accepted configuration, retains its matching emission closure, mutates nothing on cancellation, rejects stale lifecycle and cross-scene escape, and requires the exact deferred transaction instance before accepting coordinator completion. Build-for-testing succeeded with zero diagnostics; all 25 state tests, 27 arbiter tests, and the targeted handler-publisher descriptor regression passed (53/53 total). Same-type runtime support remains open until a reviewed integration supplies the semantic key. |
| EXP-063 | `swiftui-scene-disconnect-invalidation-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Closed state/handler divergence after scene teardown. The handler already stops and removes the disconnected scene's stack; the arbiter now silently invalidates only matching SwiftUI state, fences stale callbacks until an explicit platform remount, and retains keyed generation history so generation N cannot recreate a deleted entry. A fresh N+1 mount emits start, never replacement. Concurrent A/B transitions, a B-owned state speculatively targeting disconnected A, idempotent teardown, and exact one-stop/one-restart handler behavior pass. Build-for-testing has zero diagnostics; state 27/27, arbiter 29/29, and two targeted handler tests pass (58/58 combined). Reused-reader re-registration and unchanged-attachment delivery remain open before keyed runtime wiring. |
| EXP-064 | `swiftui-retained-reader-remount-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Added retained-reader update re-registration and an explicit reader-mount path after silent scene teardown. The first green revision passed state 30/30, arbiter 30/30, and one handler regression (61/61), the full RUM plan 1,096/1,096, and lint. Review then found that deferred reconnect lost remount authorization and that repeated unchanged `updateUIView` delivery could restart a normally disappeared view. This records the integration seam and rejected first draft, not a completed support claim. |
| EXP-065 | `swiftui-retained-reader-reconnect-hardening-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Hardened disconnect/reconnect and observer isolation after the `EXP-064` review. Ordinary unchanged updates are deduplicated; stale initial-trait input cannot resurrect disconnected state; inactive reconnect waits for semantic appearance; cancelled remount and reader-mount/disappear races rearm correctly; source-A disconnect preserves a pending migration to B; and detached or re-registered A observers cannot bypass B's coordinator gate. Final build-for-testing has zero diagnostics; state 34/34, arbiter 38/38, and two handler tests pass (74/74); the full RUM plan passes 1,108/1,108 and lint is clean across 713 source and 699 test files. Final source review found no P0/P1 issue. Live retained-reader reconnect remains open. |
| EXP-066 | `native-retained-reader-control-20260913-063151` | `b1b2313a-9cd7-4cfa-90f8-272e2ae07de9` | iPadOS 27 | Probe-only retained-reader fault-injection pass. While scene B remained foreground-active and present in `connectedScenes`, the probe posted `UIScene.didDisconnectNotification`, then updated the same retained representable witness (`0x0000000113c51880`, generation 0→1). The pre-injection B Detail occurrence `992f0e7e-6b86-4bf2-be73-e403056363f4` stopped exactly once and the post-remount B Detail occurrence `4e029fe4-338e-496f-b0ea-b9029459180a` started exactly once; the post-remount action/resource used the new UUID and scene A was untouched. Backend contains exactly six views, 13 actions, 13 resources, two long tasks, one vital, one session, and zero errors/crashes. This validates the live handler/arbiter/update integration under explicit fault injection; it is not evidence of an OS scene disconnect/reconnect or a user navigation to another Detail. |
| EXP-067 | `split-navigation-source-audit-20260913` | No backend session; source inspection only | Xcode 27 / iOS 27 target | Split/adaptive navigation has no semantic model beyond one callback-ordered stack per scene. UIKit can briefly restart a still-visible Primary when Secondary₁ disappears before Secondary₂ appears, and an app-subclassed split container passes the default predicate. SwiftUI skips its internal split container, same-controller Detail₁→Detail₂ can expose no automatic lifecycle occurrence, and explicit tracking has no public occurrence key. Actions identify the scene but not a pane. These are source-backed risks except the exact runtime callback/UUID sequences, which remain to be probed. |
| EXP-068 | `native-split-route-owned-20260913-064110` | `7d622e5f-6489-4d26-a04b-9f7809a5f070` | iPadOS 27 | Regular-width route-owned `NavigationSplitView` reproduced the navigation-occurrence failure. Detail(1) started `f83c68df-14f7-45df-9adb-a98ab833e76c`; committing same-type Detail(2) retained the adjacent platform witness `0x000000010a8ccc40`, emitted no stop or fresh view, and put Detail(2)'s action/resource on the Detail(1) UUID. A different-type Placeholder then correctly started `9717a9c1-fc89-40d1-bd9a-5918537df070` with exact marker attribution and no intermediate Sidebar/Home. Backend contains launch plus only the collapsed Detail and Placeholder, three actions, three resources, and zero SDK/probe errors. This is a runtime/payload/backend failure against the required one-UUID-per-committed-path-occurrence contract. |
| EXP-069 | `native-split-automatic-baseline-20260913-064445` | `27a59309-7862-4025-b028-94d6004487db` | iPadOS 27 | Regular-width automatic `NavigationSplitView` failed semantic creation and attribution. It emitted launch, a setup-only fallback, a transient host, and one final hosting-controller view—no Detail(1), Detail(2), or Placeholder view. Detail(1)'s marker used launch; Detail(2) and Placeholder markers both used the final host. Backend contains four non-semantic views, three actions, three resources, and zero SDK/probe errors. Unlike the route-owned baseline, even the different-type selection was invisible, confirming that scene-correct controller discovery is not a navigation-occurrence model. |
| EXP-070 | `native-split-route-id-control-20260913-064735` | `611c8142-3efc-468a-b044-93fed25864f3` | iPadOS 27 | Probe-only `.id(selection)` control passed in regular-width `NavigationSplitView`: launch → Detail₁ → Detail₂ → Placeholder used four distinct UUIDs, no Sidebar/Home interval, and all three immediate action/resource pairs used their matching occurrence. The adjacent content witness was ultimately replaced for Detail₂, confirming that `.id` changes application state lifetime. This isolates explicit occurrence identity as the missing input but is not a production/customer fix. Backend also contains one long task, one vital, one session, and zero relevant warnings/errors/faults/crashes. |
| EXP-071 | `native-uikit-split-stock-20260913-065700` | `0a320a0f-f610-450b-af79-3c47fb3c68b6` | iPadOS 27 | Isolated stock `UISplitViewController` tracking reproduced a manufactured occurrence. The platform kept the same visible Primary controller and sent it no second appearance callback, but replacing Secondary₁ with a fresh same-class Secondary₂ emitted launch → Primary₁ → Secondary₁ → Primary₂ → Secondary₂. The duplicate Primary had no marker; each genuinely materialized child action/resource otherwise used its exact view. SwiftUI automatic tracking was disabled, so the extra UUID comes from `RUMViewsHandler` restarting its lower stack item during Secondary₁ removal. Backend has five views instead of four, three actions, three resources, and no relevant warnings/errors/crash. |
| EXP-072 | `native-uikit-split-subclass-20260913-070100` | `ea8c619c-685b-4b32-93d4-286c820352c8` | iPadOS 27 | Application-subclassed `UISplitViewController` reproduced two independent false occurrences. Because the default predicate filters by framework bundle rather than container inheritance, the subclass became a ~1.3 ms startup RUM view. The same visible Primary then restarted for ~1–5 ms between Secondary₁ and Secondary₂ despite receiving no lifecycle callback. The backend chain has six views instead of four: launch → container → Primary₁ → Secondary₁ → Primary₂ → Secondary₂. Neither spurious view has markers; all three real child marker pairs are exact. SwiftUI automatic tracking was disabled and no relevant SDK/probe error or crash occurred. |
| EXP-073 | `native-uikit-split-navigation-20260913-071730` | `1a36a993-b62c-40b9-9124-6942529bd7b1` | iPadOS 27 | A stable secondary `UINavigationController` proves the defect also affects ordinary push/pop within a split column. The same Secondary₁ controller appeared once, pushed fresh Secondary₂, then appeared a second time after pop. RUM correctly allocated a fresh UUID for returned Secondary₁, but inserted a false Primary occurrence on both push and pop despite Primary remaining visible and receiving no lifecycle callback. The backend chain has seven views instead of five: launch → Primary₁ → Secondary₁ → false Primary₂ → Secondary₂ → false Primary₃ → returned Secondary₁. All four real child marker pairs use the intended occurrence; there are no relevant SDK/probe errors or crashes. This requires same-column transition coalescing while preserving one fresh RUM occurrence for the returned path item. |
| EXP-074 | `native-uikit-split-fixed-20260913-074555` | `90394971-fa37-4c64-8604-6f46a26ab9d0` | iPadOS 27 | The iOS 27 multi-scene UIKit split-column handoff candidate fixes the stock root-replacement failure. The backend now contains exactly launch → Primary → Secondary₁ → Secondary₂, with no restarted Primary; all three action/resource marker pairs use their materialized child view. The run has four views, three actions, three resources, zero errors/crashes, and accepted uploads. The implementation is double-gated to iOS 27 and declared multi-scene applications, uses public UIKit ancestry to identify a split column, and does not change the separate subclass-container predicate behavior. |
| EXP-075 | `native-uikit-split-navigation-fixed-20260913-074847` | `8d9ee17a-e7bd-4b0d-a024-23bb3b5dc2cd` | iPadOS 27 | The same candidate fixes nested secondary push/pop. The backend path is exactly launch → Primary → Secondary₁(first) → Secondary₂ → Secondary₁(returned), with no Primary interval. Returned Secondary₁ reused controller `0x00000001031b1400` but received fresh RUM UUID `bfc94bbd-fbd8-446f-9c00-3bbbc83e88a2`, preserving navigation-occurrence semantics. All four marker pairs are exact; totals are five views, four actions, four resources, and zero errors/crashes, with accepted uploads. |
| EXP-076 | `split-no-selection-resize-preflight-20260913` | No backend session; source/tooling preflight only | Xcode 27 / iOS 27 target | Blocked before uninstall or launch, so this makes no runtime claim. The route-owned split probe hardcodes Detail₁ and automatically advances to Detail₂/Placeholder; no environment input reaches its existing nil branch. The harness also has no deterministic scene-width control, and Xcode device synthesis exposes orientation rather than a reliable regular → compact → regular window resize. Add an initial-nil/sequence-disable toggle plus a system-acknowledged width transition before running this control. |
| EXP-077 | `uikit-split-lifecycle-review-hardening-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Post-run review found that a scene-only pending lookup let an unrelated UIKit appearance expose a sibling interval, and that app/scene background flushed removal while active before suspension. The corrected state machine handles an unrelated appearance directly and silently removes the now-covered pending item, suspends before lifecycle flush, and retains the disappearance timestamp through background/disconnect. Build-for-testing passed with zero diagnostics; all 57 `RUMViewsHandlerTests` and both multi-scene gate `RUMInstrumentationTests` pass. The two native controls still require rerun on this hardened revision. |
| EXP-078 | `native-uikit-split-hardened-20260913-081410` | `14a847cf-0609-475f-b023-87f29ebc3b72` | iPadOS 27 | Stock root replacement passed with the exact four-view chain and marker ownership, but the source/build timestamp raced a later no-op conditional cleanup. This valid behavioral pass is retained but superseded for final-revision evidence by `EXP-080`. An earlier install attempt used an expired interaction session and was rejected before launch, so it produced no telemetry and is excluded. |
| EXP-079 | `native-uikit-split-navigation-hardened-20260913-082047` | `78a9c268-7a84-47b0-a38b-8dc791e2174b` | iPadOS 27 | Authoritative nested push/pop rerun on the hardened candidate passed. The exact backend chain is launch → Primary → Secondary₁(first) → Secondary₂ → Secondary₁(returned), with no Primary interval. Returned Secondary₁ reused controller `0x00000001059b1400` but received fresh RUM UUID `2086f533-f0ab-4928-977e-f2fc34aa74a4`. Backend totals are five views, four actions, four resources, and zero errors/crashes; both uploads returned 202. |
| EXP-080 | `native-uikit-split-current-tree-20260913-082619` | `1771ebb0-adb5-4b5f-8e58-c3ac2d5e425b` | iPadOS 27 | Final post-rebuild stock root-replacement control passed on the exact current tree. The backend chain is launch → Primary → Secondary₁ → Secondary₂, with no restarted Primary. All three action/resource pairs use their exact view; totals are four views, three actions, three resources, and zero errors/crashes. Both uploads returned 202. Together with `EXP-079`, this is the authoritative native pair for `EXP-077`. |
| EXP-081 | `native-uikit-split-interactive-cancel-lldb-20260913-084206` plus four edge-swipe setup runs | `c2bb3b70-3044-4e6d-9015-51ee0a96f799`, `5a2a2d8c-0ad6-4394-88cc-29c15f8a29c6`, `5926a383-b5ec-4fb4-bda8-f31b91f5be19`, `4d392878-6b20-42dd-b679-1230b860c3c6` | iPadOS 27 | Tooling/harness discrimination only. Detached install-and-run could pass environment but had no LLDB process; RunProject could debug but not pass environment. The accepted straight swipe grammar could commit a pop but could not reverse it, while short drags at the split edge resized the Primary divider. These attempts make no cancelled-navigation claim and motivated the deterministic public-UIKit transition control. |
| EXP-082 | `native-uikit-split-edge-commit-20260913-090650` | `312715b2-d818-402f-b468-4aff5d7b01e8` | iPadOS 27 | A real long edge swipe committed the nested pop. The exact backend path is launch → Primary → Secondary₁(first) → Secondary₂ → fresh returned Secondary₁, with no false Primary. The same controller received the two Secondary₁ appearances but distinct RUM UUIDs. All four marker pairs are exact; totals are five views, four actions, four resources, and zero errors/crashes. |
| EXP-083 | `native-uikit-split-deterministic-cancel-20260913-092850` | `eb7c9b25-0f5c-443e-9a3a-c118ed608ace` | iPadOS 27 | A real `UIPercentDrivenInteractiveTransition` advanced a nested pop to 35 percent and cancelled it. UIKit emitted speculative S2-to-S1 lifecycle followed by reversal and a second S2 appearance, but RUM retained the original S2 UUID: launch → Primary → S1 → S2 only. No returned S1, replacement S2, or false Primary was created. Four action/resource pairs were exact; zero errors/crashes. |
| EXP-084 | `native-uikit-split-deterministic-finish-20260913-093115` | `934eadc2-2712-4659-b156-f717f0504de3` | iPadOS 27 | The same 35-percent public-UIKit transition finished instead. RUM emitted launch → Primary → S1(first) → S2 → fresh S1(returned), with no Primary interval. All four marker pairs were exact; totals were five views, four actions, four resources, and zero errors/crashes. Together with `EXP-083`, this validates cancellation-versus-commit semantics on the current candidate. |
| EXP-085 | `swiftui-navigation-public-seam-audit-20260913` | No backend session; Xcode 27 interface/source audit | Xcode 27 / iOS 27 target | No supported transparent SwiftUI navigation hook exposes both committed route identity and an early semantic destination boundary. `NavigationStack` exposes customer-owned paths and typed builders; type-erased `NavigationPath` cannot enumerate its elements; `UIHostingSceneDelegate` is only a root/lifecycle bridge; public `NavigationTransition` supplies no route metadata. The smallest viable experiment is a route-owned occurrence key delivered to the existing internal keyed reader/state path, with `.id` restricted to the hidden SDK reader only as a fallback control. Shipping requires RFC/API review and explicit automatic/manual mixing rules. |
| EXP-086 | `native-uikit-split-concurrent-scenes-20260913-093545` | `ce5c7cc2-53e7-40ba-a127-f1887269c3da` | iPadOS 27 | Two scene-owned split sequences overlapped: B's S2 push began 0.714 ms after A's pop started. B completed push/pop with a fresh returned-S1 UUID and no false Primary; A's pop stalled after `willMove(nil)` once B became fullscreen, with no activation-state callback captured, so that stall is a topology observation rather than an SDK verdict. A's S2 manual lifecycle marker was attributed to B S1 because it called source-less public `addAction`/`startResource` after B became representative. Its diagnostic scene attributes are not SDK provenance; this is the approved last-interacted fallback, not a scene-routing regression. Backend: eight views, seven actions, seven resources, zero errors/crashes. |
| EXP-087 | `e3c21695-d4a3-4a05-a606-7f192836e577` | `d2f7b981-9877-47e9-9147-ea6b01712c6a` | iPadOS 27 | The new initial-nil/sequence-disable split control passed its empty-detail baseline: the UI showed only Selections and backend intake contained no Detail occurrence, error, or crash. Deterministic regular → compact → regular remains blocked because both `devicectl device appResize start` and `info appResize` return CoreDevice error 1001: this simulator lacks `com.apple.coredevice.feature.resizableappmanagement`. No adaptive-transition claim is attached. |
| EXP-088 | `manual-rum-handoff-targeting-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Public manual `addAction`/`startAction`/`stopAction` and all three `startResource` overloads now prefer the exact RUM view in a trustworthy execution-local handoff, then its scene, then the unchanged process representative. Resource metrics/stops/errors deliberately retain resource-key owner routing. `MonitorTests` pass 15/15, the complete RUM plan passes 1,122/1,122, build-for-testing has zero diagnostics, and focused source/test lint has zero violations. A source-less lifecycle call such as EXP-086 remains representative by design. |
| EXP-089 | `ui-event-handoff-20260913-1013` | `f6db73e2-46eb-44dc-9d20-5c2edfa88485` | iPadOS 27 | First physical filtered-control run on the `EXP-088` implementation. The predicate rejected the probe button and emitted no automatic tap. Its synchronous manual action/resource and delayed GCD pair all used A S2 `62562932…`; Resource completion retained its start owner and backend reported zero errors. This does not discriminate handoff routing: switching from fullscreen B back to A had already created a fresh A S2 occurrence and made it the process representative roughly 13 seconds before the tap. It does prove the live interception/control path and the approved rule that later source-less work uses the last-interacted view. Repeat with A/B simultaneously visible so B can remain representative while A receives the tap. |
| EXP-090 | `nav-occurrence-detail-replace-20260913-1122` | `35ace8f2-e1c1-4e60-a5a7-2d2abcc4afef` | iPadOS 27 | The debug-only keyed binding created distinct Detail1 `1c759…` and Detail2 `c4f1…` RUM UUIDs while preserving one customer state token `e1c37b44…`. The exact path was launch → Home → Detail1 → Detail2 with no synthetic Home interval. This proves an SDK-owned occurrence key can replace only RUM identity without applying `.id` to customer content. |
| EXP-091 | `nav-occurrence-abort-20260913-1128` | `e9b51335-3795-431f-9fe1-a6d3ef187e20` | iPadOS 27 | A same-turn Home → Detail → Home path write coalesced before Detail materialized. Intake contained only launch and the original Home: no Detail and no restarted Home. A route binding is semantic input, not sufficient evidence that a navigation occurrence became visible. |
| EXP-092 | `nav-occurrence-return-home-20260913-1133`; `nav-occurrence-return-home-marker-20260913-1137` | `7315ab1a-2096-4830-bdec-833926a68d91`; `163ee57b-cc31-452e-8d57-3542f4bd52a8` | iPadOS 27 | The first run proved that retained Home eventually receives a fresh UUID after Detail while keeping its customer state token. The immediate-marker run exposed the remaining ordering defect: Home's second appearance action/resource still landed on outgoing Detail because the keyed reader started Home later. |
| EXP-093 | `nav-occurrence-reader-id-home-20260913-1141` | `e49ed20a-48ba-44fe-9e6d-00ed50d1ce00` | iPadOS 27 | Applying `.id` only to the hidden reader did not move returned Home creation before its outer lifecycle marker. The marker still used Detail. The control was removed; changing hidden-reader identity is not an early committed-route signal. |
| EXP-094 | `nav-occurrence-return-ordering-20260913-1205` | Local runtime ordering; backend identity was not needed | iPadOS 27 | The path setter ran at 11:59:46.714891, Home's appearance marker at 11:59:46.719548, and the fresh Home payload at 11:59:46.731364. This isolated a roughly 4.6 ms supported early hook in the customer-owned path binding and ruled out another reader-only timing change. |
| EXP-095 | `nav-occurrence-retained-source-20260913-1224` | `30eeb568-be6a-4d85-8e14-665666919bb0` | iPadOS 27 | First weak per-window retained-route source attempt failed. The source delivered `false`; Home2 was created later and the appearance action/resource remained on Detail. The same Home state token proved the destination was retained rather than recreated. |
| EXP-096 | `nav-occurrence-retained-source-rebind-20260913-1234` | `f791367c-3d5c-4c83-9336-990e5df5edb9` | iPadOS 27 | Rebinding the registration from both reader reconciliation callbacks still delivered `false`. Home2 again appeared too late. This rejected stale callback installation as the root cause. |
| EXP-097 | `nav-occurrence-source-diagnostic-20260913-1238` | `99b2e382-6bba-46a2-b225-83ead95a41a4` | iPadOS 27 | Temporary debug-only eligibility labels found two live registrations: Detail rejected the Home key, while retained Home matched but had no current scene. Source inspection established that multi-scene `willMove(toWindow:nil)` reports `.detached`, not `.attached(nil)`. The diagnostics were removed after fixing and validating the cause. |
| EXP-098 | `nav-occurrence-retained-last-proven-20260913-1249` | `08cd4ae3-eb0e-4336-8a9c-f63390c843f5` | iPadOS 27 | Retaining the last concrete scene across ordinary hidden-reader detachment passed. The exact backend path was Home `96aad43e…` → Detail `06a622ff…` → fresh returned Home `8ad9240d…`; Home reused state token `749f53ae…`. Source delivery preceded `onAppear`, and both `navigation-appearance-2` action and Resource used returned Home. Scene disconnect clears that proof and requires a newer reader remount; `.attached(nil)` remains rejected. |
| EXP-099 | `nav-occurrence-arbiter-button-20260913-1258` | `11bdae75-fc4e-4873-ab0a-95de7179591c` | iPadOS 27 | After routing source delivery through the interactive-transition arbiter, a normal Back-button pop retained the pass: Home `24453c4e…` → Detail `8de298b6…` → fresh Home `e20f3c08…`, with the same Home state token and both immediate marker events on Home2. The backend query returned 26 exact-session events. |
| EXP-100 | `nav-occurrence-arbiter-interactive-cancel-20260913-1258`; `nav-occurrence-arbiter-interactive-finish-20260913-1320` | `9c36e499-14a9-4579-9855-3d0139649370`; `bca36b14-70dc-49e8-9301-23f37295b74d` | iPadOS 27 | Both single, bounded edge drags were ignored by the simulator: Detail remained active and no path, coordinator, source, or lifecycle signal followed either gesture. They make no cancellation or completion claim. The production-shaped arbiter path is covered instead by focused cancel/finish tests, but a recognized native SwiftUI interactive gesture remains an explicit live gap. |
| EXP-101 | `post-checkpoint-attribution-hardening-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Commits `85da8fa9c` through `08126fedd` close exact-view representative updates, Resource completion ownership, manual error/view/mutation routing, internal view-command handoff, and native/OpenTelemetry span-start parity. The final RUM plan passes 1,147/1,147; the Trace plan passes 151/151, including 4/4 focused OpenTelemetry handoff tests. Focused changed-file lint has zero violations and the final probe build succeeds. These are compatibility and ownership proofs, not substitutes for the still-pending simultaneous-window runtime discriminators. |
| EXP-102 | `split-occurrence-source-20260913-1345` | `d7c4fb96-161a-4dd9-b376-628b1172238e` | iPadOS 27 | Regular-width single-scene split occurrence pass without customer `.id`. One retained Detail witness moved from Detail 1 to Detail 2 while the keyed generation advanced 1 → 2 → 3. Backend emitted exactly launch → Detail₁ `cafa2f12…` → Detail₂ `70a9f413…` → Placeholder `fa8ce9d7…`, with three exact action/Resource marker pairs and zero errors/crashes. The retained-route source returned false as expected because Detail₁ → Detail₂ was an active in-place keyed replacement, not a reveal of an inactive retained route. |
| EXP-103 | `split-occurrence-two-window-20260913-1400` | `a354f09b-557c-43a7-815c-95379ea3504d` | iPadOS 27 | Both native scenes reached regular width and independently retained their Detail witness while advancing generation 1 → 2 → 3. Backend emitted seven views: launch plus distinct A and B Detail₁, Detail₂, and Placeholder UUIDs; all six action/Resource pairs used their exact scene occurrence and no RUM error appeared. Both upload batches completed before final hierarchy capture triggered the known simulator `backboardd` Metal crash. The probe app produced no crash report; this is a concurrent telemetry pass plus a simulator-stability limitation, not an SDK crash-safety failure. |
| EXP-104 | `split-occurrence-retained-return-20260913-1408` | `0540b52f-b398-4886-b956-421cffa64df0` | iPadOS 27 | Retained split-return failure baseline. Detail₁ `2be7a2d9…` → Detail₂ `532c2db1…` → Placeholder `6334cd0c…` was correct. Returning to Detail₂ made the old subtree stop source-created UUID `ee1fd0c4…` after about 6.6 ms; the replacement reader then started `03545f03…`, which owned the marker pair. Backend therefore contained a ghost fifth semantic view. This is a conclusive SDK/prototype failure, not a simulator-input limitation. |
| EXP-105 | `split-occurrence-retained-return-fix-20260913-1421` | `d4f3597e-2254-4b68-897a-5530299083cb` | iPadOS 27 | Fixed retained split return. The source-created returned Detail₂ UUID `761fe74b…` remained active while SwiftUI replaced the platform reader, and the replacement state adopted that identity without another start. Backend contains launch plus exactly Detail₁ `507ff93f…` → Detail₂ `3d921845…` → Placeholder `06dd0b13…` → Detail₂(returned) `761fe74b…`; all four action/Resource pairs use their exact occurrence, uploads returned 202, and no RUM error or app/SDK crash appeared. |
| EXP-106 | `harness-phase1-valid-20260913`; `harness-phase1-invalid-20260913` | `6f556658-1444-4ddf-8d9f-82ce0d5dea91`; none | iPadOS 27 | Named-scenario harness startup proof. The valid `regression.single-scene` launch emitted its complete resolved manifest as the first structured record, then initialized Datadog and produced the expected Home/Detail payload. The unknown-scenario launch emitted only a manifest plus rejection: no Datadog initialization, session, or RUM payload. The catalog contains 35 stable scenarios; strict resolver/catalog tests pass 15/15 and probe build-for-testing succeeds. This validates harness configuration, not a new SDK support surface. |
| EXP-107 | `structured-recorder-live-20260913` | `6b194ceb-b0d8-4d0c-8848-ab293594cb79` | iPadOS 27 | Structured-recorder/oracle phase. Versioned JSONL keeps probe source separate from mapper-observed RUM ownership; snapshot reduction derives first-observed starts and active-to-inactive stops. Five fixtures plus source tests pass 24/24. The live `regression.single-scene` prefix emitted ApplicationLaunch → Home `081e6f2c…` → Detail `f86c6dce…`; backend returned 18 events and exact Home/Detail action/Resource ownership. Xcode's device-interaction request returned `Skill not found`, so no synthetic navigation input or final live oracle result was produced and Home-return remains unproven. |
| EXP-108 | `scene-registry-live-20260913-1647` | `de29d1e3-0ff6-44bb-a3e6-14c17047429a` | iPadOS 27 | Exact probe scene-registry phase. Seven new tests cover logical/native identity, alias rejection, disconnect/reconnect generations, stale-handle rejection, weak windows, scene-local route/presentation/future-context state, and peer isolation; the full probe plan passes 31/31. After a clean uninstall, schema-v2 JSONL emitted scene A ready as native `E32B88D1…`, generation 0, 955×1253 regular/regular, then foreground activation and Home → Detail mutation. Local mapper UUIDs Home `91826d58…` and Detail `3d91c699…` match 18 backend events, including all six actions and six Resources. The initial Home mapper snapshot preceded native resolution and is joined later through its stable logical scene; this harness seam is not a shipping SDK fix. Xcode install/run recovered, but its required `device-interaction` skill is still unavailable, so no Home-return or final live oracle claim is added. |
| EXP-109 | `observable-home-return-20260913-1736-c`; `observable-home-return-20260913-1739-d`; `observable-home-return-20260913-1741-e` | `272c5006-bf32-4ee9-9adb-3b75f9a39639`; `25cc4383-8f80-4ad8-9c44-0ef65771896b`; `11dba044-6d97-4095-a607-25ee742aa804` | iPadOS 27 | Signal-driven Home → Detail → Home acceptance. After a clean uninstall, all three runs produced exactly one local `PASS` with 7/7 expectations and six acknowledged steps. The view UUID chains were `30ff5793…` → `4ca6ef28…` → `03f41a11…`, `bc6d76ab…` → `d3d7648a…` → `6352a4d2…`, and `f5cf4344…` → `51c3c342…` → `d5edb3a6…`; each post-return action and Resource belonged to Home₂. Backend intake independently contains launch plus one Home₁, Detail, and Home₂ per run, the exact post-return owners, and no errors. Two harness-only failures are retained: root `onAppear` did not repeat because SwiftUI retained Home even while RUM correctly created Home₂, and one repeat delivered Home₁'s stop mapper snapshot after Detail's start during animation. The driver now waits for the new RUM occurrence, and the oracle requires eventual stop facts without treating callback order as navigation order. The probe plan passes 35/35. This validates deterministic occurrence/attribution behavior on the experimental SDK, not automatic zero-code SwiftUI support or genuine native gestures. |
| EXP-110 | `observable-stack-abort-20260913-1800-a`; `observable-stack-same-type-20260913-1803-a`; `observable-stack-different-type-20260913-1806-a`; strengthened reruns `observable-stack-abort-20260913-1810-b`, `observable-stack-same-type-20260913-1812-b`, `observable-stack-different-type-20260913-1814-b` | `0550e989-8427-494f-b04a-505255a8acce`; `72dc8338-b5eb-470b-8d39-ecfa24f455ff`; `e7a99a66-a9d4-45e0-9719-e152de01b1a3`; `c8f6fb75-62cb-4f43-9515-988ae36d1586`; `5dea4da1-8949-4760-a89b-41c2758aebb0`; `8b913d29-e0f5-4449-880f-7e7c823e3b91` | iPadOS 27 | Signal-driven stack abort and replacement acceptance. The first clean trio proved the driver and view chains, then the oracle was strengthened to require a decisive action and Resource on the final view. The clean reruns emitted one local `PASS` each: abort 5/5 with only Home `fb10de5b…`; same-type replacement 6/6 with Home `22e06720…`, Detail₁ `40d87f4b…`, and distinct same-named Detail₂ `f75ca7dc…`; different-type replacement 6/6 with Home `47ac4967…`, Detail `b4cb7536…`, and Alternate `9a5ca46d…`. Backend intake independently reports those exact view sets, the required final action/Resource owners, and no error bucket. All 37 probe tests and repository lint pass. This validates deterministic experimental occurrence/attribution behavior, not automatic zero-code discovery or native gestures. |
| EXP-111 | `observable-split-selection-20260913-1831-a`; corrected `observable-split-selection-20260913-1840-b`; `observable-split-return-20260913-1843-a`; corrected `observable-split-return-20260913-1844-b`; automatic baseline `observable-split-automatic-20260913-1846-a` | `cc00fae2-3911-4846-b8b8-68f0c06b9c1f`; `ab78101b-8528-4e0c-9505-1d0bc926ba91`; `84a12a1a-b251-41e0-8f9a-53404427b628`; `9f5a87b0-75b0-4da3-9902-0ce3dc059c57`; `ba04a828-38f8-4135-8e1d-4c25ca875fb8` | iPadOS 27 | Signal-driven split acceptance and automatic failure baseline. The corrected route-owned runs pass 10/10 and 13/13: Detail₁ → Detail₂ → Placeholder and Detail₁ → Detail₂₁ → Placeholder → fresh Detail₂₂ each have one distinct UUID plus an exact action/Resource pair. Backend intake agrees and reports no errors. Automatic tracking fails 0/9: Detail₁ work uses `ApplicationLaunch`, while Detail₂ and Placeholder share one internal `NavigationStackHostingController` UUID. The two earlier local failures are retained as harness lessons: Resource completion is asynchronous ownership evidence rather than a navigation-order clock, and an unordered completion check must continue past an earlier same-named occurrence. All 40 probe tests and repository lint pass. |
| EXP-112 | Baseline `observable-uikit-cancel-20260913-1911-a`; first corrected `observable-uikit-cancel-20260913-1916-b`, `observable-uikit-finish-20260913-1917-a`; final `observable-uikit-cancel-20260913-1923-c`, `observable-uikit-finish-20260913-1925-b` | `dbf47e00-d912-4ef8-862b-abe462931710`; `edc0ba78-6225-4271-9b7d-97dcb34baa2a`; `7ec940ff-5960-45b9-83c6-01b24a04e1cc`; `df3e4faf-727a-4e5b-ae73-c7bac5984658`; `7f1dcd04-7b71-4285-a39a-89cfb81d6cd4` | iPadOS 27 | Signal-driven UIKit cancellation/completion acceptance plus a shipping structural-view fix. The baseline drove a real 35% `UIPercentDrivenInteractiveTransition` correctly but failed immediately because Primary became a RUM view. The iOS 27 declared-multi-scene handler now ignores regular-width structural Primary/supplementary columns and retains same-column pending reconciliation. Final cancellation passes 11/11, keeps S2 `24edf931…`, and attributes three action/Resource pairs to it; completion passes 13/13 and emits S1 `983bb960…` → S2 `b99009d3…` → fresh returned S1 `38058b25…`, with exact 1/1, 1/1, and 2/2 action/Resource ownership. Backend intake has no Primary and no errors. The native SwiftUI host still emits a short fallback before S1, but it owns no probe work. Probe tests pass 42/42, the full RUM plan passes 1,153/1,153, and repository lint reports zero violations. |
| EXP-113 | Interrupted `observable-window-close-20260913-2016-a`; final `observable-window-close-20260913-2020-b` | `6a37d312-8ca1-41fc-87e4-b42d5142fb64`; `be396759-0393-42e1-b08e-acb2a5cb0c7c` | iPadOS 27 | Exact scene-lifecycle driver acceptance. `open-window` dispatches through exact source A and waits for exact target B readiness; `close-window` dispatches through exact B and waits for B disconnect. The first launch session expired after B became ready and before a terminal result, so it is retained as inconclusive. The clean retry acknowledged all five steps and passed 9/9. B `before-close` action/Resource use B Home `22dce95f…`; after B disconnect generation 1, A `after-peer-close` action/Resource use unchanged A Home `f7f72acf…`. Backend intake confirms both pairs, two independent Home view IDs, and no error bucket. The fullscreen simulator did not prove both windows visible concurrently. Probe tests pass 43/43 and repository lint remains clean. |
| EXP-114 | Completed compatibility control `observable-window-activation-20260913-2039-a`; expired lifecycle-gated prefix `observable-window-activation-20260913-2056-b`; compositor-interrupted prefix `observable-window-activation-20260913-2059-c` | `d2d11fda-28ce-4fce-bf46-cd858ce49adb`; no terminal session claim; locally observed `fe55cea1-4c9f-4a72-97e0-398c4302ed71`, zero backend events | iPadOS 27 | Exact activation-harness boundary. The first scenario version acknowledged ten exact-scene commands, but its source-labelled markers were plain public RUM calls with no SDK provenance. Backend therefore correctly kept A-labelled source-less work on last-interacted B until B closed; this is compatibility evidence, not an activation attribution failure. The corrected scenario dispatches activation only through the target registered `UIWindowScene`, waits for its foreground-active state, and requires the peer's latest non-superseded state to become background before asserting a fresh occurrence or marker ownership. The simulator kept both scenes foreground-active. One retry lost its Xcode launch/stdout session before a verdict; another ended when simulator `backboardd`, not the probe, aborted in CoreAnimation/Metal before the 10-second harness timeout. The latter produced no terminal OSLog or backend event. Probe tests pass 45/45 and repository lint is clean. Exact activation remains inconclusive pending capable hardware. |
| EXP-115 | `semantic-authority-coexistence-20260913-2146-a` | `fae57f5a-ba01-4d42-9e32-2774090b1585` | iPadOS 27 | Target-scoped SwiftUI authority pass. Navigation-occurrence mode enabled `DefaultSwiftUIRUMViewsPredicate` at the same time as explicit route-owned tracking. An active explicit hidden reader suppressed automatic discovery only for a containing controller hierarchy; unrelated sibling controllers remain eligible and UIKit predicate acceptance remains authoritative. The signal-driven scenario passed 7/7 and both mapper output and backend intake contained exactly `ApplicationLaunch → Home H1 → Detail D1 → Home H2`, with distinct Home UUIDs and no hosting-controller duplicate. Intake totals were four views, nine actions, nine Resources, three long tasks, one session, and one vital. The RUM suite passes 1,157/1,157, the probe 45/45, and lint is clean. This closes the internal coexistence/dedup mechanics, not the reviewed once-per-container path/router API or automatic-only semantic-navigation gap. |

The ledger preserves what each run emitted, even when a later product decision
changes its acceptance meaning. In particular, UIKit split rows that contain an
initial Primary still prove the removal of *restarted* Primary intervals and fresh
returned-Secondary occurrence identity, but they now fail the final requirement
that structural Primary/sidebar/container surfaces never become RUM views.
`EXP-112` is the superseding stock regular-width acceptance run; the historical
rows remain negative evidence and are not rewritten.

## Real-device and human-driven rerun queue

This queue separates SDK evidence gaps from simulator topology and synthetic-input
limits. A simulator result stays inconclusive until the listed observable signal
occurs; a screenshot or unchanged final screen alone is insufficient. A human may
perform the analog interaction while an agent captures logs, payloads, and backend
intake. Prefer iPhone Duo on iOS 27.1 for the release pass; a physical iPad with a
real simultaneous-window layout is useful for earlier discrimination.

| Priority | Experiments | Why the simulator or driver was insufficient | Appropriate rerun | Evidence required to close the row |
| --- | --- | --- | --- | --- |
| P0 | `EXP-100` | Both bounded SwiftUI edge drags were ignored; no path, transition coordinator, source, or lifecycle signal occurred | Human-driven edge-pop cancel and complete on a physical iOS 27.1 device, preferably iPhone Duo; an agent can record the run | For cancel, prove the coordinator became interactive and cancelled while Detail stayed the sole active occurrence. For complete, prove a committed path contraction, fresh returned-Home UUID, and immediate action/resource on Home₂ |
| P0 | `EXP-081` | The available driver cannot express a right-then-left reversal; short drags hit the split divider instead of navigation | Human-driven native UIKit edge-pop cancel on physical iPad/iPhone Duo, followed by a completed pop | Capture coordinator start/completion and exact view chain. Cancellation must add no S1/Primary/restarted-S2 occurrence; completion must create a fresh returned-S1 UUID without Primary |
| P0 | `EXP-086`, `EXP-103` | Fullscreen topology stalled one UIKit transition in `EXP-086`; both split sequences completed in `EXP-103`, but final capture crashed simulator `backboardd` before stable simultaneous visibility could be recorded | Two visibly active windows on iPhone Duo or a physical iPad multitasking layout; navigate A and B concurrently | Record both scene activation states, stable simultaneous visibility, and both transition completions. Each scene must keep its own destination path and immediate markers with no structural Primary/sidebar view or cross-scene stop |
| P0 | `EXP-041`, `EXP-089`, `EXP-113` | Exact open/close now passes, but fullscreen switching backgrounded or reactivated A and never proved stable simultaneous visibility or a different-representative handoff discriminator | Keep A and B visibly active. Make B representative, interact with A without foreground re-entry, then exact-close B while A remains visible | A Resource start invoked before any representative-changing action and the manual action must use A; later source-less work must use last-interacted A. Closing B must not stop/restart A, and delayed B completion must retain B ownership |
| P0 | `EXP-114` | The simulator kept both exact scenes foreground-active instead of acknowledging a focus handoff, then crashed `backboardd` in CoreAnimation/Metal during a rapid retry | Run `windows.activation-sequence` on iPhone Duo or a physical multi-window iPad; let the OS complete each focus transition before continuing | For every step, record target foreground-active plus peer background before judging telemetry. Each confirmed foreground re-entry must create the scenario's fresh Home occurrence, and its immediate action/Resource pair must use that occurrence. A plain source label must never be treated as SDK provenance; source-less fallback remains last-interacted |
| P1 | `EXP-076`, `EXP-087` | The simulator lacks `com.apple.coredevice.feature.resizableappmanagement`; no requested width transition occurred | Device/window environment that acknowledges regular → compact → regular resizing, ideally iPhone Duo | Capture acknowledged geometry/size-class changes plus semantic split selections. No view may be created for an empty detail; collapse/expand must preserve one occurrence per committed destination without any Primary/sidebar RUM view |
| P1 | `EXP-042` | Relaunch restored only B; A never reconnected | Human-driven physical-device restore with two persisted windows, repeated enough to obtain an OS restoration of both | Preserve native scene-session IDs across termination/relaunch, then prove fresh RUM occurrences and exact lifecycle attribution for both restored scenes with no cross-stop |
| P1 | `EXP-001` | The integration-runner half-and-half arrangement repeatedly respawned simulator `backboardd` | Physical device only if UIKit-hosted SwiftUI parity remains a release requirement; otherwise use the stable native `WindowGroup` probe | Two windows must remain alive through an alternating A-B-A-B flow with no system-process restart; capture the same semantic IDs and markers as the native probe |

`EXP-039` is not in this device queue. Its `ViewThatFits` candidate was never
constructed, so changing devices or using a human does not improve the experiment.
Replace it with a deterministic container that demonstrably constructs but does
not present the tracked subtree. Likewise, `EXP-100` must not be rerun with more
arbitrary synthetic coordinates unless a path/coordinator signal first proves the
driver reached the native navigation gesture.

## Experiment log

### 2026-09-11 — Baseline and tooling

- Confirmed Xcode 27.0 and a booted iOS 27.0 iPad simulator.
- Connected to Xcode's tool server through `xcrun mcpbridge`; workspace, schemes,
  destinations, build, run, console, and test calls work. The requested
  `device-interaction` skill is not installed, so synthesized native gestures and
  visual UI input are unavailable. Exact programmatic scenario driving is
  available through the probe registry and observable driver (`EXP-109`).
- Confirmed Datadog RUM backend search/aggregation access is available.
- Confirmed the integration host opts out of multiple scenes and the Example host
  has no scene manifest.
- Confirmed current branch and preserved pre-existing project/local-config edits.
- Built the unmodified `Example` scheme successfully for the iOS 27.0 iPad.
- The control app was then terminated at launch by UIKit with:
  `Application failed to launch: UIScene life cycle is required for apps built
  with this SDK.` This is a probe-host compatibility failure, not yet evidence
  about RUM event attribution. The Example target must adopt scenes before it can
  be used for the experiment.
- The first attempt to prepare the isolated `IntegrationTests` runner with
  `make ui-test-podinstall` failed before CocoaPods ran because the repository's
  locked Ruby gems are not installed (`Bundler::GemNotFound`, including
  CocoaPods 1.15.2). No Pods or project files were produced by this attempt.
- Installed the repository-locked Bundler 2.5.21 and CocoaPods 1.15.2 bundle,
  then generated `IntegrationTests/IntegrationTests.xcworkspace` successfully.
- The unmodified generated Pods project then failed to build with Xcode 27
  because 21 build configurations from transitive pod targets declare iOS 12,
  while this Xcode supports simulator deployment targets from iOS 15. For the
  experiment only, the ignored generated `Pods.xcodeproj` was mechanically
  raised to the repository's existing iOS 15 minimum. This must be reapplied
  after `pod install` unless a reviewed Podfile/toolchain fix replaces it.
- The existing `Runner iOS` scheme in its `Integration` configuration then
  failed because the Runner imports `DatadogTrace` with explicit modules while
  that local module was built without `-enable-testing`. A dedicated shared
  `RUM MultiScene Probe` scheme now uses the Debug build and launch
  configurations and built successfully on the iOS 27 iPad before probe sources
  were added. Keep this scheme isolated from the normal integration-test matrix.
- Enabled `UIApplicationSupportsMultipleScenes` in the integration Runner and
  added an optional programmatic root-controller hook to `TestScenario`. The
  default implementation returns `nil`, so existing storyboard scenarios retain
  their current launch path.
- Added a scene-aware RUM probe scenario with independently labelled UIKit and
  SwiftUI navigation, duplicate-name views, modal transitions, automatic and
  manual actions, and delayed resource, trace, and feature-operation controls.
  Every control records the native scene-session identifier and an independent
  source-scene marker; only the run identifier is installed as a global RUM
  attribute. This separation is essential for detecting wrong SDK attribution.
- Payload mappers now print compact view/action/resource/error/long-task records
  with their resulting RUM view identifier and name. At this checkpoint the next
  gate was compilation and backend correlation; both were completed by the later
  runs below.
- The complete UIKit and SwiftUI probe built successfully with Xcode's project
  build action in 7.475 seconds and launched on the target iPad. The first live
  control run is `a9fab1c4-5cb6-4468-9d1a-dc0936116c46`; it created RUM session
  `18e48c14-7073-4353-9b85-0121b93c74e0` and native scene session
  `82E7F28F-E381-4FC3-B9FB-4FAB11809C13` for scene A.
- Console payloads show the expected single-window control transition from
  `ApplicationLaunch` (`0c7b7745-8546-433a-90ca-e9271c0bd010`) to
  `UIKit scene-A Home` (`5c8e6e7f-0c44-4307-946d-5c8cb5886140`). This proves
  the harness is instrumented; it is not evidence of concurrent correctness.
- Datadog intake returned seven initial events for that exact run and session,
  including both views, three long tasks, the session event, and the app-launch
  vital. Detailed events preserve `context.probe.run_id`; scene-A view-derived
  events also preserve `context.probe.source_scene` and the native scene-session
  identifier. Backend connectivity and marker round-tripping are therefore
  validated before opening a second window.
- The reproducible backend query is
  `@context.probe.run_id:<run-id>`. The shorter `@probe.run_id:<run-id>` returned
  no results because custom RUM attributes are indexed below `context`.
- Concurrent simulator-flow and backend-attribution claims remain pending until
  the two-window interaction sequence completes.
- The first `Open another window` control was delivered at 11:35:08 local time.
  SpringBoard created a second application scene and began arranging the new and
  existing scenes in a half-and-half layout. At approximately 11:35:10,
  simulator `backboardd` respawned; RunningBoard then killed probe PID 94704 with
  reason `backboardd respawn` / `SIGKILL`, followed by a SpringBoard restart.
  This is a simulator-system interruption, not an application or SDK crash. The
  run ended before any scene-B RUM payload could be observed. Retry once with the
  same explicit run marker; if it repeats, treat the iOS 27 window-manager path
  as an environment blocker and use a less aggressive window arrangement while
  preserving two connected scenes.
- Relaunched with the same run marker. The new process created RUM session
  `5fc61f1f-9253-4c12-9917-d1568e4ca9d5` and scene-A native session
  `D141101B-5822-4CDC-BE73-713885B62DF3`.
- The second open-window attempt reproduced the simulator-system failure, but
  captured the critical unchanged-SDK sequence first: scene B connected with a
  distinct native scene session, both application scenes entered SpringBoard's
  multi-window layout, RUM emitted scene-A Home with `active=false`, and only
  then started `UIKit scene-B Home` with view ID
  `0fcf2aa2-313e-4157-b3dd-27ab577e57dc` and `active=true` in the same RUM
  session. That attempt's native scene-B session was
  `1BD5DCB9-0024-4115-9055-1A24027C00A2`. Scene A had not been closed. This is
  direct evidence that the process-global view stack incorrectly models
  concurrent scene creation as navigation away from A.
- The second interruption again killed the app, SpringBoard, InputUI, and other
  simulator UI processes with `OS_REASON_RUNNINGBOARD` after a `backboardd`
  respawn. Repetition makes this an iOS 27 simulator/window-manager constraint;
  one final retry may avoid Xcode's post-tap XCTest snapshot by using Device Hub
  directly. Further identical retries are not useful.
- A final Device Hub/CUA-controlled attempt temporarily held scene A
  (`D141101B-5822-4CDC-BE73-713885B62DF3`) and a new scene B
  (`7B2E694F-A3B0-48DB-945A-4B51FB35D4FA`) visibly side by side. The next
  accessibility refresh coincided with a third global `backboardd` respawn at
  11:48:24. It killed the app (PID 5055), SpringBoard, InputUI, widgets, and
  other simulator UI processes before alternating A/B controls could be sent.
  The third system-wide reproduction means both Xcode interaction and direct
  Device Hub/CUA paths are unstable on this simulator image.
- The CUA relaunch reached backend RUM session
  `86a1a492-24db-485c-80dc-1a4a21dab1e7`, with scene-A view
  `9ea7f2f3-40ba-4638-8fe8-a0ed8804ff25`. Scene B was killed before upload.
  The prior console run remains the complete concurrent-view evidence, with
  scene-A view `ea085412-f0a1-4425-b830-7bf67184bf57` and scene-B view
  `0fcf2aa2-313e-4157-b3dd-27ab577e57dc`.
- Began the proactive core fix after preserving the unchanged-SDK evidence.
  Current edits keep one session, track one active view branch per scene, target
  automatic UIKit navigation and touch commands at their source scene, retain a
  process-representative compatibility path, and reserve intentional broadcast
  for lifecycle/session-stop commands. Focused handler tests now cover concurrent
  scene starts and navigation in A while B remains open. After adding the legacy
  SwiftUI handler overload required by the existing internal protocol, the full
  `RUM MultiScene Probe` scheme built successfully through Xcode in 9.566 seconds.
  Seven focused `DatadogRUM` tests then passed through Xcode: concurrent handler
  starts, navigation isolated to one handler stack, two simultaneously active
  session view branches, navigation isolated to one session branch, a targeted
  action attributed once to the earlier scene, an unscoped action emitted only
  once through the representative branch, and session stop closing all branches.
  The edits remain experimental until lifecycle/session-rollover coverage,
  broader regression, and fixed-runtime attribution pass.
- Extended the action path beyond taps: continuous scroll/swipe commands now
  retain the source scene from gesture start through deceleration and completion.
  Automatic UIKit/SwiftUI taps, manual SwiftUI taps, and manual SwiftUI views
  also carry a scene target; a hidden non-interactive SwiftUI representable reads
  the hosting `UIWindowScene` without changing public API. Four focused action
  and modifier tests pass, including the legacy unscoped fallbacks.
- Added scene lifecycle observation. `UIScene.didEnterBackgroundNotification`
  suspends only that scene's visible view, `willEnterForeground` restarts only
  that branch, and disconnect stops/removes only that scene. Application-level
  notifications remain the process lifecycle signal and fallback for views whose
  scene cannot be resolved; idempotent stack state prevents duplicate stops when
  scene and application background notifications both arrive. Three lifecycle
  tests pass, including the existing legacy application-background regression.
- Session continuity is now multi-scene-aware. Maximum-duration/inactivity
  refresh and explicit stop/restart retain every active foreground scene view,
  assign each a new view ID in the new session, preserve the representative
  scene, and route the triggering action to its scene. New concurrent expiration
  and explicit-restart tests pass alongside the existing single-view tests.
- Interaction-to-next-view state is now isolated per scene. A focused test proves
  that A1 -> action A -> A2 remains one INV history while concurrently visible B
  receives neither A's action nor A2 as its successor; the legacy no-scene path
  keeps its existing tracker.
- The first URLSession experiment snapshots whichever view selection is available
  during request modification and retains that exact internal target through
  start, metrics, response, and error callbacks. The per-task target map is locked
  and removed on completion. Four handler tests cover success, error, reverse
  completion, and legacy fallback; a scope test proves that an already-correct
  scene-A selection does not migrate to B. These tests validate owner freezing,
  not source discovery. A plain exported representative view does not prove that
  A originated the request.
- Error logs mirrored into RUM now carry the same captured RUM view ID as the log
  across the asynchronous feature-message bus. RUM removes this private routing
  metadata before event encoding and targets the exact still-active view. Sender
  and receiver tests pass with two concurrent scene branches. If asynchronous
  delivery outlives the captured view, routing may move only to a newer active
  view in the same scene. If the captured scene is gone while another survives,
  the mirrored error is dropped rather than crossing scenes. Only legacy no-scene
  work retains representative fallback. Resource completion separately retains
  its cached owner. This aligns the log and mirrored RUM error without silently
  misattributing a delayed error to another window.
- Manual and OpenTelemetry spans freeze the RUM context selected at span creation,
  but the process-wide exported context is not necessarily their originating
  scene. Trace-only URLSession spans are created at completion with an earlier
  start timestamp, so the experiment captures a request-start selection and
  supplies it to the late writer. Four Trace tests prove that supplied A/B
  selections survive reverse completion and later representative changes. They
  do not prove that a generic request automatically selected A or B correctly.
  Requests tracked as RUM resources still avoid duplicate client spans as before.
- The first feature-operation routing experiment remembered the scene that owned
  the start and resolved every later step against that scene's current view. It
  fixed A1 -> A2 navigation while B was process-representative, and used the same
  selected view for the vital, containing view update, and profiling message.
  Local tracking also moved from string concatenation to a typed `(name, key)`
  identity; formerly colliding pairs remained independent. The permanent start-
  scene rule was later rejected because a legitimate operation may start in A and
  finish in B. The typed application-wide identity remains. Identical `(name,
  key)` starts are never silently rewritten with scene identity; the latest start
  replaces local tracking and the earlier backend operation times out after four
  hours unless customers use unique keys.
- The first profiling-message assertion exposed that feature-operation profiling
  unnecessarily traversed an active view's unowned parent. Random legacy test
  fixtures could therefore crash when operation options requested RUM context.
  `RUMFeatureOperationManager` now derives application/session context from its
  own retained parent and overlays only the selected view ID/name. The four
  previously failing operation tests pass. After adding the later action-routing
  regression, the full RUM suite passes 964/964.
- Duplicate SwiftUI identities exposed a remaining asymmetry: scene identity was
  retained for `onAppear` but discarded for `onDisappear`, so the first matching
  stack could be stopped. The modifier now supplies the same captured scene on
  disappearance, and the handler restricts removal to that scene. Handler- and
  session-level tests prove two scenes can use the same identity and stopping A
  leaves B active.
- WebView RUM events now retain the scene of the exact `WKWebView` delivered by
  `WKScriptMessage`. The bridge adds a private message-bus marker, RUM removes it
  before encoding, and `ViewCache` keeps scene identity with each native view. A
  browser event from A therefore selects A's historical replay-enabled container
  even when B has the newer native view. Bridge, cache, and receiver tests pass;
  no public or intake schema changed.
- Fatal/crash context now follows the single representative active view instead
  of whichever concurrent scope happened to emit the last update. Non-
  representative resource updates cannot clobber it, and stopping the
  representative scene restores the still-active scene's latest full view state.
  Five focused new and legacy fatal-context tests pass. Crashes and fatal hangs
  remain process-wide single events by policy.
- Feature-flag payloads contain only flag key and value, so neither the SDK nor an
  integration receiver can recover a source scene after asynchronous delivery.
  Adding deterministic attribution requires a new context-bearing internal
  payload contract or scene-scoped API; current behavior remains representative.
- Main-run-loop long tasks, app hangs, and memory warnings have no intrinsic
  window owner. Broadcasting them would inflate counts. They remain single events
  on the representative view pending a different product policy.
- Concurrent same-display views each summarize the shared process CPU/memory and
  render-loop samples. INV is now scene-isolated and TNS follows resource
  ownership, but refresh normalization still uses `UIScreen.main`; external-
  display windows are therefore not fully supported by the vital path.
- Session Replay remains a known limitation for end-to-end multi-window replay: both
  recorders select the first key window across an unordered connected-scene set
  while consuming one representative RUM context. Touch buffering and layer/view
  snapshot state are also singular. A safe fix requires a scene-keyed recorder or
  multiplexor, not a different arbitrary-window heuristic. That semantic work is
  out of scope here; only crash-free coexistence gates the base-RUM work.
- Profiling correctly remains one process profiler, and feature-operation messages
  now carry the operation's selected scene view. A profile covering events from
  several windows still has last-writer-wins top-level RUM attributes, however;
  aggregation needs a backend-compatible correlation contract before changing it.
- Unscoped manual `startView(key:)` now joins/replaces the representative scene
  rather than creating a third scene-less branch. An unscoped stop for a detached
  `UIViewController` searches active identities across scenes, so it still stops
  its original branch after another scene becomes representative.
- SwiftUI manual view modifiers use a reference-backed hidden scene reader. The
  first implementation waited for `didMoveToWindow`, stopped only a view it had
  actually started, and reused the captured scene on disappearance. Later runtime
  evidence below disproved the assumption that attachment necessarily precedes
  customer `onAppear` work; do not treat this checkpoint as the final ordering
  contract.
- Broad module regression results after the core changes: DatadogRUM 964/964,
  DatadogLogs 89/89, DatadogTrace 142/142, and DatadogWebViewTracking 31/31.
  DatadogSessionReplay on iOS 26.5 produced 738 passes, 3 skips, and one unrelated
  failure where UIKit did not create the private `_UIScrollPocket` used by the
  test. On iOS 27 its Example-based test host was terminated by UIKit because that
  host has not adopted the required scene lifecycle; that is a host/toolchain
  compatibility issue, not a Session Replay SDK crash. Crash-free coexistence in
  the actual two-window probe remains the relevant runtime gate.
- The first fixed iPadOS 26.5 two-window run was
  `574be7dd-4482-48e5-b4cc-eaaa332179bd`, RUM session
  `59a3329e-1a21-486c-9ee5-190d111bfbf3`. Scene A Home used view
  `62209d98-78d2-45a2-a650-ba3adea0bd4e`; opening scene B created Home view
  `f5a8f052-653b-4303-9aad-9e09dd6f3802` without an inactive update for A.
  UIKit taps and the Home -> Detail transition were attributed only to B, with
  Detail view `b4b49f9b-2f28-4605-be76-5b5b97fd062b`.
- In that run, a 3-second resource, manual span, and feature operation started on
  B Detail 1, then B navigated to Shared Detail
  (`57237c78-2126-434f-881b-5adeee1325ab`) before completion. Backend intake
  stored the resource once on Detail 1. The span matched
  `_dd.view.id:b4b49f9b-2f28-4605-be76-5b5b97fd062b` once and matched the Shared
  Detail ID zero times. The operation's reduced event reports Detail 1 as
  `start_view` and Shared Detail as `end_view`.
- The same run exposed a new overlapping-action defect. While scene A still held
  the automatic action for opening B, source-less `addAction(.custom)` from B was
  propagated both to the representative view and to every view with an older
  action scope. Backend intake stored two `manual-action-scene-B` events: one on
  A Home and one on B Detail 1. Routing now fans out only
  `RUMStopUserActionCommand`; new start/add commands select one target. A focused
  regression test reproduces the overlap and passes.
- The rebuilt live verification run is
  `4d7dc23b-721d-4038-8c89-3b29a1c373c9`, RUM session
  `0caa932a-7c4c-4c9d-9fb5-4acb691118f9`. It retained A Home
  (`da5d853a-ce31-409a-b0aa-f1d738870998`) while opening B Home
  (`4fff5481-a693-4ff3-8505-c4a1a23953d2`). The same manual B action now appears
  exactly once in console and backend, attached to B Home. Switching only B to
  SwiftUI created Home `85c8dea1-4fbc-44b0-8980-0ccce59a0d7f`, then
  `NavigationStack` created Detail 1
  `25038ecf-e4c8-4fbb-ae34-ae81a18f1718`, without cross-scene view IDs.
- Device Hub control became unavailable when the host Mac locked during this run.
  Xcode console and Datadog intake remained available and the probe process was
  left running. Resume physical tap, scroll, modal, A/B switching, lifecycle, and
  Session Replay coexistence checks after unlocking; do not discard this session
  merely because GUI input paused.

### 2026-09-11 — Fixed-runtime and causal-context checkpoint

- A later iPadOS 26.5 two-window run used run
  `6a0b61d0-85a8-4915-b02e-63ab53fa13db` and RUM session
  `2b282934-aae9-4495-b7fc-797736f58735`. It kept scene A UIKit Home
  (`40e6dda1-67ef-4d67-b770-0e5ec8a132a4`) active while scene B opened UIKit
  Home (`be5c0926-d927-4ce9-a39f-f6abccdc23d0`), then created scene B SwiftUI
  Home (`2516c6f7-41a8-4343-a5a1-e287cda95c75`). Session Replay uploads were
  accepted and no SDK crash occurred; no scene-correct Replay claim is made.
- The iPadOS 27 run `e7bf0f3e-2e46-4487-af4f-072cd7ba8ab8` produced RUM session
  `feb94679-4b2e-4821-8146-a531e8608672`. A physical SwiftUI navigation tap was
  attributed to its originating Home view and the resulting Detail view was
  correct. Opening the second window then crashed simulator `backboardd` in Metal
  validation (`invalid pixelFormat`), with no Datadog, Session Replay, or probe-app
  frames and backend `crash_count:0`. Do not repeat that iOS 27 compositor path;
  use iPadOS 26.5 for the complete two-window matrix until the simulator image is
  stable.
- The branch now has experimental synchronous UI-event context handoff,
  structured-Task propagation, request pre-start, captured owner maps, exact
  delayed-event routing, and third-party URLSession-handler compatibility changes.
  Build-for-testing succeeds. Twelve focused RUM tests and four focused
  DatadogInternal tests pass at this checkpoint; complete module regressions have
  not been rerun after the newest changes.
- Review found correctness risks before those mechanisms can be kept:
  `.view` routing is recomputed while scopes mutate; cached legacy ownership is
  conflated with unknown ownership; pending-action merging can revive another
  scene from an intentional nil or disagree with a rejected action; and a later
  custom URLSession handler can mutate an allowed pre-started request into a
  disallowed one, orphaning the resource.
- The two core-routing risks are now fixed independently of source discovery.
  Exact `.view` routing resolves one destination before any scope mutates, and
  `ViewCache` distinguishes scene-backed, known-legacy, and unknown ownership.
  Seven focused regressions pass, including a completion owned by inactive A1
  while A2 has an action: the resource remains on A1 and A2's action resource
  count remains zero. The pending-action and custom-handler risks remain open.
- The intentional-nil part of the pending-action risk is fixed. Logs and spans
  now require a captured source-scene context before merging a subsequently
  accepted action, so an explicit nil cannot acquire another scene's
  representative action. Both focused regressions pass. The complete Logs suite
  passes 95/95.
- The complete Trace run initially caught a single-scene compatibility regression:
  adding scene-aware RUM baggage made a customer request with existing tracing
  headers look like an SDK-created trace, changing which RUM session baggage won.
  The handler now distinguishes pre-existing Datadog, B3 multi, B3 single, and
  W3C `traceparent` contexts. SDK-created traces use the frozen request selection;
  pre-existing traces retain the former process-context behavior. All 147 Trace
  tests now pass.
- Product clarification established that generic Resource/Trace source discovery
  is impossible once causal provenance is lost. Further expansion is paused until
  the required real-URLSession experiment matrix determines which handoff pieces
  are necessary. The [implementation plan](PLAN.md) supersedes earlier statements
  that described automatic URLSession attribution as solved.
- Actual URLSession run `da902d8a-f16e-4fa9-b82c-8dcdbaa6dc5f` produced RUM
  session `5e65abff-6999-45b2-b8ca-cf199b1b13e4` on iPadOS 26.5. Scene A used
  native session `94F798B5-7D24-4990-80BC-EFB621257719`, ApplicationLaunch view
  `f4f2c0e7-c6db-4ae6-9c41-5acacb5b1cf3`, and UIKit Home
  `1760e0e1-1fcd-4dfc-a5af-4a1f5a793917`. Scene B used native session
  `04A1C58A-6A9A-4387-9F7A-442BD29FE70A`, UIKit Home
  `6a5cc2ea-ab30-4f62-a6b8-28694dc80fd4`, and UIKit Detail 1
  `35107714-29c8-4cf6-9c53-23a34f94228f`.
- That run proves lifecycle work is not automatically scene-attributed. Intake
  stored scene A's connection request on ApplicationLaunch, but both scene B's
  connection request and scene B's Home `viewDidAppear` request on scene A Home.
  Scene B's own source markers survived, making the mismatch unambiguous. This is
  a correctness gap, not merely an unknown source in the test harness.
- Synchronous scene-B UIKit work was correctly frozen to B Home: request
  `0019d18e-4fad-441a-8439-0019762ec6e0` emitted resource
  `23df7b22-777c-4a51-a115-8ee852d1c6ef` and both its RUM Resource and APM span
  retained accepted action `45d48652-5e7f-4306-92c2-20833be6b94e`. A filtered
  action emitted the resource once on B Home with no action ID, as intended.
- A URLSession task created on B Home and resumed after navigating to B Detail 1
  resolved at resume/interception time rather than task-object creation time.
  Request `3d4bffbb-2cac-4cd0-92d4-309b1fde8591`, resource
  `ad079bd1-c1f6-4c53-a2f7-ae2990933811`, and its APM span all use Detail 1 and
  the resume tap action. This validates actual-start selection for the current
  session; session rollover before start remains a separate case.
- The first structured-task case waited 200 ms, beyond RUM's 100 ms discrete
  action timeout. Its missing action ID is therefore expected, not evidence of a
  handoff defect. The probe now separates a 20 ms suspended task that should
  retain the accepted action from a 200 ms post-expiry task that should not.
  Detached, GCD, and timer starts now wait three minutes so another scene can become
  representative before they start; the earlier run accidentally left B
  representative and could not prove their lack of provenance. A separate
  three-minute structured-Task control distinguishes inherited scene provenance
  from those source-less schedulers. A compound UIKit control also schedules
  structured work, stops the RUM session, navigates, and starts the request
  afterward. The updated probe builds successfully.
- Fresh run `8a71b04b-ee69-4670-bdb1-28a6a3625662`, initial RUM session
  `462f633d-b3fb-4fd5-83e6-bd83123187ee`, validates both structured-task action
  boundaries. Request `74b9feb7-ca7e-4669-8bd3-bac9e18b9368` produced resource
  `b04b59e6-cb2f-4795-b8dd-aa8f1cbf296c` on B Home with action
  `d9aa94f4-1a0a-4da2-96fa-35e16c6e04a5` after a yield and 20 ms suspension.
  Request `1dddb2ca-35ea-4ec4-bed7-d1465bccbdb6` produced resource
  `20428a3f-e94f-4414-8c05-e0c1875397eb` on the same view without an action after
  200 ms, as required by the 100 ms discrete-action expiry.
- The same run disproved the previous claim that explicit rollover was covered.
  Stopping the session from B Home and immediately navigating B to Detail created
  session `2df86288-72c8-43dc-ab53-7d13d70c6367` and correctly attached delayed
  request `704dfa3b-3906-48cc-a7b7-005a81d5333a` to B Detail, but did not restore
  any A view into the new session. The timeout-focused regression exercised a
  different renewal path and could not detect this explicit-stop loss.
- A new regression reproduces that exact sequence. It failed with one active view
  instead of two before the fix. Session restart now excludes only the view branch
  being replaced by the scene-targeted start/stop command, restores every other
  foreground scene, and emits a synthetic boundary update only for a restored view
  that did not already emit while processing the trigger. The new regression and
  the existing explicit-action, inactivity-timeout, and max-duration cases pass
  together, 4/4. The complete DatadogRUM suite then passed 1,005/1,005.
- Fixed live run `e03e31d3-eb19-4955-9782-1b583f37b28f` began in session
  `aeafc8d8-8c9f-4bf5-8521-e3c41063219c`. Repeating the compound control created
  explicit-stop session `29784a34-5196-4ed1-8c56-8e3337f31205`, restored A Home
  as view `42d80ad8-775b-44f2-a10f-bdea2ba50227`, and started B Detail 1 as view
  `7eb3a288-5fdf-4162-9160-09facee6bf9f`. Delayed request
  `ccbc1dbc-e6ca-4cab-af90-810efa1fcf32` produced resource
  `7c06fa6c-e61b-4e1f-be1f-e9a047ba798f` on B Detail. Console and backend raw
  intake both contain the two new-session view IDs and the correctly routed
  resource. The session reducer initially reported `view.count:1` while the
  second view update was still being reduced. After activity in restored A and
  B's scene closure, the same session document converged to `view.count:2`, chose
  A Home as its initial view, and retained two resources. This was intake lag,
  not evidence of a backend overlapping-view limitation.
- Focused reruns confirm that a timeout triggered by stopping scene A transfers
  and initializes unaffected scene B, an unscoped continuous-action stop ends
  only the representative action, and interaction in B still expires a stale
  discrete action in A. These three audit cases pass; the cross-window action-stop
  blocker remains covered by the current implementation.
- Delayed-provenance run `70ccd6cf-1514-4387-86ef-25cc255744c4`, RUM session
  `8ea9108c-3fb3-4cdf-ae76-c429348b16b0`, scheduled four requests from B Home
  (`607abb86-12db-40cc-bbbc-79e9844d3aa2`) and then made A Home
  (`a1b79f91-a04e-4118-85cc-b5d06947724d`) representative well before their
  three-minute start. Structured-task request
  `d8d0675e-717a-4649-ba3c-37a8cdc39564` retained B through suspension. Detached
  task `3fa81cb7-752d-4068-ba38-ac374fb009dc`, GCD
  `143f67c5-b01c-443d-b0ac-708e3ceaf3f0`, and timer
  `09412301-8cc8-421a-8ed3-091f3e309a03` all used representative A. Console
  payloads, all four backend RUM Resource documents, and APM aggregation by
  `_dd.view.id` agree. This is the tested automatic-attribution boundary:
  structured inheritance works; provenance lost to detached/GCD/timer scheduling
  cannot be recovered automatically.
- A custom URLSession handler experiment changed an already instrumented request
  across capture and first-party/disallow boundaries. A finalization hook could
  defend that sequence, but it added shared networking and tracing complexity for
  a developer-error case rather than a multi-scene requirement. Product guidance
  explicitly rejected that scope. The hook, header/GraphQL repair, and three tests
  were removed; the normal 43-test resource-handler suite passes. Do not repeat or
  reintroduce this defensive path without a separate networking requirement.
- iOS 27 ordering run `5ebc59df-6fc1-4620-bcb2-1177d9ab3409`, RUM session
  `d49d1cdf-5a6d-4787-af1e-1422ec841ea4`, reproduced a SwiftUI lifecycle defect in
  one scene without exercising the unstable second-window compositor path. Home
  `onAppear` resource `98da1b25-a72b-48d8-a329-b408ede05847` started before Home
  view `31882973-7e07-4793-b097-df4d2c5fb3fb` and landed on preceding UIKit Home
  `91657525-5add-4f00-bc18-122bc7b0fe4c`. Detail resource
  `07c002bd-9483-4e21-9e02-a342949f9f3c` likewise started before Detail view
  `b4e265a6-fc43-4d24-b625-960d2cd9a85e` and landed on SwiftUI Home. Both delayed
  `.task` requests started after their views and were correct; that did not test
  the synchronous prefix because the probe yielded and slept first.
- The next SwiftUI experiment reported the destination window in
  `willMove(toWindow:)`, retained lifecycle identity in reference-backed state,
  and treated detachment separately from an attached legacy window with no
  scene. Seven initial state/observer tests passed, but rebuilt runtime evidence disproved
  the ordering hypothesis. Run `fd44bcd2-cde3-4488-a9f4-7756683d85f4`, RUM
  session `dab21bf2-8fee-406a-bd84-81b7211e934e`, attributed Home `.onAppear`
  resource `aab3afbb-e0dc-4264-bc1a-aa15080866da` and immediate `.task`
  resource `6f559479-5459-4df0-87ab-9b0a68949581` to preceding UIKit Home
  `baecfe4b-20cc-435f-94f2-806629ffe2ea`. Detail `.onAppear` resource
  `833d9ae6-3467-4d0d-9add-2df5733e7807` and immediate `.task` resource
  `408f5be9-8c28-4683-b395-bbfa1f1e2f0d` similarly landed on preceding SwiftUI
  Home `efff3c99-ad99-475c-b39d-4158f8458be0`. Only the delayed `.task`
  resources were correct. Navigation also emitted backend-indexed duplicate Home
  view `00d24725-3925-4990-9e1c-57fc9d3d92ad` for 791,907 ns before Detail.
  This hook is an attachment detector, not an appearance-ordering fix. The state
  machine now ignores transient detach/reattach in the same scene, migrates only
  when a different scene resolves, and stops the original owner on disappearance;
  ten focused lifecycle tests pass and rebuilt runtime verification is pending.
- A follow-up child-controller experiment tried to obtain scene attachment from
  `UIViewControllerRepresentable.viewWillAppear`. Run
  `16e48aa6-6826-49ea-b764-6c0af6f16c0b`, RUM session
  `c8c5b90c-ef71-4bbe-842a-fa22ed5587fd`, disproved that path as well. Home
  `.onAppear` resource `4da8eaa8-56e2-4890-b6ec-6a8eb2ab8b4e` and immediate
  `.task` resource `d2b8ab05-e7ad-4683-b395-bbfa1f1e2f0d` preceded SwiftUI Home
  by 35/34 ms and landed on UIKit Home. Detail equivalents
  `717b1d98-5b5b-45e2-98eb-d76080d7c781` and
  `d1326f13-5890-4a92-a9ee-01f853f8b6fa` preceded Detail by 5/4 ms and landed
  on SwiftUI Home. Delayed tasks remained correct. The run emitted exactly four
  expected views, no duplicate/helper view, zero RUM errors or crashes, and
  accepted Session Replay uploads. The controller and its UIKit exclusion were
  removed because they added overhead without improving ordering.
- The scene-only SwiftUI reader and UI-event causal swizzle are now gated by the
  configured bundle's `UIApplicationSupportsMultipleScenes` value. Ordinary
  apps use the original modifier lifecycle and action-only dispatch path. Ten
  lifecycle tests plus four gating/handoff regressions pass; the complete RUM
  suite passes 1,018/1,018. The `RUM MultiScene Probe` then rebuilt successfully
  through Xcode in 14.997 seconds.

### 2026-09-12 — Checkpoint review cleanup

- An independent diff review found that the extra UI-event causal handoff still
  ran when an ordinary app enabled automatic action tracking. The handler now
  scopes downstream work only when the configured app declares multi-scene
  support; ordinary action tracking retains its original publish-then-dispatch
  behavior. A direct regression test covers this boundary.
- The request-local handoff's four thread-dictionary keys and exact-nil decoding
  had been reconstructed in RUM, Internal, Logs, and Trace. `DatadogInternal` now
  owns that private SPI contract and restores nested values; all consumers read
  one coherent snapshot.
- Feature-operation API commands now consume a known handoff scene, and the
  session scope resolves that scene before recording operation start ownership.
  Tests prove a scene-A operation does not start on representative scene B and
  continues on scene A after navigation.
- The review rejected substituting representative-session baggage when a request
  already contains customer trace headers. Removing all existing-header handling
  initially broke the established no-header-mutation test, so the final behavior
  keeps that compatibility boundary without representative fallback: it adds no
  RUM session baggage to a pre-traced request while retaining the source-scene RUM
  context for the local span.
- Added an iOS 17+/visionOS 1+ scene trait publisher for apps declaring multiple
  scenes. It seeds `UIWindowScene.traitOverrides` with the real persistent scene
  identifier and bridges that private trait into SwiftUI. Ordinary apps do not
  construct the publisher; iOS 15/16 continue through the attachment-backed path.
  Three focused activation/value tests and ten existing lifecycle-state tests pass.
- First trait run `68786559-42b4-4087-8e34-997e77d081c5`, RUM session
  `799d975d-9597-4b2e-9c4e-833835aed5de`, started SwiftUI Home after customer
  `.onAppear`/immediate `.task` by 35/34 ms and Detail by 2/1 ms. Unlike the
  attachment-only and child-controller runs, all six resulting URLSession
  resources were ultimately indexed on their correct Home or Detail view. The
  source Home navigation action also remained correct, and intake reported zero
  errors/crashes with Session Replay present.
- Second trait run `92326a81-441e-48b9-97b3-3db2b00bc3ab`, RUM session
  `4bd7fa85-dda2-4712-9cce-33cb23f73a3c`, used
  `onChange(of:initial:)` as the earliest supported lifecycle callback. Home
  outer `.onAppear` and immediate `.task` still preceded the RUM view by 2.825 ms
  and 2.222 ms; Detail preceded it by 3.468 ms and 2.696 ms. The later modifier
  tasks ran about 100 ms after their views. Datadog intake again contains all six
  resources on the correct views, the navigation action on source Home, four
  expected views, and a session with zero errors/crashes. This narrows but does
  not eliminate the ordering gap.
- Synchronous-action run `c77883d4-80fe-4730-a3ff-575221a3c262`, RUM session
  `67fdbd11-1d6a-440d-afd0-db11ff6bc6c4`, temporarily invoked custom RUM actions
  at the beginning of customer outer `.onAppear` and immediate `.task`. The four
  invocations preceded their Home/Detail view payloads by 0.292-4.128 ms, but the
  serial RUM queue processed the view transitions first. All four actions were
  emitted once on their intended new views; the navigation action stayed on
  source Home, all six lifecycle resources were correct, and Datadog intake
  reports five actions with zero errors/crashes. The probe-only actions were then
  removed to avoid perturbing the broader interaction matrix.
- The complete post-trait `DatadogRUM` suite passed 1,020/1,020 on the iOS 27
  simulator. This supersedes the 13-test focused checkpoint while retaining
  1,018/1,018 as the pre-trait baseline.

### 2026-09-12 — Broad fixed-runtime matrix and scene teardown

- Run `91864fb5-cace-4f29-a348-5769bf2ffa65`, RUM session
  `02b150f8-3b2f-43fd-b032-8cac2ef91cd9`, produced 46 events: 9 views,
  16 actions, 14 resources, 2 long tasks, zero errors/crashes, and replay. A
  SwiftUI scene-B operation and manual resource retained B Detail while scene C
  opened. Scene C connection and initial lifecycle resources landed on the
  previous representative B Detail because they began before C's first RUM view;
  this is the approved source-less fallback boundary, not a header-injection
  defect.
- Run `31d0a951-095a-4a71-8c48-b6e4fb4d0af2`, RUM session
  `3160c14e-95d7-4a0e-a40b-204060cfae45`, proved UIKit modal
  presentation/dismissal and duplicate-name A/B views remain independent. The
  first delayed switch result was invalid because the scrolled control tree was
  stale. Both UIKit and SwiftUI probe screens now expose fixed Close and Other
  Window toolbar controls so switching and teardown do not depend on scroll
  position. SwiftUI uses the non-deprecated `.topBarLeading` and
  `.topBarTrailing` placements.
- Run `76599137-09c8-4fb1-b54a-92b3c9ff04d1`, RUM session
  `725418d9-aae5-4570-8bd0-1bad452bbb8c`, repeated the delayed UIKit flow with
  the fixed controls. The B Home trace and operation kept B ownership while A
  became active. APM trace `6aa50e250000000095c6c6caacd03265` retained resource
  `probe-span-scene-B` and the B source view.
- Broad run `972c83f7-9c13-4ea3-b5b6-d43857bb7815`, RUM session
  `3a8b0c3b-53e4-4426-b4b1-12e92ec715d5`, reached 18 views, 17 actions,
  33 resources, 4 long tasks, zero errors/crashes, and replay. UIKit and SwiftUI
  modal/dismiss flows, duplicate-name views, SwiftUI scroll, delayed resources,
  and origin-scene closure retained their source windows. UIKit trace
  `6aa50f23000000001829c0dfb272bbb9` and SwiftUI trace
  `6aa5128c0000000048ed46829eb03478` retained their destroyed source scenes.
- Closing a nested SwiftUI scene D caused customer `.onAppear` and `.task`
  callbacks to run again after its tracked view stopped; three lifecycle requests
  then used the Background representative. Closing another SwiftUI scene from
  Home did not reproduce it. The callbacks no longer expose a public source-scene
  identity once detached, so tombstoning them in the SDK would risk dropping
  legitimate work. Keep this as a targeted teardown/restoration experiment rather
  than inferring a fix from one nested callback sequence.
- The broad run exposed a distinct operation defect. Raw start vitals for UIKit B
  key `5EC831AF-0135-4AE6-B74A-088B292787BE` and SwiftUI E key
  `EC54293B-2ED0-4D97-8C89-B308FCE020BC` reached intake on their correct source
  views, but no end vital arrived and no reduced operation existed. The manager
  deliberately selected no active view after the owner scene closed; a null-view
  end step was therefore not sufficient to preserve the operation.
- The teardown fix made `RUMFeatureOperationManager` retain a lightweight last-
  proven view ID, name, and path. Its first implementation followed the start
  scene's current view, refreshed after navigation there, and used the snapshot
  after teardown. This proved that a stopped view need not be retained or
  resurrected. The later cross-window contract keeps the snapshot mechanism but
  removes permanent start-scene ownership: every trustworthy step can replace it,
  including a step in another scene. The original 17 manager tests passed; the
  superseding focused Operations set now passes 98/98 across manager and session
  scope.
- Post-fix run `c8d2aa31-127a-4d4c-a910-8e56eea5fb48`, RUM session
  `6c05508c-18fc-41df-85e8-32c573fbf37e`, used one ordered HID batch to start
  operation key `206E691E-33AC-4BF1-8D26-E48D81315D9A` in UIKit scene D and
  close D one second later. Intake contains start at `09:31:59.034Z` and end at
  `09:32:02.184Z`, both on D Home view
  `547eb0b9-5743-47f7-ab07-c309e5b5bb29`. The reducer created one successful
  3.15-second operation whose start and end views are that same D view. The final
  session contains 8 resources, 8 views, 7 actions, 3 vitals, 1 long task,
  1 operation, and 1 session; replay is available.
- The first complete command-line RUM rerun reported one timing-sensitive failure
  in the unrelated timeseries pause test: its pause flush increased the event
  count from two to three. Xcode then spent several minutes collecting simulator
  diagnostics, so that run was interrupted after all 980 XCTest cases had
  otherwise completed. The exact test immediately passed 1/1 through Xcode MCP.
  A fresh complete Xcode MCP run then passed 1,022/1,022 with zero failures,
  skips, or tests not run. The generic iOS `Datadog-Package` Swift Package build
  also succeeded through Xcode 27 and restored the temporarily hidden workspace.
  Repository lint and `git diff --check` are clean.

### 2026-09-12 — Goal-backward review

- At this checkpoint, auditing the probe against the original objective found
  that all SwiftUI runtime view evidence used explicit `.trackRUMView`;
  `swiftUIViewsPredicate` was disabled and SwiftUI was hosted by the runner's
  UIKit scene delegate. That gap was promoted to P0 and has since been exercised
  in both automatic UIKit-hosted and native `WindowGroup` runs. Both now provide
  failing baselines rather than being silently included in the support claim.
- The accepted “last-interacted” fallback currently means the RUM process
  representative. A predicate-filtered touch supplies scene provenance to work
  executed inside dispatch but emits no interaction command that would necessarily
  advance the later representative. No focused post-dispatch manual-API experiment
  has been run; it is now an explicit edge rather than an assumed guarantee.
- The explicit-session-stop experiment already proved raw intake and the backend
  session reducer accept overlapping scene views: the reducer converged to
  `view.count:2`. At this checkpoint, product UI presentation and analytics
  semantics were still open. The later approved direction makes Window Execution
  Context visualization follow-up work: the SDK must preserve internal scene
  ownership now without adding a temporary serialized window concept.
- Operation teardown is fixed for unique identities. The later contract decision
  confirms that local and backend identity intentionally omit scene. Focused tests
  now validate duplicate `(name, key)` starts, parallel distinct keys, reverse
  completion, and cross-window view changes; live backend validation remains.
- The remaining downstream runtime plan requires probe work first. The current
  logger control emits `.info` rather than a mirrored RUM error, and there are no
  WebView, split-navigation, restoration, fatal-context, or exported-context
  controls. The shared-request helper is one-shot, and “Other Window” is ambiguous
  once more than two sessions exist.

### 2026-09-12 — Automatic SwiftUI tracking baseline

- The existing probe now selects between its previous explicit `.trackRUMView`
  behavior and `DefaultSwiftUIRUMViewsPredicate` with
  `DD_MULTI_SCENE_SWIFTUI_VIEW_TRACKING`. Manual remains the default, so all prior
  runs and ordinary probe launches keep their previous behavior. The automatic
  variant removes only the explicit view modifier; action tracking and the same
  UIKit scene delegate remain enabled. Xcode 27 rebuilt the probe successfully on
  the iPadOS 26.5 destination.
- Control run `0b5749cf-e4fd-4bd5-a3e8-4789d3ee6d97`, session
  `cc9e9e0c-1f85-401b-9f33-ba66843b9e50`, launched the same binary with manual
  mode. Explicit tracking created `SwiftUI scene-A Home`
  `63b52dac-d854-498e-951b-137d59eef48e` before the three lifecycle requests
  completed. All three resources use that view in the backend, with no transient
  automatic root. The session has 12 events, zero errors/crashes, and replay.
- Automatic run `76f40f1f-554f-4842-86a1-7bf4955b734c`, RUM session
  `ae9530b4-4117-4895-a1fe-7442a160e76f`, reproduced the same ordering in both
  scenes. Scene A's three SwiftUI Home lifecycle requests first completed on UIKit
  Home `7b1be550-1311-4017-8813-65847a2182da`; only afterward did automatic
  tracking emit transient root `2d15f54c-b6ce-4793-9526-0bfe2591e1ef` and active
  navigation host `9c37bebb-d4b7-4519-bf52-42c069dd2962`. Scene B repeated that
  sequence from UIKit Home `95668237-673d-4e11-ac71-d65b61d3c418` through root
  `8b52edfa-4d51-414e-b05d-c46693dc5a1b` to navigation host
  `6a1e9fac-d2e6-4e95-9f1c-2bded75541d2`.
- SwiftUI detail navigation makes the semantic defect more direct. Scene B's
  `.onAppear`, immediate `.task`, and task-modifier resources all completed on its
  source navigation host `6a1e9fac-d2e6-4e95-9f1c-2bded75541d2`. The tap action
  was also correctly attributed there, then the tracker emitted transient root
  `a67ddc8d-d3e2-4b36-99b4-cdff41b65863` and final Detail
  `9887bd8a-e850-44bc-8a1e-d256bb4a7102`. Scene A repeated the same sequence from
  reactivated host `01f5d769-4732-4e17-96d9-21b5ba5f4333` through transient root
  `cec5e006-88c0-4c50-b7f3-66885ababe77` to Detail
  `61cfefe2-5848-4da6-bc10-b4a972e689be`.
- Alternating scenes did not cross their view branches. Reactivating scene B
  created Detail view `56acd446-462b-4188-a6ca-e553b82c2be5` and stopped only A's
  current Detail. Closing B stopped only that B view. Three SwiftUI lifecycle
  callbacks then ran again after detachment and their resources used Background
  view `8941267e-f589-407f-b65f-3148e17390d3`, never scene A. This matches the
  earlier nested-close observation and remains a teardown/restoration edge, not a
  reason to guess another scene.
- Datadog lookup initially failed during a local Wi-Fi interruption and succeeded
  on retry. Exact-session intake confirms the console's view IDs, source-scene
  actions, preceding-view resources, transient roots, and final destinations.
  The session reports zero crashes and Session Replay available. The Stage Manager
  arrangement displayed one probe window at a time and returned to SpringBoard
  after closing B, so this run does not replace the broader simultaneous-window
  evidence and does not establish automatic behavior in a native SwiftUI app.
- Target-runtime run `5c807364-100d-44b1-8d35-9d5cfd802fc5`, session
  `2133b271-2079-4d9c-b570-fcea81e1f062`, repeated Home -> Detail on an iPadOS 27
  simulator without opening a second window. Home `.onAppear` and immediate
  `.task` resources stayed on UIKit Home
  `4f32626f-0467-4567-a19c-d9e7d392d776`; the delayed task-modifier resource used
  final navigation host `d1c35ad8-3bc7-4faa-93fe-c37eb3d3b4cc`. On Detail, all
  three lifecycle resources and action `b469f984-051b-4784-a543-a429668b7164`
  stayed on that source host. Automatic tracking then emitted transient root
  `82f273ff-f75e-46bb-bc4d-4c1e560a4e22` and final Detail
  `f0b78f55-f0ca-46a0-a330-9391df1d6fa9`. Backend intake contains 21 events,
  including six views, eight resources, one action, zero errors/crashes, and
  replay. This establishes target-OS relevance without invoking the known
  second-window compositor failure.
- A narrowly gated follow-up temporarily intercepted
  `UIViewController.viewIsAppearing` only for iOS 27 multi-scene applications
  with automatic SwiftUI view tracking. Three focused tests and then both full
  `RUMInstrumentationTests`/`RUMViewsHandlerTests` classes passed (53/53). The
  integration probe also built successfully and the full linter reported zero
  violations. This established that the candidate composed with the current
  swizzler and preserved UIKit-predicate precedence; it did not establish useful
  runtime ordering.
- Rejected run `13e39eae-ccc8-47a6-8125-3f52fab589b8`, session
  `092c7b63-661e-4f8c-a8ff-b21b92665c96`, measured the actual ordering on iPadOS
  27. Home `.onAppear` ran at `14:52:12.666749` and immediate `.task` at
  `14:52:12.667454`; the transient root did not start until
  `14:52:12.736296`, followed by the navigation host at `14:52:12.740000`.
  Those first two resources remained on UIKit Home; only the delayed task used
  the navigation host.
- On Detail, `.onAppear` ran at `14:52:44.169378`, immediate `.task` at
  `14:52:44.169823`, and the delayed task at `14:52:44.275860`. All three
  resources remained on source navigation host
  `eef201a0-ae06-4a0b-a4da-849aebd8b605`. The source view stopped only at
  `14:52:44.683788`; transient root
  `2d7bfd77-fc7f-41b4-8f5b-2e9a246bad57` followed, and final destination
  `0eda31f6-317d-4905-b1f0-a5bee6495b2d` started at
  `14:52:44.684773`, about 515 ms after destination `.onAppear`. Backend intake
  matches the console IDs and attribution. A later manual action and three-second
  resource correctly used the final view, uploads returned HTTP 202, replay was
  available, and no crash occurred.
- Because the added lifecycle interception neither advanced view discovery nor
  removed the transient root, all candidate production and test changes were
  removed. This is a completed negative experiment, not pending implementation.
- Conclusion: the branch's scene-keyed routing also works for controllers found by
  automatic SwiftUI tracking, but automatic view creation/navigation itself does
  not yet meet the objective. Its destination appears too late for lifecycle work
  and the extra root view makes the backend navigation chain noisy. Treat these as
  a general automatic-tracking semantic defect exposed by the multi-scene matrix,
  separate from cross-scene owner selection.

### 2026-09-12 — Cross-window RUM Operations contract

- The operation identity decision is now explicit: exact `(name, operationKey)`
  is application-wide and scenes never namespace it. Parallel same-name instances
  require unique opaque keys and every step for one instance must reuse the same
  tuple.
- The prior permanent start-scene rule was removed. Every start, update, retry,
  success, and failure now resolves a trustworthy call-site target independently.
  A resolved target refreshes the operation's retained last-proven view snapshot;
  an unresolved or source-less later step uses that snapshot before falling back
  to the process representative. The snapshot remains lightweight and cannot
  reactivate or update a stopped view scope.
- Starting the same identity twice emits both requested start vitals, logs that
  only the latest is tracked locally, and does not synthesize an end. One later
  success or failure ends the latest instance. The warning explains that the
  earlier backend operation remains open until its four-hour timeout and
  recommends a unique `operationKey`.
- The Operations-focused Xcode run passed 98/98: 26 manager tests and 72 session-
  scope tests. Coverage includes A start/B success, A start/B failure, A1 -> A2,
  parallel same-name/different-key instances, reverse completion, a trustworthy B
  step overriding the stored A snapshot, explicit scene targeting overriding an
  incorrect process representative, closed-scene snapshot fallback, explicit B
  completion after A closes, duplicate starts with no synthetic end, typed-
  identity collision resistance, legacy/source-less compatibility, and the
  process-representative fallback when a target cannot resolve and no snapshot
  exists.
- The complete post-change `DatadogRUM` Xcode run passed 1,033/1,033 with zero
  failures, skips, expected failures, or tests not run. Its result bundle is
  `Test-DatadogRUM-2026.09.12_15-56-14-+0200.xcresult`.
- A downstream identity audit found that both Profiling implementations still
  indexed operation messages with `"\(name)-\(operationKey)"`. Commit
  `ac90b5865` replaces those string keys with an exact typed tuple and tests both
  a delimiter collision and omitted-versus-empty keys. The first build exposed
  one stale `[String: Vital]` helper annotation; after correcting it, the
  complete `DatadogProfiling` scheme passed 233/233 and repository lint passed
  with zero violations. Do not restore delimiter-based correlation.
- Public API was not added speculatively. The
  [Operations proposal](OPERATIONS.md) supports inferred
  behavior, current view in a `UIWindowScene`, manual view key plus scene, and a
  tracked `UIViewController` without exposing RUM UUIDs. The review established
  that explicit and inferred candidates must remain separate, that additive
  extension-only overloads avoid changing protocol witness requirements, and
  that the `view` argument must remain required to avoid overload ambiguity.
  The later product direction fixed the duplicate-start behavior and the
  four-hour orphaned-operation warning. API review is still required for the
  scene-targeted manual-key prerequisite and final public type/selectors.
- The probe now has fixed UIKit and SwiftUI controls to start/duplicate-start,
  succeed, or
  fail one app-scoped cross-window key. It built and launched on the stable iPadOS
  26.5 simulator as probe run `c28442df-d11a-456b-9ca7-1ffe13bad483`, RUM session
  `722d9a8b-5a00-4ab7-8d02-e609baaf7bb3`. The Mac GUI was locked: the accessibility
  tree exposed the controls, but injected taps did not invoke them. This launch is
  setup evidence only, not an A-to-B runtime pass. Resume the same three flows
  after unlock rather than interpreting the inactive controls or retrying HID.
- After the reported Wi-Fi failure cleared, a fresh Datadog query for run
  `c8d2aa31-127a-4d4c-a910-8e56eea5fb48` again returned both raw operation-step
  vitals and the reduced success in session
  `6c05508c-18fc-41df-85e8-32c573fbf37e`. The reduced duration is 3.15 seconds;
  start and end both reference scene D view
  `547eb0b9-5743-47f7-ab07-c309e5b5bb29`. This revalidates connector access and
  the teardown proof only; it is not the pending A-to-B experiment.

### 2026-09-12 — Rejected base-`viewWillAppear` SwiftUI experiment

- Apple's lifecycle contract places `viewWillAppear` before UIKit adds the view
  to the hierarchy, so an owning `windowScene` is not generally available there.
  An iPadOS 27 LLDB run nevertheless found the exact
  `RUMSceneIdentifierTrait` on both the outer `UIHostingController` and inner
  `NavigationStackHostingController` at the base implementation entry. The outer
  controller's parent was already attached to the scene window; the inner
  controller and its parent were not. This establishes the trait as the reliable
  early scene input, with attached ancestry as a useful secondary source.
- A candidate optionally intercepted base `UIViewController.viewWillAppear` only
  for iOS 17+/visionOS 1+ declared multi-scene apps with automatic SwiftUI view
  tracking. It used the trait, attached ancestry, or a presenting controller to
  resolve scene ownership, preserved UIKit predicate precedence, and fell back to
  the established `viewDidAppear` path when early discovery was unavailable.
  Focused tests covered early start/deduplication, unresolved-scene fallback,
  predicate precedence, and swizzler ordering.
- Probe run `b4bbfa9a-3094-4345-b64e-bb1728bec061` used automatic tracking and
  launch-controlled Home -> Detail navigation on the iPadOS 27 simulator. The
  Home `.onAppear` and immediate `.task` resources still resolved to
  `ApplicationLaunch` view `802783a4-2384-4da5-b9b3-162738a85487`; the delayed
  Home task used navigation host `7f2ca0fc-31fe-4902-bafb-7a7029b2758c`. On
  Detail, `.onAppear`, immediate `.task`, and delayed `.task` also used
  `7f2ca0fc-31fe-4902-bafb-7a7029b2758c`. The repeated class name initially looked
  promising, but the exact ID proves it was still the Home/source view, not a new
  destination view.
- Datadog intake for session `ae51b4e7-c88b-4413-98bb-455f93c38dd6` agrees:
  17 events, 5 views, 7 resources, zero errors/crashes, and Session Replay
  available. It retains short-lived outer-root views
  `7e66ee40-e4d4-4dd5-ad84-a1ba270cd0f5` and
  `87f53c3f-ba5a-4158-b9cf-373933f2915e`, so view identity/noise remains an open
  part of the P0.
- A follow-up moved notification from immediately before to immediately after the
  base implementation while remaining inside the subclass's `super` call. Run
  `20462f01-45d6-4838-9102-151467c4c47f`, session
  `da12ef5f-539e-4821-afa9-c2814e63be91`, produced the same exact-ID result:
  Home lifecycle work used `ApplicationLaunch`, and the delayed Home task plus
  all three Detail resources used Home host
  `445ec932-6eb3-49bf-a25b-aff6bacbc29a`. Intake contains 16 events, 5 views,
  7 resources, zero errors/crashes, and replay.
- Before removal, four focused handler/instrumentation tests and all three
  swizzler tests passed. The candidate build completed, the temporary full RUM
  run passed 1,037/1,037 including the four candidate tests, and the repository
  linter reported zero violations. These prove composition, not semantic value.
  The full `DatadogCore` scheme was not a clean baseline on this iOS 27 simulator:
  813 passed, 3 skipped, and 3 unrelated tests failed.
  `BrightnessLevelPublisherTests/testMultipleBrightnessChanges()` crashed,
  `CrashReportReceiverTests/testReceiveCrashAndViewEvent()` rejected its fixture,
  and `TracingURLSessionHandlerTests/testGivenAllTracingHeaderTypes_itUsesTheSameIds()`
  observed a baggage session-ID mismatch. Each failure reproduced when run alone.
- Exact backend IDs showed no destination improvement, so the production hook,
  protocol method, mocks, and candidate tests were removed. A real NavigationLink
  tap was attempted as a final differentiator in run
  `fb857d2d-450a-4e80-993c-c57e6b72be19`, session
  `1e97266b-253a-4141-9cf0-37399e071040`, but Xcode device interaction held a
  stale session and CUA confirmed that the Mac was locked. No tap occurred; the
  launch-controlled state transition is the completed evidence for this
  candidate, while a physical post-fix tap remains part of any future distinct
  implementation's validation.
- After removal, the integration probe rebuilt successfully and the complete
  `DatadogRUM` scheme returned to its current 1,033/1,033 pass. The final scoped
  diff has no production lifecycle hook or candidate test residue.
- The probe retains the opt-in
  `DD_MULTI_SCENE_AUTORUN_SWIFTUI_DETAIL=1` capability and starts on its SwiftUI
  tab in automatic mode. The temporary automatic/autorun values were removed
  from the shared scheme after the run.
- This checkpoint's next step was a native `WindowGroup`/`openWindow` exact-ID
  comparison. That work is complete in the two following experiments and no
  longer remains a pending plan item.

### 2026-09-12 — Native SwiftUI `WindowGroup` baseline

- Added an isolated iOS 27 app in `Datadog/Example/MultiSceneProbe` instead of
  changing the already-dirty main `Datadog.xcodeproj`. XcodeGen links the local
  `DatadogCore` and `DatadogRUM` package products and reads the existing token and
  application-ID build settings through `xcconfigs/Datadog.xcconfig`; no secret
  value is copied into the probe. The native `@main App` declares a typed
  `WindowGroup`, bound `NavigationStack`, and deterministic `openWindow` flow.
- The first generated build inherited the SDK's iOS 15 deployment target from the
  shared xcconfig despite XcodeGen's target declaration. Adding an explicit target
  `IPHONEOS_DEPLOYMENT_TARGET = 27.0` fixed availability checking. The next build
  showed that Xcode 27 supplies a non-optional typed-window binding when
  `defaultValue` is present; removing the stale optional unwrap fixed it. The
  third Xcode MCP build succeeded against the iPadOS 27 SDK. Preserve both project
  settings when regenerating instead of repeating those compiler failures.
- Every Home and Detail lifecycle phase emits one synchronous custom action and
  one 50 ms manual resource with run, logical scene, native scene, screen, phase,
  and monotonic-time attributes. Event mappers print the exact RUM session and
  view IDs. The probe's own hidden `UIViewRepresentable` still reported
  `unresolved` during Home `.onAppear` and immediate `.task`, then resolved the
  real scene session before navigation. This independently demonstrates why an
  attachment reader cannot be the early automatic source.
- Two-window run `native-swiftui-20260912171529` opened scene B without a tap.
  Scene A native session `69412B88-C4BC-4A9C-A7CB-484C166BACA6` and scene B
  native session `1F1874F2-6843-4AE8-AAA9-83E138C8E3A2` were distinct. B Home
  `.onAppear` and immediate `.task` nevertheless emitted on A's final Detail RUM
  view `b33cbe9a-4613-4327-9e2f-a6ceadba5896`; B's navigation host appeared only
  afterward. The final B `ProbeDetailView` also appeared after all three Detail
  phases. This is a real cross-window semantic failure, not only a naming issue.
- After uninstalling the probe to clear restored window state, single-window run
  `native-single-20260912171659` reproduced the generic ordering without scene B.
  Home `.onAppear` and immediate `.task` used `ApplicationLaunch`; delayed Home
  and all Detail phases used the preceding navigation host. No automatic
  `ProbeHomeView` was emitted, and final `ProbeDetailView` started after its three
  lifecycle phases. The automatic tracker therefore observes controller identity
  after the semantic SwiftUI transition, even in a native lifecycle.
- Backend query `@context.probe.run_id:<run-id>` matched console attribution
  exactly. The single-window session retained 6 actions and 6 resources in the
  six expected wrong-view buckets. The two-window session retained 12 actions and
  12 resources; both B Home early phases use A Detail, while B delayed Home and
  Detail use B's navigation host. View aggregation found 5 documents for the
  single-window run and 9 for the two-window run, including 2 and 4 transient
  `AutoTracked_HostingController_Fallback` views respectively. View documents
  report zero errors and crashes. Session Replay was intentionally not linked;
  its crash-free requirement already has separate two-window proof.
- This completes the native-lifecycle experiment requested by the plan and rules
  out the Runner's UIKit scene delegate as the cause. Do not add another
  `UIViewController` appearance hook. Continue from supported SwiftUI view/name
  publication on iOS 27 or an explicit root/navigation integration subject to
  normal public API review.

### 2026-09-12 — Native SwiftUI lifecycle and reflection inspection

Experiment `lldb-native-lifecycle-20260912` is local runtime/LLDB evidence only.
It did not change SDK code, emit a distinct backend dataset, or validate payload
attribution. It completed both Home and Detail portions of the inspection against
the standalone iOS 27 `WindowGroup` probe.

- At the generic root `UIHostingController` base `viewWillAppear` entry, its
  navigation title was nil and `childViewControllers` was empty. The application
  already had a connected foreground `UIWindowScene` and window, but the probe's
  child `UIViewRepresentable` still exposed `unresolved` scene identity.
- `ProbeHomeView.onAppear` ran next. At that exact breakpoint the root still had
  no child controller, and the current reflection extractor returned
  `AutoTracked_HostingController_Fallback` for the generic root type.
- `UIKitNavigationController.viewWillAppear` ran only after Home `.onAppear`.
  `NavigationStackHostingController<AnyView>.viewWillAppear` followed with the
  correct `scene-A: Home` navigation title. A breakpoint at the public
  `UIHostingController.viewWillAppear` implementation entry also occurred after
  Home `.onAppear`, so intercepting that override would not repair the ordering.
- On the real Home-to-Detail tap, `ProbeDetailView.onAppear` fired before either
  `UIHostingController.viewWillAppear` or the base UIKit implementation. At the
  callback, the navigation controller already held two hosting controllers and
  its top controller had the correct `scene-A: Detail` title. The SDK had no
  earlier public controller lifecycle callback through which to observe it.
- After Detail `.onAppear` emitted its marker, the direct
  `UIHostingController.viewWillAppear` entry fired for the destination and still
  carried the correct Detail title; the base UIKit callback followed later. This
  completes the previously pending Detail-navigation portion.
- The iOS 27 reflected `NavigationStackHostingController<AnyView>` structure no
  longer has the existing `content.list.item.type` path. Its `content.list`
  contains `elements`, `implicitID`, `traitKeys`, and `traits`.
  `elements.body.viewType` resolves to
  `NavigationDestinationModifier<ProbeRoute, ProbeDetailView>.Type` while Home
  is visible. It exposes the registered destination type, not the active screen,
  and would falsely create Detail at launch.

Conclusion: the failure is an observation and semantic-identity boundary, not a
missing scene token or a one-segment reflection update. Do not use navigation
titles as customer view names, replace the old path with `elements.body.viewType`,
or add another controller appearance swizzle. The next distinct path is a
reviewed semantic root/navigation integration for automatic tracking that knows
application semantics before customer lifecycle work.

### 2026-09-12 — Explicit SwiftUI early-mount candidate

The native probe gained an `automatic`/`manual` switch. Manual mode disables
`DefaultSwiftUIRUMViewsPredicate` and applies the existing public
`.trackRUMView` modifier to semantic Home and Detail roots. It also has a
`tab-preload` stress layout with an explicitly tracked but initially unselected
tab. These controls isolate explicit tracking from the still-failing automatic
tracker without changing the public SDK API.

Two unchanged-SDK controls first disproved modifier placement as a solution:

- In `EXP-030`, placing `.trackRUMView` inside each screen left Detail
  `.onAppear` and immediate `.task` work on Home. Only delayed Detail work used
  the Detail view.
- In `EXP-031`, wrapping the fully constructed screen made initial Home worse:
  its early work used `ApplicationLaunch`, while Detail's early work still used
  Home. Moving the same modifier around the view tree therefore does not create
  a reliable ordering boundary.

The candidate passes the scene identifier already bridged from the hosting
`UIWindowScene` into the hidden `UIViewRepresentable`. On iOS 27 only, creation
of that platform reader marks the explicitly tracked RUM state as mounted and
enqueues the semantic view start before later SwiftUI lifecycle callbacks. The
existing attachment callbacks still correct a changed scene, and the ordinary
`onAppear`/`onDisappear` path remains idempotent. The early behavior is disabled
on iOS 15-26, on visionOS, and for applications that do not declare multiple
scenes. This is an internal implementation change to `.trackRUMView`, not a new
public API and not a change to automatic view discovery.

`EXP-032` was the first single-window proof. Although the Detail lifecycle log
preceded its mapped view payload by about 2.8 ms, source ordering plus the exact
final attribution indicate that the start command reached RUM's serial queue
before the customer work. Queue-entry instrumentation was not captured. All 12
lifecycle markers resolved to the exact Home or Detail UUID, with no fallback.

`EXP-033` repeated the complete A/B flow three times after clean uninstall. Each
run emitted exactly four semantic views plus `ApplicationLaunch` and exactly 24
lifecycle markers. Across the 72 action/resource records, every combination of
scene A/B, Home/Detail, on-appear/immediate/delayed, and action/resource appeared
once on its intended UUID. Device mapper output and backend aggregation agree;
there were no duplicate or fallback semantic views and no SwiftUI warning,
crash, or hang. All three exercised behavior-equivalent candidate code; the third
alone exercised the final iOS 27 availability gate.

`EXP-038` then repeated that final-gated revision twice after clean uninstall.
Sessions `0fa4998d-4c39-4674-ac70-8dc91702fac9` and
`683e6b94-efbc-4ff3-a865-8ee46915f9d3` each contained exactly five backend views,
12 lifecycle actions, and 12 lifecycle resources. Every A/B Home/Detail phase
appeared once on its exact semantic UUID, no marker used `ApplicationLaunch`, and
no fallback or duplicate semantic view appeared. Both runs ended with scene A and
B concurrently on Detail and remained running without an SDK/SwiftUI warning,
crash, or hang. Together with the third `EXP-033` run, this is the required three
clean repetitions of the final availability-gated implementation: 72/72 exact
markers. Across all five behavior-equivalent A/B candidate runs, 120/120 markers
were exact.

The construction-versus-appearance risk was then tested rather than assumed:

- `EXP-034` left a registered Detail destination dormant. No Detail RUM view or
  lifecycle marker existed locally or in backend intake.
- `EXP-035` performed three complete push/pop cycles. RUM correctly emitted
  seven distinct occurrences in the exact navigation path
  `Home → Detail → Home → Detail → Home → Detail → Home`, with strict
  stop-before-start ordering. SwiftUI retained the Home view's state, but that
  does not collapse the RUM history: a RUM view represents each navigation
  occurrence, not the lifetime of a platform object. Each return created a new
  Home UUID rather than resuming the prior Home occurrence.
- `EXP-036` left a second tab unselected. Neither its content `onAppear` nor a
  `ProbeOffscreenTabView` RUM event occurred. This particular `TabView` did not
  preload the platform reader, so the result rules out a false view in that case
  only; it is not a documented SwiftUI construction guarantee.
- `EXP-039` put an oversized explicitly tracked candidate before Home in
  `ViewThatFits`. SwiftUI rejected it without calling either its diagnostic
  platform reader's `makeUIView` or its `onAppear`; no candidate RUM view reached
  local mapping or backend intake. The positive-control Home occurrence and all
  six of its markers were exact. Because no platform object was constructed,
  this result is deliberately classified as inconclusive and the probe-only mode
  was removed.

`EXP-037` exposed a separate navigation-lifecycle defect. A short edge swipe
cancelled visually and left Detail on screen, but explicit tracking stopped
Detail, emitted a false Home for about half a second, then started a replacement
Detail. The candidate produced a 546 ms false Home; a control build with early
mount disabled produced the same sequence with a 506 ms false Home. Both reached
backend intake. No lifecycle action or resource was emitted during either false
interval. The A/B comparison proves this is existing SwiftUI
`onDisappear`/`onAppear` transition behavior, not a regression introduced by the
early-mount candidate. It remains a P1 explicit-navigation gap because RUM should
represent the completed navigation path, not an interactive transition that was
cancelled.

`EXP-040` then validated modal occurrence semantics with the retained harness.
The exact client and backend path was `Home₁ → Sheet → Home₂`; Home₂ received a
new UUID even though SwiftUI retained Home's platform state. The present tap used
Home₁, the dismiss tap and all six Sheet lifecycle markers used Sheet, and a
post-dismiss manual action/resource used Home₂. Stop/start ordering was strict,
with no extra semantic view or fallback attribution.

`EXP-041` closed scene B 25 ms after its root task began. B still produced one
semantic Home occurrence and all three action/resource lifecycle pairs stayed on
that B UUID, including completions after `dismissWindow`; B then stopped once.
Closing the frontmost fullscreen window returned the simulator to SpringBoard,
made A inactive, and required explicit foreground activation. The replacement A
UUID is therefore consistent with a real background/foreground lifecycle rather
than evidence that B teardown mutated an active A branch. Repeat A-continuity only
in a stable simultaneous-window layout where A demonstrably stays foreground.

`EXP-042` intentionally terminated the process while A and B both had correctly
isolated Home occurrences, then relaunched without uninstalling. iPadOS restored
only B, with the exact same native scene session ID but a new RUM session and new
Home occurrence. All restored-B lifecycle work and a manual marker used that new
B UUID. This validates one restored scene without cross-attribution, but the
platform did not reconnect A, so it cannot close the concurrent-restoration gate.

`EXP-043` instrumented the retained Home and Detail subtrees with a probe-only
responder-chain reader. During the short cancelled edge swipe, speculative Home
`onAppear` synchronously resolved `NavigationStackHostingController<AnyView>` and
its public UIKit transition coordinator. The coordinator was initially
interactive, but cancellation was still false at that callback and became known
only at completion. When SwiftUI later reversed Home with `onDisappear`, the
coordinator was already absent; Detail supplied no corresponding lifecycle
callback. Backend intake retained the exact false path: initial Home, initial
Detail, a 0.549-second Home, a replacement Detail, and the later correctly
completed Home, plus `ApplicationLaunch`. This turns the cancellation experiment
from a theoretical UIKit option into a qualified iOS 27 implementation boundary:
defer scene-local explicit lifecycle mutation until coordinator completion,
discard it on cancellation, and commit it on success. It does not establish a
general SwiftUI guarantee outside the exercised native `NavigationStack` shape.

`EXP-044` applied the scene-local completion gate to the same native path. The
first launch was deliberately invalidated: `WindowGroup(for:)` restored a
serialized `ProbeWindow` carrying the prior run identifier even though the
process environment had changed. After stopping and uninstalling only the probe,
the clean run used native scene `1C546E56-EF9B-467A-8C1D-E3EC03D7453E`.
Home₁ `a81641e6…` stopped for a normal push and Detail `0b3bebb8…` started. A
short edge swipe produced the same speculative Home `onAppear` and reversal
diagnostics as the baseline, but no RUM view start/stop occurred; Detail remained
visible and active. A subsequent completed interactive swipe stopped Detail and
created Home₂ `1a995513…`. A manual post-pop action and resource used Home₂.
Backend aggregation independently reports exactly four views including
`ApplicationLaunch`, three lifecycle actions and resources on Home₁, three on
Detail, and the one manual action/resource on Home₂. No false Home or replacement
Detail exists in the 22-event session, and no error, crash, warning, or rejected
upload was observed. This validates cancellation and committed-return occurrence
semantics together; it does not yet cover a second scene transitioning at the
same time.

`EXP-045` reviewed the implementation against lifecycle shapes that the retained
Home run did not exercise. The first draft asked only already attached scene
observers for a transition coordinator. A newly recreated destination therefore
had no responder ancestry during `makeUIView` and could publish immediately. It
also stored one pending transaction per scene, allowing an unrelated sheet, tab,
or split subtree to be discarded with a cancelled pop. The corrected provider
uses the tracked state's own controller and ancestors when attached. Before an
observer attaches, it searches public controller hierarchy only in the
`UIWindowScene` whose persistent identifier matches the intent, and marks that
membership provisional. Trait updates and appearance callbacks do not clear the
provisional flag; real responder attachment either confirms the same coordinator
or commits that independent lifecycle outside the pop. A trustworthy attachment
to another scene overrides the earlier trait and produces only the corrected
scene occurrence. Pending transactions are keyed by scene and ephemeral UIKit
coordinator identity, so independent coordinators in one scene and concurrent
scenes resolve separately.

The 19 focused arbiter/provider tests cover cancelled appearance and mount,
reversal before completion, completed stop-before-start, repeated returns of the
same platform identity, recreated-reader fallback, unrelated attached and
initially unattached state, same-scene independent coordinators, two-scene
isolation, scene correction, registration failure, duplicate callbacks,
disconnect, and stale completion. An independent final read-only audit found the
bounded retained/recreated `NavigationStack` gate clear after those corrections.
This is source and focused-test evidence, not a second runtime run: `EXP-044`
remains the native/backend proof. A provisional view that never attaches can
still be committed when an unrelated transition succeeds, and a representable
that survives disconnect/reconnect may have to use the less precise scene-root
fallback because registration occurs in `makeUIView`. Keep both cases in the
aborted-container and restoration matrix.

`EXP-046` first tested a semantic path boundary without adding SDK public API.
The probe disabled hosting-controller discovery and per-screen modifiers,
observed its authoritative typed `[ProbeRoute]` binding, and recreated a hidden
tracker for each path mutation. In one scene, the programmatic push started
Detail before its lifecycle work. A short interactive edge drag left Detail
visible and produced no path commit or RUM mutation. A completed drag committed
occurrence 2 and created Home₂, distinct from Home₁; the post-pop marker pair used
Home₂. This established that the typed binding exposes the right commit and
cancellation semantics for the exercised `NavigationStack`, but did not prove
where the tracker must be installed.

The first launch for this experiment, run suffix `…-0124`, is retained as a
harness lesson. Its initial Home/Detail ordering and backend attribution were
valid, but the Xcode launch session expired before gesture interaction. A later
device-only activation started a new process without the requested environment
and restored the serialized probe window. It was excluded from the cancellation
claim. The clean run uninstalled the probe and kept workspace launch plus all
gestures in one interaction session.

`EXP-047` through `EXP-049` then rejected three root-only placements in two
windows. A background sibling was created after B's content lifecycle. Wrapping
the entire stack remained too late and additionally rebuilt the stack whenever
the tracker identity changed, replaying retained Home lifecycle work after Detail
started. Keeping that tracker as a stable first child removed the replay but did
not fix B's initial ordering. In all three shapes, B Home `.onAppear` and its
immediate task still used A Detail. These runs are important negative evidence:
the bound path is an authoritative commit signal, but a detached root tracker is
not an authoritative semantic view-creation boundary.

`EXP-050` moved the existing explicit modifier directly onto the Home and typed
Detail content builders while retaining the bound path for commit diagnostics.
That route-owned placement passed in two windows. The backend session contains
only `ApplicationLaunch` plus A Home, A Detail, B Home, and B Detail. Each of the
12 lifecycle actions and 12 resources used its exact source view, including B's
first synchronous work, with no lifecycle replay or fallback. This is the first
concurrent proof of the minimum integration shape, not a transparent automatic
tracking fix or a reviewed public API.

`EXP-051` repeated the committed-occurrence contract on that passing shape. A
cancelled interactive pop emitted no new view. A completed pop stopped Detail and
created a fresh Home₂ UUID, distinct from Home₁, even though SwiftUI retained the
Home platform state. The final marker action/resource both used Home₂. This is
the required semantic result: `Home → Detail → Home` is three RUM views because
RUM models the path the user took, not platform-object lifetime. The probe had
also copied its diagnostic path counter into view attributes. On retained Home₂
that attribute remained `1` although the path log correctly reported occurrence
`2`; SwiftUI had retained the earlier modifier value. The UUID sequence and
event attribution were correct, but the stale diagnostic was removed so future
runs cannot mistake it for the RUM occurrence identity.

The passing boundary still does not cover `NavigationLink(destination:)`,
type-erased `NavigationPath` inspection, `NavigationSplitView`, path replacement,
restoration, or a production mixing contract with automatic discovery. Those are
separate gates rather than reasons to weaken the occurrence rule.

`EXP-052` separated a path mutation from an occurrence. One task wrote
`[.detail]` and immediately wrote `[]`. The binding observed both mutations, but
SwiftUI coalesced them without a Detail lifecycle callback, Detail RUM payload,
or second Home start. The post-abort action/resource used the original Home UUID.
Backend intake contains exactly ApplicationLaunch plus that one Home, four
actions, four resources, zero Detail events, and zero errors/crashes. A route
binding can tell the integration what was requested and, for the exercised
interactive pop, when UIKit committed it; arbitrary writes are not independently
RUM views. The semantic boundary remains the route content that actually
materializes. Future probe logs therefore call these writes mutations, and RUM
UUIDs plus stop/start order remain the occurrence evidence.

The first materialized-replacement run, `EXP-053`, was invalid by construction.
The new Alternate route was omitted from navigation-path mode's explicit-tracking
allow-list. Its missing RUM view and rejected delayed work therefore say nothing
about SDK support. This was caught before accepting the apparent ordering failure;
the run remains in the ledger because repeating or citing it would produce the
wrong conclusion.

`EXP-054` reran the same flow after tracking Alternate at its route builder.
Detail remained visible for one second before the app replaced `[.detail]` with
`[.alternate]`. The exact backend path is ApplicationLaunch, Home, Detail, then
Alternate—one UUID each, no intermediate/restarted Home, and no duplicate. Home,
Detail, and Alternate each emitted three lifecycle actions and resources on their
own view. Alternate started 0.614 ms before its `.onAppear`; its immediate and
delayed work stayed on that UUID. This closes the single-scene materialized
replacement row for the probe boundary while leaving concurrent replacement and
production API/mixing behavior open.

`EXP-055` checked the remaining documented scene-root API in Xcode 27.
`UIHostingSceneDelegate` is available from iOS 26 and lets an app-owned scene
delegate publish a static SwiftUI `rootScene`, either through scene configuration
or the new activation requests. It can receive normal `UISceneDelegate` lifecycle
callbacks, but the protocol contains no current navigation route or destination
builder hook. Adopting it also changes how the customer declares/activates scenes;
the SDK cannot transparently retrofit it around an existing SwiftUI `App` and
`WindowGroup`. It is worth retaining as an explicit root/lifecycle integration
option, not as an answer to semantic view creation. No runtime claim was made.

`EXP-056` repeated the materialized Detail-to-Alternate replacement while opening
scene B. The exact backend order was ApplicationLaunch, A Home, A Detail,
A Alternate, B Home, B Detail, then B Alternate. These are seven distinct view
UUIDs—one occurrence for each route in each scene—with no intermediate Home,
restarted route, or lifecycle replay. Every on-appear/immediate marker and all
three delayed markers from scene B used the correct route view. Scene A's delayed
Alternate marker executed after B Home became the process representative. That
manual `.task` call carried probe diagnostics saying A/Alternate, but it had no
SDK view or scene target and was outside the UI-event handoff, so its action and
resource used B Home under the approved source-less compatibility rule. A
Alternate remained active at that time, cleanly separating the causal-attribution
limit from view creation. No automatic tap was expected because autorun mutated
the bound path programmatically; all 18 actions were custom lifecycle markers.
The backend indexed 47 documents: 7 views, 18 actions, 18 resources, 2 long tasks,
and 1 vital, with zero errors or crashes. Upload requests
`F4388197-838B-4982-9BE1-D3E1D57FEDDD`,
`DACBC0DE-453F-4ED9-955D-D86F0C6961D6`, and
`E92A018D-4C5A-4FCD-96E5-3DB4EEB114D1` all returned 202. A later capture-only
interaction session found the app in `NotRun` state with an empty log; retain its
artifacts only as provenance, not live UI evidence.

`EXP-057` changed only the value of the top route while keeping its destination
type and RUM name stable: `[.detail(1)]` became `[.detail(2)]`. The visible UI and
accessibility hierarchy settled on `scene-A: Detail 2`, but the probe logged
`destination reader reused ... from=detail-1 to=detail-2` rather than creating a
new reader. RUM kept Detail₁ `446de300-cad6-42c3-966d-42856dfb399c` active with
its original `screen=detail-1` attributes. No stop/start, Detail₂ UUID,
`.onAppear`, immediate task, or delayed task marker followed, even after more than
one minute. This is a semantic failure under the navigation-occurrence contract:
the route committed even though SwiftUI retained the platform and modifier state.
The backend indexed 18 documents: 3 views, 6 actions, 6 resources, 1 long task,
1 vital, and 1 session, with zero errors or crashes. Uploads
`646D9D42-0FF1-4422-83A6-BA77BA920ABA` and
`F6A2F562-50E2-4284-90ED-F0B4E7D0A297` returned 202. The build log is
`BuildProject-Log-20260913-024952.txt`; the captured running hierarchy visibly
shows Detail 2. Next test an explicit probe-only route identity. If that passes,
it proves the missing input without making `.id` itself the customer API.

`EXP-058` supplied that identity only as a probe control by applying `.id(route)`
around the tracked destination. The authoritative run emitted ApplicationLaunch
`59e58db7-ba39-4dea-8b0a-cea4a3ee4e05`, Home
`fe23e592-96ea-45c4-9a01-96e41a896fff`, Detail₁
`a7ffe4c7-2daf-447a-a133-e5d411cce9f2`, and Detail₂
`62d0e6c9-566f-4137-89af-d8c4f31efc8b`, in that order. Both Detail views use the
same `ProbeDetailView` RUM name and SwiftUI type. There was no intermediate Home,
and each Home/Detail₁/Detail₂ on-appear, immediate, and delayed action/resource
pair used its exact UUID. A Detail₂ reader was created before its view started.
An additional old-reader update logged detail-1 to detail-2 just after the start;
runtime evidence alone cannot identify that reader, but it did not alter the
semantic result. Backend contains 25 documents: 4 views, 9 actions, 9 resources,
1 long task, 1 vital, and 1 session, with zero errors or crashes. Uploads
`7626268F-D993-47CD-AF42-F6AB3C683741` and
`8D3C83C8-EFAE-43B1-B4E4-668D758440E4` returned 202. The captured running UI
shows Detail 2. The earlier `…-025856` launch/session
`c427051d-a3c9-4538-8b18-44a9b4820964` reached Detail₂ but was interrupted before
delegated capture and backend verification; it was uninstalled and excluded from
the PASS. `.id(route)` validates the required input but is not a suitable public
RUM contract because it also changes the customer's content-state lifetime. A
reviewed integration must restart only RUM occurrence state when the token changes.

`EXP-059` repeated the `.id(route)` control in two windows. The exact client
occurrences were launch `90ad3649-8ff0-4b50-a465-16db81059dda`; A Home
`678ba34b-65f5-4929-b20f-d88d4b78e04d`, Detail₁
`81f82227-ae86-4dfc-ba97-f1e3d03fb9fa`, Detail₂
`c5a63750-63df-42b4-941b-4e5a7c3d0475`; and B Home
`49c08c73-0628-4130-a0ee-4fff748e421c`, Detail₁
`52e1db36-c39c-41ea-9793-c0de6dae35d2`, Detail₂
`401ad07f-94cc-4715-ab05-cfae427f626a`. Backend chronology matches those two
overlapping branches. There was no intermediate/restarted Home, duplicate, or
replay. All on-appear/immediate markers and every B delayed marker used their
exact occurrence. A Detail₂'s delayed source-less action
`0d96753f-dd81-4d0d-b9d4-6ddfaf57c2d2` and resource
`bc1f0ba0-f03d-48bc-8bc9-3bb6d61d740f` executed after B Home became process
representative and used B Home, matching the decided fallback rather than
invalidating view creation. Backend indexed 47 documents: 7 views, 18 actions,
18 resources, 2 long tasks, 1 vital, and 1 session; errors and crashes were zero.
Uploads `E9CC88AE-C7CA-42B2-91AC-F19EBCE49031`,
`DFBEF37C-105B-43D1-9F73-129B8EB12124`, and
`D4B2D838-1D7B-4808-8A74-454DC206E1CF` returned 202. Both captured windows show
Detail 2. The preceding `…-031603` session
`fa9e52ab-5b57-4a09-b700-1314c0f03031` used a misspelled environment key;
console confirmed `force_route_identity=false`, so it is excluded and must not
support any product conclusion.

`EXP-060` implements the first production-side building block without adding a
public API. `RUMViewsHandler` can now replace one exact SwiftUI occurrence in a
scene stack atomically. Replacing the visible Detail slot emits only
`stop Detail₁ → start Detail₂`; it never performs the ordinary remove behavior
that would restart Home between them. Replacing a covered or inactive slot emits
nothing until that slot is revealed or its scene returns to the foreground. A
missing old identity and a request whose old identity exists only in another
scene are no-ops, preventing cancelled, stale, or migrating work from creating a
view implicitly. Tests also prove that a covered old slot cannot reappear after
its replacement is removed and that scene B retains its original same-named
identity when only scene A is replaced. All 43 handler tests passed in
`Test-DatadogRUM-2026.09.13_03-37-17-+0200.xcresult`; the two strengthened final
unwind assertions passed in
`Test-DatadogRUM-2026.09.13_03-39-42-+0200.xcresult`. This is source and focused
test evidence only. The reader/state/arbiter still need a reviewed occurrence key
before the same-type runtime failure can use this primitive.

`EXP-061` closes a separate retained-scope correctness gap revealed by the
navigation-occurrence contract. A fresh backend UUID was already allocated when
Home returned, but the old inactive Home scope could still match that later
same-identity start and absorb Home₂ attributes while it remained alive for a
pending Resource. Inactive occurrences now ignore subsequent view start/stop
commands with the reused lifecycle identity; exactly targeted Resource completion
still reaches Home₁, and current scene work reaches Home₂. The same review
found that a transferred/restored scope had not recorded its synthetic start
boundary, allowing a later same-identity start to leave two active scopes. Restored
scopes now establish that boundary when created. Build-for-testing succeeded, the
three focused regressions passed 3/3, all 75 session-scope tests passed in
`Test-DatadogRUM-2026.09.13_04-12-37-+0200.xcresult`, and all 27 application-scope
tests passed in `Test-DatadogRUM-2026.09.13_04-12-54-+0200.xcresult`. This is
source and focused-test evidence; no new runtime/backend support claim is attached.

`EXP-062` completes the next internal-only state and arbiter slice. A future
navigation integration can provide an opaque occurrence key plus a monotonic
binding generation without changing the customer's SwiftUI identity. Keyed
occurrences receive fresh handler identities; a same-scene key change emits the
atomic replacement from `EXP-060`, a simultaneous scene change emits stop A then
start B, and a detached key change stops against the last-proven scene before
waiting for attachment. Ordinary lifecycle returns on the existing API retain
their stable command identity and still create fresh backend occurrences through
the scope behavior proven in `EXP-061`.

The interactive arbiter now captures the state's base revision, keeps only the
final accepted key and matching emission closure, and allocates an occurrence
only when the transition commits. Cancellation leaves state, generation, and
identity allocation untouched. Older binding generations cannot replace the
final descriptor closure or escape a pending transition into another scene.
Completion also checks the concrete deferred-transaction instance, preventing an
old completion from resolving newer work when UIKit reuses the same coordinator
identity.

The first green revision passed 22 state and 25 arbiter tests, but review found
three material correctness holes: an old lifecycle generation could affect a
same-key return or scene migration, the descriptor lived only in an emission
closure instead of the committed occurrence, and keyed state still accepted
unversioned lifecycle intents. The hardened revision stores an immutable
descriptor with the occurrence, requires a strictly newer binding generation for
every keyed materialization, and fails closed on unversioned keyed lifecycle
events. It also preserves a valid pending replacement when a stale event claims a
different scene. One intermediate build failed because two new assertions were
placed in the preceding legacy test and referenced out-of-scope configurations;
the assertions were moved into the keyed-return test rather than weakening them.
Do not retry that placement.

The hardened revision first passed 25 state tests, 26 arbiter tests, and the
targeted handler-publisher descriptor regression. A final review found no P0 or
P1 issue, then identified two compositional P2 coverage gaps. The final test
revision adds a keyed A/B arbiter case where A cancels and B commits, proving
independent configuration, generation, descriptor, identity allocation, and
scene target. The publisher regression now also checks all three command targets.
All 25 `RUMViewTrackingStateTests`, all 27
`RUMSwiftUIInteractiveTransitionArbiterTests`, and the targeted publisher
regression pass, 53/53 total. The final focused artifacts are
`Test-DatadogRUM-2026.09.13_05-10-23-+0200.xcresult`,
`Test-DatadogRUM-2026.09.13_05-10-42-+0200.xcresult`,
`Test-DatadogRUM-2026.09.13_05-10-55-+0200.xcresult`, and
`BuildProject-Log-20260913-051120.txt`. This is deliberately
dormant internal machinery: the reader and public modifier do not yet provide a
semantic key, so `EXP-057` remains the runtime verdict for same-type replacement.
At the `EXP-062` checkpoint, the complete `DatadogRUM` plan passed
1,087/1,087 with zero failures, skips, or not-run tests in
`Test-DatadogRUM-2026.09.13_05-13-57-+0200.xcresult`. The immediately preceding
full run was 1,086/1,087 because the unchanged timeseries pause/sampling test
observed a third sample instead of two; its isolated retry passed before the clean
full rerun. This is the same timing-test class already recorded below, not a
multi-scene regression. A final build after the lint-only brace correction
completed with zero diagnostics in `BuildProject-Log-20260913-051120.txt`;
repository lint passed all 713 source and 699 test files with zero violations.

`EXP-063` fixes the disconnect half of the retained-reader lifecycle. Before this
slice, `RUMViewsHandler` stopped and removed scene A's stack while the SwiftUI
state continued to believe its occurrence was active. A later callback could
therefore emit no start or attempt a replacement against a handler entry that no
longer existed. Scene discard now gathers A-owned registered and pending states,
removes only A's deferred transactions, and silently invalidates those states.
It clears attachment, appearance, and the active occurrence without emitting a
second stop, increments the revision to fence late completions, and requires an
explicit platform remount. Keyed configuration, last-started binding generation,
and lifecycle generation remain intact, so stale generation N cannot resurrect
the entry; an N+1 remount creates a fresh identity with `.start`.

The first build of this slice failed before tests because eight new reconcile
call sites omitted the private method's explicit configuration/revision arguments
(`BuildProject-Log-20260913-052924.txt`). The call sites were fixed explicitly;
do not loosen the reconcile overloads to hide the distinction. The final build
has zero diagnostics in `BuildProject-Log-20260913-053257.txt`. State tests pass
27/27 in `Test-DatadogRUM-2026.09.13_05-30-57-+0200.xcresult`, arbiter tests pass
29/29 in `Test-DatadogRUM-2026.09.13_05-31-26-+0200.xcresult`, and the handler
disconnect and publisher regressions each pass in
`Test-DatadogRUM-2026.09.13_05-33-05-+0200.xcresult` and
`Test-DatadogRUM-2026.09.13_05-33-17-+0200.xcresult`. The handler integration
proves one A stop from teardown, no stop from state invalidation, one A start from
remount, and no B stop. The complete current RUM plan passes 1,092/1,092 in
`Test-DatadogRUM-2026.09.13_05-33-59-+0200.xcresult`; repository lint remains
clean across 713 source and 699 test files. Reused `updateUIView` re-registration
and authoritative unchanged-attachment delivery remain a separate integration
requirement; this slice fails closed if SwiftUI retains the old reader rather
than creating a new platform mount.

`EXP-064` implemented that retained-reader seam. `RUMSceneIdentifierReader`
gained a distinct mount callback; `updateUIView` rebinds and re-registers the
observer; an unattached window scene is treated as disconnected; and ordinary
unchanged attachments are deduplicated. State tracks remount authorization and
allows an actual reader remount without letting an ordinary update after a
semantic disappearance invent a new occurrence. The first green revision passed
30/30 state tests, 30/30 arbiter tests, and one handler regression (61/61), the
complete RUM plan passed 1,096/1,096, and lint was clean.

That revision was not accepted as complete. Review found two correctness gaps:
a deferred reconnect lost its remount authorization when committed through the
general reconcile path, and repeated unchanged `updateUIView` delivery could
restart a normally disappeared retained view. The first hardening split the
reader-mount path from ordinary updates and reached 64/64 focused tests.

Further review found four more gaps: a stale initial scene trait could remount
after disconnect while the reader was still unattached; observer registrations
were not scene-specific enough and an old A observer could contaminate B's
coordinator selection; disconnecting source A discarded a pending migration to
B; and cancellation consumed the retained reader's only mount notification.
The first implementation of those corrections passed 67/69. One failure came
from an old test using a detached-controller seam that could not establish real
scene ownership; it was corrected to inject its intended coordinator provider.
The second exposed a real arbiter defect: disconnect candidate discovery looked
only at transitions targeting the disconnected scene and therefore missed a
state migrating away from it. Candidate collection now includes every deferred
state, invalidates the A occurrence, and rebases the surviving B transition.

After those fixes, 71/71 passed. Review then found that a detached, re-registered
A observer had no current scene and could still prevent B from falling back to
its scene-root coordinator, allowing immediate ungated B lifecycle. The observer
now retains a last-proven scene across detachment and disconnect; B filters it
out. This reached 72/72 focused tests and 1,105/1,105 in the complete RUM plan.
A final review found one remaining race: merging a reader mount with a disappear
could clear remount authorization and permanently fence the state. Reader-mount
authorization now remains sticky through coordinator completion; success clears
the reconnect fence without starting an inactive view, cancellation rearms the
reader, and a later semantic appearance creates exactly one occurrence.

`EXP-065` is the final hardened source/focused-test checkpoint. It covers stale
trait rejection, inactive reconnect, deferred success and cancellation,
reader-mount/disappear ordering, source-A disconnect during pending migration to
B, old-A observer removal, and detached-A isolation from B's cancellation gate.
The final build-for-testing completed with zero diagnostics in
`BuildProject-Log-20260913-061213.txt`. The combined focused plan passes 74/74
(state 34/34, arbiter 38/38, two handler tests) in
`Test-DatadogRUM-2026.09.13_06-12-22-+0200.xcresult`. The complete `DatadogRUM`
plan passes 1,108/1,108 in
`Test-DatadogRUM-2026.09.13_06-12-43-+0200.xcresult`, and repository lint remains
clean across 713 source and 699 test files. Final source review found no P0/P1
issue. At this checkpoint no retained-reader runtime had run, so `EXP-065` alone
must not be promoted to runtime or backend evidence. `EXP-066` below adds a
synthetic integration control; genuine OS disconnect/reconnect remains open.

`EXP-066` adds a live integration control without overstating what the platform
did. The probe targeted scene B after both scenes reached Detail, confirmed that
B's `UIWindowScene` was foreground-active and still present in
`UIApplication.connectedScenes`, and posted `UIScene.didDisconnectNotification`
for that object. It then incremented a probe attribute to force representable
update delivery while leaving the SwiftUI tree alive. A parallel diagnostic
representable retained object `0x0000000113c51880` and reported generation 0→1,
showing that the update was not a fresh probe tree.

The SDK stopped the pre-injection B Detail occurrence
`992f0e7e-6b86-4bf2-be73-e403056363f4` exactly once and started post-remount B
Detail `4e029fe4-338e-496f-b0ea-b9029459180a` exactly once. Both carry B native
scene ID `0C4ADCA5-128D-4D9C-A6EB-5DC3E92B1FAA`; A retained native scene ID
`11EB84CD-18A5-4275-A905-8DF61E52F4C0` and its active RUM branch. The
post-remount marker action and Resource both used the new B UUID. Backend session
`b1b2313a-9cd7-4cfa-90f8-272e2ae07de9` contains exactly six views, 13 actions,
13 resources, two long tasks, one vital, one session, and no errors or crashes.
Three uploads returned HTTP 202 with request IDs
`98531630-1ABC-467E-9E17-461593F6A7B9`,
`B5C860B8-B72E-4F54-9A7D-C4E1B09EA351`, and
`35165CD4-5E1F-46C5-983E-4AA7AE915C8B`.

This is runtime, payload, and backend evidence for the explicitly synthetic
handler/arbiter/retained-update integration. It is not an OS lifecycle result:
the scene deliberately remained connected before and after the notification.
The original Xcode interaction session expired before final capture. A later
capture-only session showed SpringBoard and has no evidentiary value; do not cite
its screenshot as the run's UI state. Genuine OS disconnect/reconnect and
restoration remain open because iOS normally destroys and reconstructs the scene
tree rather than preserving this exact representable.

`EXP-067` is a source-only split/adaptive navigation audit. Both UIKit and SwiftUI
ultimately publish into one `RUMViewsHandler` stack per scene. UIKit automatic
tracking observes every eligible child controller's `viewDidAppear` and
`viewDidDisappear`; if Secondary₁ disappears before Secondary₂ appears, ordinary
stack removal stops Secondary₁ and restarts the lower Primary before the new
secondary stops it again. A stock `UISplitViewController` is filtered with UIKit,
but an application subclass is eligible under the default predicate and can add
another container occurrence.

SwiftUI automatic tracking explicitly skips
`SwiftUI.NotifyingMulticolumnSplitViewController` and depends on child hosting
controller lifecycle/reflection. A same-controller selection from Detail(1) to
Detail(2) can therefore expose no semantic occurrence signal. Explicit
`.trackRUMView` has scene ownership but its occurrence token remains dormant
pending API review. Tap and scroll attribution carries a scene, not a pane, so it
follows whichever column won callback order. The exact lifecycle order and false
or missing UUID sequences were hypotheses at this source-only checkpoint;
`EXP-068`/`EXP-069` below resolve the SwiftUI cases, while UIKit split remains to
be run. No runtime/backend claim is attached to `EXP-067` itself.

`EXP-068` turns the SwiftUI same-type hypothesis into a backend-proven failure.
The probe used a regular-width `NavigationSplitView`, route-owned explicit
tracking, and no `.id(route)` control. Native scene
`0C4ADCA5-128D-4D9C-A6EB-5DC3E92B1FAA` started Detail(1) as RUM view
`f83c68df-14f7-45df-9adb-a98ab833e76c`. It then visibly committed Detail(2)
while the adjacent content witness retained object address
`0x000000010a8ccc40`. RUM emitted no stop/start and continued the first Detail
UUID, so the Detail(2) `selection-committed` action and Resource were attributed
to Detail(1). This violates the navigation-path contract even though the
platform object behaved normally.

The following different-type Placeholder correctly started RUM view
`9717a9c1-fc89-40d1-bd9a-5918537df070`, and its immediate action/resource used
that UUID. There was no intermediate Sidebar or Home occurrence. Backend session
`7d622e5f-6489-4d26-a04b-9f7809a5f070` contains exactly three views—the launch
view, collapsed Detail, and Placeholder—three actions, three resources, and no
SDK or probe errors. Uploads returned HTTP 202 with request IDs
`1F7F9AE6-300F-4046-818D-DBD720C52E84` and
`84AF6996-6523-4952-BA99-B4B376E9B5D7`. The required sequence was three semantic
selection occurrences, `Detail₁ → Detail₂ → Placeholder`, each with a distinct
UUID. The automatic-only baseline and route-identity control remain separate
experiments so controller discovery and explicit occurrence input are not
conflated.

`EXP-069` records the automatic-only counterpart. In the same regular-width
layout and native scene `0C4ADCA5-128D-4D9C-A6EB-5DC3E92B1FAA`, automatic
tracking emitted launch `bd43e6cb-98a5-4cfa-8988-8fd2d8c690b9`, setup-only
fallback `4d724467-9080-47c8-b0e5-a53926af36a6`, transient host
`a93704fc-252b-4629-b088-3537886e8301`, and final host
`42020e4a-0a3e-49c3-82dd-d35ee5a30cad`. It emitted no semantic selection view.
Detail(1)'s immediate marker used launch, while Detail(2) and Placeholder both
used the final host. Backend session `27a59309-7862-4025-b028-94d6004487db`
contains four views, three actions, three resources, and no SDK or probe errors.
Uploads returned HTTP 202 with request IDs
`41D2162D-4867-43B3-BA4B-ADC032F303BC` and
`2EA7F421-DBC5-4FD5-8525-DB70A466B38D`. The screenshot at
`EXP 067 Split Automatic Baseline-06_46_04_266-screenshot.png` confirms the
regular-width visual state, but the backend UUIDs are the semantic evidence.

`EXP-070` is the positive route-identity discrimination control. With
`.id(selection)` around the tracked split destination, backend session
`611c8142-3efc-468a-b044-93fed25864f3` contains the exact semantic chain launch
`4276dce9-a5bd-401a-934b-a794dc2ebe9a` → Detail₁
`61857c33-549b-48dc-936c-bf8dc0fb065a` → Detail₂
`674a3b9f-005a-45e5-92be-1dee5b9c66cc` → Placeholder
`bdf5eec4-7cef-4ea6-b88a-d124113a0472`, with no Sidebar/Home occurrence.
Detail₁, Detail₂, and Placeholder each emitted one action and Resource on that
exact UUID. Their action IDs are `34773550-f743-4b2d-bfc2-5bd1311b6b2a`,
`8a967975-55df-4deb-a082-3fa8cc3b7117`, and
`0144f283-5679-457a-82e6-4638977e7d0a`; their Resource IDs are
`48854d28-b5a0-42a1-b380-c1f5198b12d9`,
`f3571779-f149-41b4-a07b-59032ac6d024`, and
`a7b842cf-28e8-48d6-97b7-721bb630df9f`.

The transition order is equally discriminating: Detail₁ stopped before Detail₂
started, Detail₂'s markers followed that start, then Detail₂ stopped before
Placeholder started and received its markers. The old Detail witness
`0x000000010acccc40` briefly observed the Detail(1) → Detail(2) update before
`.id` created Detail₂ witness `0x0000000112492bc0`; Placeholder used
`0x0000000112491f80`. The control therefore proves the missing semantic input,
but also proves why `.id` cannot be customer guidance: it replaces application
content state rather than rotating only the RUM occurrence. Backend counts are
four views, three actions, three resources, one long task, one vital, and one
session. Uploads returned HTTP 202 with request IDs
`78B2CA0D-B290-445D-8D0C-0B74DD45CCD6` and
`D898F434-7BBA-4F93-B308-389C2248394F`; no relevant SDK/probe
warning/error/fault/crash was present. The Xcode build log is
`BuildProject-Log-20260913-064731.txt`, and the final screenshot stem is
`EXP 067 Split Route Identity Control-06_49_09_309`.

`EXP-071` backend-proves the UIKit stack-ordering defect with SwiftUI automatic
tracking disabled and `DefaultUIKitRUMViewsPredicate` enabled. A stock split
controller `0x00000001035b0a00` displayed Primary
`0x00000001035b0f00`, then Secondary₁ `0x00000001035b1900`, and replaced it
with fresh same-class Secondary₂ `0x00000001035b1400`. The replacement log
confirmed `primary_visible=true`. Primary received no second `viewDidAppear` or
intervening disappearance; Secondary₁ disappeared before Secondary₂ appeared.

The platform path was therefore launch → Primary → Secondary₁ → Secondary₂.
Backend session `0a320a0f-f610-450b-af79-3c47fb3c68b6` instead contains launch
`d1e21f87-1ed5-4226-9219-f7cb0d369cd0` → Primary₁
`bac07614-5836-438f-add6-45dff9aa940b` → Secondary₁
`ea45d1fa-5766-47b1-856d-10b291bce0c8` → manufactured Primary₂
`7b4b1cb9-c649-4cd7-8ed6-3503acb198c2` → Secondary₂
`c55b671c-78cd-4a7c-9b40-323dfc690879`. Primary₂ has no lifecycle marker and
was created solely because removing the active Secondary₁ restarted the lower
handler-stack item before Secondary₂ arrived.

The three real child markers remained exact: Primary action/resource
`9625de7c-5763-4103-b7cf-fd2b12f62afc`/
`1e3d287b-5d99-4ced-afee-27459dde601c`, Secondary₁
`55ac1a04-399c-485d-9798-62054ddda9a9`/
`3af06581-5a00-46ed-8c27-09ef66e1f64b`, and Secondary₂
`f68825f7-f96c-4acf-8eb8-aa58a2e8b084`/
`6873182c-4b67-46e2-8151-e87d4aed417f` used their matching RUM UUIDs. Backend
totals are five views, three actions, three resources, one long task, one vital,
and one session. Uploads returned HTTP 202 with request IDs
`40A187B7-BAAD-48B3-B3BF-9D7312AEF9DC` and
`64775B88-5A1A-4FFF-8E45-E98FEEA3A5F7`; no relevant SDK/probe warning, error,
or crash occurred. The build log is `BuildProject-Log-20260913-065647.txt`; the
final screenshot stem is `EXP 068 UIKit Split Stock-06_58_12_584`.

`EXP-072` repeats that isolated flow with an application subclass of
`UISplitViewController`. Container `0x0000000103db0a00`, Primary
`0x0000000103db0f00`, Secondary₁ `0x0000000103db1400`, and Secondary₂
`0x0000000103db1900` remained in the same regular-width native scene. Primary
stayed visible without a disappear/reappear, and the container received no
child-transition appearance callback. Nevertheless, backend session
`ea8c619c-685b-4b32-93d4-286c820352c8` emitted launch
`fabe644c-50a2-45e5-981b-560f2571bed9` → extra subclass-container
`dbf26236-4c35-4f7d-ae61-1ef8687b66b8` → Primary₁
`802061f7-ba1a-4d4c-ae64-6d61e73bde7d` → Secondary₁
`213d793e-aa39-4dc6-9111-26220a3c46c7` → manufactured Primary₂
`2ac1c8e6-d704-4e54-994a-e5c6dceb33ff` → Secondary₂
`3ab7f656-1fd8-4b08-bb14-36072334fe1d`. The container lasted about 1.3 ms;
the duplicate Primary lasted about 1–5 ms depending on client/backend boundary.
Neither had a marker.

Primary, Secondary₁, and Secondary₂ action/resource IDs were respectively
`43c9b5c1-1aa0-498d-86d2-210afe7c478e`/
`98f3fb97-2e5c-446b-b3fe-cd4cc0cc63c3`,
`bba46fc6-e677-45dc-8e0b-9c1b389f3ad9`/
`fdad2611-726b-432e-baa6-82a681aebddd`, and
`04347e63-a492-4239-95a1-206e7405252c`/
`b34b85a8-44ec-4956-9100-d5cd58f25de3`; every pair used its genuine child
view. Backend totals are six views, three actions, three resources, one long
task, one vital, and one session. Uploads returned HTTP 202 with request IDs
`061FD24F-F336-4AB6-A6FD-583F5B2717D5` and
`A7F29602-D6EE-443D-8CE0-9495DF30A453`; no relevant SDK/probe error or crash
occurred. The final screenshot stem is
`EXP 068 UIKit Split Subclass-07_02_18_954`.

This separates two fixes. Split-column replacement must suppress the lower-stack
restart without weakening ordinary push/pop, and container filtering must decide
whether subclass inheritance is sufficient without breaking customers who
intentionally track an application-owned container. The second change needs an
explicit compatibility review rather than being bundled into the ordering fix.

`EXP-073` then tests ordinary navigation inside a stable secondary
`UINavigationController`, rather than replacing the split column root. Stock split
controller `0x0000000105db0a00`, Primary `0x0000000105db0f00`, secondary
navigation controller `0x0000000105dba400`, Secondary₁/root
`0x0000000105db1400`, and pushed Secondary₂ `0x0000000105db1900` remained in
native scene `0C4ADCA5-128D-4D9C-A6EB-5DC3E92B1FAA`. Primary received only its
initial appearance and stayed visible. Secondary₁ appeared once initially and
the exact same controller object appeared a second time after Secondary₂ was
popped.

The platform path was launch → Primary → Secondary₁ → Secondary₂ →
returned Secondary₁. Backend session
`1a36a993-b62c-40b9-9124-6942529bd7b1` instead contains launch
`1536d66b-941c-4ccf-8c05-dcd9d00db5d3` → Primary₁
`bd6b7f44-88f9-4c97-9230-bdceaadee2dd` → first Secondary₁
`2999a158-40cc-4509-b611-ea4fe4895e09` → false Primary₂ on push
`9eba74cb-bd1d-41e8-bfe7-44e310bbb064` → Secondary₂
`5584bf3b-ac4e-43b1-abc5-30b057b171ec` → false Primary₃ on pop
`0b7067fd-9716-4f84-95e1-cba5d1ca6c50` → returned Secondary₁
`038e40bf-8d8c-486a-86b8-2010b4357010`. The returned UUID is correctly distinct
from the first Secondary₁ UUID even though both appearances use the same view
controller. The two Primary UUIDs are incorrect because no Primary navigation
occurrence happened.

Primary, first Secondary₁, Secondary₂, and returned Secondary₁ marker
action/resource IDs are respectively
`5826e07f-8f00-4c01-b55a-e5cd0d4e02c1`/
`d70a2a32-df04-4c65-9f38-f3051cac811a`,
`585c3ff0-6649-4048-a7a8-fd09fde5b03b`/
`ddc3a737-004d-4737-a5b2-db6be8d33c43`,
`8bbc117a-000f-4e28-8126-ed68e14aca73`/
`d9c84dce-cf3d-462f-a63b-e799c751c9dd`, and
`4f6346db-ba1b-416c-a569-8a9401e6d571`/
`2f20dd9f-ffe8-4127-bc6d-35e834c3cf87`; every pair uses its intended UUID.
Backend totals are seven views, four actions, four resources, one long task, one
vital, and one session. Uploads returned HTTP 202 with request IDs
`6D4F3A45-0ED7-42D5-AC2B-9DAED10BCAA4` and
`21D3A036-4C10-4E82-AC6B-1E7F1B1490CE`; no relevant SDK/probe error or crash
occurred. The build log is `BuildProject-Log-20260913-071722.txt`; the final
screenshot stem is `EXP 069 UIKit Split Navigation-07_18_54_492`.

This changes the implementation boundary from column-root replacement to any
materialized navigation transition within the active split column. The RUM
handoff must stop the outgoing secondary and start the incoming secondary
without restarting a visible sibling column. It must still allocate a new RUM
view occurrence when the incoming controller is a reused path item, as the
returned Secondary₁ UUID in this baseline already demonstrates.

`EXP-074` validates the first production candidate against the stock replacement
control. On iOS 27, and only when the application declares multiple-scene
support, `RUMViewsHandler` defers an outgoing active split-column removal for one
main-queue turn. A trustworthy incoming controller in the same scene, split
container, and column consumes that pending removal as one atomic handoff. The
backend session contains exactly launch `b56bd2fa…` → Primary `77d88232…` →
Secondary₁ `e27a3e4b…` → Secondary₂ `6d912ee2…`; it contains no second Primary.
All three marker pairs use their intended occurrence. The run produced four
views, three actions, three resources, and no errors or crashes. Full UUIDs are
`b56bd2fa-c717-413f-bafe-0b27efeaa5ce`,
`77d88232-40f9-4851-af0d-cb6b62c82fc4`,
`e27a3e4b-2cce-4c1c-9cbd-d360e4ee2eae`, and
`6d912ee2-4bd7-4d27-8ad9-a6a802483865`. Uploads returned HTTP 202 with request
IDs `39963DD1-6D22-4A84-B38A-27B6F6F8B661` and
`6F942F47-58EB-4AD7-9B77-0929CCB7B02B`.

`EXP-075` validates the same implementation against nested navigation in a stable
secondary `UINavigationController`. The exact controller used for Secondary₁,
`0x00000001031b1400`, appeared first, yielded to Secondary₂, and appeared again
after pop. The backend contains exactly launch `b0987aa0…` → Primary `8578f7fb…`
→ Secondary₁ `ec3cd76b…` → Secondary₂ `8e03aa83…` → returned Secondary₁
`bfc94bbd-fbd8-446f-9c00-3bbbc83e88a2`. Full preceding UUIDs are
`b0987aa0-cd97-4891-8cbc-7feb4f9b7831`,
`8578f7fb-cff8-4f3e-bbe7-4c3c2ccfb577`,
`ec3cd76b-f5a5-40ae-9e82-27f5270fd590`, and
`8e03aa83-75a9-44f6-b831-e51c9831678c`. There is no intervening Primary, while
the returned instance receives a fresh RUM UUID. Its four action/resource pairs
are exact; totals are five views, four actions, four resources, and no errors or
crashes. Uploads returned HTTP 202 with request IDs
`2F0CB9DA-6D93-4B3F-9ECA-1E1D9A299852` and
`8FBCD2BE-DB82-417A-A203-ED8DF58A9602`.

After correcting a test assertion that counted scene B's legitimate setup stop
instead of only scene-A disconnect teardown, all 54 then-current
`RUMViewsHandlerTests` passed. The two focused `RUMInstrumentationTests` for
multi-scene capability propagation also passed. Together `EXP-074`/`EXP-075`
turned the original UIKit split-ordering defect into a
source/test/runtime/payload/backend pass without altering the still-open
subclass-predicate decision.

`EXP-076` stopped at preflight and created no run, session, upload, or capture
artifact. `ProbeSplitLayout` currently initializes `selection` to `.detail(1)`
and its materialization task automatically commits Detail₂ and Placeholder. Its
nil detail branch is therefore not reachable as a stable experimental mode.
The probe logs horizontal size class but has no scene geometry control; Xcode's
device synthesis can rotate the simulator but cannot deterministically resize
this iPad window through regular → compact → regular. The target-runtime UIKit
headers confirm that iOS geometry preferences request interface orientation,
while `sizeRestrictions` are preferences rather than a deterministic current-size
request. Do not repeat this run until the probe can hold `selection == nil` and
the system can acknowledge each width transition. This is a harness gap, not an
SDK failure.

Review after those native passes found two adjacent P1 ordering defects. First,
the pending lookup selected by scene before validating the incoming split/column,
so an unrelated appearance could remove the secondary, restart Primary, then add
the unrelated view. The corrected path performs the ordinary direct transition
and immediately removes the now-covered pending item, preventing another
same-turn callback from revealing it. Second, app and scene background flushed
pending removals while stacks were active, which deterministically started and
then immediately suspended Primary. `EXP-077` suspends first, removes while
inactive, and uses the recorded disappearance time when the pending identity is
still top. Disconnect now preserves that timestamp too. New regressions cover an
unrelated appearance, scene background, app background, and exact disconnect
time; the full handler class passes 57/57, the two capability-plumbing tests pass,
and build-for-testing reports zero diagnostics. Because this hardening followed
`EXP-074`/`EXP-075`, both native controls were repeated as `EXP-079`/`EXP-080`
before promoting the corrected revision to a runtime-backed pass.

The reconciliation tests inject split/column context. An earlier attempt to test
the default resolver with a retained `UIWindow` and real `UISplitViewController`
inside the XCTest host did not reproduce native containment reliably, so it was
removed rather than normalized into a false positive. Do not repeat that detached
fixture as proof. `EXP-074`/`EXP-075` exercise the public UIKit resolver in the
native app; add a direct resolver unit only if the test host can establish and
assert the same containment contract deterministically.

`EXP-078` first repeated stock split replacement on the hardened revision. Native scene
`0C4ADCA5-128D-4D9C-A6EB-5DC3E92B1FAA` emitted launch
`c3317588-501b-4572-a425-d93cd8fb1d9a` → Primary
`bd80860a-28b7-4d01-9d78-4cce91ef00a7` → Secondary₁
`12871423-90e6-4259-a0f5-e9b4883018b9` → Secondary₂
`aefdee70-1a80-4208-9ab2-fa6c2c17fb9a`, with no second Primary callback or
RUM UUID. The three action/resource marker pairs are exact. Backend totals are
four views, three actions, three resources, and zero errors/crashes. Uploads
returned HTTP 202 with request IDs `67D74524-10C0-4818-B464-D268F2CD4CAB` and
`ECFC03C2-3BA1-4597-B914-CD8046298C9C`. One earlier attempt expired before
launch and emitted no telemetry; it is excluded rather than counted as a run.
Because a later no-op platform conditional cleanup raced source/build timing,
this behavioral pass is retained but not used as exact final-tree evidence.

`EXP-079` repeats nested push/pop on that revision. The same scene emitted launch
`01613b1a-844e-4c20-85e0-22456a7b8faa` → Primary
`ae6bff57-c9dd-4606-8972-42ac7b18c532` → first Secondary₁
`c3ec803e-7f8f-45dd-9635-195d829ba89c` → Secondary₂
`18023259-2e72-4a2c-bef6-4a8092727a0c` → returned Secondary₁
`2086f533-f0ab-4928-977e-f2fc34aa74a4`. The returned view reused controller
`0x00000001059b1400` across appearances 1 and 2 but received a fresh RUM UUID,
which is the required occurrence-per-navigation-path behavior. No Primary
interval was emitted; all four marker pairs are exact. Backend totals are five
views, four actions, four resources, and zero errors/crashes. Uploads returned
HTTP 202 with request IDs `54F62E56-62A4-4F74-9668-F4D84C173867` and
`E2886D5F-35F6-4A43-A86B-D96F646C07CA`.

After an explicit current-tree probe rebuild, `EXP-080` provides the final stock
control. It emitted launch `5d4c02cf-4b91-48b3-91c4-4fbeb402230d` → Primary
`c8655d49-71ff-48d9-af92-55340a35af02` → Secondary₁
`2aaa7ae8-bea2-4f69-8720-fc3dc1b9aa3a` → Secondary₂
`7eb93e48-c49c-4755-9897-8eba0c8e5d63`, with no extra Primary and exact marker
ownership. Backend totals are four views, three actions, three resources, and
zero errors/crashes. Uploads returned HTTP 202 with request IDs
`1637636A-8DC5-431B-AB95-41AAE0C3F2B6` and
`1D0179C3-01D5-48B4-AED4-BFAA6BA83609`. The final build-for-testing reports zero
diagnostics and all 57 handler tests pass. `EXP-079`/`EXP-080` are therefore the
authoritative nested/stock pair for the post-review implementation.

`EXP-081` records the complete cancelled-edge-gesture tooling investigation so it
is not mistaken for runtime evidence or repeated. Detached Xcode install-and-run
accepted the required environment in
`native-uikit-split-interactive-cancel-lldb-20260913-084206`, but LLDB reported no
active debug process; the debugger-backed runner could not inject the environment.
After adding `DD_MULTI_SCENE_UIKIT_SPLIT_AUTOMATIC_POP=0`, build
`BuildProject-Log-20260913-084430.txt` passed. Recovery run
`native-uikit-split-interactive-cancel-20260913-084836`, session
`c2bb3b70-3044-4e6d-9015-51ee0a96f799`, reached S2 and positively logged that
automatic pop was disabled.

The first attempted gesture, run
`native-uikit-split-edge-cancel-20260913-085301`, session
`5a2a2d8c-0ad6-4394-88cc-29c15f8a29c6`, used invalid shorthand
`s 322 688 372 688 0.8`; the tool rejected it and generated no device event. The
accepted grammar is `t x1 y1 f x2 y2 duration`. Short straight drags in
`native-uikit-split-edge-cancel-retry-20260913-090011`, session
`5926a383-b5ec-4fb4-bda8-f31b91f5be19`, and
`native-uikit-split-edge-cancel-proven-20260913-091535`, session
`4d392878-6b20-42dd-b679-1230b860c3c6`, were captured by the split divider and
widened Primary from 320 to 358.5 points. They emitted no navigation lifecycle.
AXe's swipe and drag commands support one point-to-point path; gesture presets do
not expose an edge-pop reversal, and batch touch exposes only down/up without
move segments. A physical right-then-left cancellation is therefore not
expressible with the available driver. These runs are setup evidence only.

`EXP-082` proves the adjacent physical committed path. Run
`native-uikit-split-edge-commit-20260913-090650`, session
`312715b2-d818-402f-b468-4aff5d7b01e8`, sent
`t 334 688 f 950 688 0.8`; Primary stayed 320 points wide and UIKit committed the
pop. The exact backend chain was launch
`33dd1065-44ab-4938-85ae-e6547676404b` → Primary
`8c5f77ab-8e80-4b7a-a018-553f0dbfc87d` → S1(first)
`068aa499-6c6d-4607-909b-9b2cc61fc276` → S2
`0ba127ac-7fcd-45b3-9074-0078ebbf41b8` → S1(returned)
`6a7e95c7-20ee-454e-b9f3-46e80cfa9a4c`. The same S1 controller received two
appearances and two RUM UUIDs. All marker pairs were exact; uploads returned 202
with `F2540746-50D0-46C2-90B2-1F16DB92A3BA`,
`44B4973C-FB49-4519-9777-8588D4157E05`, and
`2E080842-0A68-4F35-A150-01504E28E01E`.

`EXP-083` replaces the unavailable reversal gesture with a deterministic control
that still uses public UIKit transition machinery. Run
`native-uikit-split-deterministic-cancel-20260913-092850`, session
`eb7c9b25-0f5c-443e-9a3a-c118ed608ace`, drove a real
`UIPercentDrivenInteractiveTransition` to 35 percent and cancelled it. At
09:26:51.232 S2 `0x103dc1900` began a speculative transition to S1
`0x103dc1400`; UIKit then reversed it and invoked `viewDidAppear` a second time on
the same S2. Coordinator completion at 09:26:51.548 reported
`cancelled=true`, with S2 still top. Backend remained exactly launch
`e0bdffb1-e097-4149-a9ce-db7d7604fd1b` → Primary
`f7aa9e2d-ff15-45ae-8dda-5d35149a209e` → S1
`349a0459-a799-4516-a894-b5b31e39a4cd` → original S2
`929efbd3-2f03-41f6-9ed1-ac63c1dedd87`. No returned S1, replacement S2, or
false Primary occurrence was emitted. Both initial and reversal S2 markers used
the same S2 UUID. Uploads returned 202 with
`A4D88406-98E1-41A7-A065-1793111C1F04` and
`B36346CD-1708-4865-AD92-56C48CE26562`; build
`BuildProject-Log-20260913-092521.txt` passed.

`EXP-084` ran the same deterministic transition with completion instead of
cancellation. Run `native-uikit-split-deterministic-finish-20260913-093115`,
session `934eadc2-2712-4659-b156-f717f0504de3`, reported
`cancelled=false`. Backend emitted launch
`44afe8ab-71f6-4aba-9689-c969c495ff68` → Primary
`481f3af9-9c17-4bcd-ac99-2791a07b1f75` → S1(first)
`b1875986-6494-4364-b849-d325bb01651b` → S2
`c8db2b31-c807-4945-b628-f3e74a244777` → S1(returned)
`6e913601-9c3b-4144-adfb-21371e756e86`. The returned occurrence reused the S1
controller but received a fresh RUM UUID. No Primary interval was emitted; all
four marker pairs were exact. Uploads returned 202 with
`97717463-9647-40C4-A374-D6ABAAFD0D40` and
`8F85B474-D5A7-4075-AC70-CA23D88856B9`.

`EXP-085` audits the remaining supported Xcode 27 SwiftUI seams before proposing
another automatic-tracking experiment. `NavigationStack` exposes customer-owned
path initializers, while typed `navigationDestination` builders are the only
public boundary carrying the route value into materialized content. A type-erased
`NavigationPath` exposes count, codability, append, and remove operations but no
element iteration. `UIHostingSceneDelegate` supplies scene root and lifecycle,
not destination identity. `NavigationTransition` exposes no public semantic route
metadata. The automatic tracker still first learns a semantic controller in
`notify_viewDidAppear`, and its predicate receives only an extracted string.

The smallest credible next experiment therefore delivers an opaque occurrence
key at the root and every typed destination builder into the dormant keyed
`RUMViewTrackingState`. `updateUIView` must reconcile occurrence configuration and
attachment atomically. If updating a retained hidden reader remains too late,
applying `.id(key)` to only that SDK-owned reader is an experimental fallback; it
must never key customer content or reset customer `@State`. A shipping overload
or destination wrapper needs RFC/API review, must not serialize or describe route
values, and must define mixing with automatic tracking before use.

`EXP-086` adds the first overlapping native UIKit split run. In
`native-uikit-split-concurrent-scenes-20260913-093545`, RUM session
`ce5c7cc2-53e7-40ba-a127-f1887269c3da`, scene A was
`0C4ADCA5-128D-4D9C-A6EB-5DC3E92B1FAA` and scene B was
`343ABCC2-E15F-4BBA-ADC4-4A4214516C8D`. A's pop began at 09:35:34.741125;
B's S2 push began 0.714 ms later and completed while A's transition remained
open. B then completed its pop to the same S1 object and received a fresh RUM
UUID. Neither scene produced a false Primary occurrence.

A emitted only S2 `willMove(nil)` for its pop and never completed disappearance,
removal, or returned-S1 appearance before the final observation. The screenshot
showed B fullscreen, while accessibility retained roots for B returned-S1 and A
S2. No explicit activation, inactive, background, foreground, or disconnect
callback appeared in the capture, so the exact `UIScene.ActivationState` and cause
of the stalled A transition are unproven. This is a fullscreen-topology/harness
observation, not an SDK lifecycle defect.

The same run is a useful negative control for manual-source inference. A's S2
marker action `07db621d-6f30-4255-9e3c-266a76945f6b` and resource
`bda363f9-c245-4c68-b391-1f7baf39ef59` were emitted at 07:35:33.748 while A S2
`99602670-7e97-4f9b-ad05-68352dbce68f` was alive, but B S1
`cc3f7104-a9ba-42a7-b04e-988709c5a672` had become process representative one
millisecond earlier. Both marker APIs were public manual `addAction` and
`startResource` calls with no SDK scene target. The `source_scene`, native ID,
and screen fields are arbitrary diagnostic attributes and do not create trusted
SDK provenance. Their use of B S1 is therefore the approved source-less
last-interacted fallback, not a routing defect. The test must use an actual
source-bearing UIEvent/URLSession boundary before judging exact A ownership.

Backend view lifetimes were launch `6a066c02-51f6-4dd6-a2a5-6a1e4b0c278e`, A
Primary `94325cf3-8405-4feb-8edc-4ed4960f754d`, A S1
`bcea0e0a-41e5-4067-903c-e305a6c3dc8e`, B Primary
`75727a3a-c9f4-4392-831f-2ac7234a9eea`, A S2
`99602670-7e97-4f9b-ad05-68352dbce68f`, B S1
`cc3f7104-a9ba-42a7-b04e-988709c5a672`, B S2
`dd8fa541-c0cc-4184-b772-b80f5c5e6f94`, and B returned S1
`3aa0ee7f-814e-4823-b2a8-0021b79eafc5`. Totals were eight views, seven actions,
seven resources, two long tasks, one vital, zero errors/crashes. Uploads returned
202 with `B250CC5F-DB6E-4D80-A36E-E3082D1262FD` and
`18D7ED4B-5A54-4D0D-A878-DC37917841C6`. The final artifact stem is
`DeviceInteractionSynthesize/UIKit Split Concurrent Scenes-09_35_41_644-`.

`EXP-087` exercises the new no-selection control before attempting adaptive
collapse. Run `e3c21695-d4a3-4a05-a606-7f192836e577`, session
`d2f7b981-9877-47e9-9147-ea6b01712c6a`, used route-owned split tracking with
`DD_MULTI_SCENE_SPLIT_INITIAL_SELECTION=none` and
`DD_MULTI_SCENE_SPLIT_AUTOMATIC_SEQUENCE=0`; second-window and navigation autoruns
were disabled. The UI hierarchy showed the Selections sidebar and an empty detail
area. Backend intake contained 15 matching events, three total views, no Detail
occurrence, and no error/crash. Build
`BuildProject-Log-20260913-094444.txt` passed. This is a positive empty-detail
baseline, not an adaptive transition result.

The exact resize request
`xcrun devicectl device appResize start -d B4E4F039-CA5D-4D04-A904-1D71099BE651
--preferred-size 1024x768 --corner-radius 0 --json-output /dev/stdout --timeout 60`
and the corresponding `device info appResize` request both failed with CoreDevice
error 1001. The simulator does not support capability
`com.apple.coredevice.feature.resizableappmanagement`. No width was requested or
acknowledged, so regular → compact → regular lifecycle and RUM semantics remain
open. The hierarchy artifact is
`DeviceInteractionSynthesize/Adaptive Split Resize Empty Detail-09_48_47_882-hierarchy.txt`.

`EXP-088` closes a narrower action/resource gap discovered while classifying
`EXP-086`. The existing `UIApplication.sendEvent` interception already establishes
a trustworthy execution-local RUM context around customer target-action dispatch,
but public manual actions and manual Resource starts ignored it. They now resolve
the exact handoff view first, its scene second, and the process representative only
when neither exists. This applies to `addAction`, continuous action start/stop, and
all URLRequest, URL, and method/string Resource-start overloads. Resource metrics,
success, and error completion commands deliberately remain untargeted: existing
resource-key owner lookup must complete an A-owned Resource even when B is current.

Focused `MonitorTests` pass 15/15 and cover exact-view precedence, scene fallback,
unchanged source-less representative behavior, all three Resource starts, and a
source-less completion retaining its start owner. Build-for-testing reports zero
diagnostics. The complete `DatadogRUM` plan passes 1,122/1,122 with no failures,
skips, or not-run tests; focused source and test lint report zero violations.
Artifacts are `BuildProject-Log-20260913-095316.txt`,
`RunSomeTests/AADF4B45-9F69-4189-81BA-B1B238844172.txt`, and
`RunAllTests/11359C12-1C7D-4473-B74F-B3DD3CFF8019.txt`. This change does not alter
`EXP-086`: its lifecycle marker ran after the UI-event scope and remains correctly
source-less.

`EXP-089` adds a physical UIKit control whose predicate deliberately returns
`nil` while `UIApplication.sendEvent` still resolves the touched scene. Build
artifact `BuildProject-Log-20260913-101118.txt` passed. The clean run used native
scene IDs `343ABCC2-E15F-4BBA-ADC4-4A4214516C8D` for A and
`37D00025-9F80-474C-BC1C-2264798BE001` for B. Initial A S2
`246bf6a4-c43f-44a5-b9e0-176cefa2752c` yielded to B S2
`fc07dc1c-7c7b-4395-bff2-975c5454318c` in the fullscreen topology. Switching
back to A created fresh A S2 `62562932-7ce3-44a1-b8d8-4f7c01d9f82e` at
08:13:01.366Z; B became inactive by 08:13:02.302Z. The physical button tap did
not occur until 08:13:15.935Z, so A was already the process representative.

The predicate logged the exact filtered A control and backend intake contains no
automatic tap. Synchronous manual action `e24189eb-56ec-4328-b5fe-70e7fb8d4911`
and Resource `70368cdb-b899-46ea-b54d-1e2c80b25317` used fresh A S2. The GCD
post-scope action `c0646d2b-37f8-4e4b-9146-ed79cbbdc66c` and Resource
`1cf9c043-ca22-4b50-ae03-4a8a91040344` also used A S2, correctly following the
last-interacted representative after losing the event handoff. Resource
completion stayed with each start owner. Backend totals were ten views, eight
actions, eight Resources, and zero RUM errors; no crash was observed. The run is
live proof of the interception/control path and compatible fallback, but not of
exact-handoff precedence over a different representative. Repeating fullscreen
window activation cannot provide that discriminator because activation itself
materializes a new occurrence. Arrange both windows simultaneously visible first.

The next source/focused-test sweep tightened already-known ownership rather than
inventing provenance. Exact-view actions now also update the last-interacted
representative; Resource completion uses its key-owned start scope; manual errors,
manual views, per-view mutations, and internal view commands consume a trustworthy
event handoff; and OpenTelemetry now uses the same span-start snapshot selection
as the native tracer. These changes are commits `85da8fa9c` through `08126fedd`.
The final module results are recorded in `EXP-101`.

`EXP-090` and `EXP-091` validate the debug-only keyed SwiftUI seam added in
`119afcac6` and installed in the probe by `c5cf8cfaf`. A same-type Detail
replacement receives a new RUM UUID without replacing customer state, while a
coalesced push/revert creates no synthetic occurrence. Returning to retained Home
then exposed a separate ordering issue in `EXP-092`: Home2 existed eventually,
but its first outer lifecycle work still used Detail. `EXP-093` rejected changing
only the hidden reader's `.id`; `EXP-094` measured the customer-owned path setter
as the earliest supported signal, roughly 4.6 ms before the marker.

The first weak per-window occurrence source did not pass. `EXP-095` delivered
false, and rebinding from both reader callbacks in `EXP-096` changed nothing.
Temporary labels in `EXP-097` isolated the reason: SwiftUI keeps Home's state but
detaches its hidden UIKit reader while Detail is on top. The state therefore had
a prior concrete scene but no current attachment when the path contracted.
This was `.detached`; `.attached(nil)` is a distinct unresolved state and remains
rejected.

`eece6ec17` retains the last concrete scene only across ordinary reader
detachment, clears it on scene disconnect, and requires a newer concrete reader
mount before reuse. A source retains registrations weakly, never replays an old
route selection, requires a previously started and currently inactive matching
route plus a greater binding generation, and is owned per navigation window.
`EXP-098` backend-proves that this moves Home2 before its immediate action and
Resource without resetting the retained Home value. `EXP-099` repeats the pass
after source delivery was routed through the existing interactive-transition
arbiter.

`EXP-100` preserves two native gesture attempts as tooling failures rather than
semantic evidence. Cancel used `t 333 600 f 380 600 0.8`; finish used
`t 330 600 f 650 600 0.8` from one point inside a 375-point-wide app window.
Neither produced a transition signal. Focused source tests still exercise the
real arbiter's cancellation and successful-completion branches, in addition to
ordinary detachment, `.attached(nil)` rejection, disconnect/remount, scene
migration, duplicate-generation rejection, and same-key A/B source isolation.
The final focused set passes 13/13. The complete RUM result is
`RunAllTests/AE2B46B1-C858-4045-8AA5-855A8C020E0A.txt`; the final probe build is
`BuildProject-Log-20260913-131828.txt`.

`96222a6b1` extends the keyed occurrence input to regular-width
`NavigationSplitView` without applying `.id` to customer content. Each split root
owns its source and generation counter. An active Detail 1 → Detail 2 replacement
updates the stable hidden reader in place; the source correctly reports
`delivered=false` because no inactive retained route needs early reveal. The keyed
state still atomically replaces the RUM occurrence before the selection marker.

`EXP-102` proves this first in one scene. The same Detail tracking witness
`0x108cd0c40` survived the change, generation advanced 1 → 2 → 3, and backend
intake contained exactly four views, three actions, and three Resources. Detail 1
`cafa2f12…`, Detail 2 `70a9f413…`, and Placeholder `fa8ce9d7…` each owned their
marker pair; no error or crash appeared. The first launch inherited a compact
375-point Stage Manager window and skipped the sequence, so its separate session
`b51c1f30-d04b-4fd3-9d0a-c0fc0029eae3` is setup-only and must not be combined
with the authoritative session.

`EXP-103` repeats the result concurrently. Scene A
`343ABCC2-E15F-4BBA-ADC4-4A4214516C8D` and scene B
`E2F1B50F-904F-4DDC-9DF2-5D6EA81844AF` both logged regular width, stable but
scene-distinct Detail witnesses, independent generations, and exact local
markers. Backend session `a354f09b-557c-43a7-815c-95379ea3504d` contains launch
plus six semantic views, six exact actions, six exact Resources, and zero RUM
errors. A's path is `cdb5d2ba… → e5bd8c83… → 0c2e5910…`; B's is
`dad91422… → 4b20cd87… → b6fca157…`.

The two sequences and upload HTTP 202 responses completed roughly ten seconds
before the final hierarchy capture crashed simulator `backboardd`. Crash report
`backboardd-2026-09-13-134940.ips`, incident
`42E33D3B-0889-431B-B2FC-9C5165409157`, attributes SIGABRT to Core Animation's
Metal simulator device. There is no probe-app crash report. This does not weaken
the completed RUM telemetry result, but it does leave stable simultaneous-window
presentation for physical-device validation.

`EXP-104` extended the regular-width sequence to
Detail₁ → Detail₂ → Placeholder → Detail₂(returned). This time SwiftUI replaced
the platform reader when returning from Placeholder. The navigation source
synchronously started returned UUID `ee1fd0c4-c0b9-44d7-9a44-dc45a8557e1b`, but
the outgoing state stopped it roughly 6.6 ms later; the replacement reader then
started `03545f03-2d40-45e0-aff1-c7588891d832`. Only the second UUID owned the
marker action and Resource. Backend session
`0540b52f-b398-4886-b956-421cffa64df0` confirms five semantic views plus launch,
so this is a conclusive remount handoff failure rather than a simulator gesture or
topology limitation.

`60da5316b` lets a source-created occurrence remain canonical while SwiftUI
decides whether to reuse or rebuild the subtree. A replacement tracking state may
adopt that already-published UUID without a second start and then owns its later
lifecycle and stop. Only the newest eligible registration may reveal a route, and
superseding a pending handoff settles the earlier state so disappearance cannot
remain suppressed.

`EXP-105` validates the fix locally, in emitted payloads, and through intake.
Returned Detail₂ UUID `761fe74b-8450-422e-a7ff-51f56f8477bd` stayed active across
replacement witness `0x10b0e6840`; no inactive event or second UUID intervened.
Its materialization marker, action, and Resource all used that same view. Backend
session `d4f3597e-2254-4b68-897a-5530299083cb` contains five views total—launch
plus the four committed semantic occurrences—four actions, four Resources, two
long tasks, one session, one vital, and no error or crash. The focused
navigation-source/state set passes 52/52, including 17/17 source cases, the full
RUM plan passes 1,151/1,151, changed Swift files lint with zero violations, and
the native probe rebuild succeeds in
`BuildProject-Log-20260913-143157.txt`.

`6bee92ee7` completes the named-scenario phase of the deterministic harness.
`ProbeScenarioRunner` accepts `--probe-scenario`, `--probe-run-id`, and
`--probe-run-mode`, generates a run ID only when one is not supplied, rejects
unknown probe arguments/environment keys and contradictory legacy combinations,
and maps exact supported legacy profiles to the catalog. The generated hostless
test target compiles the Foundation-only harness sources directly; all 15 catalog
and resolution tests pass. Build-for-testing succeeded in
`BuildProject-Log-20260913-150315.txt`.

`EXP-106` checked the process boundary in the iPadOS 27 simulator. Valid run
`harness-phase1-valid-20260913` emitted the complete `regression.single-scene`
manifest before Datadog initialization, then started RUM session
`6f556658-1444-4ddf-8d9f-82ce0d5dea91` and produced distinct Home and Detail
payloads. Invalid run `harness-phase1-invalid-20260913` selected an unknown
scenario. Its captured output contained exactly the structured rejection manifest
and one human-readable rejection; it contained no Datadog SDK log, session, or
RUM payload. At that checkpoint the catalog modeled signal waits and semantic
expectations, but the observable driver and oracle were not implemented, so this
experiment does not claim that modeled timelines executed or passed locally.

`ff8750dc3` completes the structured-recorder and pure-oracle phase. The recorder
emits a versioned JSONL manifest and signals with distinct `ProbeSourceContext`,
mapper-observed `ProbeRUMContext`, and trusted combined semantic context. A RUM
view mapper reports document snapshots rather than inventing lifecycle callbacks;
the pure reducer treats the first observed UUID as a start and an active-to-false
change as its stop. It does not assume a `documentVersion == 0` snapshot exists.
Error records deliberately omit message, stack, causes, and headers. The oracle
uses mapper-observed UUID ownership, never the source scene/screen label, and
returns exactly `PASS`, `FAIL`, `SKIPPED`, or `INCONCLUSIVE`.

`EXP-107` validates that implementation. The generated probe test plan passes
24/24, including fixtures for a correct Home₁ → Detail → Home₂ return, wrong-view
attribution, a missing required event, a forbidden view, and an ignored gesture.
Live run `structured-recorder-live-20260913` selected
`regression.single-scene`, emitted its manifest first, and started session
`6b194ceb-b0d8-4d0c-8848-ab293594cb79`. Local records show
ApplicationLaunch → Home `081e6f2c-6121-4535-a05e-d2f6e4a6e4fe` → Detail
`f86c6dce-9707-4770-82cc-1d5a0def06d4`, with the corresponding markers using the
exact Home and Detail UUIDs. The initial Home mapper record lacked a native scene
session ID because tracking began before the scene reader resolved it; later
Detail records had the native ID. This is the concrete Phase-3 registry gap, not
permission to infer ownership from the source label.

The exact session-ID backend query returned 18 events: three views, six actions,
six Resources, one long task, one vital, and the session event. Intake reports
`view_count:3`, `action_count:6`, `resource_count:6`, zero errors/crashes, and the
same exact Home/Detail mappings as local JSONL. Mapper callbacks happen before
persistence/upload, so this backend result is the required independent acceptance
proof for the executed prefix. Xcode's device-interaction request then returned
`Skill not found`; no synthetic input was sent, no step acknowledgement or final
live oracle result was produced, and no visual UI state is claimed from the
console's destination-materialized signal. Home return and the three-repeat live
acceptance loop remain open and are routed through the device/human queue.

`acca8907f` updates every UIKit split scenario's expected timeline to the approved
one-current-destination model. Primary lifecycle remains recorded for diagnostics,
but the semantic oracle now forbids Primary in each scene; concurrent A/B split
scenarios forbid it independently. The focused catalog regression covers all nine
UIKit split scenarios and the complete probe plan passes 24/24. Historical
`EXP-074`/`EXP-075`/`EXP-079`/`EXP-080`/`EXP-082` through `EXP-084` remain valid
proof that Primary is no longer *restarted* and returned Secondary gets a fresh
UUID. Their initial Primary RUM views are now explicitly retained as gap evidence,
not reinterpreted as final success.

`abfb93d45` completes the exact scene-registry phase. The main-actor registry
maps each stable logical probe scene to one exact native scene session, holds its
`UIWindow` weakly, and stores readiness, activation, geometry, size classes,
current route, and disconnect generation. It rejects native aliases and live
logical remaps; disconnect invalidates the old handle, and reconnect produces a
new generation without disturbing peers. An optional future Window Execution
Context ID remains non-Codable internal state and is never copied into JSONL or
RUM attributes. Seven focused registry tests plus the existing harness tests pass
31/31. Build-for-testing succeeded in
`BuildProject-Log-20260913-164450.txt`; changed harness/test lint added no new
violation, and the large probe view retains its 18 pre-existing violations.

`EXP-108` validates the registry in a clean iPadOS 27 process. Run
`scene-registry-live-20260913-1647` first emitted scene A ready as native session
`E32B88D1-3EFB-435C-B002-EAE1FCD03E14`, disconnect generation 0, frame
955×1253, and regular horizontal/vertical size classes. It then recorded
foreground activation, the exact Home → Detail path mutation, and Detail
materialization with the same native identity. Mapper evidence recorded Home
`91826d58-50be-4057-8b3a-5a764db504c5` and Detail
`3d91c699-3a04-44d1-aacd-fe93187f5be8`. Backend session
`de29d1e3-0ff6-44bb-a3e6-14c17047429a` returned 18 events: three views, six
actions, six Resources, one long task, one vital, and the session event, with the
same exact Home/Detail ownership and zero crashes/errors.

The initial Home mapper snapshot still arrived before the scene reader resolved
the native session. The harness can join that stable logical scene to its later
exact registration; this does not prove that the shipping SDK has gained a new
scene boundary. Xcode's workspace interaction session successfully installed and
ran the app, but required the unavailable `device-interaction` skill for any UI
event. No synthesized input, visual claim, Home return, or final live oracle
result is attached to `EXP-108`.

`34ba7eabf` completes the first observable-driver slice. The driver addresses the
exact logical scene through `ProbeSceneRegistry`, executes only after declared
signals become observable, records every step acknowledgement, and emits exactly
one terminal semantic result. For `swiftui.stack.return`, it waits for scene A,
the Detail path mutation and destination, the returned empty path, and the second
mapper-observed Home occurrence. The final marker is emitted only after Home₂ is
proven, rather than after an arbitrary delay or a source-only lifecycle callback.

The first attempted run, `observable-home-return-20260913-1725`, exposed a
harness assumption rather than an SDK failure: SwiftUI retained the root Home
value, so its outer `onAppear` did not fire again even though the RUM state
correctly created a distinct Home₂. The wait was changed from
`destination:home#2` to the second mapper-observed `rum-view:home#2` occurrence.
The next clean run passed locally. A repeat,
`observable-home-return-20260913-1733-b`, then exposed a second evidence-ordering
assumption: during the navigation animation, the mapper delivered Home₁'s inactive
snapshot after Detail's start snapshot. Both required lifecycle facts existed,
but a strictly consuming sequence incorrectly failed them. View starts and work
attribution remain ordered; stops are now required eventual lifecycle facts that
may be observed after the next start. The wrong-view fixture still fails with an
actionable attribution reason, and the new ordering case has a focused test.

`EXP-109` is the corrected three-run acceptance set. Each run followed a clean
uninstall, acknowledged all six driver steps, and emitted one 7/7 `PASS`:

- `observable-home-return-20260913-1736-c`, session
  `272c5006-bf32-4ee9-9adb-3b75f9a39639`: Home₁
  `30ff5793-fead-441f-bbfa-725a9af94a7c` → Detail
  `4ca6ef28-651d-4ce4-abf3-b0740fddd8b4` → Home₂
  `03f41a11-e94b-4068-a31d-e72f98695344`.
- `observable-home-return-20260913-1739-d`, session
  `25cc4383-8f80-4ad8-9c44-0ef65771896b`: Home₁
  `bc6d76ab-1d35-467e-b7c7-38b33913b854` → Detail
  `d3d7648a-5a1f-4112-8e47-65cf73088b23` → Home₂
  `6352a4d2-44a8-4659-899b-a3ff6585136d`.
- `observable-home-return-20260913-1741-e`, session
  `11dba044-6d97-4095-a607-25ee742aa804`: Home₁
  `f5cf4344-c85e-49ed-b29d-d88d65f64c22` → Detail
  `51c3c342-0370-4e26-833c-d66f659837dd` → Home₂
  `d5edb3a6-ce21-448b-972f-eca980252811`.

Backend aggregation independently reports one launch, Home₁, Detail, and Home₂
view event in every run, exactly one post-return action and matching Resource on
that run's Home₂, and no error bucket. All 35 probe tests pass. This closes the
structured Home-return acceptance loop. It does not close automatic zero-code
SwiftUI semantics or the native interactive-pop rows; those still require their
own integration and recognized gesture evidence.

`4a1311dd4` extends the observable driver to three more deterministic stack
scenarios. It executes coalesced push/revert, same-type replacement, and
different-type replacement through the exact registered scene, then advances
only after the expected path and destination signals. The old delay-driven
autorun blocks are disabled for those scenarios. The semantic timelines also
require one decisive action and Resource on the final view, so view creation
alone cannot produce a passing result. Two focused driver tests cover the abort
and same-type replacement state machines; the complete probe plan passes 37/37.

`EXP-110` retains both live passes. The first clean trio established the driver
shape before final-marker Resources were part of the timeline:

- `observable-stack-abort-20260913-1800-a`, session
  `0550e989-8427-494f-b04a-505255a8acce`, emitted only launch and Home
  `f3691ed4-99b9-4fca-87c4-2c8afbd0452f`; no speculative Detail existed.
- `observable-stack-same-type-20260913-1803-a`, session
  `72dc8338-b5eb-470b-8d39-ecfa24f455ff`, emitted Home
  `68d9b0ac-14d2-423f-ab56-7403c2f931c3`, Detail₁
  `99ad3415-a5f9-40a0-b739-7f92662dfa5d`, and distinct same-named Detail₂
  `d43a295e-ad72-4fac-bb9a-893afc52c97d`.
- `observable-stack-different-type-20260913-1806-a`, session
  `e7a99a66-a9d4-45e0-9719-e152de01b1a3`, emitted Home
  `3bfd9740-7ba2-4b1f-be4a-9b5d3deb8fcf`, Detail
  `0013d81e-5fef-446f-97d1-514979989de1`, and Alternate
  `881a6ca0-820f-4ff3-80d1-20180ff5d7b8`.

After strengthening the catalog, each scenario was rerun after a clean uninstall:

- Abort run `observable-stack-abort-20260913-1810-b`, session
  `c8f6fb75-62cb-4f43-9515-988ae36d1586`, passed 5/5. Backend contains one
  launch and one Home `fb10de5b-f55b-436f-8d82-c1fba5d8ab7b`; all five
  actions and Resources, including `post-aborted-navigation`, use Home. There is
  no Detail or error event.
- Same-type run `observable-stack-same-type-20260913-1812-b`, session
  `5dea4da1-8949-4760-a89b-41c2758aebb0`, passed 6/6. Backend contains Home
  `22e06720-665e-4e67-b724-6c3243ca1545`, Detail₁
  `40d87f4b-275d-48ee-9615-6f908d96c93f`, and distinct same-named Detail₂
  `f75ca7dc-a3b9-431d-9696-7eb3e4b8f7d0`; the `binding-update-2` action and
  Resource use Detail₂. The Detail₁ delayed task ran after replacement and used
  the current Detail₂ view. Its source label records where the task was scheduled,
  but this scenario does not decide whether post-replacement work should retain
  its origin or follow the current destination; that marker is outside the pass
  criteria and remains a downstream causal-attribution follow-up.
- Different-type run `observable-stack-different-type-20260913-1814-b`, session
  `8b913d29-e0f5-4449-880f-7e7c823e3b91`, passed 6/6. Backend contains Home
  `47ac4967-d99c-49b5-ad0b-c3782e2d90c9`, Detail
  `b4cb7536-ab2e-4c42-b7b2-f882aede748d`, and Alternate
  `9a5ca46d-2eae-4078-b35d-11fc8ebd3d52`; the Alternate `on-appear` action and
  Resource use the Alternate view. No error event was reported.

These runs close the deterministic stack abort and replacement harness rows. They
do not change the product verdict: the passing route-owned debug input is the
prototype for the reviewed container-level semantic integration, while
transparent automatic SwiftUI discovery remains insufficient.

`96a6208ff` moves split-selection ownership to the registered scene root and
drives each mutation only after its prior destination is observable. The exact
scene executor now waits for the corresponding selection mutation, and repeated
destination waits derive occurrence order when the materialization signal has no
explicit counter. Every committed split destination requires its own view plus a
`selection-committed` action and Resource.

`EXP-111` preserves two probe-oracle corrections instead of hiding their failed
runs:

- `observable-split-selection-20260913-1831-a`, session
  `cc00fae2-3911-4846-b8b8-68f0c06b9c1f`, created exact Detail₁
  `5bc8e777-32e2-47ed-b551-4cdbdd5a5fc9`, Detail₂
  `8c48507a-0d6a-4c86-ac84-89eeb36f5f00`, and Placeholder
  `e3a30472-39e0-4aa1-98e8-378f41afc310` occurrences. Its local oracle failed
  after 6 matches because Detail₂'s asynchronous Resource completed after the
  Placeholder view started. The SDK ownership was correct; Resource completion
  is now required without treating its callback time as navigation order.
- The clean corrected run `observable-split-selection-20260913-1840-b`, session
  `ab78101b-8528-4e0c-9505-1d0bc926ba91`, passed 10/10. Backend contains launch
  plus Detail₁ `68d160a9-cf1e-426a-beae-349b550de8c2`, Detail₂
  `78f47d47-47ca-4f52-843d-8e2849012551`, and Placeholder
  `ac4b1b97-aec7-4065-b322-ee61bce1683e`. Each semantic UUID owns exactly one
  action and one Resource; no RUM error exists.
- `observable-split-return-20260913-1843-a`, session
  `84a12a1a-b251-41e0-8f9a-53404427b628`, matched all 12 ordered facts, including
  fresh returned Detail₂ `7a395323-2cb2-4770-baf0-1dc192ddf6e0`, then falsely
  failed its unordered completion condition on the earlier same-named Detail₁
  action. Completion evaluation now keeps searching for a correct later
  occurrence and retains the first wrong-owner diagnostic only if none exists.
- The clean corrected retained-return run
  `observable-split-return-20260913-1844-b`, session
  `9f5a87b0-75b0-4da3-9902-0ce3dc059c57`, passed 13/13. Backend contains launch
  plus Detail₁ `60446d50-a143-402c-ac51-0d9826d4d25a`, first Detail₂
  `772f3280-9d42-4050-93d4-beaa2a9cd9c9`, Placeholder
  `e9b5a519-e3c2-48b4-8587-f9bbb9373132`, and returned Detail₂
  `bc2d8fa9-e758-4f57-8c25-fdd0b34781c2`. All four action/Resource pairs use
  their exact occurrence and no error exists.
- The clean automatic control `observable-split-automatic-20260913-1846-a`,
  session `ba04a828-38f8-4135-8e1d-4c25ca875fb8`, drove the same six steps and
  failed 0/9 at the first required semantic view. Detail₁'s marker pair used
  ApplicationLaunch `e486bf8f-9f02-49fa-8e35-6b5637ecb6fb`; Detail₂ and
  Placeholder both used internal hosting view
  `27156b00-b1fc-44e2-a08a-3ebb41e83048`. Backend also contains transient
  fallback/navigation-host views, but no semantic Detail₁, Detail₂, or Placeholder
  view. This is the controlled zero-code gap, not a crash; no RUM error exists.

The complete probe plan passes 40/40, including focused regressions for both
oracle corrections, and repository lint reports zero violations. These runs
upgrade the existing split prototype evidence to deterministic local/backend
acceptance while leaving the reviewed public semantic integration unimplemented.

Focused legacy and keyed state-machine coverage is now 35/35 and includes mount
idempotence, disappearance, transient detachment, same-key return, scene
migration, descriptor immutability, stale/unversioned lifecycle rejection, and
disconnect/remount fencing. Arbiter coverage is 38/38, and
the publisher regression proves replacement uses the committed occurrence
descriptor rather than a stale modifier fallback. A separate session-scope
regression proves that
reusing Home's platform identity after Detail creates a second Home UUID, yielding
three distinct RUM occurrences for `Home → Detail → Home`. The earlier complete
`DatadogRUM` test plan passed 1,039/1,039 in
`Test-DatadogRUM-2026.09.12_23-26-06-+0200.xcresult`. The immediately preceding
full run was 1,038/1,039 because the unrelated timeseries pause/flush timing test
observed one extra flushed batch; its isolated retry and the clean full rerun both
passed. After `EXP-045`, all 19 gate/provider tests passed in
`Test-DatadogRUM-2026.09.13_01-11-51-+0200.xcresult`, and the complete suite passed
1,058/1,058 in `Test-DatadogRUM-2026.09.13_01-12-09-+0200.xcresult`. Both the SDK
test build and native probe build in Xcode 27, and repository lint reports zero
violations. These checks and runtime runs justify retaining the narrow candidate
for continued evaluation. They do not turn `UIViewRepresentable.makeUIView` into
an Apple-documented visibility guarantee; aborted construction, restoration,
split-view, stable visible-peer closure, and additional container stress remain
release gates. Modal occurrence navigation passes, and immediate closing-scene
ownership is safe in the exercised fullscreen topology.

### 2026-09-13 — Signal-driven UIKit transition acceptance

`df0322619` moves `uikit.split.pop-cancel` and
`uikit.split.pop-finish` from scheduled transition controls into the observable
driver. Signal schema 4 adds explicit transition progress and resolution-request
records. The exact scene executor now begins the real
`UIPercentDrivenInteractiveTransition`, waits for UIKit to accept it, advances it
to 35 percent, asks it to cancel or finish, then waits separately for the
transition coordinator's observed resolution. A requested outcome is therefore
not accepted as proof of the actual outcome. The semantic timelines require S1
and S2 occurrences plus their post-materialization action/Resource pairs;
cancellation forbids a second S1 and requires post-cancel work on the original
S2, while completion requires a fresh returned S1 plus post-finish work.

The first exact run, `observable-uikit-cancel-20260913-1911-a`, session
`dbf47e00-d912-4ef8-862b-abe462931710`, failed locally at its first expectation
because the SDK created structural Primary view
`f7dd356a-d5ea-482c-aa73-98ecb83d6d42`. ApplicationLaunch was
`42e8ff59-e946-4478-bf8d-0a217bc09921`, the native-host fallback was
`57c846fd-cf7a-441d-ab20-0662ccfa8371`, S1 was
`6e35638c-8c9a-4356-b124-b727cf754314`, and S2 was
`bba31eb6-d408-446d-ab8a-5f3f2ca260a7`. The transition itself was conclusive:
begin, 0.35 progress, cancel request, and cancelled coordinator completion were
all observed; UIKit reappeared S2 but RUM kept the same S2 UUID, and the decisive
post-cancel action/Resource used it. Backend intake contained 18 events and no
error. This isolated a product-model failure rather than a transition or crash
failure.

`f4c8669c0` fixes that stock split case without changing the wire format or
ordinary-app path. On iOS 27 only, and only when the bundle declares multiple
scenes, concurrently displayed Primary and supplementary columns in a
regular-width `UISplitViewController` are classified as structural and ignored
by automatic view start. Compact, older-system, and ordinary-app behavior stays
legacy. Same-column disappearance must still enter pending reconciliation after
Primary is absent; retaining the earlier requirement for another tracked column
would bypass cancellation handling and lose fresh returned occurrences.

The first corrected runs established the fix before the final harness cleanup.
Cancellation run `observable-uikit-cancel-20260913-1916-b`, session
`edc0ba78-6225-4271-9b7d-97dcb34baa2a`, passed 11/11 with S1
`ba97a38e-8939-4f64-bdce-443aeaf29d13` and retained S2
`cc2f2a94-32ba-4328-8d93-0c3627995835`. Completion run
`observable-uikit-finish-20260913-1917-a`, session
`7ec940ff-5960-45b9-83c6-01b24a04e1cc`, passed 13/13 with S1
`98c5fc4d-7173-4bf5-83e2-d14591a99e55`, S2
`f1d2299a-1827-4ffe-ae0b-55905427869e`, and fresh returned S1
`49aa9f6d-dfa4-45cd-aaac-f3f63f18bd9b`. Both had exact semantic owners and no
Primary, but the probe's diagnostic Primary callback emitted a marker onto the
startup fallback after production tracking intentionally suppressed Primary.
That was a harness-only attribution artifact. Observable UIKit runs now retain
the Primary lifecycle signal as negative evidence without asking RUM to emit
Primary work; legacy non-observable controls retain their prior marker behavior.

Two clean-install final runs close `EXP-112`:

- `observable-uikit-cancel-20260913-1923-c`, session
  `df3e4faf-727a-4e5b-ae73-c7bac5984658`, acknowledged all six steps and passed
  11/11. S1 `894c9fbc-903e-47e2-98a6-ca63218b5540` owns one action/Resource
  pair. S2 `24edf931-4823-4863-85d5-354be1fcea3e` remains the only S2
  occurrence across cancellation and owns three pairs: initial materialization,
  UIKit's cancelled-transition reappearance, and `post-cancel-resolution`.
- `observable-uikit-finish-20260913-1925-b`, session
  `7f1dcd04-7b71-4285-a39a-89cfb81d6cd4`, acknowledged all six steps and passed
  13/13. First S1 `983bb960-5639-494f-b315-4bd56e609675` and S2
  `b99009d3-0be1-4c59-af6a-e25a1b78f9ec` each own one action/Resource pair.
  Returned S1 `38058b25-0085-40fb-a248-486cad5e7787` is a fresh occurrence and
  owns both `post-return-materialization` and `post-finish-resolution` pairs.

Backend aggregation independently contains no Primary and no error bucket for
either final run. The cancellation session has launch, native-host fallback, S1,
and S2 views; the completion session adds the distinct returned S1. The fallback
owns no action or Resource in either session. It is the native SwiftUI host's
startup automatic view and remains a separate semantic-discovery issue, not part
of the structural UIKit-column fix. The probe uses a custom UIKit predicate only
to give its child controllers stable semantic names and scene metadata; lifecycle
start/stop remains automatic, and no temporary scene field is added to the SDK
wire contract.

Two focused driver tests cover the complete cancel and finish state machines.
Seven focused handler tests cover old-before-new handoff, fresh return,
replacement, structural suppression, ordinary-app compatibility, cancelled
reappearance, and legacy immediate restart. The final probe plan passes 42/42,
the complete DatadogRUM plan passes 1,153/1,153, both projects build through
Xcode 27, and repository lint reports zero violations across 713 source and 699
test files. This closes deterministic stock UIKit cancellation/completion and
regular structural-Primary filtering. It does not close the application-subclass
container, compact/adaptive transition, stable simultaneous-window topology,
genuine human edge gesture, or live ordinary-app rows.

### 2026-09-13 — EXP-113: exact scene open, close, and peer continuity

The observable driver now gives `open-window` two explicit identities:
`scene` is the already-live source executor and `value` is the requested target.
It rejects a missing, identical, undeclared, or already-live target, invokes
SwiftUI `openWindow(id:value:)` only through the exact source root, and waits for
the target's existing `scene-ready` signal before acknowledging the step.
`close-window` invokes `dismissWindow(id:value:)` through the exact target root
and waits for that target's existing disconnected lifecycle signal. No step
selects a member of unordered `UIApplication.openSessions`.

The `windows.close-with-resource` scenario is now fully observable rather than
timer-driven. It waits for A, asks A to open B, emits `before-close` in B, closes
B, then emits `after-peer-close` in A. Its timeline requires the B pre-close
Resource on B Home occurrence 1 and the A post-close action and Resource on A
Home occurrence 1. Replacing or restarting A while B closes therefore fails the
scenario even if the marker name is otherwise present.

The first clean attempt, `observable-window-close-20260913-2016-a`, session
`6a37d312-8ca1-41fc-87e4-b42d5142fb64`, opened B and observed distinct A/B Home
UUIDs. Xcode's launch session expired after B's `scene-ready` and before the open
step acknowledgement or a terminal semantic result. It is inconclusive and is
not support evidence; it also emitted no SDK crash evidence. A new clean install
was required rather than interpreting the partial prefix.

The final clean run, `observable-window-close-20260913-2020-b`, session
`be396759-0393-42e1-b08e-acb2a5cb0c7c`, acknowledged all five steps and emitted
one 9/9 `PASS`. Scene A retained native scene
`58904B41-3982-4B3E-A35A-49ED0BA83ABE` and Home view
`f7f72acf-3541-4cfc-bf68-0d87b8ac939a`. B resolved as native scene
`E7CF8AF3-4EA1-4CF9-A932-2A051319C09E` with independent Home view
`22dce95f-2536-4374-9340-c1c5d386fbb4`. The exact evidence chain is:

1. A's executor requested B and the driver acknowledged B's readiness.
2. B's `before-close` action and Resource both used B Home `22dce95f…`.
3. `dismissWindow` ran through B's executor and B emitted disconnect generation 1.
4. A's `after-peer-close` action and Resource both used the original A Home
   `f7f72acf…`; A did not restart as Home occurrence 2.

Backend aggregation contains independent A and B Home views, four actions and
four Resources on each, one long task on each, and no error bucket. A targeted
raw query independently confirms the decisive B pair carries source scene B and
view `22dce95f…`, while the decisive A pair carries source scene A and view
`f7f72acf…`. This confirms payload persistence and backend interpretation, not
only mapper output.

Two boundaries remain explicit. Device Hub presented each window fullscreen and
reported both scene snapshots as `foreground-inactive`; this run proves exact
scene addressing and surviving A ownership, but not two simultaneously visible
interactive windows. Exact activation is still unsupported by the driver. Those
rows stay in the physical-device/human queue. This slice changes the evidence
harness only and does not by itself expand the shipping SDK support claim.

Two discarded implementation paths are preserved for handoff. The first draft
added a separate `scene-control` signal and let `open-window` choose an implicit
opener; review showed the existing readiness/disconnect signals already provide
the effect acknowledgement and that implicit selection would hide the very
source identity under test, so the draft was removed before validation. The first
focused test also constructed B's `UIWindow` inline; the registry intentionally
owns windows weakly, so the fixture immediately lost B. Retaining the window in
the test fixed the fixture without weakening production ownership. The complete
probe plan passes 43/43 and repository lint reports zero violations across 713
source and 699 test files. Commit `45e5999e4` contains the exact-path harness
checkpoint.

### 2026-09-13 — EXP-114: exact activation and simulator boundary

The harness now supports exact activation without consulting unordered
application session collections. `activate-window` resolves the requested
logical scene through `ProbeSceneRegistry`, invokes activation for that registered
`UIWindowScene` session, and acknowledges only after the target's latest lifecycle
state is foreground-active. The scenario then waits for the peer's background
state before it emits a marker or evaluates a fresh view occurrence. A scene-state
wait is a latched current-state condition: it accepts the latest exact-scene state
even when the background notification arrived before target activation was
acknowledged, but cannot accept a state superseded by a later lifecycle signal.
A missing transition produces `INCONCLUSIVE`, not `FAIL`.

The first install attempt never launched because the previous Xcode
device-interaction session had expired. It contains no runtime observation and
must not be interpreted as an app or SDK failure.

The first completed run,
`observable-window-activation-20260913-2039-a`, session
`d2d11fda-28ce-4fce-bf46-cd858ce49adb`, used the scenario's earlier contract.
Scene A was native `58904B41-3982-4B3E-A35A-49ED0BA83ABE` with Home
`4c2012c5-2596-4b88-b462-abbfbf6d396b`; scene B was native
`AA98B535-9419-4A8A-9E6B-AEB4094DE153` with Home
`ee3f5828-ae47-4ad8-bd0e-67a88c2f1fc1`. All ten exact commands were
acknowledged, but the local oracle failed because A-labelled markers following an
A activation still used B. Backend intake contains only the original A/B Home
views plus ApplicationLaunch: A Home owns four actions and four Resources, B Home
owns six of each, and each owns three long tasks.

That result is not an SDK routing defect. `emit-marker` calls public RUM APIs
outside any UI-event handoff. Its `scene` field is probe source metadata, not
trustworthy SDK provenance. The approved compatibility behavior therefore keeps
that source-less work on the last-interacted/process representative, which
remained B until B closed. The simulator also kept both native scenes
foreground-active, so the activation request never provided the focus transition
needed to expect a fresh A occurrence. The earlier semantic failure is retained
as a probe-contract correction and must not be used as a shipping support verdict.

The scenario was then tightened to require target foreground-active and peer
background before any occurrence or ownership assertion. Run
`observable-window-activation-20260913-2056-b` reached exact B activation and
started waiting for A background, but the Xcode launch/stdout session expired
before the timeout and terminal result. This is an inconclusive prefix only.

The clean retry, `observable-window-activation-20260913-2059-c`, locally opened
RUM session `fe55cea1-4c9f-4a72-97e0-398c4302ed71`. A was native
`2B3FBB41-977C-464D-9C0D-2E1340299D96` with Home
`23c33ee8-2190-4fe9-a3af-4587955b323e`; B was native
`4171C189-4F70-44D1-886F-04EE885AE37F` with Home
`b73dcf08-597b-4d1a-8f99-d7d4d80873aa`. It again reached exact B
foreground-active while A remained foreground-active. Before the harness's
10-second state timeout, simulator `backboardd` PID 70194 received SIGABRT. The
diagnostic `backboardd-2026-09-13-205937.ips`, incident
`46F71CC6-9329-4D72-A069-02F83F1928F7`, identifies the faulting
`com.apple.coreanimation.display.primary` thread and an abort from Metal texture
validation during CoreAnimation rendering. Probe PID 71587 did not crash. There
was no terminal semantic result because the system compositor failed first, and
exact run-ID and session-ID backend queries returned zero events. This is a
simulator-system interruption, not SDK crash evidence or an attribution result.
The simulator was shut down and booted after the incident. An earlier process
check also failed because this simulator image has no `pgrep`; that command error
must not be mistaken for a missing probe process.

Two implementation corrections are retained. `SceneSessionReader` now defers its
registry callback to the next main-actor turn; the synchronous draft mutated
SwiftUI state while the view was updating. A weak-window registry test now scopes
its `XCTUnwrap` temporary in an autorelease pool; the direct unwrap extended the
window lifetime under the current compiler/runtime and falsely suggested that the
registry retained it. Neither correction changes production SDK ownership.

Terminal semantic JSON is now mirrored through OSLog so an ordinary Xcode console
session expiry does not discard a completed verdict. Two focused activation and
state-condition tests raise the probe plan to 45/45. Repository lint remains clean
across 713 source and 699 test files. Commit `4d1783198` contains only the harness
slice. No production SDK source changed. Do not repeat the rapid A/B activation
loop on this simulator; the prepared scenario belongs on iPhone Duo or a physical
multi-window iPad.

### 2026-09-13 — EXP-115: explicit SwiftUI authority with automatic tracking

The first implementation slice for the approved SwiftUI coexistence contract is
internal and iOS 27 multi-scene-only. `RUMSwiftUIViewAuthorityRegistry` records
weak pairs of the explicit modifier's hidden scene observer and tracking state.
When automatic controller discovery fires, it suppresses the automatic SwiftUI
candidate only if an explicit state is currently appeared, its observer is still
attached to a window, and that observer is a descendant of the candidate
controller's view. A separate sibling controller is not suppressed. UIKit
predicate acceptance is evaluated first and is unchanged. The registry is not
created for single-scene applications, iOS 15-26, or configurations without
automatic SwiftUI tracking.

This containment rule intentionally suppresses a structural hosting ancestor
that would describe the same explicit subtree. It does not claim that one
hosting controller containing several independent customer navigation containers
can itself represent all of them: the reviewed container integration still needs
an explicit authority boundary for that case. The registry is a runtime
deduplication mechanism, not the public path/router API.

The clean run `semantic-authority-coexistence-20260913-2146-a` used the existing
signal-driven `swiftui.stack.return` scenario while enabling
`DefaultSwiftUIRUMViewsPredicate` and the explicit route-owned occurrence path at
the same time. It emitted one terminal 7/7 `PASS` with no issues. Mapper output
contained this unique view-occurrence sequence:

```text
ApplicationLaunch  db302964-bab6-49d5-84bd-548887705d85
ProbeHomeView H1    6eb25220-6d96-4233-921b-9f75e53cf360
ProbeDetailView D1  3a3f8924-8ef0-4f81-a4fb-d8fd142f31b3
ProbeHomeView H2    dab1c405-1013-4c48-bc6d-cb1d6c731471
```

Repeated mapper snapshots for one UUID were normal document updates after
actions and Resources, not new starts. No extra hosting-controller name or view
UUID appeared. H1 and H2 remained distinct even though SwiftUI reused customer
content state.

Datadog query
`@context.probe.run_id:semantic-authority-coexistence-20260913-2146-a`
returned session `fae57f5a-ba01-4d42-9e32-2774090b1585` and exactly four view
buckets matching the mapper UUIDs above. Aggregate intake was nine actions, nine
Resources, four views, three long tasks, one session, and one vital. This is
backend evidence that coexistence did not create a duplicate automatic view in
the exercised container.

Focused tests cover active containment, detached/never-appeared state, an
unrelated sibling controller, handler suppression, and UIKit precedence. The
complete RUM plan passes 1,157/1,157 on a clean rerun; an immediately preceding
run had one unrelated timeseries sampling timing failure that passed both in
isolation and in the clean full rerun. The native probe passes 45/45 and repository
lint reports zero violations across 713 source and 699 test files. Commit
`85d03e5ee` contains the six source/test/probe files. The probe project file and
local xcconfig remain excluded.

This closes only target-scoped coexistence for an already explicit semantic
boundary. It does not make transparent automatic SwiftUI navigation semantic,
does not yet let a customer install one resolver on a `NavigationStack`, and does
not yet prove automatic tracking in a separate live container or scene while an
explicit exception is active. Those are the next integration/runtime rows.

### Attempts not to repeat

- Do not infer support from the integration runner merely having a scene delegate;
  its multiple-scenes flag is false.
- Do not retry the unmodified Example target on iOS 27. It builds but cannot launch
  until its app-delegate-owned window is migrated to the required scene lifecycle.
- Do not retry `make ui-test-podinstall` until the locked bundle has been installed
  with a consistent Ruby toolchain; the failure occurs before pod installation.
- After regenerating Pods with CocoaPods 1.15.2 under Xcode 27, reapply the local
  iOS 15 deployment-target workaround before building the Runner.
- Do not use named SDK instances per scene as a shortcut. It would split application
  telemetry and does not solve shared instrumentation or downstream context.
- Do not expose or copy values from `Datadog.local.xcconfig` into source, logs, or
  this document.
- Do not rely on an exact `git add` path list to isolate a checkpoint while the
  local xcconfig is pre-staged. Ordinary `git commit` includes every staged path.
  Use `git commit --only -- <exact paths>` or an isolated index, then verify both
  the commit tree and the xcconfig's original `AM` state.
- Do not consider callback counts, compilation, or crash safety proof of correct
  semantic attribution.
- Do not treat `probe.source_scene` or `probe.screen` as RUM ownership. Those
  fields describe the call site. Only mapper/backend view UUIDs and trusted scene
  association establish where RUM attributed the event.
- Do not treat a probe source label on a plain public RUM call as trustworthy SDK
  provenance. `EXP-114` correctly kept such source-less markers on the
  last-interacted representative. Exercise an actual UI-event handoff or an
  explicit target before judging exact scene attribution.
- Do not treat a mapper callback as persistence or upload proof. It observes an
  event before storage/filtering; retain an exact backend query for support claims.
- Do not serialize navigation on Resource completion to make a semantic timeline
  look ordered. Resource mapper callbacks describe completed work and may arrive
  after the next view starts; require their exact frozen owner as an eventual fact.
- Do not fail an unordered completion condition on the first earlier event with
  the same name. Repeated destinations intentionally repeat marker names; keep
  searching for the requested occurrence, then report the earliest ownership
  violation only if no correct event exists.
- Do not require a first RUM view snapshot with `documentVersion == 0`. The live
  structured run first observed Home at version 1, so semantic start is derived
  from the first observed UUID and stop from an active-to-false transition.
- Do not claim visual UI state because console logs say a destination materialized.
  The Xcode device-interaction guidance is now available, but the completed
  `EXP-115` session had already expired before its opaque interaction key could be
  handed to the observer. That did not block its auto-driven semantic run or
  read-only OSLog verification. Use a live key plus hierarchy/screenshot or human
  observation for specifically visual claims, and recognized coordinator/path
  evidence for native gesture claims.
- Do not treat the probe scene registry as a shipping SDK fix or serialize its
  future Execution Context seam. It makes exact experiment addressing and joins
  deterministic; production RUM scopes must still preserve their own scene
  ownership, and backend Execution Context serialization is separate work.
- Do not add a second scene-control acknowledgement stream or let `open-window`
  choose an implicit live source. Existing `scene-ready` and disconnected signals
  are the effect acknowledgements; explicit source and target identities keep the
  command itself testable.
- Do not make the scene registry strongly own `UIWindow` merely to stabilize a
  test. The exact-scene test must retain its fixture window just as UIKit retains
  a live application window; weak registry ownership is intentional. Scope any
  `XCTUnwrap` temporary before asserting deallocation because it can extend the
  fixture lifetime under the current compiler/runtime.
- Do not mutate probe SwiftUI state synchronously from `SceneSessionReader`'s
  registration callback. Defer it to the next main-actor turn or SwiftUI reports
  state mutation during a view update.
- Do not call an activation request or target `foreground-active` state a focus
  handoff while the peer is still foreground-active. The exact activation row
  requires the peer's latest non-superseded state to become background before it
  judges a fresh occurrence or marker ownership.
- Do not model that peer-state requirement as "the next notification." Either
  valid notification order can occur. Treat the latest exact-scene lifecycle
  value as a latched condition while rejecting any value superseded by a later
  state.
- Do not repeat the rapid A/B activation loop on the current iOS 27 simulator.
  `EXP-114` crashed simulator `backboardd` in CoreAnimation/Metal before the
  harness timeout while the probe process stayed alive. Use capable physical
  hardware, and distinguish simulator diagnostics from app/SDK crash reports.
- Do not use `pgrep` as a process-health discriminator on this simulator image;
  the command is absent. Use a supported process listing or the captured system
  diagnostic before classifying the app as terminated.
- Do not query this probe with `@probe.run_id`; use
  `@context.probe.run_id` or fall back to `service:ios-sdk-multi-scene-probe`
  followed by an exact session-ID query.
- Do not classify the first two-window attempt as an SDK crash: the termination
  reason was a simulator `backboardd` respawn and SpringBoard also restarted.
- Do not keep retrying the same iOS 27 half-and-half window arrangement through
  either Xcode device interaction or Device Hub/CUA. All three attempts caused
  the same system-wide `backboardd` respawn before a full alternating flow.
- Do not assume `UIView.willMove(toWindow:)` precedes SwiftUI `.onAppear` or the
  synchronous prefix of `.task`. The rebuilt iOS 27 probe proves both can run
  first, and treating every transient detach as a view stop can create duplicate
  sub-millisecond views during navigation.
- Do not retry a child `UIViewControllerRepresentable` as a transparent ordering
  fix. The controller run remained 4-35 ms behind customer lifecycle work, and
  UIKit does not guarantee an ancestor window is available at `viewWillAppear`.
- Do not describe a scene custom trait or `onChange(initial:)` as a transparent
  view-before-callback guarantee. The trait supplies early scene identity and the
  initial callback materially narrows the gap, but two iOS 27 runs still emitted
  the RUM view after customer outer `.onAppear` and immediate `.task`.
- Do not disable automatic SwiftUI tracking for the entire scene or application
  merely because one semantic/manual boundary is active. `EXP-115` proves the
  viable boundary is an active, attached explicit subtree; unrelated controllers
  must remain eligible, and an inactive or detached reader must not suppress
  automatic discovery.
- Do not retry moving the unchanged `.trackRUMView` modifier inside or outside
  the screen hierarchy as the early-attribution fix. `EXP-030` and `EXP-031`
  preserve both placements; Detail early work still used Home, and the outer
  placement also left Home early work on `ApplicationLaunch`.
- Do not equate a retained SwiftUI value or `@State` object with one RUM view.
  Returning through navigation must create a new RUM occurrence. `EXP-035`
  validates seven distinct occurrences across three complete push/pop cycles.
- Do not validate a returned navigation occurrence from fresh UUIDs alone. An old
  inactive scope can remain alive for pending Resources and previously matched a
  later start with the same platform lifecycle identity. Keep the `EXP-061`
  pending-Resource regression: Home₁ must remain immutable while Home₂ owns
  new scene work.
- Do not place a semantic tracker as a background sibling, whole-stack wrapper,
  or stable first child and call it a scene-root solution. `EXP-047` through
  `EXP-049` show that all three remain too late for B's initial Home lifecycle;
  the whole-stack wrapper also replays retained screen lifecycle.
- Do not apply `.id` only to the hidden SDK reader to advance a retained route.
  `EXP-093` kept Home's immediate return marker on Detail. The missing input was
  the committed route contraction, not platform-reader identity.
- Do not require a retained route's hidden reader to still be attached when it
  returns. iOS 27 detaches that reader while preserving its SwiftUI state. Keep
  only its last concrete scene, reject `.attached(nil)`, and clear/fence the
  snapshot on scene disconnect as in `EXP-097`/`EXP-098`.
- Do not classify an edge drag as an interactive cancel or finish without a path,
  coordinator, or lifecycle signal. Both bounded `EXP-100` drags were ignored;
  Detail remaining visible alone cannot distinguish cancellation from no gesture.
- Do not serialize a probe path counter as the RUM occurrence identity.
  `EXP-051` showed that retained SwiftUI content can keep the earlier attribute
  value while RUM correctly creates a new UUID. Validate occurrences with view
  start/stop order and distinct UUIDs.
- Do not treat every bound-path write as a committed RUM view. `EXP-052` observed
  two same-turn writes but no materialized destination and correctly retained the
  original Home UUID. Path state is input to semantic tracking, not the event by
  itself.
- Do not use `EXP-053` as SDK replacement evidence. The probe forgot to track its
  new Alternate route in navigation-path mode. Only corrected `EXP-054` exercises
  the intended route-owned boundary.
- Do not present `UIHostingSceneDelegate` as transparent automatic navigation
  tracking. `EXP-055` confirms it is an app-owned scene/root lifecycle bridge and
  exposes no destination identity.
- Do not equate a same-type destination update with the absence of navigation.
  `EXP-057` visibly committed Detail₂ while RUM retained Detail₁. Name, path,
  attributes, and the outer modifier's freshly generated identity are not safe
  occurrence detectors: ordinary renders can change them, while real occurrences
  can share them.
- Do not prescribe `.id(route)` as the customer fix. `EXP-058` proves that route
  identity is the missing input, but `.id` also resets customer SwiftUI state.
  `EXP-102`/`EXP-103` now prove the same for split selection: a reviewed SDK token
  can rotate only the internal RUM generation while the Detail witness survives.
- Do not classify `delivered=false` from the retained-route source as a failed
  active replacement. Detail₁ → Detail₂ updates one active keyed state and uses
  atomic occurrence replacement; the source is for revealing a previously
  inactive retained route. `EXP-102`/`EXP-103` prove both windows take the former
  path correctly.
- Do not implement token rollover as a normal stop followed by start in
  `RUMViewsHandler`. Removing the top view intentionally restarts the underlying
  stack entry and can synthesize Home between Detail₁ and Detail₂. Replace the
  same-scene stack slot atomically.
- Do not scope the UIKit split fix only to replacement of a column root.
  `EXP-073` proves that a stable secondary navigation controller produces the
  same false Primary interval on both push and pop. Coalesce the materialized
  outgoing/incoming lifecycle pair within the active column, while starting the
  returned controller as a fresh RUM occurrence.
- Do not accept the initial Primary/sidebar/container views in historical UIKit
  split runs as final product semantics. Those sessions remain valuable evidence
  that the branch removed *restarted* Primary intervals and preserved fresh
  returned destinations, but the approved model forbids structural RUM views
  entirely and the current oracle encodes that negative expectation.
- Do not make a missing atomic-replacement source fall back to ordinary add.
  Post-run review of the first `EXP-060` draft found that it could materialize a
  cancelled or stale candidate, stop an unrelated current view, or turn scene
  migration into an implicit add. Missing and cross-scene sources now fail closed;
  a separately proven appearance must use the normal start path.
- Do not treat every unchanged `updateUIView` as a retained-reader remount.
  SwiftUI can update a reader after its semantic view disappeared; only a
  disconnect-rearmed attachment or real appearance may create the next
  occurrence. The first `EXP-064` draft restarted such views.
- Do not reuse the initial scene trait as reconnect proof after disconnect. It is
  valid only for the first clean iOS 27 mount. A retained reader must regain an
  attached scene, and an inactive view must still wait for semantic appearance.
- Do not index a detached observer only by its current scene. Preserve its last
  proven scene for unregister/filter decisions, or a stale A reader can
  participate in B and bypass B's interactive coordinator gate.
- Do not delete all pending state merely because its source scene disconnected.
  A committed migration may already target surviving scene B. Invalidate the A
  occurrence, rebase the B transaction, and let coordinator success or
  cancellation decide whether B materializes.
- Do not consume the retained reader's sole remount signal before an interactive
  transition resolves. Cancellation and a mount/disappear merge must preserve or
  rearm authorization so the next real appearance can create exactly one view.
- Do not attribute cancelled-interactive-navigation view churn to the iOS 27
  early-mount candidate. `EXP-037` reproduced the same false half-second Home and
  Detail restart with the candidate disabled. Fix cancellation as its own
  explicit SwiftUI navigation problem and retain that A/B control.
- Do not wait for SwiftUI's cancellation-reversal callback to discover transition
  state. `EXP-043` found the public UIKit coordinator during speculative Home
  `onAppear`, but it was already gone by Home `onDisappear` and Detail emitted no
  matching callback. Capture `initiallyInteractive` at the first callback and use
  coordinator completion as the commit/cancel boundary; mutable `isInteractive`
  is not the decision signal.
- Do not resolve a recreated destination only through already attached tracked
  readers. Its own reader has no responder ancestry during `makeUIView`; use the
  matching scene hierarchy provisionally, then confirm ownership after attachment.
- Do not group every interactive lifecycle callback in one scene-wide pending
  bucket. Key by coordinator identity and state membership, or a cancelled pop can
  discard an unrelated sheet, tab, or split-subtree occurrence.
- Do not trust a changed process environment to replace a restored
  `WindowGroup(for:)` value. The first `EXP-044` launch restored the prior
  `ProbeWindow.runID`; stop and uninstall the probe before an exact-run test, or
  explicitly classify the run as restoration evidence rather than mixing its
  attributes with the new experiment.
- Do not generalize the clean unselected-tab result into a platform guarantee.
  `EXP-036` emitted no false view because that container did not construct the
  offscreen reader. Other aborted, restored, modal, split, or preloaded
  containers still need direct runtime validation.
- Do not retry the `ViewThatFits` rejected-candidate arrangement from `EXP-039`.
  It never constructed the diagnostic `UIViewRepresentable`, so the absence of a
  false RUM view is not evidence about construction without appearance. Use a
  container whose platform child is demonstrably realized or record the case as
  unsupported by available public SwiftUI lifecycle signals.
- Do not cite the `EXP-042` force-termination relaunch as concurrent restoration.
  It correctly restored B with the same native scene ID, but iPadOS did not
  reconnect A. A repeat needs a lifecycle/setup that demonstrably restores both
  scene sessions, not another identical terminate-and-launch sequence.
- Do not count automatic SwiftUI tracking as correct merely because its tap and
  final hosting-controller view use the right scene. Run
  `76f40f1f-554f-4842-86a1-7bf4955b734c` proves the destination is discovered only
  after its lifecycle resources and an extra root view. Preserve both assertions
  in the focused regression.
- Do not retry `UIViewController.viewIsAppearing` as the automatic SwiftUI timing
  fix. The iOS 27-only, multi-scene-only candidate compiled, passed 53 focused
  tests, and still created the final Detail view about 515 ms after `.onAppear`,
  with all lifecycle resources on the source view and the transient root intact.
  It was removed to avoid a new global controller swizzle without semantic value.
- Do not retry a base-`viewWillAppear` hook as the automatic SwiftUI timing fix.
  The scene trait was already correct, but both pre-base run
  `b4bbfa9a-3094-4345-b64e-bb1728bec061` and post-base run
  `20462f01-45d6-4838-9102-151467c4c47f` kept Home work on
  `ApplicationLaunch` and reused the Home exact view ID for all Detail lifecycle
  resources. The hook and tests were removed. Continue from view/name discovery
  or a native SwiftUI integration boundary.
- Do not swizzle the public `UIHostingController.viewWillAppear` override as an
  earlier substitute. LLDB shows both Home and Detail `.onAppear` execute before
  the relevant navigation-host entry. Its correct navigation title therefore
  becomes observable only after the lifecycle work that needs attribution.
- Do not use `navigationItem.title` as the automatic SwiftUI view name. In addition
  to arriving too late, titles can be absent, dynamic, localized, or contain
  customer/user content and are not equivalent to a semantic view identity.
- Do not replace the iOS 27-missing `content.list.item.type` reflection path with
  `elements.body.viewType`. It returns the registered `ProbeDetailView` destination
  type while Home is visible and would create a semantically false destination.
- Do not retry native `WindowGroup` merely to distinguish the Runner lifecycle.
  Runs `native-single-20260912171659` and
  `native-swiftui-20260912171529` already prove the same late discovery in a
  standalone `@main App`, plus B-to-A leakage during `openWindow`. A repeat is
  useful only after changing the discovery or integration boundary.
- Do not classify the automatic-run return to SpringBoard after requesting scene-B
  destruction as an SDK crash or proof that scene A was destroyed. The backend
  session reports zero crashes, and this Stage Manager arrangement did not
  automatically foreground the hidden window. Use an explicit restoration or
  activation experiment before drawing a lifecycle conclusion.
- Do not invent a provisional scene ID or rebind an existing RUM view piecemeal.
  Ownership is immutable across the view scope, INV tracker, cache, operations,
  lifecycle maps, and snapshots; ordinary stop/start also allocates a new view ID.
- Do not restore permanent start-scene ownership for Operations. It fixed
  same-scene navigation but makes a legitimate A-to-B operation report the wrong
  end view. Retain only a last-proven snapshot and let every trustworthy later
  step replace it.
- After activating the other Device Hub window, refresh the accessibility tree
  before addressing an element by index. A cached B button can still invoke B's
  controller while the screenshot visibly shows A, leaving the representative
  unchanged and invalidating a delayed-provenance experiment.
- Do not switch from fullscreen B to fullscreen A to prove that an A touch
  overrides representative B. `EXP-089` shows the switch creates a fresh A view
  occurrence and makes it representative before the touch. Keep both scenes
  visibly materialized and interact with A without an intervening appearance.
- The fixed “Other Window” control is predictable only when exactly two sessions
  exist: it selects the first other member of unordered `openSessions`. With more
  windows, verify the recorded target or add explicit target selection first.
- The shared/coalesced request helper stores one task and does not clear it after
  completion. Relaunch or reset/fix that state before a second shared-request run,
  or it can silently join an already completed task.
- Do not look for restoration, WebView, fatal/exported-context, or mirrored
  `logger.error` controls in the current probe. They do not exist yet; extend the
  harness before scheduling those rows. Stack, SwiftUI split, and UIKit split
  navigation controls do exist and now have signal-driven coverage.
- Do not use separate simulator-driver processes to race a three-second operation
  against scene closure. Process initialization can reverse the taps. Use AXe's
  ordered `batch` command and fixed toolbar controls; the final teardown run
  proves the intended start-then-close order in console and backend data.
- Do not attribute a missing reduced operation to reducer lag without inspecting
  raw `@type:vital` operation steps. The pre-fix teardown runs had a source-scene
  start and no retained end; the post-fix run has both steps and a reduced event.
- Do not treat a successful AXe tap report as simulator interaction while the Mac
  is locked. In run `c28442df-d11a-456b-9ca7-1ffe13bad483`, the accessibility tree
  was readable but the operation controls never invoked and their status remained
  unchanged. Unlock the GUI before resuming the cross-window Operation matrix.
- Do not restore the requirement that a pending UIKit split removal must find a
  tracked controller in another split column. Once structural Primary is
  intentionally absent, S1/S2 navigation has only one tracked column; that guard
  bypasses the coordinator reconciliation needed to distinguish cancel from
  completion.
- Do not count UIKit's second `viewDidAppear` for S2 during a cancelled transition
  as a new RUM occurrence. `EXP-112` proves UIKit may re-deliver appearance while
  RUM correctly retains the same S2 UUID. Use view UUIDs and the coordinator
  result, not callback count alone.
- Do not attach a diagnostic Primary marker after production tracking has
  intentionally suppressed Primary. The marker falls onto the startup fallback
  and creates a false harness attribution failure. Keep Primary lifecycle as a
  probe signal without asking RUM to own Primary work in observable acceptance
  runs.
