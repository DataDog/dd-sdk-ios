# RUM multi-scene experiment history

Read this document when reproducing a result, checking exact run or RUM session
identifiers, reviewing rejected approaches, or continuing from a prior checkpoint.
The [assessment](ASSESSMENT.md) interprets this evidence; the
[plan](PLAN.md) decides what to run next. Start at the
[canonical overview](../MULTI_SCENE_SUPPORT.md) for the current resume point.

Last updated: 2026-09-15

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
| 59 | `Centralize probe SwiftUI navigation tracking` | Probe-only once-per-container `NavigationStack` wrapper, one bound path, centralized route metadata resolver, and route-owned root/destination tracking placement |
| 60 | `Document container SwiftUI navigation evidence` | `EXP-116` local/backend evidence, clean-run contamination warning, and refreshed handoff state |
| 61 | `Prepare semantic and automatic scene coexistence probe` | Scene-selective semantic tracking, exact source-versus-owner oracle evidence, automatic-view origin checks, and rejection of owner views created before the target scene opened |
| 62 | `Document automatic scene coexistence evidence` | `EXP-118` partial mapper evidence, simulator compositor failures, physical-device rerun routing, and refreshed plan |
| 63 | `Probe exceptional manual SwiftUI view coexistence` | Automatic Home, one explicit Sheet exception, fresh automatic Home expectations, presentation commands, semantic-view intervals, and exact owner-relation checks |
| 64 | `Report the active SwiftUI presentation screen` | Correct source labeling for driver markers and the explicit presentation interval while a sheet is active |
| 65 | `Document multi-scene navigation API direction` | Approved navigation-occurrence, one-destination-per-scene, container-level SwiftUI, scene-aware manual-view, Execution Context, and coexistence contracts |
| 66 | `Probe keyed manual view coexistence` | Direct keyed manual-over-automatic discriminator, exact authority interval, H1/M1/H2 owner relations, adversarial oracle fixtures, and catalog-owned observable-driver selection |
| 67 | `Route scene-targeted manual views through navigation stacks` | Internal exact-scene manual-view capability, per-scene stack authority, automatic-destination staging, nested manual suffixes, stop attributes, and compatibility regressions |
| 68 | `Retain semantic destination across manual view authority` | Retained underlying destination plus generic automatic-fallback rejection while an exact-scene manual view is authoritative |
| 69 | `Exercise scene-targeted manual view routing` | Probe-only switch from legacy direct keyed commands to the internal exact-scene handler path used by `EXP-121` and `EXP-122` |
| 70 | `Document scene-targeted manual view evidence` | `EXP-121`/`EXP-122` mapper/backend evidence, corrected support verdict, validation snapshot, and exact resume state |
| 71 | `Record manual authority and presentation decisions` | Approved underlying-navigation, nesting, targeted-pairing, and complete SwiftUI presentation-destination contracts |
| 72 | `Preserve semantic presentation authority through dismissal` | Suppression-only SwiftUI presentation boundary plus underlying-navigation, nested-manual, and duplicate-start regressions |
| 73 | `Exercise semantic SwiftUI sheet authority` | Exact-scene semantic Sheet lifecycle, target-scoped automatic suppression, presentation-subtree intervals, and adversarial oracle coverage |
| 74 | `Document semantic SwiftUI sheet evidence` | `EXP-123` through `EXP-125` local/backend evidence, aggregate-lifetime oracle correction, validation snapshot, and exact resume state |
| 75 | `Exercise semantic SwiftUI full-screen authority` | Independent `fullScreenCover` lifecycle, complete-destination resolver state, target-scoped automatic suppression, and strict dismiss ownership oracle |
| 76 | `Document semantic SwiftUI full-screen evidence` | `EXP-126` clean local/backend evidence, presentation-style parity, validation snapshot, and exact resume state |
| 77 | `Exercise sibling container authority` | Two real sibling `NavigationStack` controller branches, mandatory ancestry assertion, container-local manual authority, latest-destination reveal, and exact measurement-view filtering |
| 78 | `Document sibling container authority evidence` | `EXP-127` local/backend evidence, probe-only measurement-noise lesson, validation snapshot, and exact resume state |
| 79 | `Refresh multi-scene commit references` | Signed-history hash refresh after the local branch was re-signed |
| 80 | `Exercise nested manual view authority` | `EXP-128` nested Compose/Preview suffix, duplicate-active-key crash safety, immutable prior-evidence waits, and adversarial oracle coverage |
| 81 | `Exercise same-key manual views across scenes` | `EXP-129` same-key A/B isolation and reverse-stop driver contract plus cross-scene adversarial fixtures |
| 82 | `Exercise operation attribution across navigation` | `EXP-130` success, failure, and duplicate Operation invocation driver across fresh semantic navigation occurrences |
| 83 | `Update the multi-scene support checkpoint` | Progressive-disclosure checkpoint through `EXP-130`, consolidated evidence, aligned next-work order, and signed-history handoff |
| 84 | `Prepare cross-scene operation attribution probe` | `EXP-131` A-to-B success/failure plus same-name distinct-key reverse-completion driver and adversarial ownership fixtures |
| 85 | `Exercise UIKit scroll attribution across navigation` | `EXP-132` threshold-qualified real `UITableView` fling, navigation during deceleration, exact-once origin action, fresh-destination follow-up ownership, and adversarial oracle coverage |
| 86 | `Update multi-scene support through UIKit scroll validation` | Documentation checkpoint through `EXP-132`, deferred single-scene extraction gate, simulator/hardware routing, and exact resume state |
| 87 | `Exercise trace-only URLSession attribution across scenes` | `EXP-133` held Trace-only URLSession completion after A→B representative churn, exact start-view/session oracle, no-RUM-Resource contract, and adversarial coverage |
| 88 | `Exercise trace-only reverse completion across scenes` | `EXP-134` independent A/B Trace-only requests, opposite-scene representatives at B-before-A completion, exact start-owner/session oracle, and adversarial coverage |
| 89 | `Document trace-only reverse completion evidence` | `EXP-134` local/backend evidence, signer recovery, bounded remaining causal rows, and refreshed resume state |
| 90 | `Exercise SwiftUI structured task attribution across scenes` | `EXP-135` real SwiftUI Button tap, suspended child-task handoff/trait diagnostics, strict expected-origin oracle, and source-less fallback classification |
| 91 | `Document SwiftUI structured task attribution boundary` | `EXP-135` accepted runtime/backend evidence, all incomplete attempts, corrected causal conclusion, and refreshed resume state |
| 92 | `Exercise shared URLSession ownership across scenes` | `EXP-136` one A-created Trace-only task, B consumer join without another task, exact-one creator-owner oracle, and adversarial coverage |
| 93 | `Document shared request validation boundary` | `EXP-136` simulator-system failure evidence, physical rerun routing, tooling runbook, and customer-shaped API resume point |
| 94 | `Prototype scene-targeted manual view APIs` | iOS 27 Swift SPI and Debug-only Objective-C customer-shaped start/stop calls, custom/NOP fallback, probe migration, restored-window run isolation, and compile/runtime coverage |
| 95 | `Document scene-targeted manual API validation` | `EXP-137` through `EXP-140`, Xcode/tooling corrections, current support assessment, and the semantic SwiftUI plus Operation SPI resume plan |
| 96 | `Prototype SwiftUI semantic navigation integration` | iOS 27 builder-owning Swift SPI, typed path occurrence state, Sheet/full-screen-cover authority, target-scoped automatic suppression, and focused tests |
| 97 | `Exercise semantic navigation API in native probe` | `EXP-141` customer-shaped H1/D1/H2/Sheet/H3/Cover/H4 scenario and strict action/Resource/dedup oracle |

Rows 1-97 are committed and signed. Rows 93-97 are `d2a5b9491`, `01e5d1ffb`,
`3b26da106`, `eb89a4f24`, and `3af24003c` respectively. Row 16 is commit `e56262485`; row 17 is commit
`2fb8dd9b5`; row 18 is commit `6fa2baf24`; rows 19-21 are commits
`874dcad11`, `ea787a35a`, and `a24527b17`; rows 22-23 are commits
`32dd4dbe5` and `77e064a1d`; row 24 is commit `3a4b98f6d`, row 25 is
`b180ecc33`, row 26 is `37f363bd5`, and row 27 is `73f6574a6`. Rows 28-37 are
`fb6b3bde7`, `a6cd5df60`, `efa91fa34`, `e4526162a`, `5c977da32`, `bfb752fa1`,
`9fc9e1123`, `051e71292`, `251f6b8bc`, and `9a656cd41` respectively. Row 38 is
`81da104d2`; row 39 is `7c3601c37`, row 40 is `89e9cb19f`, row 41 is
`22f027113`, row 42 is `41029e1e3`, row 43 is `051eac32c`, row 44 is
`e70e5ca51`, row 45 is `494dc4e66`, and row 46 is `af18679f2`.
Row 47 is `115dc9e38`, row 48 is `116220bed`, row 49 is `da701a043`, row 50
is `38b6868a3`, row 51 is `4b85048a7`, row 52 is `a001c8377`, and row 53 is
`35e53ba30`. Row 54 is `481ba47d1`, row 55 is `0234183e0`, row 56 is
`210a80fd9`, row 57 is `853f90648`, row 58 is `4fc9d91b3`, and row 59 is
`93cbb3387`.
Row 60 is `04305cb0a`, row 61 is `3cdb4b915`, row 62 is `44b4921cf`, row 63
is `2a15478df`, row 64 is `dd1b1cf34`, row 65 is `b5494adb0`, and row 66 is
`56969d8a5`. Rows 67-69 are `29c8cec2c`, `b1a0fb6b8`, and `a40e7903c`.
Rows 70-73 are `76d1a9e71`, `b61e783a6`, `f452e9e3f`, and `fad83f58f`.
Rows 74-79 are `f1c0547b6`, `c70920c94`, `100fa116a`, `45ec5656a`,
`0c6b35770`, and `b6b1b57bc`.
Rows 80-92 are `af2a2666d`, `9fa58e3c0`, `5d536e0bd`, `140e57c11`,
`a653e29f2`, `3c9730805`, `99e6c4a29`, `130ba7646`, `353679bb5`,
`0dca626df`, `2972d3de1`, `75becb324`, and `e804d3bd6`. Their signatures were verified against the
configured Datadog developer key before this checkpoint.

The first row-94 signing attempts failed with the same external-agent
communication error recorded below. The user explicitly allowed unsigned
development checkpoints, producing historical objects `e51376b6f` and
`0ba14da6f`. When signing recovered, rows 94-97 were replayed with signatures in
a temporary worktree. The old and new tips have the identical tree
`58bf65ab2ac8d5748c6bbd5fad2e0ce1b0b978d9`; the branch now points only to the
signed tail. It remains local-only and must not be pushed.
A raw commit-object audit after repointing the branch finds a `gpgsig` block on
all 105 commits after the `develop` merge base, with no missing signature.

Twelve earlier signed attempts failed before writing a commit object. The last
attempt that returned signer stderr reported:

```text
error: Signing file /var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T//.git_signing_buffer_tmpm6SzCt
Couldn't sign message (signer): communication with agent failed?
Signing /var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T//.git_signing_buffer_tmpm6SzCt failed: communication with agent failed?

fatal: failed to write commit object
```

That blocker is superseded. The complete branch history was subsequently
re-signed, and row 79 refreshes all commit references to the signed objects. The
pre-rewrite unsigned tip is retained only as local backup ref
`refs/backup/multi-scene-before-resign-20260914`; it is not branch history. The
branch remains local-only and must not be pushed.

Four `git commit -S` attempts for `EXP-128` on 2026-09-14 failed before creating
an object with the same signer-agent communication error, although `ssh-add -L`
still listed the configured key. The isolated-index workflow preserved the exact
code-only boundary until signing recovered. `EXP-128`, `EXP-129`, `EXP-130`,
`EXP-131`, and `EXP-132` were then created as separate signed commits from frozen trees
`082310e18ecfbdb9fc18a4f9d1914c7660a6edfd`,
`0b41cbbb34cd5ff138a9b792a0c8e528505e17a8`, and
`22ddf1f9b4ab1193cc1bb635b6ebae83f97e0f20`,
`67eb64a23f985494992ef53db36130557414fd1d`, and
`3f1edaf17f4d7dd4fe654c8738ca6cb9c09440f7`. Their diffs contain respectively
six, seven, eight, four, and eight harness/test paths and contain no documentation,
project file, or xcconfig. The intervening documentation-only checkpoint is
signed commit `140e57c11` with frozen tree
`ac22bf1ad1a4adc4d60bfa00d8a375b9aa8a4851`. This closes the signing blocker
without an unsigned fallback.

The next documentation checkpoint is signed commit `99e6c4a29`, frozen tree
`45cbee4510ef4f15540859b1823a9494a6152477`. `EXP-133` is signed commit
`130ba7646`, frozen tree `942f1207f6e6dad9cfab6c897894f2e1ea5f7a15`.
Its 12-path boundary contains only the native probe source, tests, XcodeGen
specification, and regenerated standalone probe project. It does not contain the
repository project, local xcconfig, support documentation, or intake artifacts.
`EXP-134` is signed six-path commit `353679bb5`, frozen tree
`efe7f2a754c0191ebfacd1952eb422a41fafa315`; its documentation checkpoint is
signed commit `0dca626df`, frozen tree
`614e83f2d1bdad6ba166f152b9bc90c5a2bc30a9`. Temporary unsigned objects
`9d5be7be2` and `87fedd595` were replaced with those signed commits while
preserving their exact trees, messages, and author/committer metadata; they are
not branch history. `EXP-135` is signed ten-path commit `2972d3de1`, frozen tree
`05f9db5089a769acbb1fe5df79645641cc83464e`. It contains only native probe
scenario, driver, UI, and focused-test changes; it excludes documentation, the
repository project, local xcconfig, and tooling runbook.

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
| EXP-101 | `post-checkpoint-attribution-hardening-20260913` | No backend session; source and focused-test evidence | Xcode 27 / iOS 27 simulator | Commits `fb6b3bde7` through `251f6b8bc` close exact-view representative updates, Resource completion ownership, manual error/view/mutation routing, internal view-command handoff, and native/OpenTelemetry span-start parity. The final RUM plan passes 1,147/1,147; the Trace plan passes 151/151, including 4/4 focused OpenTelemetry handoff tests. Focused changed-file lint has zero violations and the final probe build succeeds. These are compatibility and ownership proofs, not substitutes for the still-pending simultaneous-window runtime discriminators. |
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
| EXP-116 | Return `container-navigation-prototype-20260913-2210-a`; abort `container-navigation-abort-clean-20260913-2247-a`; replacement `container-navigation-same-type-clean-20260913-2254-a` | `9d1653fc-80e8-4794-9a29-50a60246d2ca`; `8b89254e-ba81-4595-86a6-5fa399d480c5`; `0436c9b2-08fc-4c92-a311-7336eafaad4a` | iPadOS 27 | Once-per-container SwiftUI integration-shape pass. A probe-only wrapper consumes one bound `NavigationStack` path and centralized route-to-RUM resolver, owns root/destination materialization, and injects the existing route-owned tracking boundary without putting metadata into Home/Detail view types. Clean return passed 7/7 with launch plus Home H1 `a2dc84f9…`, Detail D1 `2a20ec3c…`, and fresh Home H2 `c82a59c9…`; abort passed 5/5 with only Home `b0166eb3…` and no Detail; same-type replacement passed 6/6 with same-named Detail₁ `f5311b38…` and Detail₂ `d8375a2b…` plus final action/Resource on Detail₂. Backend view sets and ownership agree, with no automatic/hosting duplicate. A delayed source-less callback scheduled by removed Detail₁ used the then-current Detail₂, preserving the approved fallback. Probe tests pass 45/45 and repository lint has zero violations. Commit `93cbb3387` is probe-only; no public API was added. |
| EXP-117 | Contaminated abort `container-navigation-abort-20260913-2225-a`; contaminated replacement `container-navigation-same-type-20260913-2232-a` | `18cb3927-8afb-4f39-92bf-75b3391de050`; `1f6964c8-0200-44b9-a775-ffd91e4a0bc9` | iPadOS 27 | Clean-run isolation failure in the harness workflow, not an SDK-semantic failure. Both back-to-back Xcode launches passed their local oracle, but the test bundle had not been uninstalled. Their newly created Home/Detail view documents retained `container-navigation-prototype-20260913-2210-a` as `context.probe.run_id`, while later actions and Resources carried the new run ID. A new-run aggregate therefore showed only ApplicationLaunch until direct view-ID inspection exposed the mixed metadata. Explicit host-side uninstall followed by the `EXP-116` reruns removed the contamination. `--probe-run-mode clean` is only manifest input inside the app; Phase 5's host runner must perform teardown and verify every semantic view's run ID before accepting backend evidence. |
| EXP-118 | `semantic-auto-coexistence-20260913-2256-a`; `semantic-auto-coexistence-20260913-2259-b` | `5a4d3add-7100-4ca3-bb8f-62f0c012b4d0`; `43e42ece-f77d-4215-8c6c-22c5ce101136` | iPadOS 27 simulator | Prepared automatic/semantic scene-coexistence discriminator; simulator-inconclusive after two explicitly uninstalled runs because `backboardd` aborted in Metal/CoreAnimation before the terminal oracle. Both runs kept scene A's explicit marker on A/Home H1 and created scene-B automatic fallback plus navigation-host views after B opened, proving A's authority did not suppress B globally. Attempt 1 mapped B's delayed source-less marker to B's non-launch automatic host, but the decisive driver marker never ran. Earlier B source-less lifecycle work used representative A before discovery settled, which is the approved compatibility fallback rather than exact provenance. No probe/SDK crash or terminal PASS/FAIL occurred; rerun the named scenario on physical hardware. Probe tests pass 49/49 and lint reports zero violations. |
| EXP-119 | Invalid-source run `automatic-manual-sheet-20260913-2332-a`; corrected run `automatic-manual-sheet-20260913-2338-b` | `b2f50cf0-1394-4b1b-9da9-09d752a22bbf`; `f483b9eb-3ea8-4cfc-a884-c0b547effb5a` | iPadOS 27 simulator | Exceptional explicit SwiftUI Sheet over automatic Home. The first run exposed a probe-only source label defect, fixed in `dd1b1cf34`. The corrected run then failed conclusively after 6 matches: Home-source work in immediate `onDismiss` still belonged to Sheet S1 because automatic Home H2 had not started; settled work used H2. Local mapper and backend intake otherwise agree on launch, an 18 ms automatic fallback, automatic H1 `60a6d680…`, explicit S1 `fad831da…`, and fresh automatic H2 `c36d0109…`; sheet work owns S1, pre-sheet work owns H1, no duplicate automatic Sheet appears, and no error/crash occurred. Probe build-for-testing and 56/56 tests pass. This proves coexistence/dedup and exposes a real return-boundary attribution gap. |
| EXP-120 | Invalid harness `automatic-keyed-manual-20260914-0005-a`; partial `automatic-keyed-manual-20260914-0010-b`; conclusive `automatic-keyed-manual-20260914-0015-c`; hardened baseline `automatic-keyed-manual-20260914-0030-d` | `54005e3d-daf7-460e-8c38-2cf4e7505e4f`; `26990bc0-7785-4eda-b0f7-f3971516f5a3`; `9382bf4d-5985-4047-898c-deb8103af68b`; `3609bce2-ea31-41b1-9d8b-ad2ab39ec7c0` | iPadOS 27 simulator | Existing direct keyed manual API over automatic Home fails authoritative coexistence. Attempt A never started because the scenario was omitted from a second driver allowlist; the catalog now owns that selection. Attempt B proved Compose was already stopped before a now-removed wait. Attempts C/D conclusively show H1 → M1 → automatic fallback → fresh H2: M1 lasts only 31–48 ms, active and immediate-stop action/Resource pairs use the fallback, and only settled work uses H2. Final D has six views, ten actions, ten Resources, zero errors/crashes. Its initial H1-stop failure was an oracle matcher defect caused by a deferred exact stop arriving after an unrelated M1 stop; the corrected matcher scans onward and keeps the real manual-authority failure. Commit `56969d8a5`; probe 65/65, build-for-testing and repository lint pass. |
| EXP-121 | `scene-targeted-manual-20260914-0120-a` | `f32f25c8-7403-4513-89fa-75d9e3a3952d` | iPadOS 27 simulator | First internal scene-targeted manual-stack run after `29c8cec2c`. Compose M1 remained authoritative and owned its active action/Resource, closing the `EXP-120` preemption. The run still failed because automatic discovery staged a generic hosting fallback beneath M1; exact stop revealed that fallback for the immediate pair before fresh H2 owned the settled pair. Mapper and backend agree on six views and 30 events with zero errors/crashes. This isolated fallback selection from manual authority rather than reopening the direct-command diagnosis. |
| EXP-122 | `scene-targeted-manual-20260914-0135-b` | `7194cd61-23d0-4727-877a-79fbc985fc32` | iPadOS 27 simulator | Clean exact-scene manual-view acceptance after `b1a0fb6b8`. The oracle passes 16/16. Mapper and backend contain only launch, the expected startup-only fallback, Home H1, authoritative Compose M1, and fresh Home H2; no generic fallback appears during or after manual authority. Pre-manual work uses H1, active Compose work uses M1, and both immediate and settled post-stop pairs use the same H2, distinct from H1. Exact-run intake has 28 events: five views, ten actions, ten Resources, one long task, one vital, zero errors, and zero crashes. Host uninstall and ENOENT container lookup prove clean isolation; all five view documents carry the requested run ID. |
| EXP-123 | `scene-targeted-sheet-20260914-0208-a` | `33b814f6-c709-4f14-bc08-ffebd43f4203` | iPadOS 27 simulator | Exact-scene Sheet lifecycle without a UI-attached suppression boundary. The semantic Sheet M1 was authoritative, but automatic discovery still emitted structural `NavigationStackHostingController` churn and a redundant automatic `ProbeSheetView` presentation-host occurrence. The transient automatic presentation preempted the early revealed Home and produced two returned-Home occurrences. Pre-Sheet, active-Sheet, immediate-dismiss, and settled owners otherwise remained observable; zero errors or crashes occurred. This rejects handler-stack authority alone as a complete semantic-presentation integration. |
| EXP-124 | `semantic-sheet-suppression-20260914-0222-a` | `8101b16d-ed17-4ded-8a29-c9bbf8aa219b` | iPadOS 27 simulator | First suppression-only presentation-boundary run. Mapper output contains exactly launch, the startup fallback, H1, semantic Sheet M1, and fresh H2; active work owns M1 and both dismiss pairs own H2, with no automatic `ProbeSheetView`. The old oracle nevertheless failed because a pending Sheet Resource delayed M1's final aggregate snapshot until after H2 started. This is an oracle interval defect, not a RUM ownership failure: aggregate delivery lifetime is not semantic presentation authority. |
| EXP-125 | `semantic-sheet-authority-20260914-0232-a` | `c01631fb-8b2c-4071-b7c3-78c6f042774f` | iPadOS 27 simulator | Clean complete-destination Sheet acceptance after `f452e9e3f` and `fad83f58f`. The oracle passes 14/14. Mapper and backend contain only launch, the expected startup fallback, H1 `76aada56…`, semantic Sheet M1 `81ecbf07…`, and fresh H2 `b7e26b43…`. No automatic `ProbeSheetView` occurs while its native presentation subtree is mounted. Pre-Sheet work owns H1, active work owns M1, and immediate plus settled dismissal work own the same fresh H2. Backend intake has 29 exact-session events: one session, five views, ten actions, ten Resources, two long tasks, and one vital, with zero errors or crashes. Probe tests pass 68/68 and the complete RUM suite passes 1,169/1,169. |
| EXP-126 | Uncaptured setup `semantic-full-screen-cover-authority-20260914-0304-a`; accepted `semantic-full-screen-cover-authority-20260914-0312-b` | none claimed; `ba5d005c-ce65-40eb-b639-2845e570f70b` | iPadOS 27 simulator | Independent complete-destination `fullScreenCover` acceptance after `c70920c94`. The first Xcode interaction session expired before capture and receives no semantic or backend claim. The explicitly uninstalled retry passes 14/14. Mapper and backend contain only launch, the expected startup fallback, H1 `700cf5c7…`, semantic Cover M1 `6cc95aa2…`, and fresh H2 `baf8d431…`. No automatic `ProbeFullScreenCoverView` occurs while the native cover subtree is mounted. Pre-cover work owns H1, active work owns M1, and immediate plus settled dismissal work own H2. Backend intake has 28 exact-session events: one session, five views, ten actions, ten Resources, one long task, and one vital, with zero errors or crashes. Probe tests pass 69/69; build-for-testing, repository lint, and `git diff --check` pass. |
| EXP-127 | Probe-only-noise trial `sibling-container-authority-20260914-0350-a`; clean successor `sibling-container-authority-20260914-0354-b`; accepted hardened `sibling-container-authority-20260914-0403-c` | `6b0407b0-ec2e-49c1-927b-eb0ac3ef589f`; `c484fb2a-bd67-45f6-9c4e-8f284baaf843`; `46b9029f-eee9-4e1f-9fec-67a735efcc19` | iPadOS 27 simulator | Sibling-container authority acceptance after `45ec5656a`. Two `NavigationStack` branches mount under one outer SwiftUI host; a required ancestry assertion proves distinct left and right controller branches. Left manual M1 remains current while right Home commits to Detail, no automatic view starts during M1, and exact stop reveals only fresh right Detail. All three runs pass 19/19 locally. The first is retained as harness-negative evidence because the probe-only ancestry reader became a late fifth automatic view. The exact measurement-type predicate removes it in the clean successors, and the final driver waits for the immutable topology assertion. Accepted backend intake has 31 events: one session, four views, 11 actions, 11 Resources, three long tasks, and one vital, with zero errors or crashes. Probe tests pass 76/76; build-for-testing, repository lint, and `git diff --check` pass. |
| EXP-128 | Harness-race trial `nested-keyed-manual-20260914-0835-a`; accepted retry `nested-keyed-manual-20260914-0837-b` | no backend claim for attempt A; `7e617c78-c0a4-4494-8b90-7d11e635ccdf` | iPadOS 27 simulator | Nested keyed-manual authority and duplicate-start acceptance. Attempt A timed out because Compose C1's exact mapper snapshot preceded the driver's `rum-view:compose#1` wait; immutable exact-view waits now search recorded evidence before subscribing. Attempt B passes 29/29 with automatic H1 `3e67eb39…` → Compose C1 `e8393107…` → Preview P1 `82b08791…` → fresh Compose C2 `996d39fe…` → fresh automatic H2 `c7a6332f…`. Duplicate active Compose creates no view and its action/Resource remain on C2. Immediate/settled reveal work uses C2 after Preview and H2 after Compose. Backend intake contains seven views including launch/startup fallback, 15 actions, 15 Resources, one long task, one vital, and no error or crash. Probe tests pass 83/83; build, repository lint, and `git diff --check` pass. |
| EXP-129 | `same-key-manual-two-scenes-20260914-0931-a` | local RUM session `5986e490-0f5d-426c-8bb1-b9490d18843c`; no backend event received | iPadOS 27 simulator | Prepared exact same-key A/B isolation with reverse-order stop. The 91-test local plan proves the scenario and adversarial oracle: A/B Compose must have distinct UUIDs, exact work cannot cross scenes, stopping B cannot preempt A, and each returned Home must be fresh. The clean runtime reached distinct native scene A `1FB7195F…` and scene B `AFAB95FA…`, with B ready at signal 43, then the Xcode launch/device session expired amid CoreAnimation/BoardServices interruptions before the first manual start or terminal oracle. The interaction session vanished before a hierarchy capture, and exact run/session backend queries returned zero events. This is simulator-inconclusive with no semantic or app/SDK-crash claim; do not repeat this topology on the simulator. Run the named scenario on iPhone Duo or a physical multi-window iPad. |
| EXP-130 | `operations-navigation-20260914-1015-a` | `74b23c67-b6b7-4917-86ed-2ff8c7c4f559` | iPadOS 27 simulator | Operation per-step navigation and duplicate-start acceptance. An explicit uninstall plus missing-container check established a clean run. The named scenario passes 27/27 and the full probe plan passes 93/93. Six fresh semantic occurrences carry success H1 `d6617ab6…` → D1 `11e4efeb…`, failure H2 `88e9e4d6…` → D2 `e7a48e28…`, and duplicate H3 `b6d3feb0…` → D3 `e0b3e68c…`. Backend intake has seven raw `operation_step` documents and three reduced Operations: success H1→D1, failure H2→D2 with its error, and duplicate D3→D3. The duplicate raw sequence is `[start H3, start D3, end D3]`; no synthetic H3 end exists, so the earlier operation remains open for the documented four-hour timeout. The corrected warning appeared exactly, and the session contains no error event or crash. Local assertion signals prove only the API call site; raw/reduced backend documents are the Operation attribution oracle. Cross-scene A-to-B and the public view target remain open. |
| EXP-131 | No live run attempted | No backend session claimed | Xcode 27 hostless tests; hardware run pending | Prepared `operations.cross-scene.lifecycle`. Its exact eight-step driver starts success/failure in A and completes them in B, then starts same-name `parallel-alpha` and `parallel-beta` instances in A and B and completes beta before alpha. The 100/100 hostless plan includes a passing fixture and rejects a shared A/B view ID, B Home owned by A, a B completion attributed to A, and A owner drift after B completes. Local assertion/action/Resource signals prove invocation and scene context only; raw and reduced Operation documents remain the acceptance oracle. Build-for-testing, repository lint, and `git diff --check` pass. No redundant simulator run was attempted after `EXP-129` established that this two-scene compositor topology expires before the decisive steps. |
| EXP-132 | Incomplete `uikit-scroll-20260914-1156-b`; accepted `uikit-scroll-20260914-1205-c` | `47557219-bfe9-4a52-8ed2-c717d3fcf9dd`; `ef240096-9449-464b-a20d-59888693f444` | iPadOS 27 simulator | Real UIKit scroll/navigation acceptance. Earlier Xcode interaction sessions expired before a gesture and are invalid tooling attempts. The first completed run produced one origin `.scroll` locally and in backend intake, but its oracle did not measure whether lift speed exceeded the SDK's 500 pt/s swipe threshold, so it is retained as incomplete. After adding the fail-closed threshold witness, an explicit uninstall and missing-container check established a clean accepted run. A 3,792 pt/s lift began deceleration on Secondary 2 `2a4f0428…`; Secondary 3 `08802270…` appeared before deceleration ended. Exactly one `uikit-scroll-origin` action `23ceac7d…` remained on Secondary 2, and the fresh destination owned its immediate action and Resource. The local oracle passes 7/7; backend returns exactly one matching action with the same type, source, and owner. No RUM error, retry, app crash, or SDK crash occurred. The full probe plan passes 109/109; repository lint and `git diff --check` pass. Signed commit `3c9730805` contains the eight probe/oracle paths. |
| EXP-133 | Tool-incomplete `trace-only-20260914-1301-a`; accepted `trace-only-20260914-1310-b` | local-only `aa1e1aea-f5a4-4efa-96dd-37186f2aed42`; accepted `46330376-b5d0-4ee2-875c-d050aeab4c72` | iPadOS 27 simulator | Trace-only automatic URLSession owner-freezing acceptance. Attempt A reached the trace mapper with A ownership after B became representative, but the Xcode interaction session ended before a terminal result; no crash report, fatal/assertion output, or UI crash state existed, so it is tooling-incomplete rather than an SDK-crash claim. Clean retry B passes 8/8. The held request starts on A/Home H1 `4e84ed1e…`, B/Home B1 `a108479b…` becomes representative, and B releases the response. Exactly one `urlsession.request` span retains A/H1 and session `46330376…`; the B-view predicate returns zero and no matching RUM Resource exists. Raw span search and aggregate queries agree. Trace-detail lookup returned no trace for the same ID, which is retained as a backend-tool retrieval discrepancy rather than an SDK result. The full probe plan passes 115/115; repository lint and `git diff --check` pass. Signed commit `130ba7646` contains the 12 probe/project paths. |
| EXP-134 | `trace-reverse-20260914-2330-a` | `a9d038c5-d8e4-4d82-aa09-449a6f0b82cd` | iPadOS 27 simulator | Independent Trace-only reverse-completion acceptance. A/Home H1 `b0bff76c…` starts request A, B/Home H1 `6c67dece…` starts request B, then B completes first while A is representative and A completes second while B is representative. The local oracle passes 14/14 with exactly two Trace mapper events. Backend intake contains exactly one B span on B/H1 and one A span on A/H1, zero opposite-view matches, and both spans on session `a9d038c5…`; neither Trace-only URL appears as a RUM Resource. Trace upload returned HTTP 202. The initial exact backend query returned zero before indexing caught up; later raw URL/run searches and six aggregate predicates are the accepted result. Xcode marked the launch session expired only after PASS and upload, with no crash/fatal/assertion evidence. The full probe plan passes 120/120; build-for-testing, repository lint, and `git diff --check` pass. |
| EXP-135 | Timeout/tooling attempts `swiftui-button-task-20260915-0005-a`, `swiftui-button-task-20260915-0007-b`, `swiftui-button-task-trait-20260915-0030-a`, `swiftui-button-task-trait-20260915-0040-a`; pre-diagnostic failure `swiftui-button-task-20260915-0010-c`; accepted boundary `swiftui-button-task-trait-20260915-0050-a` | accepted `a423021e-49d1-455e-ac11-bf018c517c82`; pre-diagnostic `6c024fcd-7ffb-49d2-99d8-d7e6b349e426`; other incomplete IDs retained below | iPadOS 27 simulator | Ordinary SwiftUI Button → structured-task causal-boundary result. A hierarchy-derived physical tap emits exactly one automatic `tap on SwiftUI_Button` action on A/Home H1 `308f0a66…`. SDK handoff is nil in the button callback, child-task start, and resumed task; UIKit's ambient scene trait starts as A and changes to B after suspension and B takeover. The resumed manual Action `888ffe58…` and Resource `3e8b5cf4…` carry source A diagnostics but are attributed to B/Home H1 `cb3d2a7b…`, the approved source-less representative fallback. The strict expected-A scenario terminates `FAIL` after four matched expectations, intentionally preserving the unsupported exact-origin contract. Backend intake has 28 events, one automatic tap, both resumed events on B, and zero errors/crashes. The full probe plan passes 126/126; build-for-testing, repository lint, and `git diff --check` pass. Exact async origin requires explicit targeting/scoping; `UITraitCollection.current` is not durable provenance. |
| EXP-136 | `trace-shared-20260915-0115-a`; clean retry `trace-shared-20260915-0120-b` | no accepted session; partial retry session `370da769-c1f0-4707-9057-ab85b01a2017` | iPadOS 27 simulator; physical rerun required | Shared/coalesced Trace-only request discriminator. One underlying task is created on A/Home; B joins it without creating or resuming another task and then should release it. The 132/132 hostless plan requires exactly one A/Home span and rejects B retargeting, absence, or duplication. Both explicitly uninstalled runs crashed simulator `backboardd` in identical Metal texture validation while rendering B, before response release. The retry first reached start PASS at sequence 37 and B join PASS at sequence 66, with A/Home `c26fee76…` and B/Home `109659d9…`. There is no completion, trace mapper signal, or terminal result, no probe app `.ips`, and no app RUM error/crash signal. Backend indexed 16 partial retry events on session `370da769…`, zero error/crash bucket, and zero matching APM span; this is expected because release never occurred. Signed commit `e804d3bd6` contains the eight harness/test paths. Stop simulator retries and run the unchanged scenario on iPhone Duo or a physical multi-window iPad. |
| EXP-137 | `api-keyed-manual-20260915-0200-a` | `3d946de5-caee-4a4e-8949-2298f97dce85` | iPadOS 27 simulator | First customer-shaped scene-targeted Swift SPI acceptance. The probe resolves its real `UIWindowScene` and calls `startView(key:name:in:attributes:)` / `stopView(key:in:attributes:)` rather than the internal handler protocol. The 16/16 oracle and backend agree on Home H1 `c54e2e47…` → Compose M1 `c36eb9b3…` → fresh Home H2 `2dda52df…`; active work belongs to M1 and immediate plus settled stop work belongs to H2. Exact intake has five views, ten actions, ten Resources, one long task, one session, and one vital, with zero errors/crashes. |
| EXP-138 | rejected mixed-run `api-nested-manual-20260915-0210-a`; accepted `api-nested-manual-normalized-20260915-0215-a` | rejected `a2980fff-af5d-40f0-b2ad-dd3941d75be5`; accepted `6b9ef22e-0cec-4e78-be76-3fbc42ceecf9` | iPadOS 27 simulator | Customer-shaped nested-manual acceptance and harness-isolation fix. The first run passed 29/29 locally and had the correct seven-view session, but C1/P1/C2 view documents retained the preceding launch's run ID because SwiftUI restored a `WindowGroup` value outside the deleted app container. It is invalid acceptance evidence. The probe now normalizes restored telemetry to the current launch while preserving the original routed value for window identity/dismissal. The clean accepted run passes 29/29 with H1 `2bdc8076…` → Compose C1 `a9e27247…` → Preview P1 `1a4546b0…` → fresh Compose C2 `105e61cb…` → fresh H2 `526e3651…`; the duplicate Compose start creates no C3. All seven view documents carry the current run ID. Backend intake has 40 events and zero errors/crashes. |
| EXP-139 | `api-scene-sheet-20260915-0225-a` | `f497175c-a44d-4d0c-9436-28cf2f28751a` | iPadOS 27 simulator | Customer-shaped scene-targeted Sheet acceptance. The 14/14 oracle and backend contain H1 `8a5f8cc8…` → one semantic Sheet `83705cb0…` → fresh H2 `4fb5c337…`, with no automatic Sheet duplicate. Active action/Resource use the Sheet; immediate and settled dismiss pairs use H2. Every semantic payload carries the current run ID. Exact intake has 29 events and zero errors/crashes. |
| EXP-140 | `api-scene-fullscreen-20260915-0235-a` | `4edb6a3d-50fa-4d0b-ae5c-064b0720815d` | iPadOS 27 simulator | Customer-shaped scene-targeted full-screen-cover acceptance. The 14/14 oracle and backend contain H1 `43326c6e…` → one semantic Cover `1d7f7dd0…` → fresh H2 `238b6fa3…`, with no automatic cover duplicate. Active action/Resource use the Cover; immediate and settled dismiss pairs use H2. Every semantic payload carries the current run ID. Exact intake has 28 events and zero errors/crashes. |

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
| P0 | `EXP-041`, `EXP-089`, `EXP-113` | Exact open/close now passes, and `EXP-132` separately closes UIKit deceleration across same-scene navigation. Fullscreen switching still backgrounded or reactivated A and never proved stable simultaneous visibility or a different-representative handoff discriminator | Keep A and B visibly active. Make B representative, interact with A without foreground re-entry, then exact-close B while A remains visible | A Resource start invoked before any representative-changing action and the manual action must use A; later source-less work must use last-interacted A. Closing B must not stop/restart A, and delayed B completion must retain B ownership. Do not repeat the already-passing same-scene scroll case as a prerequisite |
| P0 | `EXP-114` | The simulator kept both exact scenes foreground-active instead of acknowledging a focus handoff, then crashed `backboardd` in CoreAnimation/Metal during a rapid retry | Run `windows.activation-sequence` on iPhone Duo or a physical multi-window iPad; let the OS complete each focus transition before continuing | For every step, record target foreground-active plus peer background before judging telemetry. Each confirmed foreground re-entry must create the scenario's fresh Home occurrence, and its immediate action/Resource pair must use that occurrence. A plain source label must never be treated as SDK provenance; source-less fallback remains last-interacted |
| P0 | `EXP-118` | Two clean runs created B's automatic views but the simulator compositor aborted before the exact B marker and terminal oracle completed | Run `swiftui.coexistence.semantic-a-automatic-b` on iPhone Duo or a physical multi-window iPad after an explicit uninstall | Require A's semantic marker on A/Home H1; a B-sourced marker on a non-launch automatic view first observed after opening B; no automatic duplicate in A; no cross-scene stop; terminal local PASS followed by exact run-ID backend confirmation |
| P0 | `EXP-129` | The clean run reached both native scenes, then Xcode/device capture expired amid simulator graphics/window-service interruptions before either manual view started | Run `swiftui.coexistence.same-key-manual-two-scenes` on iPhone Duo or a physical multi-window iPad after an explicit uninstall | Require distinct A/B automatic Home owners, distinct Compose UUIDs for the same customer key, B-first stop revealing fresh B Home without changing A Compose, A stop revealing fresh A Home, exact action/Resource ownership, terminal PASS, and exact run-ID backend confirmation |
| P0 | `EXP-131` | `EXP-129` already showed that the required two-scene simulator compositor/session expires before decisive cross-window work; repeating it would not add evidence | Run `operations.cross-scene.lifecycle` unchanged on iPhone Duo or a physical multi-window iPad after an explicit uninstall | Require distinct A/B Home view IDs, eight raw Operation steps, and four reduced Operations: cross-success A→B, cross-failure A→B with its error, parallel-alpha A→A, and parallel-beta B→B. Raw beta completion must precede alpha completion. Require no extra/orphan Operation, RUM error, or app/SDK crash |
| P0 | `EXP-136` | Two clean runs crashed simulator `backboardd` in the same Metal texture-validation path while rendering B. The retry proved B joined the one active request but the system process failed before B could release it | Run `traces.urlsession-shared-request` unchanged on iPhone Duo or a physical multi-window iPad after an explicit uninstall | Require start on A/Home, B join without a second URLSession task, response release from B, terminal PASS, exactly one `urlsession.request` span on A/Home and the original session, zero B-owned or duplicate spans, zero matching RUM Resource, and no app/SDK crash |
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
  destinations, build, run, console, and test calls work. At this checkpoint the
  requested `device-interaction` skill was unavailable through the attempted
  route, so no synthesized native gesture or visual input was claimed. Exact
  programmatic scenario driving remained available through the probe registry and
  observable driver (`EXP-109`). Later `EXP-132` exported Xcode 27's packaged
  device-interaction skill and used its measured-coordinate gesture command.
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
  `EXP-133` adds the live automatic path: after A's request-time selection is
  established, one completion-created span retains A/H1 while B/H1 is the later
  representative. Unknown simultaneous-window source discovery remains open.
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
as the native tracer. These changes are commits `fb6b3bde7` through `251f6b8bc`.
The final module results are recorded in `EXP-101`.

`EXP-090` and `EXP-091` validate the debug-only keyed SwiftUI seam added in
`9fc9e1123` and installed in the probe by `051e71292`. A same-type Detail
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

`9a656cd41` retains the last concrete scene only across ordinary reader
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

`81da104d2` extends the keyed occurrence input to regular-width
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

`89e9cb19f` lets a source-created occurrence remain canonical while SwiftUI
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

`41029e1e3` completes the named-scenario phase of the deterministic harness.
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

`e70e5ca51` completes the structured-recorder and pure-oracle phase. The recorder
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

`494dc4e66` updates every UIKit split scenario's expected timeline to the approved
one-current-destination model. Primary lifecycle remains recorded for diagnostics,
but the semantic oracle now forbids Primary in each scene; concurrent A/B split
scenarios forbid it independently. The focused catalog regression covers all nine
UIKit split scenarios and the complete probe plan passes 24/24. Historical
`EXP-074`/`EXP-075`/`EXP-079`/`EXP-080`/`EXP-082` through `EXP-084` remain valid
proof that Primary is no longer *restarted* and returned Secondary gets a fresh
UUID. Their initial Primary RUM views are now explicitly retained as gap evidence,
not reinterpreted as final success.

`af18679f2` completes the exact scene-registry phase. The main-actor registry
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

`115dc9e38` completes the first observable-driver slice. The driver addresses the
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

`116220bed` extends the observable driver to three more deterministic stack
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

`38b6868a3` moves split-selection ownership to the registered scene root and
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

`35e53ba30` moves `uikit.split.pop-cancel` and
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

`a001c8377` fixes that stock split case without changing the wire format or
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
source and 699 test files. Commit `0234183e0` contains the exact-path harness
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
across 713 source and 699 test files. Commit `853f90648` contains only the harness
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
`4fc9d91b3` contains the six source/test/probe files. The probe project file and
local xcconfig remain excluded.

This closes only target-scoped coexistence for an already explicit semantic
boundary. It does not make transparent automatic SwiftUI navigation semantic,
does not yet let a customer install one resolver on a `NavigationStack`, and does
not yet prove automatic tracking in a separate live container or scene while an
explicit exception is active. Those are the next integration/runtime rows.

### 2026-09-13 — EXP-116: once-per-container SwiftUI prototype

The next probe slice removes RUM configuration from `ProbeHomeView`,
`ProbeDetailView`, and `ProbeAlternateView`. `ProbeRUMNavigationStack` is called
once for the navigation container with:

- the application's existing bound `[ProbeRoute]` path;
- one root RUM descriptor;
- one centralized `ProbeRoute`-to-RUM resolver; and
- ordinary root and destination content builders.

The wrapper owns `NavigationStack` materialization and installs
`ProbeRUMTrackedScreen` at the root and inside the typed destination builder.
That placement is material: `EXP-047` through `EXP-049` already showed that a
background sibling, outer wrapper, or stable first child sees the path too late
and can replay retained lifecycle. The new call site centralizes customer
configuration without moving the SDK boundary away from the route that actually
materializes. The internal generation/source parameters are probe mechanics and
are not a proposed public surface.

The initial clean return run
`container-navigation-prototype-20260913-2210-a`, session
`9d1653fc-80e8-4794-9a29-50a60246d2ca`, passed 7/7 with no issues. Mapper and
backend both contained exactly:

```text
ApplicationLaunch  9e98b95f-d2f5-43af-b815-3f0efe227809
ProbeHomeView H1    a2dc84f9-b773-4612-916d-612a5fa9db50
ProbeDetailView D1  2a20ec3c-3fc9-4216-9f65-4c1feaa79770
ProbeHomeView H2    c82a59c9-fc78-45bc-be32-dddf34a3d5cd
```

H1 and H2 are distinct occurrences. There was no hosting-controller or other
automatic duplicate. Backend totals were nine actions, nine Resources, four
views, two long tasks, one session, and one vital.

After an explicit host-side uninstall, abort run
`container-navigation-abort-clean-20260913-2247-a`, session
`8b89254e-ba81-4595-86a6-5fa399d480c5`, passed 5/5. It emitted only
ApplicationLaunch `a3d3fcf2-8a60-4c02-9a8f-5f1317726b6d` and Home
`b0166eb3-749c-40dc-b921-143fe73c0f9e`. `detail-1` appeared only in the
transient path-mutation signal; no Detail RUM UUID was created. Backend totals
were five actions, five Resources, two views, one long task, one session, and one
vital.

After another explicit uninstall, same-type replacement run
`container-navigation-same-type-clean-20260913-2254-a`, session
`0436c9b2-08fc-4c92-a311-7336eafaad4a`, passed 6/6. Its exact views were launch
`f5cefee8-7e39-44eb-8fd7-4b28b4726be8`, Home
`5598f7fa-e93c-4ba4-bbb5-9b613aa9133b`, Detail₁
`f5311b38-1167-4f33-967a-9f541347e169`, and Detail₂
`d8375a2b-26a6-4f57-937c-0ffb7f31a7e2`. Both Detail occurrences intentionally
shared the same RUM name and URL. The decisive `binding-update-2` action and
Resource used Detail₂. Backend totals were nine actions, nine Resources, four
views, three long tasks, one session, and one vital.

One delayed callback scheduled by removed Detail₁ fired after Detail₂ became
current. Its probe source label remained `detail-1`, while RUM correctly used
current Detail₂ because the public call had no trustworthy SDK source. This is
the approved last-interacted compatibility fallback, not a failed exact-source
handoff. The terminal oracle does not flag it.

The probe build-for-testing succeeds, all 45 tests pass, and repository lint
reports zero violations across 713 source and 699 test files. Commit
`93cbb3387` contains only the probe source refactor. This proves that the approved
once-per-container semantics are implementable with a builder-owning boundary;
it does not approve a public wrapper/modifier signature or make transparent
automatic navigation semantic.

### 2026-09-13 — EXP-117: non-isolated clean-mode launches

Two intermediate runs deliberately remain in the record because they exposed a
handoff-breaking experiment flaw. Abort run
`container-navigation-abort-20260913-2225-a` and same-type replacement run
`container-navigation-same-type-20260913-2232-a` passed their local oracles, but
they were started through back-to-back Xcode install/run calls without first
uninstalling the test bundle.

The new run IDs appeared on their later action and Resource events, but direct
backend inspection of semantic view UUIDs showed
`context.probe.run_id=container-navigation-prototype-20260913-2210-a`. Querying
the new run IDs therefore returned only their ApplicationLaunch view and could
have produced a false missing-view conclusion. Local sessions were
`18cb3927-8afb-4f39-92bf-75b3391de050` and
`1f6964c8-0200-44b9-a775-ffd91e4a0bc9`.

`--probe-run-mode clean` describes the requested experiment mode after the app
has launched; an app cannot uninstall itself before launch. It is not evidence
that host state was cleared. Explicit simulator uninstall followed by the two
clean `EXP-116` reruns produced correctly keyed semantic views immediately.
Until Phase 5 supplies a host runner, every clean acceptance run must uninstall
first and verify that each semantic backend view carries the exact requested run
ID. The contaminated runs support only their local state-machine result.

### 2026-09-13 — EXP-118: semantic scene A with automatic scene B

The named scenario `swiftui.coexistence.semantic-a-automatic-b` narrows the
remaining coexistence claim. Navigation-occurrence tracking stays configured so
automatic SwiftUI discovery remains enabled application-wide, but the semantic
container boundary is installed only in logical scene A. The oracle keeps
call-site source separate from mapper-observed ownership and requires B's final
marker to use a non-launch automatic view whose first snapshot occurred after the
exact open-B command. A stale automatic view from A therefore cannot produce a
false pass. Commit `3cdb4b915` contains only this probe/oracle slice.

Two explicitly uninstalled simulator runs were inconclusive because the simulator
system compositor aborted before the terminal marker and oracle result. They are
retained because their partial mapper output proves both the intended scope and
the boundary of the result:

- `semantic-auto-coexistence-20260913-2256-a`, RUM session
  `5a4d3add-7100-4ca3-bb8f-62f0c012b4d0`, emitted launch
  `27d37f44-42a1-4b11-a453-0b17ca2f04fb`, semantic A/Home H1
  `2d4aabad-eea5-4219-9474-21714e125c06`, B automatic fallback
  `d7d16229-99ec-400a-9eef-8366df7fbd8c`, and then B automatic
  `NavigationStackHostingController<AnyView>`
  `51024e58-4124-4eb0-9c4f-530f6ca6f5ea`. The fallback stopped before the
  navigation host became current. A's `semantic-a-before-peer` action and
  Resource remained on A/H1. B's delayed lifecycle action used the non-launch
  automatic host, but the driver did not reach `automatic-b-after-ready`, so the
  decisive action/Resource pair and terminal verdict remain unproven.
- `semantic-auto-coexistence-20260913-2259-b`, RUM session
  `43e42ece-f77d-4215-8c6c-22c5ce101136`, emitted launch
  `39db8093-8e01-4da8-877e-741ede177abe`, semantic A/Home H1
  `f70ee6f2-c7b0-448f-a893-212f14c841c4`, B automatic fallback
  `3f2705fa-30b1-4a39-bd2d-fe3527f41168`, and B automatic navigation host
  `d3de0fc5-8383-450b-a1b5-dce7a1c01b19`. A's marker pair again remained on
  A/H1. The simulator failed before mapped B work or the final marker.

In the first run, B's earlier `navigation-appearance-1`, `on-appear`, and
`task-immediate` source-less manual Resource work used representative A/H1 before
B's automatic controller discovery settled. The probe's source attributes do not
create SDK provenance, so this is the approved last-interacted compatibility
fallback—not evidence that a source-bearing automatic tap was misrouted. The
fallback-to-navigation-host turnover may still be undesirable automatic view
churn, but it is not a duplicate concurrent semantic destination and needs to be
judged separately from scene isolation.

Both failures were `backboardd` `SIGABRT` crashes in
`MTLTextureDescriptorInternal.validateWithDevice` / Core Animation rendering,
not crashes in the probe or SDK process. The diagnostics are
`/Users/valentin.pertuisot/Library/Logs/DiagnosticReports/backboardd-2026-09-13-225654.ips`
and
`/Users/valentin.pertuisot/Library/Logs/DiagnosticReports/backboardd-2026-09-13-225841.ips`.
One first install transiently returned
`Launch session has not been found`; its immediate retry launched. No backend
query was used because neither run produced a terminal oracle result.

The project builds for testing, all 49 probe tests pass, and repository lint
reports zero violations across 713 source and 699 test files. The scenario is now
prepared for one explicitly uninstalled iPhone Duo or physical multi-window iPad
run. It must not be upgraded from `INCONCLUSIVE` until the final B marker passes
locally and exact run-ID backend intake confirms its owner.

### 2026-09-13 — EXP-119: exceptional manual Sheet over automatic Home

The named scenario `swiftui.coexistence.automatic-manual-sheet` keeps automatic
SwiftUI discovery enabled and makes only scene A's `sheet` screen explicit. Its
required sequence is automatic Home H1 -> explicit Sheet S1 -> fresh automatic
Home H2. The oracle forbids an automatic view during S1's actual mapper lifetime,
requires sheet action/Resource work on S1, and requires returned-Home work on an
automatic owner created after dismissal and distinct from H1. Commit `2a15478df`
contains the scenario, dedicated presentation command, view-lifetime interval,
and owner-relation checks.

The first explicitly uninstalled run,
`automatic-manual-sheet-20260913-2332-a`, RUM session
`b2f50cf0-1394-4b1b-9da9-09d752a22bbf`, stopped after three matches because the
probe driver derived marker source only from the stack path. It therefore labeled
`manual-sheet-active` as Home even though the mapper correctly attached the
action and Resource to explicit Sheet S1
`8164da1d-6b46-422f-8a13-8e6fd9a0d1bb`. This was invalid experiment metadata,
not an SDK attribution failure. Commit `dd1b1cf34` makes driver markers use the
complete current scene destination and labels the interval start as Sheet. The
project then built for testing and all 56 probe tests passed.

The corrected, explicitly uninstalled run,
`automatic-manual-sheet-20260913-2338-b`, RUM session
`f483b9eb-3ea8-4cfc-a884-c0b547effb5a`, produced a conclusive local `FAIL` after
six matched expectations. The exact mapper sequence was:

1. ApplicationLaunch `a97616e2-a188-45f3-8a0c-6b27aaabb9f5`.
2. Automatic fallback `97c08dbb-f8cd-49a0-abba-20bba27d27a9`, active for about
   18 ms and owning no decisive scenario work.
3. Automatic Home H1 `60a6d680-4f7b-4adf-af99-6809a716d4e8`.
4. Explicit Sheet S1 `fad831da-1e4c-4dc9-bec3-d71b0b14e586`.
5. Fresh automatic Home H2 `c36d0109-9b9c-476a-8b40-09ad586b816e`.

Pre-sheet action/Resource work used H1. The sheet's `on-appear`, immediate and
delayed task work, and corrected `manual-sheet-active` pair all used S1. No
automatic Sheet or hosting-controller duplicate started inside S1's mapper
lifetime. The failure is specifically the return boundary:

- dismissal state mutation was sequence 60;
- the probe observed Home materialized at sequence 68;
- Home-source `sheet-dismissed-immediate` action and Resource started at sequence
  69 while S1 was still current;
- H2 started at sequence 72;
- the immediate Resource completed on its frozen S1 owner at sequence 73;
- S1 stopped at sequence 74; and
- the settled Home action/Resource at sequences 75/78 used H2.

Backend intake independently reports the same five views and ownership. The
session aggregate contains five views, ten actions, ten Resources, two long
tasks, zero RUM errors, and zero crashes. This is not a duplicate-view failure:
the explicit exception correctly owns the sheet, automatic tracking remains
available, and a fresh H2 eventually returns. It is a semantic timing gap because
customer work executed from SwiftUI's immediate `onDismiss` callback is already
Home work but is still attributed to the outgoing Sheet.

Do not weaken the scenario to accept S1 for that callback. Investigate whether a
reviewed container/router presentation signal or a manual-stack reveal can start
H2 before immediate return work without speculative views or normal-app
regressions. UIKit `viewDidAppear` starts H2 only after `onDismiss`; retrying the
same scenario on physical hardware is useful for ordering parity but does not
replace the deterministic failure already observed. No probe, SDK, simulator, or
Session Replay crash occurred in either run.

### 2026-09-14 — EXP-120: direct keyed manual view over automatic Home

The named scenario `swiftui.coexistence.automatic-keyed-manual-view` exercises
the existing public `RUMMonitor.startView(key:name:)` and `stopView(key:)` calls
without adding a scene-aware API. Automatic SwiftUI discovery stays enabled. The
required semantic sequence is automatic Home H1 -> manual Compose M1 -> fresh
automatic Home H2. The scenario requires exact pre-manual work on H1, an authority
interval bounded by the driver steps, active Compose work on M1, exact H1 and M1
stops, and immediate plus settled returned-Home work on a fresh H2. It forbids an
automatic view from becoming current while manual authority is active.

Commit `56969d8a5` adds the scenario, keyed manual steps, exact scene/destination
driving, a catalog-owned observable-driver set, and positive/adversarial oracle
fixtures. Those fixtures reject a retained H1, an automatic view before the first
M1 snapshot, wrong M1 ownership, H1 reused as H2, and disagreement between
immediate and settled return owners.

Four attempts are intentionally retained:

1. `automatic-keyed-manual-20260914-0005-a`, RUM session
   `54005e3d-daf7-460e-8c38-2cf4e7505e4f`, is invalid as SDK evidence. The new
   scenario existed in the catalog but was absent from a separate observable-driver
   allowlist, so no scenario step started. The duplicated allowlist was removed;
   the catalog now owns the decision.
2. `automatic-keyed-manual-20260914-0010-b`, RUM session
   `26990bc0-7785-4eda-b0f7-f3971516f5a3`, is valid partial evidence. Automatic
   H1 started, Compose M1 started, then Compose stopped about 45 ms later and an
   automatic fallback began. The driver subsequently waited for a Compose-view
   signal that had already occurred, so it timed out before terminal evaluation.
   Short-lived view signals are no longer used as a driver barrier; recorded
   markers and the oracle decide acceptance.
3. `automatic-keyed-manual-20260914-0015-c`, RUM session
   `9382bf4d-5985-4047-898c-deb8103af68b`, is the first conclusive run. Compose
   stopped about 31 ms after it started. `keyed-manual-active` and
   `keyed-manual-stopped-immediate` work used the intervening automatic fallback;
   `keyed-manual-stopped-settled` used fresh Home H2. It produced six views, ten
   actions, ten Resources, and no error/crash.
4. `automatic-keyed-manual-20260914-0030-d`, RUM session
   `3609bce2-ea31-41b1-9d8b-ad2ab39ec7c0`, is the explicitly uninstalled,
   hardened acceptance baseline. The raw runner stopped after two matches because
   the first version of the exact H1-stop matcher treated M1's unrelated stop as
   a violation instead of continuing to the deferred H1 stop. H1 did stop later.
   The matcher now scans past unrelated lifecycle facts, and a regression fixture
   covers that ordering. Under the corrected oracle, the decisive failure is the
   automatic fallback that starts inside the manual-authority interval and owns
   Compose work—not the deferred mapper ordering of H1's stop.

The exact final-baseline view timeline is:

1. ApplicationLaunch `4d6fe9c9-db64-4c8c-a3bf-8db3a2527c8f`.
2. Startup fallback `e1980c0c-042b-4ed0-ae34-4d84d4f12a39`.
3. Automatic Home H1 `94196346-7199-4b1c-8c1a-5a9f13ef8989`.
4. Manual Compose M1 `ba56c80b-a043-49a3-bbbf-ef2a286889e2`.
5. Automatic fallback `2254427a-39d8-4a5c-828b-c8be9aa1319f`.
6. Fresh automatic Home H2 `fe6f151d-f312-46c5-88d5-c1314a6cc6c5`.

The authority interval spans recorder sequences 32–46. M1 starts at sequence 34
and stops at 36, about 47.5 ms later; the fallback starts at 37. H1's deferred
stop snapshot arrives at 41, the explicit manual-stop step begins at 44, H2 starts
at 55, and the fallback stops at 64. The decisive backend owners are:

- `automatic-home-before-keyed-manual` action/Resource -> H1;
- `keyed-manual-active` action/Resource -> the automatic fallback;
- `keyed-manual-stopped-immediate` action/Resource -> the same fallback; and
- `keyed-manual-stopped-settled` action/Resource -> H2.

Backend intake contains all six views, ten actions, ten Resources, zero RUM
errors, and zero crashes. Compose owns no decisive action or Resource. This is a
simulator-conclusive SDK/API behavior gap, not a gesture or topology limitation.
The source explanation matches the runtime result: direct keyed monitor commands
bypass `RUMViewsHandler`'s retained per-scene platform stack, while automatic
discovery continues to mutate that stack and can replace the manual scope.

The next production slice must not merely add a scene target to the same direct
commands. A targeted manual entry must join the handler's per-scene stack, remain
authoritative while active, stage newer automatic candidates beneath the complete
manual suffix without emitting them, and reveal the latest valid underlying
candidate as a fresh occurrence on exact scene/key stop. Existing source-less
manual APIs retain their inferred/process-representative behavior. Public Swift
and Objective-C signatures remain subject to normal API review.

The final probe plan passes 65/65, the Xcode 27 build-for-testing succeeds, and
repository lint reports zero violations across 713 source and 699 test files.
Final-run artifacts include
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/Keyed Manual Acceptance Baseline-00_30_23_041-logs.txt`
plus its matching hierarchy and screenshot.

### 2026-09-14 — EXP-121: first scene-targeted manual-stack run

Commits `29c8cec2c` and the probe switch later checkpointed as `a40e7903c`
replace only the experimental call site with an internal exact-scene capability.
`Monitor` forwards that capability to the bound `RUMViewsHandler`; existing
source-less public start/stop methods remain on their process-inferred path. The
handler inserts the keyed manual occurrence into the target scene's navigation
stack, keeps a complete nested manual suffix authoritative, stages trustworthy
automatic candidates beneath it, applies stop-call attributes, and resolves the
same key independently in two scene stacks.

The clean run `scene-targeted-manual-20260914-0120-a`, RUM session
`f32f25c8-7403-4513-89fa-75d9e3a3952d`, proves the main `EXP-120` defect fixed:
Compose M1 stays current and owns `keyed-manual-active` action/Resource work.
The 10-match terminal `FAIL` isolates a narrower reveal problem. Automatic
discovery staged a generic hosting fallback beneath M1; exact stop revealed it
for the immediate pair, then a real automatic Home H2 replaced it and owned the
settled pair.

The exact mapper chain was:

1. ApplicationLaunch `1a14eaf1-76fc-4b0f-9b7c-63571d0201c4`.
2. Startup fallback `04f5acba-eb60-4395-8b29-2f77c4a0febb`.
3. Home H1 `01a48950-4e01-45cb-aba0-3f5c6a682a43`.
4. Compose M1 `b27bf081-2b16-42eb-9580-e85b1560509b`.
5. Revealed generic fallback `14bcb8b2-ae00-4e5e-b485-f0e32c6564ca`.
6. Fresh Home H2 `2c07f716-17dc-42fa-99a6-5f0e3788d539`.

Backend intake independently returns 30 exact-session documents: six views, ten
actions, ten Resources, two long tasks, one vital, and one session, with zero
errors and zero crashes. Owners match the mapper. This run must not be reported
as manual-authority failure: authority is fixed; the remaining bug is treating a
generic hosting fallback as a trustworthy destination to reveal.

Artifacts use the prefix
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/EXP-121 Scene Targeted Manual Observation 0128-01_25_20_394`
for logs, hierarchy, screenshot, and thumbnail.

### 2026-09-14 — EXP-122: scene-targeted manual-view acceptance

Commit `b1a0fb6b8` retains the destination that was current when the first
targeted manual view takes authority. While that manual suffix remains current,
the platform disappearance of that immediate retained destination is ignored,
and generic SwiftUI hosting/navigation-stack fallback names are not staged as
semantic candidates. A legitimate automatic or semantic destination can still
replace the retained candidate beneath M1. Scene disconnect still invalidates
the complete stack rather than resurrecting it.

The explicitly uninstalled successor
`scene-targeted-manual-20260914-0135-b`, RUM session
`7194cd61-23d0-4727-877a-79fbc985fc32`, passes all 16 oracle expectations with
no issue. `simctl get_app_container` returned ENOENT after uninstall and before
launch. The exact mapper chain is:

1. ApplicationLaunch `f8fb4f51-29b5-4314-bb49-3e0546df698f`.
2. Expected startup-only fallback `60f48461-cd10-49a9-bac4-10b6b409cc69`.
3. Home H1 `9c814d8c-8403-483a-9fea-dde17983f002`.
4. Authoritative Compose M1 `553f922a-ce38-462e-8469-24322a0ab10d`.
5. Fresh Home H2 `dd04c9da-d1e8-46c0-b093-93a7c582a7f8`.

No generic fallback occurrence appears during or after manual authority.
Pre-manual action/Resource work uses H1, active work uses M1, and both immediate
and settled post-stop pairs use the same H2; H2 differs from H1. Backend intake
matches all owners and contains 28 exact-run documents: one session, five views,
ten actions, ten Resources, one long task, and one vital. The session reports
zero errors and zero crashes, and every view document carries the requested run
ID, ruling out `EXP-117` contamination.

Focused manual-authority tests pass 8/8. The complete RUM run passed 1,164/1,165;
its only failure was the unrelated timing-sensitive
`TimeseriesSessionCollectorTests.testWhenBackgrounded_pauseAlwaysStopsSampling`,
which passed immediately in isolation. A clean complete rerun then passed
1,165/1,165. The probe builds for testing and passes 65/65; repository lint
reports zero violations across 713 source and 699 test files, and
`git diff --check` passes.

Runtime artifacts use the prefix
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/EXP-122 Scene Targeted Manual Acceptance 0135-01_36_26_535`.

### 2026-09-14 — EXP-123: scene-targeted Sheet without subtree suppression

The clean `scene-targeted-sheet-20260914-0208-a` run, RUM session
`33b814f6-c709-4f14-bc08-ffebd43f4203`, used the exact-scene
`RUMSceneTargetedManualViewHandling` path for the application's semantic Sheet
destination but did not install any presentation-subtree suppression. This was
the direct test of whether the handler-owned manual suffix was sufficient on its
own.

It was not. The semantic Sheet remained observable, but automatic SwiftUI
controller discovery also created structural navigation-host churn and a
redundant automatic view named `ProbeSheetView` for the presentation hosting
controller. That transient automatic presentation preempted the early returned
Home occurrence and produced another Home occurrence afterward. A correct
manual stack cannot by itself identify which UIKit controller is merely the
platform representation of the same semantic presentation.

This run is a conclusive integration failure, not a reason to weaken automatic
tracking globally. It establishes that semantic presentation support needs two
cooperating pieces: the router publishes the exact scene's semantic lifecycle,
and a UI-attached boundary suppresses automatic discovery only for the matching
native presentation subtree. The process remained crash-safe and emitted no RUM
error.

Artifacts use the prefix
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/EXP-123 Scene Targeted Sheet-02_10_33_343`.

### 2026-09-14 — EXP-124: correct ownership with an invalid aggregate interval

Commit `f452e9e3f` generalized the weak SwiftUI authority registry so an attached
state may suppress automatic discovery without publishing a second RUM view.
The probe applied that suppression-only boundary to the Sheet subtree while its
centralized router continued to start and stop the semantic Sheet through the
exact-scene handler.

The explicitly uninstalled `semantic-sheet-suppression-20260914-0222-a` run,
RUM session `8101b16d-ed17-4ded-8a29-c9bbf8aa219b`, produced the intended
five-view set: ApplicationLaunch, the expected startup fallback, Home H1,
semantic Sheet M1, and fresh Home H2. There was no automatic `ProbeSheetView`.
Pre-Sheet work used H1, active work used M1, and both immediate and settled
dismissal work used H2.

The then-current oracle still failed 10 matched expectations. Its forbidden-view
interval ended only when the mapper observed M1's final aggregate snapshot. A
pending Sheet Resource kept that aggregate alive after the semantic stop, so H2
correctly started before the outgoing M1 snapshot arrived. RUM view aggregate
delivery lifetime is affected by child work and is not a navigation-authority
clock. Using it as the suppression interval would either reject correct overlap
or delay the revealed destination and misattribute post-dismiss work.

Artifacts use the prefix
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/EXP-124 Semantic Sheet Suppression-02_24_25_413`.

### 2026-09-14 — EXP-125: semantic Sheet authority acceptance

Commit `fad83f58f` separates the two relevant intervals. The exact
`manual-sheet-active` interval represents semantic router authority. A separate
`swiftui-presentation-subtree` interval follows the mounted platform subtree
through native dismissal and rejects only an automatic RUM view named
`ProbeSheetView`. The oracle also has a regression proving that a delayed
automatic Sheet after semantic stop is still rejected, while a fresh underlying
view may start before the outgoing aggregate's final snapshot.

The clean `semantic-sheet-authority-20260914-0232-a` run, RUM session
`c01631fb-8b2c-4071-b7c3-78c6f042774f`, passes 14/14 with no issue. The exact
mapper sequence is:

1. ApplicationLaunch `be3f8da2-3c0d-42d8-aa64-faa83626f34c`.
2. Expected startup-only fallback `af14e2e9-e5b1-400e-bcd4-a7d10fcf2bc4`.
3. Home H1 `76aada56-2822-4f7b-9177-bd8f6a35b0fe`.
4. Semantic Sheet M1 `81ecbf07-18bd-414d-a14f-a596a84431f1`.
5. Fresh Home H2 `b7e26b43-3ad6-4455-8ca5-b27b1357b019`.

The manual authority interval spans recorder sequences 32–62 and contains no
automatic view. The mounted presentation-subtree interval spans sequences 33–71
and contains no automatic `ProbeSheetView`. H2 starts at sequence 64, after
exact authority ends and before M1's delayed final snapshot at sequence 70. The
pre-Sheet pair owns H1, the active pair owns M1, and immediate plus settled
dismissal pairs own the same H2. H1 and H2 are distinct occurrences.

Backend intake independently returns 29 exact-session documents: one session,
five views, ten actions, ten Resources, two long tasks, and one vital. It matches
all three semantic view IDs and owners and reports zero errors and zero crashes.
The app remained running, and explicit uninstall plus the pre-launch ENOENT
container check establishes clean isolation.

Focused production tests pass 6/6, including the approved several-underlying-
commits, nested-different-key, and duplicate-active-key manual contracts. The
complete RUM suite passes 1,169/1,169, the probe builds for testing and passes
68/68, repository lint reports zero violations across 713 source and 699 test
files, and `git diff --check` passes. This closes the internal Sheet slice only;
full-screen-cover parity, public API review, sibling-container proof, and live
same-key A/B targeting remain open.

Runtime artifacts use the prefix
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/EXP-125 Semantic Sheet Authority-02_33_30_317`.

### 2026-09-14 — EXP-126: semantic full-screen-cover authority acceptance

Commit `c70920c94` generalizes the probe's presentation model and adds an
independent strict scenario for SwiftUI `fullScreenCover`. It does not infer
support from the Sheet result: the scenario has its own presentation command,
semantic view name/key, router-authority interval, native-subtree interval,
dismiss markers, source/owner expectations, and catalog regression. Sheet and
full-screen cover share only the harness implementation needed to express the
same approved product contract.

The initial `semantic-full-screen-cover-authority-20260914-0304-a` launch is not
classified. Its Xcode interaction session expired before a hierarchy or terminal
JSONL capture, and no backend session is claimed for it. A new clean run was
therefore created instead of inferring a result from stale simulator state.

Before `semantic-full-screen-cover-authority-20260914-0312-b`, the exact probe
bundle was uninstalled and its app-container lookup returned ENOENT. The run's
single terminal result passes 14/14 with no issue. Its exact mapper sequence is:

1. ApplicationLaunch `1f03e92f-7f8c-4c40-b8f1-ce460ec902c8`.
2. Expected startup-only fallback `a2dc9183-66bb-49af-be2c-c2ca116fb90e`.
3. Home H1 `700cf5c7-041b-45c7-854a-64f050580e18`.
4. Semantic full-screen-cover M1 `6cc95aa2-d685-4116-8ddd-02a81e177d0e`.
5. Fresh Home H2 `baf8d431-c728-431f-be4b-752066fc8784`.

The `manual-full-screen-cover-active` authority interval spans recorder
sequences 32–61 and contains no automatic view. The
`swiftui-full-screen-cover-subtree` interval spans sequences 33–70 and contains
no automatic `ProbeFullScreenCoverView`. H2 starts at sequence 63, after exact
semantic authority stops. M1's delayed final aggregate arrives at sequence 69,
and native subtree suppression ends at sequence 70. This independently confirms
the `EXP-124`/`EXP-125` distinction between semantic ownership, aggregate
delivery, and native subtree lifetime.

The decisive mapper events are:

- pre-cover action `d366f046-2da9-4782-a4de-ea2f0b02660d` and Resource
  `f2f57ccc-660c-48d8-8183-ed8d637718d0` own H1;
- active-cover action `8b15d5bf-cefb-4b29-95e1-2e54b63b9e46` and Resource
  `c0e0ed3f-e4a3-47a0-a90e-6bdd3e3c3c47` own M1;
- immediate-dismiss action `d5bfd375-6f37-4bb4-bbc4-1a07c6a8e7f1` and Resource
  `3cbd69e0-d7d2-4f91-8e0e-52b549d0e345` own H2; and
- settled-dismiss action `118ef52d-864d-45c8-8490-5f63e4b1fdc7` and Resource
  `6626bd20-457c-4f40-a066-3b900615727d` own the same H2.

Datadog intake for session `ba5d005c-ce65-40eb-b639-2845e570f70b`
independently returns 28 exact-run documents: one session, five views, ten
actions, ten Resources, one long task, and one vital. The backend owners and
view IDs match the mapper, `session.error_count` and `session.crash_count` are
zero, and all queried documents carry the requested
`@context.probe.run_id`.

The probe builds for testing and passes 69/69. Repository lint reports zero
violations across 713 source and 699 test files, and `git diff --check` passes.
The production RUM implementation did not change in this slice, so the existing
clean 1,169/1,169 RUM result remains the relevant regression gate. Internal
complete-destination presentation parity is now closed for Sheet and full-screen
cover. At that checkpoint, public API review, sibling-container isolation, and
live same-key A/B targeting remained open.

Runtime artifacts use the prefix
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/EXP-126 Full Screen Cover 0312b-03_08_59_519`.
The successful Xcode build log is
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260914-030132.txt`;
the 69-test summary is
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/BE82E273-1149-4FDD-9833-56FACB9398D3.txt`.

### 2026-09-14 — EXP-127: sibling-container authority acceptance

Commit `45ec5656a` adds
`swiftui.coexistence.sibling-container-authority`. A `TabView` was deliberately
rejected as the discriminator because selection, preload, and deactivation would
make it ambiguous whether both containers were truly mounted and independently
eligible. The accepted fixture instead places two `NavigationStack` branches in
an `HStack` under one outer SwiftUI host. The left branch mounts a
suppression-only boundary and exact-scene manual M1. The right branch begins on
automatic Home H1 and commits Detail while M1 remains current. The required
timeline is H1 -> M1 -> fresh Detail D1: no intermediate right-side automatic
view may become current during M1, and immediate plus settled post-stop work must
use the same new Detail ID.

The experiment does not infer sibling topology from SwiftUI source structure. A
probe-only `UIViewRepresentable` records each branch's real controller ancestry.
The driver waits for an immutable `assertion:sibling-controller-topology` result;
missing, nested, or collapsed ancestry times out as `INCONCLUSIVE`. In the final
run, the left branch used navigation controller `0x105de0700`; right Home and
right Detail used `0x105de0e00`; all joined outer host `0x105de4500`. Right Home
and Detail had distinct hosting controllers while remaining in the same right
navigation branch. This is the concrete containment evidence behind the authority
claim.

The first run, `sibling-container-authority-20260914-0350-a`, passed 19/19 and
proved the semantic owners, but it is not the clean acceptance artifact. Its
probe-only `ProbeControllerAncestryReader` materialized as a late fifth automatic
RUM view after the assertions. That is measurement noise, not an SDK semantic
failure, and remains documented because a hierarchy witness can perturb the very
automatic tracker it measures. The predicate now excludes only that exact probe
type rather than broadening suppression to customer controllers.

The clean successor, `sibling-container-authority-20260914-0354-b`, also passed
19/19. Session `c484fb2a-bd67-45f6-9c4e-8f284baaf843` contains 30 events and
exactly four views: launch, automatic H1, manual M1, and fresh automatic Detail.
The final hardened run, `sibling-container-authority-20260914-0403-c`, repeats
the result after making the topology wait mandatory. Its assertion step starts at
recorder sequence 60, observes a passing topology assertion at 61, and
acknowledges it at 62 before continuing. The terminal result passes 19/19 with no
issue.

Backend session `46b9029f-eee9-4e1f-9fec-67a735efcc19` contains 31 exact-run
events:

1. ApplicationLaunch `2f44b937-8d97-490d-ab29-e72a191475a4`.
2. Automatic Home H1 `a3d00b0e-2117-4816-a721-d232ceac7b19`.
3. Semantic manual M1 `727bcf82-3e4c-4ea8-96a5-a803d6559ea3`.
4. Fresh automatic Detail D1 `1851d017-2d9f-4b8c-bf87-f9e3f5e5ad01`.

Launch, H1, and D1 each own two actions and two Resources; M1 owns five of each,
including work sourced from the right Detail while it is only staged underneath.
There is no helper view, error, or crash. The remaining five events are three
long tasks, one session, and one vital. One console warning reports a delayed
Resource stop after the final view ended, even though its frozen D1 owner was
preserved and backend intake accepted the Resource correctly. Treat warning
quality as a later diagnostic item, not as an attribution failure.

Build-for-testing passed at
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260914-035946.txt`.
The full generated probe plan passes 76/76 at
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/C9332EE0-5CDF-4453-B04C-691956FA8132.txt`.
Repository lint again reports zero violations across 713 source and 699 test
files, and `git diff --check` passes. No production RUM file changed in this
slice, so the clean 1,169/1,169 RUM result remains the production regression
gate. Final runtime artifacts use the prefix
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/EXP-127 Sibling Container Authority 0403c Observer-04_08_22_968`.

This closes the internal sibling-containment and reveal mechanics, not the public
semantic API. The next simulator-capable discriminator is the approved
different-key nested manual sequence plus duplicate-active-key crash safety. The
independent scene-A semantic/scene-B automatic and same-key A/B rows remain in
the physical-device queue.

### 2026-09-14 — EXP-128: nested keyed-manual authority acceptance

The new `swiftui.coexistence.nested-keyed-manual-view` scenario exercises the
approved manual suffix with real SwiftUI destinations rather than only handler
fixtures. It starts from automatic Home H1, starts Compose C1, nests Preview P1,
stops Preview to reveal a fresh Compose C2, forwards a duplicate active Compose
start, then stops Compose to reveal fresh automatic Home H2. Every semantic
transition has paired action/Resource ownership checks. The duplicate-start
interval forbids a view of any origin and requires its marker pair to remain on
C2. The outer authority interval forbids automatic current views until Compose
stops.

Attempt `nested-keyed-manual-20260914-0835-a` was a harness failure, not an SDK
result. Compose C1 had already been emitted by the mapper before the driver began
its `rum-view:compose#1` wait, so the driver waited only for a later event and
timed out. Exact RUM occurrence snapshots are immutable evidence, like completed
topology assertions. The driver now checks the recorder first for `rum-view`
requirements before subscribing. Focused coverage proves the wait accepts the
already-recorded exact occurrence without making mutable lifecycle-state waits
stale or permissive.

Clean retry `nested-keyed-manual-20260914-0837-b` passes all 29 expectations. Its
native scene ID is `1FB7195F-106F-419F-B3CF-609884F52CEB`. Mapper output records:

1. Automatic Home H1 `3e67eb39-d014-43d7-8bcb-359122881e9b`.
2. Compose C1 `e8393107-65af-4889-b689-db656db84cd0`.
3. Preview P1 `82b08791-aefc-42c5-9e48-2b4475d42823`.
4. Fresh Compose C2 `996d39fe-1ca2-43a6-a98a-0894fa28f346`.
5. Fresh automatic Home H2 `c7a6332f-431d-408b-9dc4-19ce150fde59`.

The first Compose marker uses C1; Preview work uses P1; immediate and settled
Preview-stop work plus the resumed and duplicate-start markers use C2; immediate
and settled final-stop work use H2. C1 and C2 are distinct, H1 and H2 are
distinct, and the duplicate start creates no C3 or other view.

Backend session `7e617c78-c0a4-4494-8b90-7d11e635ccdf` independently confirms
the seven-view timeline: ApplicationLaunch, the expected startup-only automatic
fallback, H1, C1, P1, C2, and H2. It contains 15 actions and 15 Resources. The
duplicate Compose action and Resource both use C2; the Preview and final reveal
Resources use C2 and H2 respectively, matching their actions. The remaining
events are one session, one long task, and one vital. No error or crash is
reported.

The full generated probe test plan passes 83/83 at
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/E12C64EE-214C-46F9-915E-783F9EC54F18.txt`; its result bundle is
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/Test-RUMNativeMultiSceneProbe-2026.09.14_08-43-58-+0200.xcresult`.
The successful build log is
`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260914-082944.txt`.
Repository lint reports zero violations, and `git diff --check` passes.

This closes the one-scene nested-manual and duplicate-active-key runtime row. It
does not prove that the same key stays isolated in two concurrently live scenes,
nor does it approve the public Swift or Objective-C overloads. The next
simulator-capable discriminator is exact same-key start/stop in A and B with
reverse-order completion; if stable topology fails again, route its acceptance
run to iPhone Duo or a physical multi-window iPad.

### 2026-09-14 — EXP-129: same-key manual views in two scenes

The new `swiftui.coexistence.same-key-manual-two-scenes` scenario starts from
automatic Home in A and B, starts the same customer key `compose` independently
in both scenes, stops B before A, and requires each exact stop to reveal a fresh
automatic Home occurrence only in its own scene. A debug-only
`emit-scene-context-marker` step supplies the same trustworthy scene context that
a real UI-event call site would provide. Ordinary `emit-marker` and customer
source-less APIs remain unchanged and continue to exercise last-interacted
compatibility behavior.

The generated oracle requires distinct A/B Home owners, distinct Compose UUIDs,
exact action/Resource ownership in each scene, continued ownership by A Compose
after B stops, and fresh returned-Home owners for both scenes. Six adversarial
fixtures reject a shared Compose UUID, cross-scene B work, B stop preempting A,
and reuse of either original Home occurrence. The full probe test plan passes
91/91:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/9EEC23EE-5471-45BA-AB5C-F81028144D27.txt`

The result bundle is:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/Test-RUMNativeMultiSceneProbe-2026.09.14_09-28-22-+0200.xcresult`

Build-for-testing also passes with no diagnostics:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260914-092846.txt`

Repository lint reports zero violations across 713 source and 699 test files,
and `git diff --check` passes for the combined implementation and documentation
checkpoint.

The sole runtime attempt was explicitly uninstalled first; the pre-launch app
container lookup returned `ENOENT`. Run
`same-key-manual-two-scenes-20260914-0931-a` created local RUM session
`5986e490-0f5d-426c-8bb1-b9490d18843c`. Scene A resolved to native session
`1FB7195F-106F-419F-B3CF-609884F52CEB`, and scene B resolved independently to
`AFAB95FA-E954-4EA9-9144-CA959A9171A0`; B reached `scene-ready` at signal 43.
The Xcode launch session then expired while the captured prefix showed
CoreAnimation invalid-port and BoardServices connection interruptions. The
device-interaction session disappeared before a hierarchy, screenshot, or full
log artifact could be captured. No manual Compose step or terminal semantic
result was observed. Exact run-ID and session-ID backend searches returned zero
events after the attempt.

This result is simulator-inconclusive. It neither passes nor fails same-key
scene isolation and contains no evidence of an app or SDK crash. Repeating the
same simulator topology would revisit the already documented compositor limit,
so the next attempt belongs on iPhone Duo or a physical multi-window iPad. Use
the exact named scenario and require its terminal PASS plus backend ownership;
do not replace that gate with the 91/91 hostless contract.

### 2026-09-14 — EXP-130: Operation steps across navigation

The new `operations.navigation.lifecycle` scenario tests the Operation contract
without requiring a second live window. Each Operation step is invoked from an
exact scene-aware UI call site, but each navigation transition creates a fresh
semantic RUM view occurrence. The sequence is:

1. start `success` on Home H1, navigate, and succeed it on Detail D1;
2. start `failure` on Home H2, navigate, and fail it on Detail D2;
3. start `duplicate` on Home H3, navigate, start the same exact identity again on
   Detail D3, and succeed it on D3.

The harness records honest `assertion` signals after invoking the SDK APIs. It
does not emit a synthetic `rum-operation` signal: Operation steps bypass the
public RUM event mappers and are written directly as vital Operation-step events.
The assertions prove invocation location and driver progress; only raw and
reduced backend documents prove Operation attribution.

The first Xcode test run exposed one Swift explicit-self compile error in the new
driver closure. After correction, all 93 tests pass:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/F939D29B-B558-46B1-BA1C-F5817E2E2DF0.txt`

The result bundle is:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/Test-RUMNativeMultiSceneProbe-2026.09.14_10-10-50-+0200.xcresult`

Build-for-testing passes with no diagnostics:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260914-101227.txt`

Repository lint reports zero violations across 713 source and 699 test files.
The run used an explicit uninstall, and the pre-launch container lookup returned
`ENOENT`. Run `operations-navigation-20260914-1015-a`, native scene
`730D30F0-9ED2-4469-B7DF-0B883A7EEF21`, terminates with:

```json
{"result":{"issues":[],"matchedExpectationCount":27,"scenarioID":"operations.navigation.lifecycle","schemaVersion":1,"state":"PASS"},"runID":"operations-navigation-20260914-1015-a","type":"semantic-result"}
```

Backend session `74b23c67-b6b7-4917-86ed-2ff8c7c4f559` contains six semantic
occurrences: success H1 `d6617ab6-1414-4369-9beb-cb9a8ccd6a86` → D1
`11e4efeb-bd6e-4475-9120-09847cc99b59`, failure H2
`88e9e4d6-e554-4921-ac5c-8454747348e8` → D2
`e7a48e28-2711-4eb8-88f6-1176ec7f2c6c`, and duplicate H3
`b6d3feb0-27d8-49dd-adef-5bd8125de4a2` → D3
`e0b3e68c-356d-41cd-bf3d-95c87e783cdd`. Seven raw Operation steps reduce to
three Operations. Success exposes H1/D1, failure exposes H2/D2 plus its error,
and the duplicate exposes D3/D3 because the latest start wins. The earlier H3
start has no synthetic end and remains open for the four-hour backend timeout.
The exact corrected warning recommends unique keys and explains that timeout.
The session inventory is 23 actions, 23 Resources, eight vitals including seven
Operation steps, seven views including startup, three reduced Operations, two
long tasks, and one session, with no error event or crash.

This is a conclusive pass for per-step same-scene navigation attribution,
failure, and duplicate identity semantics. It does not close start-in-A/end-in-B,
reverse-order cross-scene completion, or the public view-targeting API.

### 2026-09-14 — EXP-131: prepared cross-scene Operation attribution

The new `operations.cross-scene.lifecycle` scenario isolates the remaining
cross-window Operation contract from navigation already accepted in `EXP-130`.
It requires distinct automatic Home occurrences in scenes A and B, then invokes
this exact application-wide identity sequence:

1. start `cross-success` in A and succeed it in B;
2. start `cross-failure` in A and fail it in B;
3. start same-name Operations with distinct `parallel-alpha` and
   `parallel-beta` keys in A and B;
4. succeed `parallel-beta` in B before succeeding `parallel-alpha` in A.

The driver records eight acknowledgements after the corresponding SDK calls.
Its marker actions and Resources verify only call-site progress and scene
context. The scenario intentionally has no synthetic Operation-step observation:
the runtime acceptance oracle remains eight raw `operation_step` documents and
four reduced Operations with A→B, A→B failure, A→A, and B→B ownership.

The passing semantic fixture uses distinct, stable A/B Home owners. Four negative
fixtures independently reject a shared view UUID, B Home attributed to A, a B
completion attributed to A, and drift of A's owner after B completes. The exact
eight-command order, eight acknowledgements, scenario capabilities, and absence
of fake Operation-step expectations are covered in the driver/catalog tests.

The full generated probe plan passes 100/100:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/21CC83EA-9FB8-4540-BC2B-E6F6DF92B114.txt`

The result bundle is:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/Test-RUMNativeMultiSceneProbe-2026.09.14_10-55-40-+0200.xcresult`

Build-for-testing passes with no diagnostics:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260914-105600.txt`

Repository lint reports zero violations across 713 source and 699 test files,
and `git diff --check` passes. Signed commit `a653e29f2` contains exactly four
harness/test paths from frozen tree
`67eb64a23f985494992ef53db36130557414fd1d`.

No simulator run was attempted. `EXP-129` already reached two native scenes in
the same required topology and then lost the compositor/Xcode session before the
decisive work. Repeating that known-inconclusive path would add no semantic
evidence. Run this named scenario unchanged on iPhone Duo or a physical
multi-window iPad, then inspect raw and reduced backend documents before claiming
cross-scene Operation support. A terminal local PASS alone is insufficient.

### 2026-09-14 — EXP-132: UIKit scroll ownership across navigation

The new `actions.uikit-scroll-navigation-deceleration` scenario isolates a real
UIKit ordering boundary without requiring a second live window. It installs a
production-instrumented `UITableView` on automatic Secondary 2, waits for the
customer delegate to observe a drag, and presents fresh Secondary 3 from the next
main-actor turn after lift while the table is still decelerating. The original
table remains alive long enough to receive its late deceleration callback.

The first helper placement compiled in the app target but not in the generated
hostless test target. That test failure was a harness-target mistake, not SDK
evidence. Moving the Foundation/CoreGraphics-only threshold helper into
`ProbeScenario.swift`, which both targets compile, fixed the target boundary.

Several short-lived Xcode interaction sessions expired before any gesture. They
contain no runtime observation and must not be retried or interpreted as a RUM
failure. Xcode's packaged device-interaction skill was exported and read before
the accepted interaction. Its `help` interaction command is unsupported; prepare
the measured command before opening the session instead. The real gesture used
the table's observed bounds `{{39,178},{955,1065}}` and the command:

```text
t 676 1050 f 676 320 0.15
```

The first completed run, `uikit-scroll-20260914-1156-b`, started session
`47557219-bfe9-4a52-8ed2-c717d3fcf9dd`. It passed the original local oracle and
backend intake contained exactly one origin `.scroll` action. Review found that
`willDecelerate == true` alone did not prove the lift exceeded
`RUMScrollHandler`'s 500 pt/s swipe threshold. That run therefore remains useful
behavioral evidence but is incomplete for the intended ordering discriminator.

The hardened probe mirrors only that public experiment threshold, records the
actual pan velocity at lift, and fails closed unless its magnitude is at least
500 pt/s. A focused boundary test rejects 499 pt/s and accepts a 300-by-400 pt/s
vector. The scenario also requires drag begin, `willDecelerate == true`, active
deceleration at presentation, the fresh destination, and the original delegate's
eventual deceleration-end callback. Its exact-count oracle rejects a missing,
duplicated, migrated, wrong-type, wrong-source, or wrong-owner action.

For accepted run `uikit-scroll-20260914-1205-c`, the simulator app was explicitly
uninstalled and the pre-launch container lookup returned `ENOENT`. Native scene
`730D30F0-9ED2-4469-B7DF-0B883A7EEF21` installed table
`probe.native.uikit-scroll.scene-A.secondary-2`. The gesture lifted at
3,792.000000882894 pt/s, entered deceleration, and began presenting Secondary 3
before deceleration ended. The terminal result is:

```json
{"result":{"issues":[],"matchedExpectationCount":7,"scenarioID":"actions.uikit-scroll-navigation-deceleration","schemaVersion":1,"state":"PASS"},"runID":"uikit-scroll-20260914-1205-c","type":"semantic-result"}
```

Session `ef240096-9449-464b-a20d-59888693f444` contains origin Secondary 2
`2a4f0428-798c-42a5-9006-dc0867e5593c` and fresh Secondary 3
`08802270-6fc6-424b-8cce-5d0e1807c059`. Local mapper output and an exact backend
query both find exactly one `uikit-scroll-origin` action,
`23ceac7d-09ac-4b26-8b49-6a9034ba8357`, of type `.scroll` on Secondary 2. No
matching action migrates to Secondary 3; that fresh view owns its immediate
post-navigation action and Resource.

The `.scroll` type is intentional evidence. Above threshold, a late normal
deceleration stop could promote the active action to `.swipe`; starting the fresh
view ends the action first, so the later origin callback must neither migrate nor
duplicate it. This validates the existing branch behavior and required no
production SDK fix. It does not prove exact A ownership while simultaneously
visible B is the process representative.

The complete generated probe plan passes 109/109:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/7440D0EE-AB73-43A4-B325-952C8E639FD6.txt`

The result bundle is:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/Test-RUMNativeMultiSceneProbe-2026.09.14_12-02-34-+0200.xcresult`

The accepted interaction artifacts share this stem:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/EXP132 Threshold Proof-12_04_23_107-*`

Repository lint passes 713 source and 699 test files with no violations, and
`git diff --check` passes. Signed commit `3c9730805` contains exactly eight
probe/oracle files from tree
`3f1edaf17f4d7dd4fe654c8738ca6cb9c09440f7`. Backend intake reports no RUM
error, retry, app crash, or SDK crash for the accepted run.

### 2026-09-14 — EXP-133: Trace-only URLSession ownership across scene churn

The `traces.urlsession-cross-scene` scenario exercises the production
Trace-owned URLSession path without enabling RUM URLSession tracking. A custom
scenario-only `URLProtocol` holds one first-party response so the driver can
control completion without relying on Wi-Fi or an external server.

The sequence first establishes A/Home H1 and emits
`trace-request-representative`, then starts the real automatically instrumented
request from A. It opens B, waits for B/Home B1, and emits
`trace-completion-representative`, proving that B is now the process
representative. B then releases the response. The local oracle requires exactly
one Trace mapper event named `trace-only-home-request` on A/H1 and rejects a
missing, duplicate, B-owned, wrong-session, or accidentally RUM-Resource result.

Attempt `trace-only-20260914-1301-a`, local RUM session
`aa1e1aea-f5a4-4efa-96dd-37186f2aed42`, reached the Trace mapper after the B
representative marker and showed A ownership. The Xcode/device interaction
session then reported the app unavailable before the terminal summary was
captured. There was no crash report, fatal/assertion output, or crash dialog.
This attempt is preserved as tooling-incomplete and carries no acceptance or SDK
crash claim.

Clean retry `trace-only-20260914-1310-b` passes 8/8. Its RUM session is
`46330376-b5d0-4ee2-875c-d050aeab4c72`; A/Home H1 is
`4e84ed1e-3cff-45a8-a74f-5296f2aa8b94`, B/Home B1 is
`a108479b-1833-404f-8ba9-f6026abd231e`, and B's representative marker action is
`a224a601-5218-45fe-b578-3ec140632f35`. The Trace mapper emits exactly one
`urlsession.request` span. It starts at `2026-09-14T11:06:40.240Z`, lasts
870,901,585 ns, and retains A/H1 plus the same RUM session after B became
representative.

Exact backend queries over `2026-09-14T10:55:00Z` through
`2026-09-14T11:20:00Z` find one span with trace ID
`6aa7d54000000000a0db0c6c5798739e`, span ID `3316148314706593714`, service
`ios-sdk-native-multi-scene-probe`, operation `urlsession.request`, HTTP 200,
client kind, and resource
`https://multi-scene-probe.invalid/trace-only/trace-only-20260914-1310-b/scene-A/home/trace-only-home-request`.
The base count is one, the A/H1 predicate count is one, the B/H1 predicate count
is zero, and the session predicate count is one. The RUM aggregate for that exact
URL has zero Resource buckets. Trace upload returned HTTP 202. A detail lookup
for the exact trace ID nevertheless returned `No trace found` while raw search
and aggregates continued to find the span; this is a backend-tool retrieval
discrepancy, not contradictory SDK telemetry.

Build-for-testing completes without diagnostics. The full generated probe plan
passes 115/115 in:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/Test-RUMNativeMultiSceneProbe-2026.09.14_12-56-59-+0200.xcresult`

Its build log is:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260914-125644.txt`

Repository lint passes 713 source and 699 test files with no violations, and
`git diff --check` passes. Signed commit `130ba7646` contains the 12 isolated
probe/project paths. This result closes request-time Trace owner freezing across
cross-scene representative churn. It does not close simultaneous-visible exact
source discovery, reverse completion between two requests, shared/coalesced
work, custom-handler compatibility, or handoff-overhead gates.

### 2026-09-14 — EXP-134: Trace-only reverse completion across scenes

The `traces.urlsession-reverse-completion` scenario extends the deterministic
Trace-only URLSession fixture from one held response to independent named A and
B requests. RUM URLSession tracking stays disabled. The driver starts A on
A/Home H1, opens B, starts B on B/Home H1, then establishes A as representative
before releasing B and establishes B as representative before releasing A. This
creates a B-before-A completion order that is the reverse of A-before-B starts
and makes completion-time representative selection wrong for both requests.

The scenario and four adversarial oracle fixtures add five tests, raising the
generated probe plan to 120/120. The oracle requires exactly one
`trace-only-reverse-scene-b` signal on B/Home H1 followed by exactly one
`trace-only-reverse-scene-a` signal on A/Home H1. It rejects swapped owners, a
missing B span, and a duplicate A span. The existing driver test now also proves
that named non-default requests travel through the exact-scene executor.

The clean run `trace-reverse-20260914-2330-a` passes 14/14. Its RUM session is
`a9d038c5-d8e4-4d82-aa09-449a6f0b82cd`; A/Home H1 is
`b0bff76c-1fd7-4c71-b863-618b39623270`, and B/Home H1 is
`6c67dece-3e44-4645-97af-59c953570720`. Local Trace mapper output records B's
request first at completion on B/H1, then A's request on A/H1. The Xcode launch
session expired only after the terminal PASS. There is no crash report,
crash-state result, fatal output, or failed assertion. The simulator's standard
accessibility-class warning is not classified as a crash.

The Trace uploader received HTTP 202 at `2026-09-14T22:29:52.798Z`. Exact raw
backend search over `2026-09-14T22:20:00Z` through
`2026-09-14T23:00:00Z` returns two `urlsession.request` client spans:

- request A: trace `6aa8755a000000004e49de117d84b47b`, span
  `3965348668343851039`, HTTP 200, A/Home H1;
- request B: trace `6aa8755b00000000ac30116fd24b1bbb`, span
  `8285421205566233636`, HTTP 200, B/Home H1.

The aggregate base count is two. The A-request/A-view and B-request/B-view
predicates each return one; A-request/B-view and B-request/A-view each return
zero. The expected session predicate returns two. Backend RUM intake contains
the same A and B view UUIDs in session `a9d038c5…`, while the exact
`/trace-only/trace-reverse-20260914-2330-a/` RUM Resource predicate returns zero.
The first exact APM query returned zero moments after upload even though RUM had
already indexed. A retry using the indexed `@http.url` and `@probe.run_id`
attributes returned both spans, followed by the exact aggregates. Preserve that
whole chain as ingestion latency, not as contradictory telemetry.

Build-for-testing completed without diagnostics. The full probe plan passes
120/120 in:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/Test-RUMNativeMultiSceneProbe-2026.09.14_23-27-28-+0100.xcresult`

Its build log is:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260914-232701.txt`

Repository lint passes 713 source and 699 test files with no violations, and
`git diff --check` passes. This closes independent two-request Trace-only
reverse completion. It does not close shared/coalesced ownership,
simultaneous-visible exact-source discovery, custom-handler compatibility, or
handoff-overhead gates. Local development commit `9d5be7be2`, tree
`efe7f2a754c0191ebfacd1952eb422a41fafa315`, contains the six isolated
scenario/driver/test paths in the historical unsigned object. Signed replacement
`353679bb5` preserves that exact tree; documentation checkpoint `0dca626df`
preserves the completed evidence. The unsigned objects are not branch history.

### 2026-09-15 — EXP-135: SwiftUI Button structured-task causal boundary

The `actions.swiftui-button-structured-task` scenario physically taps a real
SwiftUI Button in A. Its callback creates `Task { @MainActor in ... }`, waits on
a controlled continuation, and emits a manual Action and Resource after the
driver opens B, makes B representative, and releases the task from B. The strict
semantic contract expects the automatic tap exactly once on A/Home H1 and the
resumed work on the same A occurrence. Keeping that expected-A contract makes a
wrong fallback a visible failure instead of normalizing it in the oracle.

DEBUG diagnostics record `RUMUIEventNetworkContext.currentSceneIdentifier` and
`UITraitCollection.current[RUMSceneIdentifierTrait.self]` at the button callback,
task start, and task resume. The actual automatic action contract is SDK target
`SwiftUI_Button` and name `tap on SwiftUI_Button`; the visible button title is not
the automatic target name. The scenario timeout is 180 seconds because several
otherwise valid Xcode device-interaction sessions consumed the earlier 10- or
60-second budget before their first input.

Attempts are retained individually:

- `swiftui-button-task-20260915-0005-a`: the 10-second harness timeout elapsed
  before the device interaction delivered its tap. A later tap proved the button
  callback could be invoked, but B never opened. `INCONCLUSIVE`; no ownership
  claim.
- `swiftui-button-task-20260915-0007-b`: the fresh hierarchy/interaction session
  expired before input. `INCONCLUSIVE`; no tap or ownership claim.
- `swiftui-button-task-20260915-0010-c`: conclusive pre-diagnostic failure in RUM
  session `6c024fcd-7ffb-49d2-99d8-d7e6b349e426`. A/Home H1 was
  `84237009-d662-4110-b15d-a5cfe8e58574`; B/Home H1 was
  `7f34a167-b5ca-4d25-94df-be4c6787e292`. The automatic tap occurred once on A,
  but resumed Action `2e80dafa-c462-4b8e-8ea1-c2ea02cab865` and Resource
  `3a8d69e2-57eb-4615-9217-099ba872a3f6` used B. The original oracle incorrectly
  expected the visible button title as the SDK target, so no terminal verdict is
  claimed. Later Xcode stdout loss had no fatal/assertion/crash evidence.
- `swiftui-button-task-trait-20260915-0030-a`: the 60-second timeout elapsed
  before input. The late tap showed handoff nil and trait A at both callback and
  task start, but B never opened and the task never resumed. RUM session
  `93f5872e-1d68-41cc-8e53-adb4795fa905`, A view
  `c4cb5d5f-ad36-4002-bc3e-3ed9ab7eb6c4`; `INCONCLUSIVE` for suspension.
- `swiftui-button-task-trait-20260915-0040-a`: the second interaction session
  expired before its first hierarchy capture. Installed run session
  `eab11ef8-66f4-4c40-8583-6f8241da0361`; tooling-incomplete, no result claim.
- `swiftui-button-task-trait-20260915-0050-a`: accepted discriminator run after
  extending the timeout to 180 seconds. One hierarchy-derived tap at
  `(330.5, 479.2)` invoked A exactly once, B opened, and the task resumed after B
  became representative.

The accepted run's RUM session is
`a423021e-49d1-455e-ac11-bf018c517c82`. Native A is
`E89A20DF-DB91-4FCE-B645-0C6FF84C4470`; native B is
`837F47AC-EDD1-44CB-A2D6-2E0E9D5CBCD7`. A/Home H1 is
`308f0a66-34d7-4318-bf99-2775e4857166`; B/Home H1 is
`cb3d2a7b-fc53-468a-9cd2-a1d2bc28a9a1`. The handoff is nil at callback, task
start, and task resume. The UIKit scene trait is A at callback and task start,
then B after suspension. Automatic tap event
`5e03583e-fc23-4dd8-b5e5-21128c4ef726` occurs exactly once on A/H1. Resumed
Action `888ffe58-59ce-4e73-9773-39bdcadc4c51` and Resource
`3e8b5cf4-88e8-42c5-bca7-4249ec9c8b4a` retain source-scene A diagnostics but
both use B/H1. The terminal oracle is `FAIL` after four matched expectations:
expectation five requires A and observes B.

Exact backend query `@context.probe.run_id:swiftui-button-task-trait-20260915-0050-a`
returns 28 events: three views, 11 actions, ten Resources, two long tasks, one
vital, and one session. The session reports `view.count=3`, `action.count=11`,
`resource.count=10`, `error.count=0`, and `crash.count=0`. The exact automatic
tap predicate returns one A/H1 event. The resumed-phase predicate returns two
events; both contain source A/native-A diagnostics and B as the mapped RUM scene
with B/H1. The exact error predicate returns zero.

Xcode later labeled its device-interaction session `Crashed`, but the captured
logs contain only XPC/stdout disconnection—no crash report, signal, fatal output,
or failed assertion—and backend crash/error counts are zero. This is a tooling
disconnect, not an SDK-crash result. Primary interaction artifacts are:

- `/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/SwiftUI Trait Suspension Run-00_30_50_558-*`
- `/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/SwiftUI Trait Suspension Run-00_31_08_062-*`
- `/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/SwiftUI Trait Suspension Run-00_31_31_928-*`

This result proves the automatic SwiftUI tap path is correct, while an ordinary
SwiftUI Button's customer closure is outside the SDK's synchronous `sendEvent`
scope. A task created there cannot inherit an absent `TaskLocal`. UIKit's ambient
trait follows later execution context and is not durable provenance. The resumed
B attribution is therefore the approved source-less/last-interacted compatibility
behavior, not a new regression. Exact A attribution requires an explicit view
target or scoped public integration after API review; no trait fallback is added.

The full probe plan passes 126/126 in:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/Test-RUMNativeMultiSceneProbe-2026.09.15_00-36-04-+0100.xcresult`

Summary output is:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/8C30F235-7413-4A2F-B7D9-A5CA8A9F9604.txt`

Repository lint passes 713 source and 699 test files with zero violations, and
`git diff --check` passes. Signed commit `2972d3de1`, tree
`05f9db5089a769acbb1fe5df79645641cc83464e`, contains the ten isolated
scenario/driver/UI/test paths. This closes the SwiftUI Button/task discriminator
as a documented causal boundary.

### 2026-09-15 — EXP-136: shared Trace-only URLSession request

The `traces.urlsession-shared-request` scenario creates one real automatically
traced URLSession task while A/Home H1 is the trustworthy creator. After B/Home
H1 becomes representative, B explicitly joins the already-active request without
creating or resuming another task, then releases its controlled response. This
models two scene consumers while keeping the transport identity unambiguous. The
strict oracle requires exactly one `urlsession.request` span on A/Home H1 and
rejects a B-owned span, no span, a duplicate span, or any matching RUM Resource.

Six new focused tests raise the generated probe plan to 132/132. The scenario
catalog and driver tests prove one start on A, one join on B, and one release on
B. The controller accepts the join only while that exact request is active and
does not create a second URLSession task. Passing and adversarial oracle fixtures
cover the exact A owner, B retargeting, absence, and duplication.

Both runtime attempts established the clean precondition: host-side uninstall
returned zero and `simctl get_app_container` returned exit 2 with no application
container before Xcode rebuilt and launched the probe.

- `trace-shared-20260915-0115-a` created native A
  `0D43144C-FCDE-4B2B-BC95-FD91BE87E7C3`, A/Home
  `cd5e9a31-b630-4564-90bd-153888e26f94`, native B
  `66FB38D3-EE25-43D2-A5EE-40FBA1F6600C`, and B/Home
  `89242e19-43f7-43fb-8f30-0e399d1f4db4`. The request started, then simulator
  `backboardd` aborted at `2026-09-15 01:16:18 +0100` while rendering B, before
  the join step.
- Clean retry `trace-shared-20260915-0120-b` uses RUM session
  `370da769-c1f0-4707-9057-ab85b01a2017`. Native A is
  `C2F06CC3-07C5-43A0-AABB-0859FD72C8F0`, A/Home H1 is
  `c26fee76-b8bb-41e0-9930-6937a1bf4087`, native B is
  `A1FE3DCD-1AA6-44BA-84D0-8ED2B2FCFDB5`, and B/Home H1 is
  `109659d9-9eaf-4fd8-ba6d-ba207b9dcf61`. Request start passes at signal 37.
  B's join passes at signal 66 with the assertion that it joined the existing
  request without starting another task. Immediately afterward `backboardd`
  aborted in the same Metal texture-validation path at
  `2026-09-15 01:20:42 +0100`, before B released the response.

The expected request URL for the retry is
`https://multi-scene-probe.invalid/trace-only/trace-shared-20260915-0120-b/scene-A/home/trace-only-shared-request`.
Neither run emitted a request-completion assertion, Trace mapper signal, or
terminal oracle result. Neither produced a probe-app `.ips`, fatal/assertion
output, or local RUM error/crash signal. The system crash reports are:

- `/Users/valentin.pertuisot/Library/Logs/DiagnosticReports/backboardd-2026-09-15-011621.ips`
- `/Users/valentin.pertuisot/Library/Logs/DiagnosticReports/backboardd-2026-09-15-012045.ips`

Both show `EXC_CRASH`/`SIGABRT` through Metal texture validation and Core
Animation window rendering. Backend intake for the retry contains 16 partial
events: two views, five actions, five Resources, two long tasks, one vital, and
one session. The session has `error.count=0` and `crash.count=0`. No APM span
matches either run ID or shared-request URL, which is expected because response
release never occurred. The first run has no searchable exact-run event set.

The complete probe test result is:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/Test-RUMNativeMultiSceneProbe-2026.09.15_01-07-35-+0100.xcresult`

Its summary is:

`/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/RunAllTests/E01DAE5F-A559-4BCC-B88E-07C3137BF9A3.txt`

Repository lint passes 713 source and 699 test files with zero violations, and
`git diff --check` passes. Signed commit `e804d3bd6`, tree
`232715c3d7ff67f719508d9d37b2ba5161b27f15`, contains the eight isolated
harness/test paths.

This is simulator-inconclusive, not a RUM attribution failure or SDK crash. The
single-task B-join topology is proven, but exact creator ownership cannot be
accepted before a span exists. Stop simulator retries and run the unchanged
scenario on iPhone Duo or a physical multi-window iPad. Local work now moves to
the customer-shaped scene-aware API prototype.

### 2026-09-15 — EXP-137 through EXP-140: customer-shaped manual view APIs

Signed commit `01e5d1ffb` adds the first iOS 27 customer-shaped scene-targeted manual
view prototype. Swift callers import it through `@_spi(Experimental)` and pass a
real `UIWindowScene` to paired start/stop overloads. The bridge copies only the
scene session identifier on the main actor, routes the SDK monitor through the
existing per-scene manual-authority stack, and invokes a third-party conformer's
or `NOPMonitor`'s legacy implementation exactly once. The Objective-C selectors
exist only in Debug because Objective-C has no SPI import boundary. This is an
experimental review candidate, not approved public API.

The probe was migrated from test-only protocol casts to these customer call
sites. Four clean simulator/backend runs use the same exact native scene
`33F68994-4513-4100-B294-A1F5A5A2EE23`:

- `EXP-137`, run `api-keyed-manual-20260915-0200-a`, session
  `3d946de5-caee-4a4e-8949-2298f97dce85`, passes 16/16. It produces H1
  `c54e2e47-4aef-46bc-b926-68ff8f5d7002`, Compose
  `c36eb9b3-b8c8-4dd3-82c7-3fb9c69a0796`, and fresh H2
  `2dda52df-7800-4341-98f4-dd2a7415f811`. The pre-, active-, immediate-stop,
  and settled-stop action/Resource pairs use exactly H1, Compose, H2, and H2.
- `EXP-138`, accepted run
  `api-nested-manual-normalized-20260915-0215-a`, session
  `6b9ef22e-0cec-4e78-be76-3fbc42ceecf9`, passes 29/29. It produces H1
  `2bdc8076-adde-4d4c-a515-9192faa86a99`, Compose C1
  `a9e27247-bc8e-40e5-99a5-a5b8d76aac2e`, Preview
  `1a4546b0-ea6e-4055-b044-072a2070e443`, fresh Compose C2
  `105e61cb-1445-4d37-9955-a4f50cda1737`, and fresh H2
  `526e3651-4305-4c0a-8469-4f92a0cb3b61`. A duplicate active Compose start
  creates no C3 and does not retarget C2 work.
- `EXP-139`, run `api-scene-sheet-20260915-0225-a`, session
  `f497175c-a44d-4d0c-9436-28cf2f28751a`, passes 14/14. H1
  `8a5f8cc8-b852-4db9-a2d0-2b74588ebb51` is replaced by exactly one semantic
  Sheet `83705cb0-63ae-4ad1-ba4a-58a291991aba`, then fresh H2
  `4fb5c337-c95c-456e-9e5c-b77a6385d478` owns both immediate and settled
  dismissal work.
- `EXP-140`, run `api-scene-fullscreen-20260915-0235-a`, session
  `4edb6a3d-50fa-4d0b-ae5c-064b0720815d`, independently passes 14/14. H1
  `43326c6e-ca95-4e35-9f25-0d852c274aa3` is replaced by exactly one semantic
  Cover `1d7f7dd0-6367-459d-bea6-c807798bbf9e`, then fresh H2
  `238b6fa3-abc7-4dcd-ac25-95be3a9483cc` owns both dismissal phases.

All four sessions have zero RUM errors and zero crashes. Their exact event totals
are 28, 40, 29, and 28 respectively. Each backend view inventory matches the
mapper inventory and every semantic payload carries its current run ID.

The rejected first nested attempt,
`api-nested-manual-20260915-0210-a` / session
`a2980fff-af5d-40f0-b2ad-dd3941d75be5`, is a harness-isolation finding. It
passed 29/29 locally and the exact session had the right seven view occurrences,
but C1/P1/C2 carried run ID `api-keyed-manual-20260915-0200-a`. Host uninstall
and an absent application container did not remove the SwiftUI `WindowGroup`
value restored by the simulator window system. `ProbeWindowRoot` now normalizes
telemetry to `ProbeRuntime.runID` while retaining the original routed value only
for SwiftUI window identity and `dismissWindow`. A focused restoration test and
the accepted nested rerun prove the correction. Do not accept a run from its
terminal oracle alone; query every view in the exact session and reject any stale
run ID.

Validation for this slice is:

- focused scene-targeted bridge tests: 4/4;
- Objective-C selector smoke: 1/1;
- complete DatadogRUM suite: 1,171/1,171;
- complete native probe suite after the restoration regression: 133/133;
- repository lint: 713 source and 699 test files, zero violations;
- `git diff --check`: pass;
- Debug probe build and an authoritative Release probe build with Xcode 27.0
  (`27A266a`) and the iOS 27.0 simulator SDK: pass.

An earlier Release invocation through `/Applications/Xcode.app` used Xcode 26.6
(`17F113`). It completed while warning that iOS 27 was outside the supported
deployment-target range, so it is not acceptance evidence. The accepted build
used `/Applications/Xcode_27.app/Contents/Developer/usr/bin/xcodebuild`.

The API-surface verifier reports exactly the two Swift scene-targeted overloads
and their two Objective-C declarations as additions because it scans source and
does not hide SPI or Debug-only declarations. This is the expected prototype
mismatch; no checked-in API baseline was changed. Stable promotion still requires
normal API/RFC review and a clean approved API-surface result.

### 2026-09-15 — EXP-141: customer-shaped semantic navigation API

The first optional SwiftUI semantic-navigation prototype now uses the actual SDK
surface rather than the probe-only wrapper. The iOS 27
`@_spi(Experimental)` `RUMNavigationStack` owns a typed `NavigationStack`, the
root and destination builders, one application presentation binding, and the
sheet/full-screen-cover builders. Customer metadata stays centralized in root,
destination, and presentation resolvers. Automatic tracking remains enabled.

The internal navigation state gives committed path changes fresh occurrence
generations and synchronously reveals a retained route on pop. A presentation
does not start until its content mounts with a concrete `UIWindowScene`; it then
uses the existing scene-local manual-authority stack. Router authority stops and
reveals the latest committed underlying destination before the customer's
`onPresentationDismiss` callback, while a separate UI-attached suppression state
remains active until the native presentation subtree disappears. A presentation
that never mounts publishes no RUM view or dismissal. Repeated mount signals are
idempotent, and a mounted presentation that moves scenes stops in its old scene
before starting in the new one.

The clean iPadOS 27.0 simulator run is:

- scenario `swiftui.semantic-api.complete-destination`;
- run `semantic-api-20260915-1021-a`;
- RUM session `ff21d9ab-f59f-49cf-91c1-f1326a0a39ea`;
- native scene `33F68994-4513-4100-B294-A1F5A5A2EE23`;
- local semantic oracle `PASS`, 38/38 expectations;
- three RUM upload batches accepted with HTTP 202; and
- no SDK warning/error/failure signature, app crash, or visible layout defect.

The mapper occurrence chain is exact and every occurrence has a distinct view
ID:

1. Home H1 `986596da-f66d-47b4-b373-938cbaac7782`;
2. Detail D1 `562e9078-f37c-4d03-843d-c3917233d610`;
3. Home H2 `deeaad7d-3d09-4e05-b5d7-b1fe7288e6c7`;
4. Sheet S1 `fa32f665-3df2-405c-ba97-bca35780c8d4`;
5. Home H3 `bf9c8d03-09c3-40e7-8d3d-6291e11f85ad`;
6. full-screen Cover C1 `d398be8f-b6ac-4f08-b9db-45f48008ae83`; and
7. Home H4 `e1f36d2e-4c69-435d-a96a-5a6189973fb8`.

Every superseded occurrence is inactive and H4 remains active at the end. No
automatic view start occurs within the semantic container. The backend exact
session inventory independently contains eight one-document views: the seven
semantic IDs above plus ApplicationLaunch
`fc47765d-4274-4dad-936d-7fb82ed63e90`. It contains no automatic duplicate.
The full session has 63 events: 25 actions, 25 Resources, eight views, three long
tasks, one session, and one vital. There are zero error events and no crashed
session.

Backend action and Resource counts agree for every semantic occurrence: H1 and
D1 own five of each, H2 owns one of each, Sheet and Cover own three of each, and
H3 and H4 own four of each. In particular, post-dismiss immediate and settled
work belongs to fresh H3/H4. A delayed task emitted by the outgoing Sheet also
lands on H3 after dismissal, and the corresponding Cover task lands on H4. This
confirms the SDK's current destination at the time the work occurs rather than
retaining the presentation owner.

The clean-run precondition was proven on simulator
`B4E4F039-CA5D-4D04-A904-1D71099BE651`: termination reported no running app,
uninstall succeeded, and the subsequent application-container lookup reported
the container absent before install and launch. Runtime artifacts are:

- logs:
  `/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/Semantic Navigation API-10_23_42_136-logs.txt`;
- hierarchy:
  `/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/Semantic Navigation API-10_23_42_136-hierarchy.txt`; and
- screenshot:
  `/var/folders/54/lrjgxzh90n174wzdwxhnlnnh0000gp/T/ActionArtifacts/default/DeviceInteractionSynthesize/Semantic Navigation API-10_23_42_136-screenshot.png`.

Validation at this checkpoint is:

- six focused semantic-navigation state/handler tests pass;
- complete DatadogRUM test run passes 1,177/1,177 with zero failures or skips;
- complete native probe suite passes 134/134;
- Debug probe build passes through Xcode MCP; and
- the authoritative Xcode 27.0 (`27A266a`) Release simulator build succeeds;
- repository lint passes with zero violations; and
- the API-surface verifier reports only the expected experimental semantic
  navigation declarations plus the previously recorded manual-view additions.
  No checked-in API baseline changed.

Rejected implementation/tooling attempts remain part of the result:

- A focused command used the stale scheme name `DatadogRUM iOS` and exited 65
  before testing. The workspace scheme is `DatadogRUM`.
- The first test import used only `@testable import DatadogRUM`, which could not
  access SPI enum cases. Tests importing internal and SPI declarations need
  separate `@_spi(Experimental)` and `@testable` attributes on the import.
- The first occurrence assertions compared the stable fallback identity instead
  of the generated occurrence identity. Occurrence transitions, not the state's
  fallback identity property, prove H1/H2 uniqueness.
- One stop assertion tried to read `instrumentationType` from
  `RUMStopViewCommand`, where that field does not exist. Pair the start/stop
  identity and assert the start command's instrumentation type.
- A coverage-enabled focused run completed its tests but hung while finalizing
  the Xcode result. The accepted CLI runs add `-enableCodeCoverage NO`; the Xcode
  MCP probe run did not exhibit this problem.

This closes the first customer-shaped complete-destination usefulness loop. It
does not yet close repeated equal routes, external router mutation ordering,
state restoration, presentation replacement, semantic-A/automatic-B isolation,
or stable API review. Reusing `RUMView` is intentionally provisional because its
`isUntrackedModal` field is unrelated to semantic destinations. The next local
slice should test programmatic router mutations and presentation replacement,
then run the same API in scene A while automatic tracking remains active in an
independent scene B on capable hardware.

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
- Do not treat a relative-time backend Trace query as absence after the wall clock
  or tool session has advanced. `EXP-133` initially returned zero outside its
  moving window; the exact historical UTC interval found the accepted span and
  its A/B/session predicates.
- Do not treat an exact APM query issued immediately after an accepted upload as
  final absence. In `EXP-134`, RUM events were already searchable while the first
  APM query still returned zero. Retry the same bounded interval through an
  independently indexed attribute such as `@http.url`, then confirm with exact
  count and owner predicates before classifying the run.
- Do not classify an expired Xcode/device interaction session as an app or SDK
  crash without a crash report, fatal/assertion output, or crash UI. Preserve it
  as tooling-incomplete and rerun from a clean install, as in `EXP-133`.
- Do not infer durable asynchronous scene ownership from
  `UITraitCollection.current`. `EXP-135` observes A at SwiftUI callback/task start
  and B after suspension. It is ambient UIKit execution context, not a task-local
  origin token.
- Do not assume a SwiftUI Button closure runs inside the synchronous
  `UIApplication.sendEvent` handoff merely because the tap triggered it.
  `EXP-135` records nil handoff at callback, task start, and task resume. Only a
  task actually created while that dynamic scope is active can inherit it.
- Do not change the strict expected-A `EXP-135` oracle to accept B. B is the
  approved fallback for source-less compatibility, but the scenario deliberately
  records that exact asynchronous origin is unsupported without an explicit
  target or scope. Also use SDK target `SwiftUI_Button`, not the visible button
  title, when counting the automatic tap.
- Do not rely on an exact `git add` path list to isolate a checkpoint while the
  local xcconfig is pre-staged. Ordinary `git commit` includes every staged path.
  Use `git commit --only -- <exact paths>` or an isolated index, then verify both
  the commit tree and the xcconfig's original `AM` state.
- Do not consider callback counts, compilation, or crash safety proof of correct
  semantic attribution.
- Do not present local Operation invocation assertions as Operation telemetry.
  Operation-step vitals bypass the public RUM event mappers; require raw and
  reduced backend documents before claiming view attribution or duplicate
  reduction behavior.
- Do not use `TabView` as the sibling-container authority discriminator. Its
  selection/preload behavior cannot prove two simultaneously mounted independent
  navigation branches under the project's one-current-destination model.
- Do not accept a sibling-container run from source layout alone. Require the
  controller-ancestry assertion; missing or collapsed topology is
  `INCONCLUSIVE`.
- Do not make an exact `rum-view:<screen>#<occurrence>` driver wait depend only on
  events recorded after the wait step. The mapper may emit the immutable target
  snapshot while the command is being acknowledged. Check already-recorded exact
  evidence first, then subscribe for a later match.
- Do not let a probe-only hierarchy or measurement reader participate in automatic
  RUM view discovery. Exclude only its exact known type, then retain an adversarial
  check that unrelated customer controllers remain eligible.
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
- Do not repeatedly launch `swiftui.coexistence.semantic-a-automatic-b` on the
  current simulator after `EXP-118`. Two clean attempts created the intended B
  automatic hosts, then crashed `backboardd` before the final assertion. Preserve
  the prepared scenario and finish it on physical multi-window hardware.
- Do not repeat `swiftui.coexistence.same-key-manual-two-scenes` on the current
  simulator after `EXP-129`. Its clean run reached distinct A/B native scenes,
  then lost the Xcode/device session amid window-service interruptions before
  manual authority began. The 91/91 hostless contract is useful but cannot
  replace a terminal physical-hardware run and exact backend owners.
- Do not retry `traces.urlsession-shared-request` on the current simulator after
  `EXP-136`. Two explicitly uninstalled runs crashed `backboardd` in the same
  Metal texture-validation path before response release. The second run first
  proved B joined the existing request. Preserve that prefix and run the exact
  132/132 hostless contract on capable physical hardware.
- Do not add a driver wait for the short Compose occurrence in `EXP-120`. The
  existing direct API can start and stop M1 before the driver observes its next
  condition; the step-bounded authority interval, recorder facts, and semantic
  oracle are the acceptance mechanism.
- Do not report the raw final `EXP-120` H1-stop mismatch as an SDK lifecycle
  failure. The mapper delivered the exact deferred H1 stop after M1's unrelated
  stop. The matcher was fixed to scan onward; the SDK failure is the automatic
  fallback that preempts M1 and owns Compose work.
- Do not implement scene-aware manual views by adding only a scene target to the
  existing direct keyed commands. `EXP-120` proves those commands bypass the
  handler stack and provide no authority over later automatic appearances.
- Do not treat any automatic candidate staged under a targeted manual occurrence
  as a destination worth revealing. `EXP-121` proves that generic hosting
  fallbacks are structural churn. Retain the last semantic destination, reject
  known generic fallbacks during manual authority, and still allow a newly
  trustworthy semantic destination to replace the retained candidate.
- Do not treat exact-scene handler authority alone as presentation deduplication.
  `EXP-123` proves that the automatic presentation hosting controller still needs
  a UI-attached, target-scoped suppression boundary; disabling automatic tracking
  for the entire scene or application is not the required coexistence model.
- Do not use an outgoing RUM view aggregate's final mapper snapshot as the end of
  semantic presentation authority. `EXP-124` proves pending Resources can keep
  that aggregate alive after dismissal while fresh H2 must already own customer
  work. Track router authority and native subtree lifetime as separate intervals.
- Do not end presentation-subtree suppression at the router's semantic stop.
  UIKit can retain the hosting controller through dismissal. Keep the UI-attached
  boundary active until the subtree actually disappears and reject a delayed
  automatic view for that presentation by semantic name (`EXP-125`).
- Do not infer a result after an Xcode device-interaction key expires. The first
  `EXP-126` launch had no captured terminal JSONL or hierarchy; start a newly
  identified, explicitly uninstalled run and classify only that evidence.
- Do not open a short-lived Xcode interaction session before exporting and reading
  its packaged device-interaction skill and preparing the exact measured command.
  A `Session not found` before input is an invalid tooling attempt, not an SDK
  result. The interaction command `help` is unsupported; use the documented
  hierarchy, screenshot, tap, and drag grammar directly.
- Do not accept `willDecelerate == true` alone as proof of the late UIKit swipe
  classification path. `EXP-132`'s first completed run omitted the lift-speed
  witness. Require the measured magnitude to meet the SDK's 500 pt/s threshold
  before interpreting an exact `.scroll` at navigation as the ordering result.
- Do not use `pgrep` as a process-health discriminator on this simulator image;
  the command is absent. Use a supported process listing or the captured system
  diagnostic before classifying the app as terminated.
- Do not query this probe with `@probe.run_id`; use
  `@context.probe.run_id` or fall back to `service:ios-sdk-multi-scene-probe`
  followed by an exact session-ID query.
- Do not treat `--probe-run-mode clean` as an uninstall or chain acceptance runs
  through Xcode install/run without host teardown. `EXP-117` produced locally
  correct views whose persisted global probe attribute still named the preceding
  run. Explicitly uninstall first, then verify every backend semantic view has
  the requested `@context.probe.run_id`.
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
- Do not place one semantic tracker as a background sibling, on the whole-stack
  result, or on a stable first child and call it a scene-root solution.
  `EXP-047` through `EXP-049` show that all three remain too late for B's initial
  Home lifecycle; the single whole-stack tracker also replays retained screen
  lifecycle. `EXP-116` is different: its container wrapper owns the root and
  destination builders and injects a separate route-owned boundary at each
  materialized occurrence.
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
  `ProbeWindow.runID`, and the rejected first `EXP-138` run proves that even a
  successful uninstall plus absent application container may leave that value in
  the simulator window system. Establish the clean host precondition, normalize
  restored telemetry to the current launch without changing the routed window
  identity, and verify every exact-session view carries the current run ID.
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
