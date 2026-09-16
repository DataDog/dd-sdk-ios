# RUM multi-scene implementation and validation plan

This document owns ordered future work, dependencies, validation gates, and the
physical-device queue. Read the [assessment](ASSESSMENT.md) for the current
support verdict and the [experiment index](EXPERIMENTS.md) for evidence locators.
Historical planning through `EXP-142` is frozen in
[Archive/PLAN_THROUGH_EXP-142.md](Archive/PLAN_THROUGH_EXP-142.md).

Last updated: 2026-09-16

## Current objective and scope

Deliver correct RUM attribution for concurrent iPad and iPhone windows, with
iPhone Duo on iOS 27.1 as the release target. The branch must preserve ordinary
single-scene behavior and the iOS 15 deployment target.

The approved model is:

- one current RUM destination per scene;
- RUM views represent navigation-path occurrences, not platform object identity;
- returning to the same destination creates a fresh view ID;
- automatic tracking remains the zero-code default;
- exact SwiftUI navigation is an optional once-per-container or once-per-router
  enhancement around the application's existing navigation system; standard
  `NavigationStack`, `.sheet`, `.fullScreenCover`, and custom-container call
  sites must not be replaced throughout the screen hierarchy;
- semantic correctness must not require per-destination metadata, an exhaustive
  RUM-only route/presentation resolver, or RUM calls in every navigation method;
  default metadata is automatic and customer overrides are sparse;
- a scene-scoped semantic engine is independent of any visual container and can
  accept native-adapter, optional-capability, explicit-source, coordinator, or
  automatic-discovery input;
- the explicit transition source is an engine and adapter-author primitive, not
  the representative normal-app integration;
- exact manual authority is scene-targeted, nestable by distinct key, and paired
  with an exact targeted stop;
- source-less work keeps the last-interacted/process-representative fallback;
- Operations remain application-wide by `(name, operationKey)` and resolve every
  step's view independently;
- scene ownership must be ready to map to a future Window Execution Context, but
  this work introduces no temporary attribute, session split, or wire format; and
- Session Replay only needs to remain crash-safe.

No product question blocks the next internal experiment. Stable API names and
Objective-C Release exposure still require normal API review.

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

## Next ordered slices

| Order | Expected outcome | Prerequisite evidence | Implementation boundary | Acceptance test | Environment |
| ---: | --- | --- | --- | --- | --- |
| 1 | Close remaining explicit downstream targets | Accepted shared `RUMViewTarget`, Operations, and one-shot action proofs | Continue one signal family per slice. Next cover long-running actions and Resource/error/view-mutation boundaries; then Traces, logs, WebView, and exported/fatal context where a public target is meaningful | Each targeted signal reaches the requested scene's current view; unresolved explicit input falls through safely; legacy source-less behavior is unchanged | Simulator for controlled attribution; hardware follow-up only where simultaneous topology is essential |
| 2 | Validate ordinary-app compatibility and overhead | Current simulator-capable semantic and target fixes | Single-scene automatic/manual apps, custom handlers, event handoff, swizzle paths | No new views/actions, no custom-handler regression, bounded `sendEvent` overhead/reentrancy, all module/API/lint gates green | Simulator and benchmark host |
| 3 | Prepare semantic-navigation, shared-target, and Operation API review candidates | Accepted EXP-146-155 navigation/Operation evidence plus EXP-158 action evidence | Freeze the shared engine and accepted publisher/Observation/callback inputs. Present `RUMViewTarget.current(in:)` as evidence rather than a pre-approved name. | Review packet reconciles migration, occurrence and presentation semantics, scene isolation, target precedence, availability, Swift/Objective-C shape, and explicit limitations | API/RFC review, informed by physical results already recorded |
| 4 | Resume the physical multi-window acceptance queue below | Prepared named scenarios, clean-run recipes, and a connected iPadOS 27 iPad | Run unchanged scenarios serially on one device; preserve topology failures as inconclusive and keep analog-only rows for a human | Exact mapper plus backend owner evidence on simultaneously usable scenes, lifecycle, close, coexistence, manual views, and shared Trace work | Paused while the physical iPad is unavailable; final parity on iPhone Duo 27.1 |
| 5 | Close remaining lifecycle runtime gates | Deterministic reader-bounce plus EXP-149 lifetime/disconnect fencing PASS | Keep the existing named scenarios unchanged; do not reinterpret synthetic callbacks as platform lifecycle | Actual representable remount timing, exact host removal, and genuine OS disconnect/reconnect show no replay, resurrection, duplicate stop, or peer disturbance | Physical device; simulator only if topology becomes stable |
| 6 | Freeze the multi-scene implementation | Simulator, hardware, compatibility, and review blockers closed | Experimental Swift/Objective-C surfaces and documentation | Reviewed stable shape, availability/fallback story, compatibility evidence, and no unapproved API baseline changes | Review plus CI |

## Dependencies and decision gates

| Dependency or decision | Current rule |
| --- | --- |
| Public API review | Experimental iOS 27 SPI and Debug-only Objective-C prototypes may be implemented and exercised now. Stable symbols wait for normal RFC/API review. |
| Deployment compatibility | Multi-scene correctness may be iOS 27+ when an older-system solution would compromise it. The SDK must still compile and preserve existing behavior on iOS 15-26. |
| Automatic SwiftUI | Remains the zero-code default. Semantic/manual authority suppresses only its targeted scene/container and coexists with automatic tracking elsewhere. |
| Customer navigation compatibility | Do not require replacement navigation/presentation APIs, a Datadog router, per-screen instrumentation, exhaustive RUM-only metadata switches, or `willNavigate`/`commit` calls in every router method. EXP-147 proves one integration per existing observable router/container, automatic metadata, sparse overrides, and route/presentation-growth independence; every SDK-owned candidate must preserve that budget. |
| Semantic precision | Exact semantics require a trustworthy accepted-route, materialization, completion/cancellation, router/coordinator, or content-boundary signal. Opaque containers fall back to scene-aware automatic tracking plus exceptional manual instrumentation; do not invent exact state. |
| Engine input precedence | Explicit adapter source, then optional type-erased container capability, then native adapter, then scene-aware automatic discovery, then the existing process representative. This is engine behavior, not a recommendation that normal applications manually publish every transition. Suppression remains local to the enhanced container. |
| Source-less attribution | Preserve last-interacted/process-representative behavior. Do not silently drop source-less work or require a resolver. |
| Execution Context | Preserve reliable internal scene ownership so it can map to a Window Execution Context later. Do not add a temporary wire field or split sessions. |
| Operations | Identity is application-wide `(name, operationKey)`. Duplicate starts track only the latest client start and leave the earlier backend operation to the four-hour timeout; never synthesize `auto_restart`. |
| Session Replay | Crash safety is required; multi-scene replay correctness is a follow-up. |
| Networking misuse | Do not spend this project on a developer rewriting a request from allowed to disallowed first-party capture/header status. |
| Hardware | Do not retry a topology after two equivalent simulator-system failures before the decisive signal; run the unchanged named scenario on capable hardware. |
| Open product questions | None. Public spellings remain review questions, not blockers for prototype validation. |

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
| Remaining targeted downstream signals | Shared target and one-shot action accepted | Long-running actions, Resources, errors, view mutations, Traces, logs, WebView, and exported/fatal context; one signal family per slice | Exact requested owner, unavailable-explicit fallback, custom/NOP compatibility, and unchanged legacy behavior |
| Single-scene/custom-handler compatibility | After semantic state stabilizes | Existing integration paths | Full suites, representative behavior, no duplicate views/actions |
| Performance/reentrancy | After code shape freezes | `UIApplication.sendEvent` handoff and locks | Measured bounded overhead, no recursion/deadlock, normal apps unaffected |
| Missing deterministic harness controls | Before WebView, mirrored log, and fatal/exported context rows | Probe only | Named scenario, fail-closed prerequisites, mapper/backend oracle |

## Physical-device and human-driven queue

Do not close these rows with simulator prefixes or callback counts. A human
gesture closes a row only when path, coordinator, lifecycle, and RUM UUID evidence
prove the intended interaction.

The physical iPad is currently unavailable. Keep this queue paused and resume at
`EXP-129` without substituting simulator evidence for simultaneous topology,
real disconnect, resize, or analog gesture requirements.

`EXP-156` passes the wired-device, exact clean-boundary, signing, install,
and launch gates. iPadOS correctly rejected its first unsigned copy with
`0xe800801c`; the restricted-context zero-identity result was false, and one of
two login-keychain identities matches the installed device profile. `EXP-157`'s
first `EXP-131` launch was harness-inconclusive before scene B or any Operation:
the non-navigating scenario still used the stale occurrence-source Home setup.
Its explicit per-scene Home correction passes 163/163 probe tests. The corrected
physical run then passes 24/24, and backend intake proves eight raw steps plus
four exact A→B/A→A/B→B Operations. The inferred Operation contract is accepted.
Because A was background while B was full-screen active, simultaneous on-screen
visibility remains human-gated; continue automated execution at `EXP-129`.

| Priority | Experiments | Expected outcome | Prerequisite | Implementation boundary | Acceptance | Required environment |
| --- | --- | --- | --- | --- | --- | --- |
| P0 | `EXP-100` | SwiftUI edge-pop cancel retains Detail; completion creates fresh Home | Existing transition gate | No new implementation unless hardware disproves it | Recognized gesture plus exact path/coordinator/lifecycle/view evidence | Human, physical device |
| P0 | `EXP-081` | UIKit edge-pop cancel then completed pop matches deterministic controls | `EXP-083`/`084` | UIKit transition handling | Cancel keeps UUID; completion creates fresh returned UUID | Human, physical device |
| P0 | `EXP-086`, `EXP-103` | Both windows remain simultaneously visible and complete split navigation | Prepared two-scene split scenarios | Scene/view ownership only | Both A/B chains finish with distinct IDs and exact owners | iPhone Duo or physical iPad |
| P0 | `EXP-041`, `EXP-089`, `EXP-113` | B is representative while visible A work remains A-owned; closing B does not disturb A | Exact scene registry and close driver | Action/view/lifecycle ownership | A action/Resource and post-close continuity retain A ID | Simultaneously usable windows |
| P0 | `EXP-114` | Real focus/activation handoff backgrounds the peer | Latched lifecycle driver | Probe unless SDK behavior fails | Target foreground-active, peer background, exact owner evidence | iPhone Duo or physical iPad |
| P0 | `EXP-118` | Semantic A coexists with automatic B | Target-scoped authority | Automatic predicate plus semantic SPI | B automatic view starts after B opens; neither scene suppresses or owns the other | Simultaneously usable windows |
| P0 | `EXP-129` | Same manual key exists independently in A/B and stops in reverse order | Scene-targeted manual API | Manual stack authority | Distinct Compose UUIDs; B stop never preempts A; fresh Home per scene | iPhone Duo or physical iPad |
| P0 | `EXP-131` | Inferred call-site Operations start in A and finish in B; parallel keys finish B-before-A | Accepted in `EXP-157`; simultaneous visibility follow-up remains | Raw steps and reducer | Eight raw steps and four reduced Operations with exact start/end views, without using the explicit target | PASS on two physical scenes; human Stage Manager/split arrangement for simultaneous visibility |
| P0 | `EXP-136` | One A-created request joined from B remains one A-owned Trace | Existing held request driver | Trace request-start ownership | Exactly one A/Home span, zero B owner and zero duplicate | Physical multi-window device |
| P0 | `EXP-146` lifetime follow-up | Final removal or genuine disconnect of semantic scene A cannot resurrect A, duplicate its stop, unsubscribe B, or suppress B | Deterministic reader bounce, source release, and disconnect fence pass | Run the unchanged final-removal scenario and a genuine OS disconnect/reconnect; do not replace them with posted notifications | Exact A stop, later B navigation and ownership, no A resurrection, reconnect creates a fresh occurrence | Physical multi-window iPad or iPhone Duo |
| P1 | `EXP-152` gesture follow-up | A cancelled interactive Sheet dismissal keeps the presentation occurrence; a completed native dismissal commits one fresh underlying occurrence before `onDismiss` work | Programmatic native callbacks pass in EXP-152 | Reuse the native callback harness but drive a real analog gesture; do not infer completion from callback count alone | Recognized cancellation emits no Home; recognized completion updates accepted router state, creates one fresh Home, and attributes callback work there | Human, physical iPad or iPhone Duo |
| P1 | `EXP-076`, `EXP-087` | Regular → compact → regular keeps the one-current-destination contract | Acknowledged resize control | SwiftUI/UIKit split handling | Exact geometry/selection/path/view sequence with no structural view | Resizable capable device |
| P1 | `EXP-042` | A and B restore concurrently with fresh RUM occurrences | Restoration controls from `EXP-143` | Scene lifecycle/restoration | Both native scene sessions reconnect; no stale RUM scope or cross-owner work | Physical multi-window device |
| P1 | `EXP-001` | UIKit-hosted SwiftUI parity, only if still a release requirement | Final host matrix decision | Example/probe host | Same semantic and attribution guarantees as native host | Physical device |

### Automated physical execution order

Once `EXP-156`'s connection and local-signing gates pass, use one physical-device
owner and a fresh run ID and clean boundary for each independent scenario. Run
in this order so foundational attribution failures stop dependent batches early:

1. `operations.cross-scene.lifecycle` (`EXP-131`) — accepted for inferred
   physical context and the raw/reduced Operation model; retain only its human
   simultaneous-visibility follow-up;
2. `swiftui.coexistence.same-key-manual-two-scenes` (`EXP-129`) and
   `swiftui.coexistence.semantic-a-automatic-b` (`EXP-118`) — manual authority,
   same-key isolation, and automatic sibling coexistence;
3. `swiftui.split.same-type-selection-two-scenes` (`EXP-103`),
   `uikit.split.concurrent-scenes` (`EXP-086`), and
   `windows.parallel-navigation` — SwiftUI/UIKit occurrence isolation and
   simultaneous-window navigation;
4. `windows.close-with-resource`, `windows.activation-sequence`, and
   `actions.exact-source-handoff` — peer close, focus lifecycle, actions, and
   exact owner handoff;
5. `traces.urlsession-shared-request` (`EXP-136`) — one A-created request and
   one A-owned span after B joins;
6. `swiftui.semantic-host.final-removal-isolation` — genuine final host removal
   while the peer continues;
7. the two-stage `windows.restoration` (`EXP-042`) flow, only after preserving
   and proving the required predecessor state.

The first six groups are signal-driven or deterministic and require no analog
touch when the OS can create the requested topology. A capability rejection,
failure to keep both windows usable, or inability to drive restoration is
`INCONCLUSIVE`, not an SDK failure; keep the scenario unchanged for a human or
different device. `EXP-100`, `EXP-081`, and the `EXP-152` gesture follow-up stay
human-driven because cancellation/completion must be proved from a real analog
gesture. `EXP-076`/`EXP-087` resize stays human-driven unless a physical-device
resize controller can reproduce the same OS transition and expose exact geometry
evidence.

Forward-looking hardware gates without dedicated IDs remain: genuine
disconnect/reconnect, isolated per-scene background/foreground, and the final
iPhone Duo iOS 27.1 release matrix. `EXP-039` is not in this queue because its
candidate was never constructed; it needs a deterministic harness instead.

## Release and compatibility gates

The branch is not release-ready until all applicable gates pass:

- View lifecycle: opening, navigating, hiding, restoring, and closing one scene
  never replaces another scene's current branch; navigation returns use fresh IDs.
- SwiftUI: zero-code limitations are documented; the reviewed host/adapter model
  preserves native and existing navigation code, requires zero screen and
  navigation-method edits for baseline correctness, uses automatic metadata plus
  sparse overrides, and adds no RUM code when an ordinary destination is added.
  It also handles stack, presentation, repeated routes, router mutation,
  restoration, coexistence, and cancellation without duplicates.
- UIKit: push/pop/modal/split behavior passes automatic, subclass, interactive,
  adaptive, and concurrent-window cases.
- Manual views: exact scene/key pairing, nesting, underlying navigation, duplicate
  misuse crash safety, same-key A/B isolation, and legacy source-less compatibility.
- Attribution: actions, Resources, errors, mutations, Traces, logs, WebView,
  Operations, fatal/exported context, long tasks, and vitals have evidence at the
  appropriate source/mapper/backend tier.
- Lifecycle: activation, per-scene foreground/background, disconnect/reconnect,
  restoration, session rollover, and originating-scene closure are covered.
- Compatibility: full affected module suites, package builds, lint, API surface,
  Objective-C smoke, custom/NOP conformers, single-scene runtime, and supported
  deployment targets pass.
- Performance and safety: measured event-handoff overhead is acceptable, locking
  is reentrant-safe, no SDK-caused crash, and Session Replay remains crash-safe.
- Hardware: the P0 queue and final iPhone Duo/iOS 27.1 matrix pass unchanged named
  scenarios with exact backend evidence.

Latest checkpoint: `EXP-158` run
`exp158-sim-66f922ee-19a3-4941-b8ca-c518216e6b0d` passes 9/9 locally and in
backend session `f67c75b2-e839-4701-a283-7e4355682b6a`. Explicit A and B
one-shot actions own their requested Home while a source-A legacy action and
Resource remain on representative B. The current native probe passes 164/164,
Objective-C smoke passes 8/8, the Release simulator build passes, and complete
DatadogRUM passes 1,255 test cases with zero failures. The corrected EXP-155
Operation result remains 24/24 with eight exact raw steps and four exact reduced
Operations. The corrected EXP-154 Observation result remains
25/25 with exact backend ownership. The affected SwiftUI file passes 193/193.
Xcode 27 iOS Release and visionOS package builds pass
at their relevant checkpoints. Signed EXP-158 implementation, probe, and
documentation checkpoint: `c2d1f1f9a`; earlier signed SDK semantic-navigation
checkpoint: `24cf5078a`; signed migration fixture/probe checkpoint: `7da52ae6d`; signed
EXP-152 harness checkpoint: `0a67f3e36`; signed EXP-153 harness checkpoint:
`d6d813736`; signed EXP-154 scenario checkpoint: `7fd6a891a`; signed readiness
correction: `f92d72909`; signed EXP-155 SDK, scenario, and harness checkpoints:
`b0524bb5b`, `3e567a494`, and `eb1dd2fdc`.

Physical execution checkpoint: `EXP-156` closes physical tooling. Two preflights
failed with CoreDevice disconnect error 4000,
`Network.NWError 60`, and no USB enumeration. The third proves a stable wired
iPad, repeated inventories, exact clean uninstall, and a successful `arm64`
physical build. iPadOS rejects the unsigned app with CoreDevice error 3002 /
`0xe800801c`, and final app/process inventories remain empty. A user-context
preflight then proves two valid identities, an exact certificate/profile/device
match, and strict/deep verification of a separately signed copied artifact; its
clean install and launch succeed. `EXP-157` preserves the initial stale-fixture
failure, then accepts the corrected physical Operation run at 24/24 plus eight
raw and four reduced backend Operations. Two native scenes are proven, but A was
background while B was full-screen active; simultaneous visibility remains a
human topology row. Automated execution is queued at `EXP-129` but paused while
the physical iPad is unavailable.

Earlier `EXP-146` engine/adapter explicit and optional-capability runs each pass
42/42; runtime precedence, stable reconstruction, and adversarial replacement
each pass 43/43; opaque fallback passes 5/5. The transient real-reader bounce
passes 17/17 locally and has exact backend ownership, while focused lifecycle
and handler regressions pass 84/84. The two final-host-removal simulator attempts
are infrastructure-inconclusive before removal and remain in the physical queue.
API-surface verification reports only the expected unapproved experimental
symbols and leaves both reference baselines unchanged. The current complete
DatadogRUM run passes 1,255/1,255 with zero failures. DatadogTrace remains
151/151 at its latest affected
checkpoint. Current repository lint is clean across 713 source and 699 test
files. Unaffected module suites remain valid at their recorded checkpoints but
must rerun at release freeze.

## Completed milestone ledger

| Milestone | Experiments | Result | Detailed history |
| --- | --- | --- | --- |
| Released-baseline assessment and core scene model | `EXP-001`-`020` | Per-scene view branches, downstream owner snapshots, teardown, and Operations feasibility established; baseline early-source gaps retained | [Experiment archive](Archive/EXPERIMENTS_THROUGH_EXP-142.md), [plan archive](Archive/PLAN_THROUGH_EXP-142.md) |
| Automatic SwiftUI diagnosis and early explicit boundary | `EXP-021`-`065` | Automatic discovery proved semantically late; iOS 27 route-owned occurrence state, cancellation, reconnect fencing, and customer-state-preserving identity established | Same archives |
| SwiftUI/UIKit split and causal ownership | `EXP-066`-`105` | Semantic split occurrences, UIKit structural-column handling, exact action/Resource/error/mutation/Trace routing, and retained returns established; hardware gaps isolated | Same archives |
| Deterministic probe and lifecycle driver | `EXP-106`-`114` | Named scenarios, JSONL recorder, reducer/oracle, exact scene registry, signal-driven stack/split/UIKit/lifecycle flows, and hardware routing established | Same archives |
| Automatic coexistence and manual authority | `EXP-115`-`129`, `EXP-137`-`140` | Target-local authority, underlying navigation, nesting, Sheet/cover, sibling isolation, and customer-shaped scene-targeted manual SPI pass; same-key A/B remains hardware-gated | Same archives |
| Operations, scroll, Trace, and causal boundary | `EXP-130`-`136` | Navigation-step Operations, real scroll origin, Trace request-start freezing, reverse completion, and approved source-less SwiftUI task fallback classified; cross-scene/shared rows prepared | Same archives |
| Native-convenience semantic navigation proof | `EXP-141`-`145` | Complete stack/presentation SPI, repeated equal values, restoration, external replacement/rejection/canonicalization, bidirectional presentation replacement, and actual-SPI sibling isolation pass locally and in backend intake; latest native-convenience probe/oracle `144d6e0e7` | Same archives plus [active EXP-143-145 records](Experiments/EXP-143-199.md) |
| Container-independent navigation and explicit downstream targeting | `EXP-146`-`158` | Shared navigation engine, arbitrary host, capability/explicit/opaque modes, low-cost publisher and Observation adapters, lifetime/scene fencing, value-only rejection, synchronous accepted-state timing, native dismissal callback ordering, callback-driven custom-container integration, serial native-scene isolation, and shared `.current(in:)` Operation/one-shot-action targeting are classified. EXP-158 adds exact explicit A/B action ownership plus unchanged legacy representative fallback; simultaneous-window parity remains hardware-gated | [active EXP-146-158 records](Experiments/EXP-143-199.md) |

## Deferred and explicitly out of scope

- [Deferred single-scene extraction](DEFERRED_SINGLE_SCENE_EXTRACTION.md) starts
  only after the multi-scene freeze gate.
- Simultaneous multi-pane/tab destinations need a broader RUM model; this project
  deliberately keeps one current destination per scene.
- Window Execution Context serialization and backend visualization are separate
  work. This branch preserves the internal ownership seam only.
- Full Session Replay multi-scene correctness is out of scope; crash safety is in.
- iOS 15/16 semantic multi-scene behavior is not required if it compromises the
  iOS 27+ solution.
- Rewritten-request header/capture misuse is a developer error and is not a
  robustness target for this project.
- Profiling remains process-level; document that boundary rather than inventing
  per-scene semantics.
- Stable public API names, overload breadth, and Objective-C Release exposure are
  review outcomes. Do not expose internal RUM UUIDs or add view handles now.
- The canonical overview now measures 1,047 lines, 10,299 words, and 77,848
  bytes after the necessary routing/current-checkpoint corrections. Schedule a
  separate deduplication pass; do not mix it into this lossless hot-document
  compaction.

## Evidence routing

- Current support: [ASSESSMENT.md](ASSESSMENT.md)
- Experiment lookup: [EXPERIMENTS.md](EXPERIMENTS.md)
- New detailed records: [Experiments/EXP-143-199.md](Experiments/EXP-143-199.md)
- Rejected paths: [REJECTED_APPROACHES.md](REJECTED_APPROACHES.md)
- Tool workflow: [TOOLING_RUNBOOK.md](TOOLING_RUNBOOK.md)
- Frozen plan: [Archive/PLAN_THROUGH_EXP-142.md](Archive/PLAN_THROUGH_EXP-142.md)
