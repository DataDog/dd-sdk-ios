# S1 delivery sequence

Activated at the completed EXP-213 checkpoint on 2026-09-20.

## Outcome and authority

Deliver six independent customer fixes (E01–E05 and the display-link lifetime fix) in separate reviewable PRs, plus one test-only prerequisite PR. Start review of the qualified S1 work before further S2/S3 expansion. E03 has a signed, qualified repair and completed compatibility execution; full Replay still needs a maintainer-owned inherited-fixture correction or waiver. E01's five missing hostless checks now pass. DL01's seven remaining hostless suites and full Integration now pass with recorded skips/warnings. E02 now also passes its eight missing hostless suites, full Integration and twelve platform builds. E04's eight missing hostless suites, full Integration279/279 and twelve platform builds also pass. E05's two registered ownership additions pass within full Integration282/282, with three genuine delegate callback receipts and independent acceptance. After the reviewed Core fixture correction, all eight missing hostless suites pass2,768 executions/five predefined skips, and all twelve platform builds pass144 architecture source lists. Two backend mode cells remain open after preserved fixture failures and a budget stop; the corrected fixture is reviewed and compile-qualified but unlaunched. The paired inherited Replay diagnostic is next. S2 expansion stays paused.

This document prepares delivery; it does not perform or authorize a push, remote PR creation, merge, or change to an active experiment. Read `AGENTS.md` and `.continue-here.md` first when executing. The current experiment remains authoritative for its in-flight work. This delivery sequence applies after its safe checkpoint and incorporates the user's subsequent priority for S1 review. Preserve all experiment results, including inconclusive or failed controls.

[Structured queue](Results/S1-delivery-queue.json) contains exact source commits, paths, evidence, owners and remaining gates. It is input for the main session, not an installed automation. [release-gates.json](release-gates.json) remains the release qualification authority. Neither new artifact closes a gate.

The packet baseline is authenticated develop `62f64d7b`; clean S2 qualification `ef9d9732` remains separate. The [H00/E01 packets](Results/S1-H00-E01-packets.json) have signed local delivery commits. H00 and the initial E01 commit match their qualified trees; E01 then changes only five verification fields to a reachable parent, with all feature docs passing. Ticket metadata, missing repository-wide checks, CI/review and publication remain pending. [EXP-214](Experiments/EXP-214-resource-action-design.md) now owns the signed E03 terminal repair, its qualified owner contract and remaining compatibility checks. [DL01/E02/E04/E05 packets](Results/S1-independent-packets.json) have independent delivery histories. E05 adds local test-only commits after recorded signing timeouts; all outgoing history requires signing before separately authorized publication. DL01's standalone Core/RUM suites and twelve affected-platform build cells pass; each packet enumerates remaining iOS/platform checks and candidate-specific gaps. No publication or merge has occurred. DL01 was extracted from its immutable two-file source, not the combined S2 HEAD.

## Review units and dependency order

Every row is a separate PR. H00 and DL01 are local delivery identifiers, not new release gates. Owner for local preparation/qualification is the main session acting as SDK implementer; accountable review owners are the current RUM maintainers, presently `@DataDog/rum-mobile` and `@DataDog/rum-mobile-ios`. Recheck CODEOWNERS and assign a real ticket and human reviewer before publication; no ticket is supplied by this plan.

| PR | Customer change | Current evidence | PR base / hard dependency |
| --- | --- | --- | --- |
| H00 | Correct full/delta view-hitch assertions | Qualified test-only correction | develop; no dependency |
| E01 | Prepare URLSession instrumentation once per task | Its 15 prerequisite gates qualified; F06 still open | May stack on H00 for review; H00 must merge before E01 final delivery |
| DL01 | Release display-link observers with their owner | Separate signed extraction, full Core/RUM and twelve platform builds pass; remaining repository checks | develop; no E01/E04 dependency established |
| E02 | Isolate attributes between repeated view occurrences | Generic regression and native serialization qualified; release checks remain | develop |
| E04 | Retain delayed WebView correlation through native-view inactivity | Generic regression, full RUM and native bridge pair qualified; release checks remain | develop |
| E05 | Preserve request-time RUM ownership in automatic traces | Generic regression, full Trace and native header/span pair qualified; release checks remain | develop |
| E03 | Keep late Resource completions from changing another view's action | Signed compatible repair and owner contract qualified; candidate release checks remain | develop; no hard merge dependency |

Only H00 → E01 is a hard merge edge. Shared test files and changelog conflicts are not architecture dependencies. E03 may merge whenever ready; the table does not force it to land last.

1. Safely finish/checkpoint the current experiment and capture current source/worktree identities.
2. Prepare H00 and E01 local review packets immediately. E01 can be reviewed against H00's delivery branch without waiting for its merge.
3. Complete E03-D candidate compatibility and delivery preparation before starting another S2/S3 expansion experiment. Do not postpone this until all other S1 PRs merge.
4. While review/CI is pending, prepare DL01, E02, E04 and E05 in that default order, filling only missing or invalidated qualification. Start each review as its packet becomes ready; E03 and S2/S3 are not global blockers.
5. Merge authorized, approved, green PRs as they become ready. Default independent order is H00, E01, DL01, E02, E04, E05; insert E03 when qualified. Review availability may change independent ordering.
6. Recompose S2 from actual merged develop fixes, retaining only its still-unmerged S2-specific work. Verify source identity and invalidated checks before using the composed artifact. S3 remains separate.

There is no requirement to wait for physical Duo hardware, new scene APIs, or the broad S2/S3 review to publish these S1 fixes.

## Why E03 is open, and what happens next

[EXP-206](Experiments/EXP-206-resource-action-ownership.md) reproduced late Resource success/error changing a different view's live action counts and `error_tap`. Resource/error view and session UUIDs themselves remained correct.

The earlier stateless proposal was rejected under the then-required automatic success/error pair: success removed the key before the following error. That automatic premise is superseded by the approved failed-transfer Error outcome. Its historical evidence and manual compatibility witness remain unchanged. Admission now requires tracked ownership before action mutation, including the original unannotated foreign-owner controls, while preserving unknown/repeated manual behavior. An automatic-only filter does not close those controls. No token or completed-key history is required solely for the retired automatic pair.

E03 is now an explicit, finite repair path:

| Step | Deliverable / owner | Decisive exit | Environment / dependency |
| --- | --- | --- | --- |
| E03-A | Main implementer proposes one internal ownership design; maintainer reviews it | Contract table resolves native and manual command sequences, action transitions, key reuse/generations, cross-core isolation, session expiry, queue confinement and cleanup. No silent behavior change or assumed-compatible ledger. | Source/design review; preserve original red proof |
| E03-B | Main implementer freezes source paths and regression inventory | Original nine bodies/evidence remain intact; the ninth's automatic acceptance role is explicitly superseded by the user decision. Freeze actual-handler/native failed-body, successful/empty-response and lifetime discriminators before implementation. Reviewer accepts the bounded design or records the exact unresolved contract decision. | Isolated develop checkout; depends on A |
| E03-C | Main implementer implements the admitted repair | Four ownership reds become green; four ordinary/expiry controls remain green. Automatic failed transfer yields Error1/Resource0/action0:1; unchanged historical manual behavior and admitted native/lifetime controls pass. | Affected RUM unit/native fixtures on supported available runtime; depends on B |
| E03-D | Main implementer prepares PR; maintainers qualify/review | Candidate compatibility, docs, required CI, signed outgoing history and human review complete; independent PR is ready to land. | Exact delivery source; depends on C |

The [existing token/ledger proposal](Results/EXP-206-ownership-design-review.json) remains historical review input, not an approved implementation. The user has since approved error-first failed-transfer semantics; a token/ledger solely for the retired automatic dual terminal is no longer required. If design admission fails, state the exact missing contract and next decision at that checkpoint, then continue other S1 delivery work. Do not silently substitute another S2 expansion task for resolving it.

Freeze these additional discriminator families, with exact method names and expected counts, before C:

- Actual URLSession handler with nonnil response plus error, in the owning view and after navigation/session stop.
- Stop/start an action between success and error; preserve legitimate current-action behavior within the owning view without adopting a foreign view.
- Start Resource before action; preserve completion during that action, mapper/drop behavior and clock-driven expiration.
- Manual/unannotated response-plus-error, including action transitions; make any ambiguity an explicit contract decision.
- Unknown/repeated keys, legal key reuse and separate SDK cores; no global tombstone or guessed generation.
- Delayed queue work, action/session expiry and SDK deinitialization; no new retained owner chain or unbounded historical-key lifetime.

The [approved Resource-completion decision](E03_RESOURCE_COMPLETION_DECISION.md) supersedes the ninth control only as automatic failed-transfer acceptance: require one owning network Error, zero completed Resources and controlled active-action resource/error counts0/1, preserving received status. Keep the original ninth body/baseline as historical manual-sequence evidence and the other eight controls, including both100ms expiry boundaries. Successful bodies and legitimate empty HEAD/204 responses remain Resources. The earlier manual-compatibility question is separate; the user has not approved unrelated repeated-stop/key-reuse changes. Define exact actual-handler/native controls before implementation.

## Exact extraction and PR content

The queue is the executable path/commit inventory. Paths below describe the review boundaries, not permission to include whole worktrees.

### H00 — hitch assertions

- Source `valpertui/rum-view-hitch-assertions`, commit `d98f3540a5cf445844c2547378e05cffd2212dbd`.
- Only `Datadog/IntegrationUnitTests/RUM/RUMViewHitchesIntegration_Tests.swift`.
- Reconstruct full/delta documents by documentVersion. Missing fields retain state; explicit empty values clear it.
- Test-only PR: no production change and no user-facing changelog required.
- Use the paired evidence in [EXP-201](Experiments/EXP-201-final-compatibility.md). E01's equivalent `925b9326` commit must not appear as a second fix in its own review delta.

### E01 — URLSession exactly-once

- Qualified HEAD `652ce169773b0be5b6767179eca8ab5f4cf25f8a`; production `1bdc9286c17d69d73e5e41530e6179c72a723368`.
- Three internal networking files, two Internal test files, changelog and the five already affected feature documents. Exact commits and paths are in the queue.
- Preserve request preparation synchronization, native resume continuations, early callback buffering and weak terminal cleanup together. A claim flag alone is not this fix.
- Reuse accepted full affected suites, 278/278 integration tests, platform/client/API checks, failure/cancellation/reentrancy controls and the [four-cell backend qualification](Experiments/EXP-202-urlsession-backend.md) where their source identities still match.
- Five additional hostless suites now pass 544 tests with one predefined watchOS-only skip. Full Replay still requires its inherited fixture disposition and candidate qualification; no full-iOS pass is claimed.
- Remaining delivery: H00 upstream, verified rebase, candidate-specific F06 review, signatures and current required CI. The “15/16” score is E01 only.
- State the timing limitation: a duplicate resume during preparation can be forwarded later on the preparation thread. Preserve the inherited QoS-warning evidence without claiming harmlessness or new performance clearance.

### DL01 — display-link lifetime

- Extract only commit `a4be961d14c77c9a7787c9bfb55398784022d0f9` from the live `valpertui/s2-rum-lifetime` worktree into a fresh develop-based delivery checkout.
- Only `DatadogRUM/Sources/RUMVitals/RenderLoop/RenderLoopObserver.swift` and `DatadogCore/Tests/Datadog/RUM/RUMVitals/DisplayLinkerTests.swift`, plus its own changelog/affected feature document.
- Private weak callback target breaks the real CADisplayLink target cycle. Preserve frame forwarding, invalidation and existing AppKit/NOP/conditional branches.
- [EXP-211](Experiments/EXP-211-s2-lifetime.md) supplies eight accepted D2 tests and one corrected D4 release witness after actual pending MessageBus work drains. It reproduced on ordinary iPad iOS17.5; Duo is not required.
- The two-file extraction is independent of E01/E04. Standalone Core/RUM, seven additional hostless suites and twelve platform build cells pass. Full Integration278/278 passes on a test-only H00 composition with eight preserved QoS warnings; Replay remains pending its inherited fixture prerequisite and candidate-specific qualification. Do not import the combined S2 branch or later host-lifetime experiment.
- This establishes focused observer release, not global lifetime clearance or continuous growth in an initialize-once app.

### E02 — repeated view occurrence

- Source HEAD `96d064c4fa083a7a74c709eb4a626fc17017db01`; production `3ce541b325217188c181458d223ff2a3f1f78d49`.
- Two predicates in `RUMViewScope.swift`, two RUM scope-test files and two public-monitor integration files.
- [EXP-205](Experiments/EXP-205-view-occurrence-isolation.md): two baseline unit reds; full RUM 903 cases / 939 executions; paired native serialization two baseline failures versus 2/2 green.
- Decisive behavior: pending H1 Resource retains H1; Detail → H2 cannot mutate H1's attributes; H2 action remains on H2; restoration produces one active occurrence.
- The independent packet now adds eight full iOS suites (1,972 passes/five predefined skips), Integration280/280 with eight preserved QoS warnings, and twelve platform builds/144 complete architecture source lists. Full Replay and delivery review remain; changelog/docs are prepared. Native writer evidence does not establish backend ingestion or actual UIKit callback behavior.

### E04 — native WebView cache lifetime

- Source HEAD `a3d34069cccbe35cac0fd2bc1fb456e64b1f4c43`; production `cc83c8503ff42d8ed2b7e8c5c1bc1419e061727d`.
- `RUMSessionScope.swift` and `ViewCache.swift`, with three test files.
- [EXP-207](Experiments/EXP-207-active-view-cache.md): active entries persist; first inactivity starts TTL; repeated deactivation does not reset it. Preserve session stop/timeout/max-duration/restoration, capacity 30, ordering and Replay behavior.
- Full RUM 910 cases / 946 executions and paired native bridge 3/3 green are eligibility evidence. Injected messages/writer JSON do not claim real-browser/backend validation.
- The [changed-path lifetime review](Results/S1-E04-lifetime-disposition.json) maps every E04 teardown/restoration edge to accepted EXP207 controls; no additional host/Resource lifetime run is required for this scalar cache change. The missing iOS suites, Integration279/279 and twelve platform builds pass; full Replay and delivery review stay open. [EXP-212 composition](Experiments/EXP-212-cache-composition.md) is useful additional evidence, not a substitute for E04's own freeze. Old numerical-microbenchmark prerequisites are superseded by the current acceptance scope.

### E05 — request-time Trace ownership

- Source HEAD `9254adbcbf5a1809219ec30f6cc07df4f3af4518`; production `f270c375c74a79b69343de19e78dc2698fd7ee91`.
- Three Trace implementation files, one Trace unit-test file, one Core header-compatibility fixture and one public network integration file.
- Capture existing optional NetworkContext RUM ownership at start and use it for automatic span/baggage correlation. Explicit nil must not adopt a later view; preserve legacy fallback when capture is unavailable.
- [EXP-208](Experiments/EXP-208-trace-ownership.md): full Trace 154 passes and native 3/3 green; the initial header-preservation regression and its narrow correction remain documented.
- The [finite release admission](Results/S1-E05-release-admission.json) reuses EXP208 completion-guard/cancellation and value-only lifetime evidence after independent review. Two registered ownership/nil cases now pass within Integration282/282 with three real data/metrics/completion receipts and independent acceptance. Two candidate backend mode cells remain, with exact fixture/oracle/count/deadline admission required before execution. All eight missing hostless suites and twelve platform builds now qualify. Full Replay and human delivery checks remain separate.
- Do not absorb broader PR2683 header-merge/partial-carrier policy. Existing native qualification used automatic Trace with automatic RUM Resources disabled; it does not establish every networking configuration.

### E03 — Resource action ownership

- Existing worktree is still at develop `62f64d7b` with only two dirty reproducer test files. Preserve it and the durable [baseline patch](Results/EXP-206-baseline-reproduction.patch).
- E03-A/B are complete. The [local packet](Results/S1-E03-packet.json) has signed repair562cf74dd and documentation385583bf4 after full RUM925/961 and nine native XCTest passes. The exact owner contract qualifies with an inherited stopped-session diagnostic retained. E03-C is complete with source-reviewed metric/expiry preservation; E03-D has twelve passing platform builds and eleven executed iOS schemes. Full Replay remains unqualified because its private scroll-pocket fixture fails identically on unchanged develop. The packet names its maintainer owner, dependency, decisive full-suite test and clean iPhone26.5 environment. Resolve that correction or scoped waiver before E03 release-review sign-off; continue independent E01 checks meanwhile. Global Trace-document drift, real ticket, CI and human review stay open.
- Proposed PR title remains provisional until the implemented contract is reviewed. The fix must preserve current action semantics within the Resource's owning view, not blindly attach every callback to the action that existed at Resource start.

## Repeatable execution procedure

### 1. Checkpoint and inventory

Read current restart instructions; rediscover worktrees, branches, HEADs and actual tool/runtime availability. Check signatures without changing Git state. Capture opaque identity/status for protected dirty paths without logging their contents. Do not reuse temporary paths, simulator IDs, MCP workspace IDs or authentication sessions.

Keep the original evidence worktrees and production reference `04201edc7711361279d8487b385bc8b0ca9c63c7`. Use separate delivery checkouts and the repository's real-ticket branch convention; retain the original source branches and evidence worktrees. Reuse a previously created delivery checkout only after verifying its recorded identity and that it is inactive. Never reset, clean, stash or amend another active worktree.

Define a candidate-scoped release inventory before running new checks. An unrelated inconclusive EXP-213 host-lifetime witness is not automatically an S1-wide blocker. A demonstrated regression on an included candidate is a blocker for that candidate and must retain its evidence.

### 2. Construct each delivery diff

Use the queue's selected commits as source pointers. Inspect each diff against freshly verified develop or the approved stack parent. Do not blanket cherry-pick a branch. Preserve unrelated upstream code, especially platform-specific branches absent from the old experimental source.

Each product PR has a strict existing-code/test allowlist and separately listed changelog/feature-doc additions. Preserve public APIs, wire formats and endpoints; add no dependencies, generated-model changes or unrelated build-script changes. Keep planning documents, experiment ledgers, raw fixtures, local configuration and unrelated project edits out of product PRs. Freeze any newly needed path before editing; incidental shared-file conflicts do not authorize unrelated cleanup.

Use explicit paths for staging and committing, never `git add .`, broad directory staging or `git commit -a`. Sign directly when available; the user's local unsigned fallback applies only when unavailable. Every outgoing commit must be signed before any authorized push. If re-signing/rewording is needed, do it in the delivery checkout and retain a source-identity mapping to the qualified commits.

### 3. Bind evidence and fill finite gaps

For every PR record: baseline, delivery HEAD, production/test path hashes, dependency pins, toolchain/runtime/build identity, test inventory, pass/fail/skip counts, durable artifacts, source review, current CI and signatures.

Use [FINAL_COMPATIBILITY.md](FINAL_COMPATIBILITY.md) to freeze applicable platform, Swift/Objective-C, API, lint and documentation checks for that candidate. Do not apply an old experimental branch's platform matrix to newer develop. Deployment iOS15 remains a compile/link/availability obligation; actual older-runtime execution uses the available supported runtime such as iOS17.5, not an unavailable iOS15 debugger.

Repository PR instructions require lint and the full iOS test check (`make test-ios-all`). Record valid source-matched results or run the missing required check; a full RUM suite is not a full iOS suite. Apply any explicit approved validation exception accurately, and keep required CI checks mandatory. Refresh feature-document verification with the repository workflow when affected; do not copy stale verification metadata.

Evidence reuse rules:

| Change | Required action |
| --- | --- |
| Ticket/message/signature only; source and dependencies unchanged | Rebind identities; no automatic test rerun |
| Equivalent H00 prerequisite arrives upstream | Verify final file/tree content and remove duplicate commit; retain accepted assertion evidence |
| Upstream/test/source/dependency/configuration changes | Identify affected assertions/builds and rerun invalidated or missing cells |
| Semantic conflict resolution or new E03 implementation | Fresh affected regression and compatibility qualification |
| Zero tests, unexpected skip or missing artifact | Incomplete evidence, never a pass |

No new standalone network, per-dispatch or allocation benchmark campaign is required for these PRs. Keep lifetime/reentrancy correctness checks. If new semantic SwiftUI or multi-scene code enters a candidate, exclude it from this S1 scope or apply its already-required application-impact acceptance gate; do not silently expand a fix. Investigate concrete customer-visible performance regressions.

### 4. Prepare a complete local publication packet

For each PR prepare a real-ticket title, outgoing commit list with signature status, exact base/head and changed paths, complete body using `.github/PULL_REQUEST_TEMPLATE.md`, validation evidence and limitations, intended human reviewer and rollback.

Lead the body with a concrete customer failure and corrected behavior. Follow with the minimum implementation explanation and validation needed to review it. Use ordinary single-scene examples; experiment numbers may link evidence but are not the PR's rationale. No assistant names or co-author tags. No unrelated new public API/Objective-C/RFC work.

Use imperative titles from the queue with a real `[PROJECT-XXXX]` prefix. Do not publish a placeholder ticket. One real ticket may cover multiple related PRs when its scope fits; this plan does not require inventing seven issues. Every outgoing commit must also carry the real ticket reference. Tests-only H00 has no customer changelog; each production fix gets its own concise entry. Mark public API checklist items not applicable only after confirming unchanged surface.

Local preparation should continue until publication is the only remaining action. If external metadata is missing, collect the real tickets/reviewer choices together while continuing independent preparation.

### 5. Publish authorized drafts and preserve narrow review diffs

This request prepares the plan only. Follow the [repository PR skill](../../.claude/skills/open-pr/SKILL.md): show the concrete outgoing commits, title and full body before obtaining the necessary publication authorization. If the user has already authorized the concrete batch, reuse that authorization rather than asking again per action. No remote push or PR is performed by this plan.

After authorization, push signed delivery history and open drafts. Search for an existing PR for the branch before creating one. Record PR URL, base/head and checks. Move to ready-for-review and request reviewers only within the authorized review-routing scope and when the packet and required checks are ready. Do not imply that opening a draft authorizes merge.

For an early E01 stack, construct its delivery branch from H00's delivery branch, then apply only the selected E01 commits. Its review diff must exclude the H00 assertion change. Label the dependency and link the parent PR.

After H00 actually merges:
1. Verify remote develop and the upstream merged content, including squash-merge equivalents.
2. Rebase E01 onto that develop revision, dropping the equivalent prerequisite.
3. Compare production/test identities and refresh only invalidated checks/doc verification.
4. Retarget E01 to develop and show the exact remaining diff.
5. Refresh CI/review requirements and update the PR body.

Do not rewrite a published branch without authorization covering that branch update. If rewriting is authorized, use a lease tied to the recorded remote HEAD, never a blind force push. No other PR is stacked unless an actual reviewed source dependency makes it necessary.

### 6. Merge, verify and update the main plan

Merge only with explicit merge authorization, passing required CI, human approval and the candidate's required gates satisfied. Batch authorization may cover multiple PRs under those conditions; never silently enable auto-merge.

Verify the actual upstream merge SHA and resulting files before reporting a PR delivered. Shared RUM scope-test files and changelog entries must retain all previously landed assertions/entries. If upstream movement creates a semantic conflict, invalidate the affected checks rather than mechanically carrying forward a green result.

At each safe checkpoint, the main session updates this queue and the authoritative release/register documentation through their existing workflow. Keep:
- qualification, draft/open/review status and merged delivery as separate facts;
- a per-candidate remaining-gate list, not a single “S1 15/16” score;
- accepted experiment evidence in its owning records, not repeated in the active plan;
- current safety-review findings updated or closed with exact source evidence;
- S2 composition provenance separate from the individual S1 PRs.

The queue fields start with publication and merge authorization false, PR URLs null and no merged claims. Only execution evidence may advance them. Suggested states are `repair_required` / `qualification_pending` → `local_packet_ready` → `draft_open` → `ci_and_review_ready` → `merged_verified`; authorization is a separate field, not something elapsed time supplies.

## Completion and handoff

Delivery is complete only when all seven PR units are merged and verified, or the user explicitly removes a unit from scope. “Eligibility qualified” is not “ready to merge.” E03's design rejection is not completion.

The first useful checkpoint is concrete H00/E01 review packets, a named E03 design/admission task, and DL01's independent extraction boundary. These allow review to begin without involving S2/S3 changes. The main session should report PRs ready/open/approved/merged and exact remaining blockers, rather than counting additional experiments.

This plan creates no remote resources and leaves every existing worktree, dirty path and active experiment untouched.
