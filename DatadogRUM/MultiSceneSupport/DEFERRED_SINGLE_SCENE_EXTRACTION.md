# Single-scene reliability extraction

Status: active stage S1. The filename is retained for existing links; extraction
no longer waits for multi-scene completion or freeze. The user approved independent
reliability releases, SDK27 single-scene Duo readiness by October 16, 2026, and
full multi-scene support afterward. The [gate register](release-gates.json) owns
all scope, dependencies, status and release applicability; [PLAN](PLAN.md) renders it.

## Entry and eligibility

Preserve `valpertui/multiple-windows-scenes` as the source/evidence reference.
Use isolated clean checkouts from then-current `develop`, verified remotely and
recorded before each candidate. Do not copy protected local configuration into
those checkouts. The current checkout and both user-owned dirty paths stay intact.

Each candidate must first have an ordinary source-less single-scene regression
that fails current develop and passes its narrow fix. A repaired defect introduced
only by this experimental branch is not an existing-customer fix. Scene-targeted
tests and improved aggregate counts do not establish generic eligibility.
No blanket cherry-picking, branch-history reconstruction or scene-router transplant.
Keep unrelated upstream changes, including platform-specific behavior.

## Fixed candidate queue

| Gate | Smallest useful invariant | Source boundary / decisive discriminator |
| --- | --- | --- |
| E01 | URLSession request mutation and lifecycle happen once per task | First candidate. Synchronized task preparation plus internal resume continuation forwarding, callback buffering and weak terminal state. Repeated and suspend/resume calls, automatic/registered/dual instrumentation, completion cleanup and post-completion resume controls. Count handler mutation separately from lifecycle-start deduplication. |
| E02 | Retained old view cannot absorb a later occurrence | Retain H1 with pending Resource, navigate Detail → H2, assert H1 start/stop attributes unchanged, H1 Resource and H2 action isolation, one active restored occurrence. New Home UUIDs alone already work upstream. |
| E03 | Completion affects only its Resource owner | Reimplement by existing resourceKey; late success/error/metrics cannot increment another view's action/error_tap. Preserve ordinary same-view processing and clock-driven expiration. |
| E04 | Long-lived native view remains a valid delayed WebView container | A lone active lookup does not reproduce the upstream bug: insert B after long-lived A, then deliver a delayed A browser event. Verify inactive retention window, session release, capacity and newest-first lookup. |
| E05 | Conditional request-time Trace ownership | Only after generic red evidence and a bounded implementation using existing NetworkContext.rumContext. Reverse completion and explicit nil start retain original context; headers/sampling/user/account behavior remain unchanged. |

Historical mixed commits (`bf37a2e99`, `ea787a35a`, `a6cd5df60`, `ff37d7154`,
`dbb68ccae`) are source pointers, not extraction units. Scene-aware Logs,
UI-event/TaskLocal handoff, command targets, scene buckets, semantic authority,
cross-window Operations and scene-specific crash/lifecycle routing stay in S3.

The initial audit proposed a one-file E01 slice. EXP-197 now proves the generic
mutation-count regression red on current develop and real17.5 execution. Independent
review rejects a simple claim flag: concurrent/reentrant native resume can outrun
preparation and early completion can be lost. The bounded three-file internal
continuation/preparation repair was explicitly approved for local implementation
and testing after the automatic review rejection. Signed464af911 passes the full
Internal suite and paired17.5 ordinary/legacy matrix. E01/F07 and the bounded S1
compatibility gates close; affected consumers, performance and release checks remain
required. Duplicate resumes during preparation are forwarded later on the
preparation thread; no arbitrary same-stack/thread transparency is claimed. E02/E03's existing
scene-targeted tests require separate generic reproducers. E04's corrected delayed
container hypothesis and E05's limited writer boundary remain qualification work.
The audit also found upstream macOS click/errorClick handling absent from the
reference branch; never overwrite it with the older tap-only implementation.

## Candidate and release validation

F07 must enumerate the actual production diff, transitive dependencies and changed
customer behavior before choosing tests. Prove deferred behavior is absent from
the shipped artifact: hiding experimental APIs or setting a scene manifest flag
is insufficient. The experimental branch reads the multiple-scene manifest even
with one live window and registers some scene lifecycle paths unconditionally.
Stage S2 therefore starts from develop plus individually admitted reliability and
SDK27 compatibility slices. It depends only on the S1 fixes it needs.

Run the reproducer red on the frozen baseline, apply the smallest fix, then green
plus relevant automatic/delegate, module and ordinary native controls. Freeze the
candidate's F03 platform/Swift/Objective-C/build/API/lint inventory; preserve crash
safety, privacy/wire compatibility, ownership and original performance/retention
thresholds. Do not run device measurements concurrently with builds or tests.
Compatibility checks follow the shipped modules; unrelated new scene APIs do not
block S1/S2. S1:C06 passes deployment15 and actual17.5(21F79) candidate coverage;
S2/S3 still require their own frozen candidate matrix.
Only a bounded genuine failure permits the documented S1/S2 runtime exception,
with deployment15 compile/link, availability review and oldest runnable coverage.

Use the existing Datadog app's single-scene integration as additional evaluation,
with dedicated automatic fixtures retained. [Human acceptance](HUMAN_ACCEPTANCE.md)
owns the prepared session and internal TestFlight step; no upload is authorized.

## History and delivery

Keep each candidate independent and reviewable. Use repository branch conventions,
explicit path-limited commits, signing when available and the authorized unsigned
local fallback otherwise. Never read/log/hash/stage the protected local xcconfig,
never use commit -a, and never push/merge/publish without separate authorization.
Do not invent ticket numbers. Local qualification can use descriptive chore branches;
resolve normal issue/review metadata before delivery.

Record baseline/candidate commits, red/green evidence, exact scope exclusions and
applicable S1:F06 review. Report independent readiness; E02-E05 and all S3 gates do
not delay a ready E01 patch. Reconstruct or rebase the multi-scene stack only when
its dependency audit calls for it, preserving the original branch and comparing
production source against the delivered base.
