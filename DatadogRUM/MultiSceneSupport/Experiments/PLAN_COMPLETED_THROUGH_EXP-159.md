# Completed planning notes through EXP-159

Moved from PLAN.md on 2026-09-17. This preserves historical planning and evidence
without making completed narratives part of the active release checklist.
Current status and remaining deliverables are owned by PLAN.md; detailed attempt
records remain in EXP-143-199.md. This is not the frozen pre-EXP-143 archive.

## Latest completed engine slice

### EXP-146: container-independent semantic engine and adapter boundary

| Field | Contract |
| --- | --- |
| Expected outcome | The proven occurrence, transition, reveal, authority, source-lifetime, and disconnect-fencing state no longer fundamentally depends on `RUMNavigationStack`. An adapter boundary can wrap arbitrary content while leaving its visual navigation implementation unchanged. |
| Prerequisite evidence | `EXP-141`-`145` prove the current native convenience container, including sibling isolation. The revised API constraints require equivalent paths for native, custom, third-party-style, UIKit-coordinator, and automatic navigation. |
| Implementation boundary | First extract a scene-scoped, container-independent semantic engine without behavior change. Then add an iOS 27 experimental host whose content builder accepts any `View`. Keep `RUMNavigationStack` as a native convenience adapter over that engine, not the engine itself. Do not add Datadog replacements for standard presentation modifiers. |
| Current result | ENGINE/ADAPTER PASS. Commits `a84061840`, `354422d88`, `651b173c6`, and `47bc08eca` establish the shared engine, deterministic transition adapter, optional-capability and opaque modes, runtime precedence, and source pinning. Explicit and capability baselines pass 42/42; precedence/reconstruction/replacement pass 43/43; opaque fallback passes 5/5. A real-reader synchronous detach/reattach run passes 17/17 with one Detail ID retained and a later fresh Home. Focused tests fence stale callbacks after scene disconnect and release only the exact host. The conditional final-host-removal runtime is simulator-inconclusive after two identical `backboardd` Metal crashes before removal. |
| Acceptance | Engine occurrence and attribution semantics are accepted. The low-level probe manually publishes transitions and therefore does **not** validate normal customer migration cost. Real representable remount timing, final host removal in a two-window topology, and genuine OS disconnect/reconnect remain device gates. |
| Environment | Focused deterministic tests and iPadOS 27 simulator. Cross-scene isolation remains a physical-device acceptance row. |

The explicit-source, optional-capability, runtime-precedence, reconstruction,
adversarial-replacement, opaque-fallback, and deterministic lifetime sub-slices
are accepted at the engine/adapter boundary.

### EXP-147: customer migration-cost discriminator

The realistic fixture now closes the customer-facing discriminator for an
application that already owns observable routers. It contains 25 routes, seven
presentations, three independent router containers, one native/local-state arm,
and one opaque third-party-style arm. Instrumentation changes zero screen files
and zero of twelve navigation methods. Adding one route and one presentation
changes no adapter, boundary-composition, runtime-driver, scenario, or app-entry
RUM code. Standard `NavigationStack`, `.sheet`, and `.fullScreenCover` call sites
remain unchanged, and automatic fallback remains available for opaque input.

The dedicated existing-router adapter and its fixture-local automatic metadata
policy are historical candidate evidence, not an accepted public declaration.
EXP-148 has now moved generic observation, occurrence identity, automatic
metadata, sparse overrides, and pending-authority policy into DatadogRUM while
preserving the same migration budget. Native and opaque arms do not claim exact
semantic reconstruction when no trustworthy signal exists.

### EXP-148: SDK-owned observable-router candidate

The iOS 27 prototype observes one existing accepted-state stream at a container
boundary. It keeps automatic tracking active until the first trustworthy state,
then establishes scene-local semantic authority without falling through to a
lower-precedence capability. An in-memory occurrence token permits fresh equal-
route occurrences, and background emissions preserve FIFO submission order.

The corrected path passes 9/9 focused tests, 153/153 probe tests, and a generic
Release build. Final frozen-source run
`exp148-sdk-observed-postlint-20260916T063742Z` passes 38/38 locally and in backend
session `c951c32e-12a7-4bc4-bc5e-bdaf2f16f8aa`: eight exact views, 22 exact
action/Resource owner buckets, no automatic duplicate, and zero errors/crashes.
This accepts an experimental existing-router candidate, not stable API names or
exact inference from opaque navigation.

### EXP-149: observed-source lifetime and scene isolation

The deterministic simulator-capable lifetime matrix now passes 20/20. A real
`UIHostingController` reconstruction renders both publisher selections while the
host's `@StateObject` subscribes exactly once to the original accepted-state
stream and never subscribes to the replacement. Two SDK-owned observed adapters
remain isolated across scene A and scene B; disconnecting A releases only A,
rejects later A transitions, and lets B advance. Semantic suppression stays
within its registered subtrees, leaving an unrelated automatic container
eligible. Posted disconnect is internal fencing evidence only; genuine OS
disconnect/reconnect remains hardware-gated.

### EXP-150: render-time current-destination candidate

The first native/local-state parity candidate is rejected. Supplying an already
accepted destination value during `RUMNavigationHost` reconstruction preserves
standard SwiftUI and passes state-level transition tests, but it observes a
dismissal only when SwiftUI next evaluates the host. Frozen iPadOS 27 run
`exp150-current-destination-20260916T072321Z` fails at 17/38: immediate sheet
work is attributed to Compose, immediate full-screen-cover work is attributed to
Attachment, and each fresh Home occurrence starts one signal later. Backend
session `2294a609-76f9-47be-a643-ab51edc5b638` confirms both action/Resource
ownership failures; settled work is correct and the app remains crash-free.

This is conclusive evidence against the value-only exact API, not a simulator
limitation. The next candidate must observe a trustworthy accepted mutation
before control returns to customer code. Xcode 27's one-shot Observation
`.didSet` API is eligible for an existing `@Observable` router experiment;
continuous observation is too late, and plain local `@State` remains automatic
tracking plus sparse manual exceptions unless a separate binding/materialization
adapter proves the required timing without replacing standard navigation APIs.

### EXP-151: one-shot Observation router candidate

The iOS 27 `@Observable` router input is accepted as a trustworthy experimental
adapter boundary. One-shot `.didSet` tracking reads the stored destination,
reconciles it, and rearms before the customer's setter returns. The projection
must read one atomically updated accepted-state property; separate observed
properties represent separate committed states and may expose an intermediate.
Focused Observation/adapter tests pass 8/8, including nested reentrancy,
SwiftUI reconstruction, teardown, and invalid background-mutation crash safety.
The affected SwiftUI file passes 193/193, the native probe passes 154/154, the
explicit Xcode 27 Release build succeeds, and the visionOS package build proves
the platform availability gate. Post-review frozen run
`exp151-observation-router-postreview-20260916T083131Z` passes 38/38; backend
session `ea9adc0e-5a00-4290-9580-fb4df6bc18e7` confirms eight distinct views,
11 actions, 11 Resources, exact immediate and settled sheet/cover dismissal
ownership, and no error bucket or crash.

This accepts the input primitive, not a stable API spelling. Remaining parity
work is two-scene router isolation, custom/third-party adapters, and honest
fallback behavior. Back-to-back/nested mutation, reconstruction, and
background-misuse unit gates are closed. Plain local `@State` remains outside
this exact claim.

### EXP-152: actual native dismissal callback boundary

Native `.sheet` and `.fullScreenCover` callback characterization is accepted.
The separate harness arm waits for each standard SwiftUI presentation's content
to appear before dismissing it, then records the actual `onDismiss` entry rather
than reusing EXP-151's synthetic post-mutation marker. Clean frozen run
`exp152-native-dismiss-callbacks-20260916T094300Z` passes 38/38: both callbacks
observe `presentation=nil` and Home after the accepted router mutation, emit
exactly once, create no extra Home, and place immediate plus settled work on
fresh H3/H4. Backend session `fee27d61-1eb7-4eb6-8525-7af74a53ed7e` agrees with
eight views, 11 actions, 11 Resources, and zero errors/crashes.

This closes programmatic native callback timing without an SDK change. It does
not replace the stronger accepted-state mutation boundary, because direct
presentation replacement can omit outgoing `onDismiss`. Interactive dismissal
and cancellation remain a physical/human row.

### EXP-153: callback-driven third-party adapter

Callback-driven custom/third-party parity is accepted. A library-owned custom
visual container exposes its current accepted snapshot and synchronous committed
changes to one dedicated adapter around the container. That adapter reuses the
SDK-owned publisher host; it does not change screens or navigation methods,
retroactively conform the imported library, or require another SDK input
primitive.

Focused tests pass 7/7, the complete probe passes 161/161, repository lint and
the Xcode 27 Release build pass, and signed checkpoint `d6d813736` freezes the
harness. Clean run `exp153-third-party-callback-20260916T103122Z` passes 42/42
plus `registrations=1 active=1`. Backend session
`f2d2fb24-02d6-4bd9-9df9-ee353b899e69` contains eight views, 13 actions, 13
Resources, exact initial and returned-destination ownership, and zero
errors/crashes. This accepts the adapter-author shape, not opaque-state
inference or a stable public spelling.

### EXP-154: two native Observation scenes

Serial two-native-scene parity is accepted, without making a simultaneous-window
claim. Scenario
`swiftui.semantic-host.observation-router-two-scenes-serial` reuses the existing
per-window Observation router and requires only `.multipleScenes`. Scene A
completes Home H1 → Detail D1 → fresh Home H2 before scene B opens and completes
the same chain. The strict oracle requires six distinct semantic view IDs, six
exact action/Resource pairs, no automatic-origin destination, and an independent
backend owner inventory.

Attempt 1 is retained as `HARNESS FAIL`: `open-window` already consumed B's
readiness signal, so a redundant following readiness step timed out even though
the app and partial attribution remained healthy. Signed correction `f92d72909`
removes that duplicate wait. Corrected frozen run
`exp154-observation-two-scenes-serial-fix-20260916T111921Z` passes 25/25; backend
session `a6a5afd5-8089-4996-9805-ed62fb76927d` contains seven views, six actions,
six Resources, and zero errors/crashes. A and B independently own distinct
H1/D1/H2 occurrences and all six matching marker pairs. Focused tests pass 2/2,
the complete probe passes 162/162, repository lint and the Xcode 27 Release build
pass. Simultaneous visibility, focus/background handoff, interleaved use, peer
continuity, close/disconnect, and final host removal remain unchanged hardware
rows.

### EXP-155: explicit cross-scene Operation target

The bounded iOS 27 `.current(in:)` Operation target is implemented and accepted
as an SPI proof. Signed checkpoints `b0524bb5b`, `3e567a494`, and `eb1dd2fdc`
cover the SDK, scenario, and corrected explicit Home boundaries. Focused tests
pass 3/3, the complete probe passes 163/163, and repository lint is clean.

Corrected run
`exp155-operation-explicit-target-serial-manual-boundaries-20260916T124918Z`
passes 24/24. Backend session `bcb168fd-b5df-42ed-b416-b505a42e6e76`
contains exactly eight raw Operation steps and four reduced Operations: A→B
success, A→B failure, A→A alpha, and B→B beta, with beta completion before
alpha. Three invalid predecessors document wrong restored scene state, an
accessibility-capture timeout, and the stale occurrence-source harness that the
accepted correction removed. Stable API names, availability, Objective-C shape,
and later manual-key/controller targets remain review work. Inferred concurrent
call-site context is the separate `EXP-131` contract accepted physically in
`EXP-157`; simultaneous visibility remains only a topology qualifier.

### EXP-158: explicit scene-targeted one-shot action

The Operation-only experimental target is now the reusable `RUMViewTarget`, with
the earlier Swift spelling retained as an SPI alias. An iOS 27 `@MainActor`
one-shot `addAction(..., view:)` prototype preserves explicit and inferred
candidates independently, resolves a live explicit scene first, and falls back
to the existing inferred representative if the explicit scene cannot resolve.
Custom protocol implementations and the NOP monitor call the legacy method once.

Scenario `actions.explicit-target.cross-scene-serial` deliberately makes B the
process representative around source-A work. Run
`exp158-sim-66f922ee-19a3-4941-b8ca-c518216e6b0d` passes 9/9: explicit A owns
A, explicit B owns B, and the legacy source-A action plus Resource remain on B.
Backend session `f67c75b2-e839-4701-a283-7e4355682b6a` confirms all four
discriminators across 30 events. The complete probe passes 164/164, Objective-C
smoke passes 8/8, the Release simulator build succeeds, and the complete
DatadogRUM suite passes 1,255 test cases with zero failures. This accepts
one-shot action targeting and compatibility behavior, not stable API names,
long-running actions, or other signal families.

### EXP-159: explicit scene-targeted long-running actions

Accepted for the bounded synchronous live-view API batch. Signed SDK
`24212cb48`, harness `cdd2239df`, and correction `4611d5f0b` preserve independent
explicit/inferred candidates and existing lifetime rules. Equal-name A/B actions
complete B before A with exact final names, stop attributes, and owner UUIDs;
an empty B stop leaves A intact, and legacy source-A work remains on B.

The corrected runtime passes 15/15 plus independent backend ownership. Full RUM
passes 1,260/1,260, probe 166/166, Objective-C 8/8, Release and lint. The first
background-interrupted attempt remains INCONCLUSIVE; this result does not close
sustained simultaneous-window hardware gates. See the
[full record](Experiments/EXP-143-199.md#exp-159--explicit-scene-targeted-long-running-actions).

## Simulator-capable work

| Work | Expected outcome and prerequisite | Boundary | Acceptance |
| --- | --- | --- | --- |
| Container-independent semantic engine and explicit source | Accepted `EXP-146` sub-slice | Shared engine plus arbitrary-content outer host; no navigation or presentation replacement | Accepted 42/42 local/backend run with distinct occurrences, exact lifecycle ownership, standard SwiftUI call sites, and target-local suppression |
| Arbitrary-view host baseline | Accepted `EXP-146` discriminator | The same customer-owned custom container without semantic capability | Automatic tracking remains active, no semantic view is invented, exact Detail work uses the automatic owner, and no crash occurs |
| Optional capability | Accepted `EXP-146` discriminator | Stable type-erased source detected from the supplied container; no associated route type or per-screen changes | Exact H1/D1/H2 plus presentations match the explicit 42-event oracle; explicit precedence, repeated reconstruction, and adversarial source replacement also pass; platform remount/disconnect acceptance remains device-gated |
| Migration-diff sample (`EXP-147`) | Accepted: 25 routes, seven presentations, three router containers, native and opaque fallback arms | Realistic scaled multi-flow fixture plus preserved route and presentation growth changes | Zero screen and navigation-method edits; unchanged sheets/covers; route and presentation additions add zero RUM code; baseline correctness uses automatic metadata; optional naming cost scales only with sparse overrides |
| SDK-owned router-stream adapter (`EXP-148`) | Accepted experimental candidate | Internal iOS 27 prototype over an existing accepted state stream; no customer-owned low-level transition publisher | 9/9 focused tests, 153/153 probe tests, Release build, and final 38/38 local/backend run with exact eight-view and 22-bucket ownership |
| Observed-source lifetime and scene matrix (`EXP-149`) | Accepted deterministic slice; genuine OS lifecycle remains hardware-gated | Actual host reconstruction, delayed first value, source replacement, two scene-local sources, posted disconnect, and unrelated automatic sibling | 20/20: one stable subscription/source, no replay or stale transition, local suppression only, and automatic remains active until trustworthy semantic authority exists |
| Value-only current destination (`EXP-150`) | Rejected exact candidate | Direct accepted destination read only during SwiftUI reconstruction | Runtime FAIL at 17/38 plus backend confirmation: both immediate dismissal pairs retain the outgoing presentation; settled work is not sufficient acceptance evidence |
| One-shot Observation router (`EXP-151`) | Accepted experimental input for an existing `@Observable` router/coordinator on iOS 27 | One-shot `.didSet` tracking with explicit rearming over one atomic accepted-state property; no continuous-observation substitution; no claim for plain local `@State` | 8/8 focused tests, 193/193 affected SwiftUI tests, 154/154 probe tests, Xcode 27 iOS Release plus visionOS package builds, and post-review 38/38 mapper/backend presentation oracle. EXP-154 later closes serial two-native-scene runtime parity |
| Actual native dismissal callbacks (`EXP-152`) | Accepted characterization over the EXP-151 input | Separate harness-only standard Sheet/Cover arm with a content-appearance barrier and actual SwiftUI `onDismiss`; no SDK policy moves into callbacks | Signed checkpoint `0a67f3e36`, full probe 155/155, lint and Release PASS, clean frozen 38/38 mapper/backend run. Each callback fires once after accepted Home, creates no extra Home, and owns fresh H3/H4; interactive gesture dismissal remains device/human work |
| Callback-driven custom adapter (`EXP-153`) | Accepted adapter-author path over a reliable third-party accepted-state callback | True custom visual container plus one dedicated callback-to-publisher boundary; no retroactive conformance, screen edits, navigation-method RUM calls, or new SDK primitive | Signed checkpoint `d6d813736`, 7/7 focused, 161/161 probe, lint and Release PASS, clean 42/42 mapper/backend run, `registrations=1 active=1`, eight views, 13 actions, 13 Resources, and zero errors/crashes |
| Two native Observation scenes (`EXP-154`) | Accepted serial simulator discriminator; simultaneous topology remains hardware-only | Existing per-window Observation router and exact scene-context markers; require `.multipleScenes`, not `.simultaneousVisibleWindows` | Signed correction `f92d72909`; 2/2 focused, 162/162 probe, lint and Release PASS; corrected frozen run 25/25; backend session `a6a5afd5-8089-4996-9805-ed62fb76927d` has distinct A/B H1/D1/H2 IDs, six exact marker pairs, and no error/crash |
| Operation target API (`EXP-155`) | Accepted experimental `.current(in:)` engine proof; stable review pending | Opaque scene identifier, separate explicit/inferred candidates, extension fallback for custom/NOP handlers, Debug-only Objective-C companion | 7/7 focused API/session tests, 33/33 broadened Operation tests, Objective-C smoke 1/1, 163/163 probe, 24/24 runtime, eight raw steps and four reduced Operations with exact A/B owners |
| One-shot action target (`EXP-158`) | Accepted experimental shared-target proof; stable review pending | Generalized `RUMViewTarget`, separate explicit/inferred candidates, exactly-once custom/NOP fallback, Debug-only Objective-C companion | Focused regressions, Objective-C smoke 8/8, 164/164 probe, 9/9 runtime, and exact backend A/B explicit owners plus unchanged B representative fallback |
| Long-running action targets (`EXP-159`) | Accepted bounded live-view API discriminator; stable review pending | Explicit start/stop, empty-slot isolation, unchanged timeout/navigation/custom/NOP behavior | 1,260/1,260 RUM, 166/166 probe, Objective-C 8/8, 15/15 runtime, exact backend completion ownership; sustained simultaneous use remains hardware-gated |
| Remaining targeted downstream signals | Shared target and one-shot/long-running actions accepted; split this row on resume | Resources, errors, view mutations, Traces, logs, WebView, and exported/fatal context; define a finite completion contract for each | Exact requested owner, unavailable-explicit fallback, custom/NOP compatibility, and unchanged legacy behavior |
| Single-scene/custom-handler compatibility | Before further expansion; baseline pending | Existing integration paths | Full suites, representative behavior, no duplicate views/actions |
| Performance/reentrancy | Before further expansion; baseline and thresholds pending | `UIApplication.sendEvent` handoff and locks | Measured bounded overhead, no recursion/deadlock, normal apps unaffected |
| Missing deterministic harness controls | Before WebView, mirrored log, and fatal/exported context rows | Probe only | Named scenario, fail-closed prerequisites, mapper/backend oracle |


## Superseded overview restart notes

The following former restart section is retained as historical context. Its
then-current next-work statements and counts are superseded by PLAN, the
EXP-160/161 records and the current handoff. Do not use it as a restart position.

## Resume here

### Checkpoint

The branch is `valpertui/multiple-windows-scenes`. The latest signed checkpoint
is documentation commit `2f38d30bb` (`Document semantic host precedence and
lifetime evidence`), following implementation commit `47bc08eca` (`Exercise
semantic host precedence and source lifetime`). They close runtime explicit-over-
capability precedence, repeated stable-source reconstruction, and adversarial
capability replacement for `EXP-146`. The underlying host/engine checkpoints are `a84061840`,
`354422d88`, and `651b173c6`; the preceding native-convenience checkpoint is
`144d6e0e7`. The signed documentation baseline before this checkpoint is
`616924b72`; frozen history is commit `e51a83b15` and
the compact experiment workflow is commit `da993758b`. The scene-targeted
manual-view prototype is signed commit `01e5d1ffb`, followed by signed
documentation commit `3b26da106`; it adds the Swift SPI, Debug-only Objective-C
selectors, compatibility fallback, customer-call-site probe migration, and
restored-window normalization validated by `EXP-137` through `EXP-140`.
The preceding production SDK checkpoint is `f452e9e3f` (`Preserve semantic
presentation authority through dismissal`), following the exact-scene manual
stack in `29c8cec2c` and `b1a0fb6b8`. The earlier shared-request documentation checkpoint
is `d2a5b9491` (`Document shared request validation boundary`), following signed
probe commit `e804d3bd6` (`Exercise shared URLSession ownership across scenes`),
SwiftUI-task documentation checkpoint `75becb324`, and probe checkpoint
`2972d3de1`. Earlier probe checkpoints are signed documentation commit
`0dca626df` (`Document trace-only reverse completion evidence`), signed probe
commit `353679bb5` (`Exercise trace-only reverse completion across scenes`), `130ba7646`
(`Exercise trace-only URLSession attribution across scenes`), `3c9730805`
(`Exercise UIKit scroll attribution across navigation`), `a653e29f2` (`Prepare
cross-scene operation attribution probe`), `5d536e0bd` (`Exercise operation
attribution across navigation`), `9fa58e3c0` (`Exercise same-key manual views
across scenes`), and `af2a2666d` (`Exercise nested manual view authority`). Their
frozen trees from newest to oldest are
`232715c3d7ff67f719508d9d37b2ba5161b27f15`,
`163604e679db1021a16fd6a11959d7ba069afe5f`,
`05f9db5089a769acbb1fe5df79645641cc83464e`,
`614e83f2d1bdad6ba166f152b9bc90c5a2bc30a9`,
`efe7f2a754c0191ebfacd1952eb422a41fafa315`,
`942f1207f6e6dad9cfab6c897894f2e1ea5f7a15`,
`3f1edaf17f4d7dd4fe654c8738ca6cb9c09440f7`,
`67eb64a23f985494992ef53db36130557414fd1d`,
`22ddf1f9b4ab1193cc1bb635b6ebae83f97e0f20`,
`0b41cbbb34cd5ff138a9b792a0c8e528505e17a8`, and
`082310e18ecfbdb9fc18a4f9d1914c7660a6edfd`. The approved product decision
checkpoint is
`b61e783a6`; the public-navigation proposal starts at `b5494adb0`.
All new branch checkpoints must remain signed local commits and must
not be pushed. Earlier signer outages and the exact rewritten commit
mapping remain preserved in the experiment ledger. The
chronological checkpoint table in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md) is authoritative.

The 2026-09-17 restart audit defines `EXP-159` for explicit long-running
action start/stop, including reverse A/B completion, empty-action isolation, and
unavailable-target fallback. Its definition precedes implementation; EXP-158
remains the latest accepted result. See the current plan and active EXP-159 record.

Resume after accepted `EXP-158` at signed implementation, probe, and
documentation checkpoint `c2d1f1f9a` (`Target one-shot actions to a window
scene`). EXP-149 closes the deterministic lifetime/scene
matrix for the `EXP-148` SDK-owned implementation. `EXP-148` moves the `EXP-147`
existing-router policy into the SDK-owned iOS 27 prototype while preserving zero
screen edits, zero
per-navigation-method RUM calls, automatic metadata with sparse overrides, and
zero RUM-code growth for added routes or presentations. Its authoritative post-
lint frozen run is `exp148-sdk-observed-postlint-20260916T063742Z`, session
`c951c32e-12a7-4bc4-bc5e-bdaf2f16f8aa`. EXP-149's 20/20 selection proves actual
host reconstruction keeps one subscription, A/B observed sources remain isolated,
posted disconnect releases only the exact source, and an unrelated automatic
subtree remains eligible. EXP-151 then accepts one-shot Observation for one
atomically updated accepted-state property on an existing iOS 27 `@Observable`
router. The post-review frozen run is
`exp151-observation-router-postreview-20260916T083131Z`, session
`ea9adc0e-5a00-4290-9580-fb4df6bc18e7`; it passes 38/38 locally and in backend
intake with exact synchronous dismissal ownership. Signed SDK checkpoint
`24cf5078a` and signed migration fixture/probe checkpoint `7da52ae6d` preserve
the frozen sources used for that run. EXP-152's signed harness checkpoint is
`0a67f3e36`; clean run `exp152-native-dismiss-callbacks-20260916T094300Z`,
session `fee27d61-1eb7-4eb6-8525-7af74a53ed7e`, passes 38/38 and proves actual
Sheet/Cover `onDismiss` work uses fresh H3/H4 without creating another Home.
EXP-153's signed harness checkpoint is `d6d813736`; clean run
`exp153-third-party-callback-20260916T103122Z`, session
`f2d2fb24-02d6-4bd9-9df9-ee353b899e69`, passes 42/42 plus
`registrations=1 active=1`. The custom container's one callback adapter reuses
the SDK publisher host; backend intake has eight views, 13 actions, 13 Resources,
and zero errors/crashes. EXP-154 scenario checkpoint `7fd6a891a` plus signed
readiness correction `f92d72909` freeze the accepted source. Clean run
`exp154-observation-two-scenes-serial-fix-20260916T111921Z`, session
`a6a5afd5-8089-4996-9805-ed62fb76927d`, passes 25/25. Backend intake has seven
views, six actions, six Resources, and zero errors/crashes; A and B independently
own distinct H1/D1/H2 occurrences and all six marker pairs. Serial native-scene
parity is therefore closed. Prepare the semantic API review candidate and begin
the physical-device queue. EXP-155 SDK/scenario/correction checkpoints are
`b0524bb5b`, `3e567a494`, and `eb1dd2fdc`. Clean run
`exp155-operation-explicit-target-serial-manual-boundaries-20260916T124918Z`,
session `bcb168fd-b5df-42ed-b416-b505a42e6e76`, passes 24/24 with eight raw
steps and four reduced A→B/A→A/B→B Operations. The `.current(in:)` SPI is an
accepted engine proof, not stable API approval. EXP-157 then accepts inferred
ownership on two physical scenes; only simultaneous visibility remains as a
human topology qualifier. EXP-158 generalizes the target and accepts one-shot
action targeting plus unchanged legacy representative fallback. Continue
simulator-capable downstream target slices while the physical iPad is
unavailable. Do not retry
the rejected value-only `currentDestination` initializer: frozen run
`exp150-current-destination-20260916T072321Z`, session
`2294a609-76f9-47be-a643-ab51edc5b638`, matched only 17/38 because immediate
sheet work stayed on Compose and immediate cover work stayed on Attachment. The host,
low-level explicit source, optional capability, and opaque fallback remain
engine/adapter evidence; do not describe low-level harness calls as the normal
customer integration. Run genuine final-host removal and OS scene disconnect on
capable hardware; synchronous reader-bounce and posted-notification tests do not
close those rows. Public review blocks stable promotion of the Operation target,
not physical validation. Keep same-key A/B manual views, semantic-A plus
automatic-B, inferred cross-scene Operations, activation, shared-request
completion, and adaptive/restoration rows in the physical-device queue.

`EXP-090` through `EXP-105` establish the debug SwiftUI occurrence mechanics,
including abort, replacement, retained return, state preservation, and remount.
`EXP-106` through `EXP-113` make stack, split, UIKit transition, and exact
open/close results signal-driven, locally self-validating, and backend-confirmed.
`EXP-114` adds exact activation dispatch, latched scene-state conditions, durable
terminal-result logging, and explicit `INCONCLUSIVE` classification when the
topology does not transition. The current simulator did not produce a qualifying
activation sequence and crashed its own compositor during one retry. Native
gesture, adaptive topology, and genuine lifecycle rows remain separate.
`EXP-115` then enables automatic and explicit SwiftUI tracking together and
proves target-scoped authority with an exact backend H1/D1/H2 sequence and no
duplicate automatic view. `EXP-116` installs that route-owned boundary once at a
probe navigation container, with one bound path and centralized resolver, and
passes return, abort, and same-type replacement locally and in backend intake.
`EXP-117` records why host-side uninstall remains mandatory for an isolated clean
run. `EXP-118` adds the exact separate-scene automatic/semantic discriminator.
Two clean simulator attempts proved that A's authority does not suppress B's
automatic controller views, but `backboardd` crashed before the decisive B marker
and terminal oracle. That row remains explicitly simulator-inconclusive and is
queued for physical multi-window hardware. `EXP-119` proves exceptional explicit
Sheet dedup and eventual automatic Home restoration, while conclusively exposing
incorrect immediate `onDismiss` ownership. `EXP-120` then proves that direct
keyed manual start/stop is also not authoritative: automatic discovery displaces
M1 during its authority interval and takes its action/Resource work. `EXP-121`
proves the first internal stack route fixes that preemption but still reveals a
generic fallback. `EXP-122` closes the narrower defect: the clean 16/16 run and
backend intake contain H1 → authoritative M1 → fresh H2, with no intervening
fallback and exact active/immediate/settled ownership. `EXP-123` then proves
handler authority alone does not suppress the automatic controller representing
a semantic Sheet. `EXP-124` produces the correct five-view chain but exposes an
oracle error: a pending Resource can delay an outgoing aggregate snapshot beyond
semantic stop. The corrected `EXP-125` run passes 14/14 locally and in backend
intake with exact H1 → semantic Sheet M1 → fresh H2, no automatic Sheet, and
immediate plus settled dismissal work on H2. `EXP-126` independently repeats the
complete-destination contract for `fullScreenCover`: its clean 14/14 run and 28
backend events contain H1 → semantic Cover M1 → fresh H2, no automatic
`ProbeFullScreenCoverView`, exact pre/active/dismiss ownership, and zero errors or
crashes. `EXP-127` then proves sibling containment on real iOS 27 controller
topology: the left manual boundary stays authoritative while right Detail stages,
and exact stop reveals a fresh right Detail occurrence. The accepted hardened
run passes 19/19 and its 31-event backend session contains four views, 11 actions,
11 Resources, three long tasks, one session, and one vital with no error or crash.
`EXP-128` then exercises the approved nested manual suffix in a real SwiftUI
destination hierarchy. The first attempt exposed a driver race because the exact
Compose mapper snapshot arrived before its wait step; exact occurrence waits now
accept already-recorded immutable evidence. The clean retry passes 29/29 with
H1 → C1 → P1 → fresh C2 → fresh H2. A duplicate active Compose start creates no
new view; its action and Resource remain on C2. The seven-view backend session
adds only ApplicationLaunch and the expected startup fallback, and reports no
error or crash.
`EXP-129` then adds the exact two-scene same-key and reverse-stop contract. Its
hostless plan passes 91/91, but the clean simulator run reached only the A/B
automatic prefix before the Xcode/device session expired. It has no terminal or
backend result and is queued for capable hardware.
`EXP-130` adds an independently driven single-scene Operation/navigation
scenario. Its 27/27 local oracle and 93/93 full plan agree with backend intake:
successful and failed Operations retain different start/end views across
navigation, while a duplicate identity emits `[start, start, end]`, reduces from
the latest start, and leaves the earlier raw start open without a synthetic end.
`EXP-131` prepares A→B success/failure and two distinct same-name Operations
completed B-before-A. The full hostless plan passes 100/100 with four adversarial
cross-scene ownership fixtures; live execution remains in the hardware queue.
`EXP-132` then drives a real threshold-qualified UIKit fling on Secondary 2,
presents Secondary 3 while UIKit is still decelerating, and proves one `.scroll`
action remains on the stopped origin occurrence. The fresh destination owns its
post-navigation action and Resource. At that checkpoint the full probe plan
passes 109/109; mapper and backend intake agree on exact ownership and count.
`EXP-133` then starts a Trace-only URLSession request on A/Home H1, makes B/Home
B1 representative, and releases the response from B. The 8/8 run and exact
backend predicates find one span on A/H1, none on B/H1, the original session,
and no RUM Resource for the Trace-only URL. The full probe plan now passes
115/115.
`EXP-134` then starts independent requests on A/Home H1 and B/Home B1 and
completes them B-before-A while deliberately making the opposite scene
representative. The 14/14 run and backend predicates find exactly one span for
each request on its own start view, zero on the opposite view, the same RUM
session for both, and zero matching RUM Resources. The full probe plan now
passes 120/120.
`EXP-135` then drives a real SwiftUI Button in A, creates a child task, suspends
it, opens B, and resumes from B. The automatic button tap emits once on A/H1.
Diagnostic evidence shows the SDK handoff is already nil in the SwiftUI closure
and at task creation; UIKit's ambient scene trait begins as A but changes to B
after suspension. The resumed manual Action and Resource consequently use the
approved source-less fallback and land on B/H1. The strict expected-A oracle
terminates `FAIL` after matching four of six expectations, intentionally preserving
the unsupported exact-origin contract, while backend intake confirms the same
boundary and reports zero errors or crashes. `EXP-136` then adds the shared
A-created/B-joined URLSession task contract and raises the plan to 132/132; two
simulator attempts crash `backboardd` before response release, so exact span
ownership remains a physical-device row. `EXP-137` through `EXP-140` replace the
probe's internal manual-view calls with the customer-shaped Swift SPI and pass
manual, nested, Sheet, and full-screen-cover semantics locally and in backend
intake. The rejected first nested run exposes restored `WindowGroup` metadata
surviving uninstall; run normalization plus exact-session view inspection close
that harness defect. `EXP-141` then replaces the probe-only navigation wrapper
with the actual iOS 27 semantic-navigation SPI. Its combined stack, Sheet, and
full-screen-cover run passes 38/38 locally and matches backend intake across seven
fresh semantic occurrences, including four distinct Home IDs. The probe plan at
that checkpoint passed 134/134. `EXP-142` closes sequential repeated equal routes
through native value links. `EXP-143` then closes initial repeated restoration
and external router replacement, rejection, and canonicalization. `EXP-144`
closes direct Sheet → Cover → Sheet replacement without exposing Home between
presentations; its final 43/43 run and backend intake preserve distinct S1/F1/S2
IDs and reveal one fresh H2. `EXP-145` then runs the `EXP-127` sibling topology
through the actual SPI. Two harness-invalid attempts expose a redundant late wait
and a timing-dependent delayed-callback expectation; the corrected run passes
19/19 and backend intake preserves only launch/H1/M1/D1 with exact ownership.
`EXP-146` then extracts the shared semantic engine. Deterministic explicit-source
and optional-capability adapter paths each pass 42/42 around unchanged standard
SwiftUI, preserve eight exact view documents including launch, and keep 26
actions plus 26 Resources on the intended semantic occurrences. The identical
opaque specialization passes 5/5 with automatic capture, no semantic view, and
exact Detail work on the automatic controller owner. Runtime precedence, stable
reconstruction, and adversarial replacement each pass 43/43 with identical
backend ownership and no decoy. A synchronous real-reader bounce passes 17/17;
focused disconnect/lifetime tests pass 4/4 and the handler suite passes 84/84.
Two final-host-removal simulator attempts fail in `backboardd` before removal and
remain hardware-INCONCLUSIVE. EXP-147 then validates the low-cost existing-router
candidate on a 25-route, seven-presentation fixture. Zero screens and zero of
twelve navigation methods change; route and presentation growth add no RUM code;
the final frozen-source run passes 38/38 locally and in backend intake with no
automatic duplicate, error, or crash. The probe plan passes 154/154. The low-level
transition publisher and fixture-local metadata remain adapter-author proof, not
the accepted public API.
The [experiment index](MultiSceneSupport/EXPERIMENTS.md) locates the frozen
chronology and every failed attempt without loading it wholesale.

### Exact next work

The deterministic engine/adapter harness is complete through the `EXP-146`
explicit, capability, opaque-fallback, precedence, reconstruction, replacement,
and focused lifetime matrix;
[PLAN.md](MultiSceneSupport/PLAN.md) owns the finished phases and full release
matrix. The scene-aware manual-view, native convenience, shared
semantic engine, arbitrary host, and stable explicit-source prototypes are
implemented behind iOS 27 experimental boundaries. Continue in this order:

1. Run the prepared automatable physical-iPad scenarios serially, beginning with
   inferred cross-scene Operations, then same-key manual A/B, semantic-A plus
   automatic-B, activation, close continuity, split/parallel navigation, shared
   Trace work, and final host removal. Require each unchanged scenario's terminal
   oracle plus exact backend ownership. A topology the device cannot express is
   inconclusive, not an SDK failure.
2. Run genuine final host removal, OS scene disconnect/reconnect, and delayed
   same-scene remount on physical iPad or iPhone Duo. The synchronous reader
   bounce and EXP-149 posted-notification tests are only internal lifetime evidence.
3. Finish `swiftui.coexistence.same-key-manual-two-scenes` on iPhone Duo or a
   physical multi-window iPad. The simulator prefix reached both native scenes
   but expired before manual starts. Stop B before A and prove each exact
   scene/key closes only its own Compose occurrence while automatic tracking
   remains active.
4. Finish `swiftui.coexistence.semantic-a-automatic-b` on physical multi-window
   hardware. The simulator prefix already proves B automatic discovery remains
   eligible; require the final B marker and backend owner before closing it.
5. Run `traces.urlsession-shared-request` unchanged on iPhone Duo or a physical
   multi-window iPad. The simulator retry proves A creation and B join but twice
   lost `backboardd` before release. Require one A/Home span, zero B-owned or
   duplicate spans, and no matching RUM Resource.
6. Close the remaining action-attribution hardware row: keep A and B
   simultaneously visible, make B representative, interact in A without a
   focus-driven fallback, and prove exact A ownership. `EXP-132` already closes
   UIKit drag/deceleration across same-scene navigation and should remain a
   regression gate rather than be repeated as a prerequisite.
7. Run `windows.activation-sequence` on iPhone Duo or a physical multi-window
   iPad. Require the activated scene to become foreground-active and the peer to
   become background before asserting fresh view occurrences or marker ownership.
8. Take the experimentally validated manual-view, host, capability, adapter,
   native-convenience, and Operation `.current(in:)` shapes through normal API
   review. Review stable type-erased source ownership, descriptor/target shape,
   availability, and Objective-C Release exposure without replacing standard
   navigation/presentation APIs or exposing RUM UUIDs.
9. Route recognized native gestures, adaptive resize, and stable simultaneous A/B
   topology through the real-device/human queue; ignored simulator input is not
   evidence.
13. Run per-scene background/foreground and
   concurrent restoration.
13. Finish explicitly targeted downstream-signal runtime rows. `EXP-133` closes
   one-request Trace-only owner freezing across A→B representative churn;
   `EXP-134` closes independent two-request reverse completion; `EXP-135`
   classifies an ordinary SwiftUI Button child task as source-less after the
   framework callback escapes the synchronous handoff.
   Then prove live single-scene/custom-handler compatibility and measure
   event-handoff recursion and overhead. Repeat the release matrix on iOS 27.1
   and iPhone Duo.
14. Only after the multi-scene runtime is frozen and every experiment is closed or
   explicitly deferred, execute the
    [single-scene reliability extraction](MultiSceneSupport/DEFERRED_SINGLE_SCENE_EXTRACTION.md).
    Preserve the completed branch, prove every extracted fix as a source-less
    defect on `develop`, rebuild the multi-scene branch on the generic stack, and
    stop before any push.

### Proven and implemented

- Scene identifiers and routing targets are internal and are never serialized.
- Core UIKit and explicit SwiftUI view stacks, sessions, navigation, actions,
  scrolls, INV, lifecycle, rollover, delayed completions, WebView containers,
  Operations, and representative fatal context accept scene-aware routing.
- The hidden SwiftUI scene reader and UI-event causal handoff activate only when
  the app declares `UIApplicationSupportsMultipleScenes = true`. Ordinary apps
  retain the original direct SwiftUI modifier path.
- On iOS 17+, a scene-level custom UIKit trait bridges each real scene identity
  into SwiftUI. It improves attribution but does not guarantee internal tracking
  occurs before customer outer lifecycle callbacks.
- On iOS 27, explicitly tracked multi-scene SwiftUI views use that inherited
  trait at hidden-reader creation to enqueue the semantic view before early
  customer work. iOS 15-26, visionOS, and single-scene applications retain their
  prior lifecycle path. Three clean final-code A/B runs and focused stress pass,
  while the construction/visibility matrix remains incomplete.
- The internal keyed-occurrence seam can replace a RUM occurrence without
  replacing customer SwiftUI content. Its debug per-window source now reveals a
  retained returned route before immediate post-pop work and preserves the same
  customer state token. The same key/generation model independently replaces
  retained split Detail occurrences in two windows. A source-started returned
  split occurrence can also transfer to a replacement SwiftUI tracking state
  without a duplicate start. This is integration evidence, not a shipped API.
- On the iOS 27 declared multi-scene path, active explicit SwiftUI boundaries are
  registered weakly and suppress automatic controller discovery only for a
  containing hierarchy. Inactive, detached, and unrelated sibling boundaries do
  not suppress discovery, and UIKit tracking keeps precedence. `EXP-115` proves
  exact H1/D1/H2 occurrence output with both SwiftUI tracking modes enabled.
- `EXP-127` proves that containment remains scoped between two sibling
  `NavigationStack` controller branches under one SwiftUI host. A left authority
  boundary does not suppress right-hand automatic materialization, and the latest
  right destination becomes one fresh current occurrence when manual authority
  ends. The topology assertion is mandatory and times out as `INCONCLUSIVE`.
- `EXP-128` proves the approved distinct-key manual suffix with real probe
  destinations: Compose C1 → Preview P1 → fresh Compose C2. Duplicate active
  Compose start remains crash-safe, creates no view, and leaves action/Resource
  ownership on C2; final exact stop reveals fresh automatic Home H2.
- The probe-only container prototype accepts one binding to the application path
  and one centralized route resolver, and owns root/destination materialization
  so the route-owned boundary is early enough. `EXP-116` preserves return,
  cancellation, and same-type replacement semantics without putting RUM metadata
  into each destination view. This is design evidence only; no public API was
  added.
- Operations resolve every step independently. Trustworthy new context replaces
  the last-proven snapshot; the snapshot and then process representative are
  fallbacks. Identity is the exact application-wide `(name, operationKey)` tuple.
- Profiling uses the same typed Operation identity and distinguishes omitted from
  empty keys.
- Session Replay is required only to coexist without an SDK crash.
- The standalone probe now resolves 50 named scenarios from command-line input,
  preserves exact known legacy environment profiles, and fails closed before SDK
  initialization. It records ordered versioned JSONL signals, keeps call-site
  source separate from mapper-observed RUM ownership, derives view start/stop from
  snapshots, and evaluates ordered/negative expectations using only `PASS`,
  `FAIL`, `SKIPPED`, and `INCONCLUSIVE`. Its observable driver waits for exact
  scene, path/selection, destination, and RUM-occurrence signals. Home return,
  abort, same-/different-type replacement, split replacement, and retained split
  return plus deterministic UIKit cancel/finish, exact scene open/close, and
  lifecycle-gated activation passed 45/45 at the `EXP-113` harness checkpoint.
  Clean semantic runs through `EXP-113` have one final verdict per run. `EXP-114` deliberately emits
  `INCONCLUSIVE` when the simulator cannot prove the requested scene-state
  transition, and writes the terminal result to OSLog so it survives an Xcode
  console-session expiry. The automatic SwiftUI split control
  produces the intended semantic `FAIL`.
  This improves evidence quality but does not change the RUM support verdict.
- UIKit split scenario manifests forbid Primary as a RUM view. On iOS 27 in a
  declared multi-scene app, the shipping handler now ignores regular-width
  Primary/supplementary columns while retaining their probe lifecycle as
  structural diagnostic evidence. Cancellation keeps S2's UUID and completion
  creates a fresh returned S1 UUID. The startup SwiftUI hosting fallback and
  application-subclassed split-container case remain separate gaps.

### Validation snapshot

As of 2026-09-16:

- The current complete DatadogRUM run passes 1,255/1,255 test cases with zero
  failures. The result bundle records 1,291 expanded device/configuration
  invocations. Earlier complete
  suites pass:
  Internal 477/477, Logs 95/95,
  Trace 151/151, WebView 31/31, and Profiling 233/233.
- Focused retained-route, occurrence-isolation, transition-arbiter, Operations,
  UIKit-scroll, and OpenTelemetry ownership regressions pass. Native SwiftUI
  edge gestures remain unproven because `EXP-100` produced no navigation signal.
- The named runner validates fail-closed startup (`EXP-106`), and its recorder,
  oracle, scene registry, and observable driver pass 150/150. Clean runs prove
  Home₁/Detail/Home₂, aborted and replacement stacks, split replacement/retained
  return, and exact per-occurrence action/Resource ownership (`EXP-109` through
  `EXP-111`). The fully driven automatic SwiftUI split control fails locally as
  expected because it has no semantic selection boundary.
- Clean UIKit cancellation and completion pass 11/11 and 13/13. Cancellation
  retains S2; completion creates a fresh returned S1. Backend intake has exact
  marker pairs, no Primary, no errors, and no work on the startup hosting fallback
  (`EXP-112`).
- A clean exact-lifecycle run passes 9/9: A opens B through A's registered
  executor, B emits and uploads `before-close`, B disconnects, then A emits and
  uploads `after-peer-close` on A's unchanged Home UUID (`EXP-113`). The
  fullscreen simulator topology does not close simultaneous-visible continuity.
- The exact activation scenario dispatches through each registered
  `UIWindowScene`, acknowledges target foreground state, and treats the peer's
  background state as a latched condition so notification ordering cannot create
  a false timeout. The completed source-less control reached backend intake; the
  lifecycle-gated retries remained inconclusive, including one interrupted by a
  simulator `backboardd` SIGABRT rather than an app/SDK crash (`EXP-114`).
- With automatic SwiftUI discovery and explicit route-owned tracking enabled
  together, `swiftui.stack.return` passes 7/7. Mapper and backend intake contain
  exactly ApplicationLaunch, Home H1, Detail D1, and Home H2; H1/H2 are distinct
  and no hosting-controller duplicate exists (`EXP-115`).
- The once-per-container probe wrapper repeats that exact return result, rejects
  an aborted Detail occurrence, and gives same-named Detail₁/Detail₂ distinct
  UUIDs with exact final action/Resource ownership. All three isolated runs agree
  locally and in backend intake (`EXP-116`).
- The actual native-convenience semantic SPI preserves the sibling authority
  boundary (`EXP-145`). Its corrected run passes 19/19 and backend intake has
  exactly launch, semantic Home, manual authority, and fresh semantic Detail;
  11 actions and 11 Resources use the expected owners with zero error/crash.
- The exceptional-manual-Sheet scenario builds. Its
  corrected local and backend run has exact H1/S1/H2 occurrence and dedup
  evidence, but fails because immediate `onDismiss` action/Resource work remains
  on S1 before H2 starts (`EXP-119`).
- The direct keyed-manual scenario and hardened oracle bring the probe plan to
  65/65 tests. Clean simulator/backend runs prove M1 is displaced by an automatic
  fallback during its authority interval and that Compose work follows that
  fallback; fresh H2 eventually receives only settled work (`EXP-120`).
- The internal exact-scene manual path routes through the target scene's handler
  stack. `EXP-121` proves M1 authority and isolates a generic-fallback reveal;
  `EXP-122` rejects that structural candidate and passes 16/16 with exact
  H1/M1/fresh-H2 mapper and backend ownership. Existing source-less APIs are
  unchanged, and no public API has been added.
- The exact-scene semantic Sheet successor passes 14/14 (`EXP-125`). A
  suppression-only state follows the native presentation subtree without
  publishing its own RUM view, so automatic discovery remains enabled outside
  that subtree. Mapper and backend contain exactly H1, semantic Sheet M1, and
  fresh H2 after startup; active work uses M1 and immediate plus settled dismiss
  work uses H2. The backend session has 29 events and zero errors or crashes.
  `EXP-123` preserves the failure without that boundary, and `EXP-124` preserves
  the corrected lesson that delayed aggregate snapshots are not authority clocks.
- The independent full-screen-cover successor passes the same 14/14 contract
  (`EXP-126`). Its mapper and 28-event backend session contain only the expected
  startup views plus H1, semantic Cover M1, and fresh H2. No automatic
  `ProbeFullScreenCoverView` starts; active work owns M1, both dismiss pairs own
  H2, and zero errors or crashes appear. This closes internal presentation-style
  parity without approving the public semantic API.
- The sibling-container scenario passes 19/19 twice after the controller topology
  was proven. Final backend intake contains exactly four views and 11
  action/Resource pairs: Home work uses H1,
  underlying Detail work stays on M1, and immediate plus settled post-stop work
  uses one fresh Detail. The first pass is retained because its probe-only
  ancestry reader became a late fifth view; the accepted predicate filters only
  that measurement type.
- The nested keyed-manual scenario passes 29/29. Backend intake contains distinct
  automatic Home H1, Compose C1, Preview P1, Compose C2, and automatic Home H2
  after startup. The duplicate
  Compose marker and Resource remain on C2, and the final immediate return pair
  uses H2. The first attempt is retained as a harness failure because the C1
  snapshot arrived before its wait step. The driver now searches
  already-recorded evidence for exact immutable RUM occurrence waits.
- The two-scene same-key scenario raises the local probe plan to 91/91 and rejects
  shared Compose identity, cross-scene work, wrong-scene stop effects, and reused
  returned Home occurrences. Its clean iPad simulator run reached distinct A/B
  native scenes, then lost its Xcode/device session before manual authority
  began. It produced no backend documents or terminal verdict; `EXP-129`
  therefore remains hardware-inconclusive.
- The Operation/navigation scenario `operations.navigation.lifecycle` passes
  27/27 locally; the full probe plan is 93/93. Backend intake contains six fresh
  semantic Home/Detail occurrences, seven raw Operation steps, and three reduced
  Operations. Success
  preserves H1→D1, failure preserves H2→D2 and its reason, and the duplicate case
  reduces from D3→D3 while its earlier H3 start remains unclosed. The corrected
  four-hour-timeout warning appeared, with no synthetic end, error event, or
  app/SDK crash (`EXP-130`). Exact identifiers and artifacts for these runs stay
  in [EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).
- The exact cross-scene Operation scenario raises the probe plan to 100/100. Its
  driver proves the eight A/B invocations and reverse-completion order. The
  semantic oracle passes its valid fixture and rejects four ownership failures.
  Because the same two-scene simulator topology already expired in `EXP-129`, no
  redundant runtime claim is made; `EXP-131` is queued for capable hardware.
- The real UIKit scroll/navigation scenario raises the probe plan to 109/109.
  A measured lift above the SDK's swipe threshold entered deceleration, then
  Secondary 3 appeared before deceleration ended. Exactly one `.scroll` action
  stayed on the stopped Secondary 2 occurrence; a fresh Secondary 3 owned the
  immediate action and Resource. The terminal oracle, mapper output, backend
  count and ownership, and zero-error/crash checks all pass (`EXP-132`).
- The Trace-only URLSession scenario raises the probe plan to 115/115 and passes
  8/8 live assertions. After B/Home B1 became representative, one held request
  completed with its original A/Home H1 and session correlation. Backend counts
  are exactly one for A/H1, zero for B/H1, and zero matching RUM Resources
  (`EXP-133`). The first attempt ended with the Xcode interaction session and no
  crash evidence; only the clean retry is acceptance evidence.
- The two-request Trace-only scenario raises the probe plan to 120/120 and
  passes 14/14 live assertions. B completed before A while the opposite scene
  was representative for each completion. Backend intake contains exactly one
  A span on A/Home H1 and one B span on B/Home B1, zero opposite-view matches,
  both on the expected RUM session, and zero matching RUM Resources
  (`EXP-134`). The initial backend query returned zero before indexing caught
  up; the accepted 202 upload and later raw plus aggregate results are retained
  as the complete evidence chain.
- The real SwiftUI Button → structured-task scenario raises the probe plan to
  126/126 (`EXP-135`). Its accepted run emits exactly one automatic tap on A/H1,
  then intentionally fails the expected-A semantic oracle after matching four
  expectations because resumed source-less Action/Resource work lands on the
  later B/H1 representative. SDK handoff is nil at callback, task start, and
  resume; the ambient UIKit scene trait changes from A to B across suspension.
  Backend intake confirms those owners, one tap, and zero errors/crashes. Four
  earlier timeout/tooling attempts and the pre-diagnostic failure remain recorded
  separately and make no support claim.
- The shared-request scenario adds six focused tests (`EXP-136`). Two clean
  simulator runs reached A creation and B rendering; the retry also passed the B
  join assertion without creating another task. Both then crashed simulator
  `backboardd` in the same Metal validation path before response release. No span,
  terminal result, app crash report, or RUM error/crash signal exists. The
  unchanged 132/132 contract is queued for capable physical hardware.
- The customer-shaped scene-targeted manual API runs pass in `EXP-137` through
  `EXP-140`: H1/Compose/H2, nested Compose/Preview/Compose/Home, Sheet, and
  full-screen cover all preserve fresh occurrence and action/Resource ownership.
  Four backend sessions contain zero errors/crashes. Swift/custom/NOP forwarding,
  Debug-only Objective-C selectors, lint, and an Xcode 27 Debug plus Release build
  pass. The API-surface verifier reports only the expected experimental additions;
  no baseline changed.
- The native-convenience semantic-navigation SPI passes `EXP-141`: automatic
  tracking stays enabled while one probe container produces
  H1/D1/H2/Sheet/H3/Cover/H4
  with distinct IDs and no automatic duplicate. All 38 local expectations pass;
  backend intake contains 25 actions and 25 Resources on the seven exact semantic
  owners, plus zero error/crash events.
- The container-independent engine/adapter boundary passes the `EXP-146`
  explicit-source and optional-capability arms at 42/42. One outer host wraps unchanged
  `NavigationStack`, `.sheet`, and `.fullScreenCover` code; H1 starts before
  initial lifecycle work, all four Home occurrences have distinct IDs, and each
  backend session contains 26 actions plus 26 Resources with zero errors/crashes.
  The identical opaque specialization passes 5/5, leaves automatic capture
  active, emits no semantic view, and keeps Detail work on its automatic owner.
  Runtime explicit precedence, repeated stable-source resolution, and
  adversarial capability replacement each pass 43/43 locally and in backend
  intake. Each session contains launch plus seven unique semantic occurrences,
  26 actions, 26 Resources, no decoy/automatic duplicate, and no error event.
  A synchronous real-reader detach/reattach passes 17/17 without replacing the
  Detail UUID. Focused disconnect/lifetime tests pass 4/4, full handler tests pass
  84/84, and an Xcode 27 Release build passes. Two final-host-removal simulator
  attempts crash `backboardd` before removal and remain physical-device work.
  These results validate engine and adapter-author primitives, not an accepted
  normal-customer transition-publishing API.
- `EXP-147` closes the separate migration discriminator for an existing-router
  candidate. The fixture contains 25 routes, seven presentations, three exact
  router boundaries, and two automatic-fallback boundaries. Customer screens and
  all twelve navigation methods stay Datadog-free; route and presentation growth
  change no RUM integration code. The final frozen-source run
  `exp147-router-stream-20260916T052101Z` passes 38/38 with seven distinct
  semantic occurrences, exactly one action and Resource for each of eleven
  phases, no automatic duplicate, and no error/crash in session
  `5f3f47cb-5845-41c3-a1ef-d3b9e95c16d8`. Its adapter and automatic metadata
  remain historical fixture-local evidence rather than the accepted public API.
- `EXP-148` moves the generic observation and metadata policy into DatadogRUM.
  It fixes equal-route occurrence identity, pre-first-value authority, FIFO
  background delivery, and explicit observed-source precedence while pending.
  The corrected source passes 9/9 focused tests, 153/153 probe tests, and a
  generic Release build. Final frozen run
  `exp148-sdk-observed-postlint-20260916T063742Z` passes 38/38 with exact eight-view
  and 22 action/Resource bucket ownership in session
  `c951c32e-12a7-4bc4-bc5e-bdaf2f16f8aa`, with no automatic duplicate and zero
  errors/crashes. Stable public shape and adapter parity remain open.
- `EXP-149` closes the deterministic observed-source lifetime/scene matrix at
  20/20. The actual SwiftUI host keeps one subscription through reconstruction
  and publisher replacement; A/B observed sources stay isolated; posted
  disconnect releases only A while B continues; an unrelated automatic subtree
  remains eligible. Genuine OS disconnect/remount remains hardware-gated.
- `EXP-150` rejects render-time current-value observation as an exact adapter.
  Focused and state-level suites remain green, but the frozen iPadOS 27 run fails
  17/38 and backend intake confirms that synchronous sheet and cover dismissal
  work remains on the outgoing presentation. Fresh Home appears one signal later;
  settled work is correct. This is a timing failure, not a crash or simulator
  limitation. Continuous observation and plain local `@State` do not satisfy
  this boundary.
- `EXP-151` accepts one-shot Observation `.didSet` for an existing iOS 27
  `@Observable` router whose complete current destination is one atomically
  updated property. Its post-review frozen run passes 38/38 locally and in
  backend session `ea9adc0e-5a00-4290-9580-fb4df6bc18e7`: eight views, 11
  actions, 11 Resources, no error bucket, and exact immediate plus settled Sheet
  and cover dismissal owners. Focused Observation/adapter tests pass 8/8, the
  affected SwiftUI file passes 193/193, the probe passes 154/154, and both the
  Xcode 27 iOS Release and visionOS package builds pass. The API spelling remains
  experimental; later EXP-154 evidence closes serial native-scene parity.
- `EXP-152` separates actual native SwiftUI callback timing from EXP-151's
  stronger synchronous post-mutation markers. After confirmed Sheet and cover
  content appearance, each native `onDismiss` fires once with accepted Home
  current, creates no additional Home, and owns its immediate plus settled work
  on fresh H3/H4. The clean frozen run passes 38/38; backend session
  `fee27d61-1eb7-4eb6-8525-7af74a53ed7e` contains eight views, 11 actions, 11
  Resources, and zero errors/crashes. Gesture
  dismissal/cancellation remains a physical/human experiment.
- `EXP-153` closes callback-driven custom/third-party adapter parity. A true
  custom visual container publishes synchronous accepted snapshots to one
  boundary adapter, which reuses the SDK publisher host without changing
  screens or navigation methods and without retroactive conformance. Its clean
  frozen run passes 42/42 plus `registrations=1 active=1`; backend session
  `f2d2fb24-02d6-4bd9-9df9-ee353b899e69` contains eight views, 13 actions,
  13 Resources, and zero errors/crashes. The full probe now passes 161/161.
- `EXP-154` closes serial two-native-scene Observation parity. The corrected
  frozen run passes 25/25; backend session
  `a6a5afd5-8089-4996-9805-ed62fb76927d` contains seven views, six actions, six
  Resources, and zero errors/crashes. Native scenes A and B own distinct
  H1/D1/fresh-H2 occurrences and all six matching action/Resource marker pairs.
  The full probe passed 162/162 at that checkpoint. The current suite passes
  164/164 after the explicit Operation and action-target scenarios. This does not claim simultaneous visibility,
  interleaved focus, genuine disconnect, or final host removal.
- Repeated native value-link navigation passes `EXP-142`: H1/D1/D2/fresh D3/
  fresh H2 is lifecycle-correct after a stronger oracle exposed and the
  implementation fixed returned-Detail work on D2. The accepted run passes
  48/48; backend intake has 55 events, no duplicate semantic view, and zero
  errors/crashes. Six focused SDK tests, the full 1,181-test RUM suite, the
  recorded probe and Xcode 27 Release checkpoints pass.
- Both probes build through Xcode 27; package build, recorded repository lint, and
  focused changed-source lint pass at their stated checkpoints.

These are regression and implementation checks, not substitutes for the missing
runtime rows. Detailed run evidence remains in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).

### Blockers and workspace safety

Stable SwiftUI and Operation APIs require normal RFC/API review; experimental
iOS 27 SPI implementation and validation are not blocked by that review. The
branch tail through `3af24003c` is signed, and a raw commit-object audit found a
signature block on all 105 commits after the `develop` merge base at that
checkpoint. A 2026-09-16 verification of every then-local-only commit found all
36 with a good ED25519 signature from the configured key; later implementation
and probe commits `24cf5078a`, `7da52ae6d`, `0a67f3e36`, and `d6d813736` also
verify with that key. No history rewrite was required. The earlier
signer outages, replaced hashes, and exact frozen trees remain documented in
[EXPERIMENTS.md](MultiSceneSupport/EXPERIMENTS.md).
The iOS 27 integration-runner half-and-half layout repeatedly respawned
`backboardd`, although the standalone native `WindowGroup` probe opens two windows.
The standalone probe also reproduced a `backboardd` CoreAnimation/Metal SIGABRT
while rapidly requesting exact A/B activation; no probe crash or backend event was
recorded for that interrupted run. Do not repeat that activation loop on this
simulator.
The current iPad simulator also rejects `devicectl appResize` because it lacks
Resizable App Management; adaptive width proof needs a capable destination.
Xcode's packaged device-interaction skill can be exported before opening its
short-lived session. `EXP-132` used the documented measured-coordinate command
and now supplies real UIKit gesture evidence. Earlier sessions expired before
input and remain tooling-only attempts. Other native gesture and visual claims
still require a live interaction key or human/device evidence; programmatic runs
do not become native-gesture proof.
Ignored native edge drags, fullscreen-only peer-window layouts, partial scene
restoration, and unsupported resize are tracked in the dedicated
[physical-device and human-driven queue](MultiSceneSupport/PLAN.md#physical-device-and-human-driven-queue).
Those rows require observable path/coordinator/lifecycle evidence, not more
unverified simulator touches.

`--probe-run-mode clean` is an in-app manifest value, not a host teardown action.
Back-to-back Xcode install/run calls can leave semantic view documents carrying
the previous run's global probe attribute even when later actions and Resources
use the new run ID (`EXP-117`). `EXP-138` additionally proves that the simulator
window system can restore an old `WindowGroup` value after successful uninstall
and absent-container proof. The probe now normalizes restored telemetry while
preserving routed window identity. Continue explicit host teardown and reject any
backend set whose view documents do not all carry the requested
`@context.probe.run_id`.

Do not stage, commit, revert, or expose
`Datadog/Datadog.xcodeproj/project.pbxproj` or
`xcconfigs/Datadog.local.xcconfig`. Both predate this work and the latter contains
local credentials. An exact `git add` is insufficient while the xcconfig is
pre-staged; use `git commit --only -- <exact paths>` or an isolated index, then
verify the commit tree and restore/preserve its exact `AM` state.

Rejected experiments and do-not-repeat guidance are authoritative in
[REJECTED_APPROACHES.md](MultiSceneSupport/REJECTED_APPROACHES.md).
