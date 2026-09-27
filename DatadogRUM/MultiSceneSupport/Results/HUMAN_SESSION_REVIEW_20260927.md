# Future human-session review

**The scoped repair loop is complete; native qualification is still pending.**
The [repair record](human-harness-repair-loop-20260927.json) owns the four review
cycles,262 offline controls, three passive-observer builds and successful replay of
the saved physical capture. No actionable scoped finding remains. The
[input index](S2-input-session-preparation.json) routes to the current preparations;
fresh package prerequisites precede the first needed native cell. No SDK gate closed.

The findings below describe the original reviewed state. Their reproductions and
all original verdicts are preserved. A later full-object metadata comparison also
rejected valid View/Action schema differences; the repaired collector compares
shared stable ownership fields. S3 now has an explicit reviewed human-setup wrapper;
the residual S3 gesture matrix remains unprepared. These were harness findings,
not evidence of an SDK regression.

Reviewed at SDK workspace `621b7f12`, using the exact frozen coverage, physical
candidate and Resource/Trace runners named in the
[review record](human-session-review-20260927.json). Five findings have six offline
reproductions; no device, build, SDK suite or backend query ran. The designated
reviewer independently checked all five findings and the S3 setup limits.
Existing accepted evidence and all original failures remain unchanged.

## Findings

### HUMAN-01 — P1: failure cleanup can terminate a held gesture

Automatic coverage calls cleanup after host-worker quiescence, even when a human
step fails. The shared cleanup unconditionally terminates and uninstalls the task
app; there is no human-release or native-idle fence. A held gesture can therefore be interrupted by harness cleanup, producing an
apparent app crash.

Source: [coverage cleanup](../../../tools/multi-scene/automatic-coverage/human_runtime.py#L377),
[shared teardown](../../../tools/multi-scene/acceptance/s2_webview_driver.py#L165).
The offline spy runs the actual frozen cleanup with scenario `INVALID` and no
release/idle evidence: it issues both operations and reports no cleanup error.

**Repair before coverage admission:** retire the prompt, require a request-bound
release acknowledgement and fresh native idle proof, then remove only the task app.
If proof is unavailable, preserve the app and record incomplete cleanup. Reuse the
physical fence semantics. Decisive controls must show zero teardown calls for a
held gesture, missing/late release, failed idle capture and replaced process.

### HUMAN-02 — P1: delayed callback actions fail before the relaxed oracle

The physical collector waits for native transition completion, sleeps 1.2 seconds,
takes one effect snapshot and immediately requires the mapped callback action.
An action arriving after that snapshot fails as missing. The newer rule making
mapper-before-callback timing diagnostic is reached too late to prevent this.

Source: [physical interactive collector](../../../tools/multi-scene/interactive-transitions/physical_capture.py#L146),
[callback lookup](../../../tools/multi-scene/interactive-transitions/transition_contract.py#L117),
[scoped semantics](../../../tools/multi-scene/interactive-transitions/s2_local_contract.py#L15).
Reordering only the real saved callback action after its first effect snapshot
rejects the prefix; the same action in the later complete inventory qualifies.
A foreign-owner mutation still rejects.

**Repair before the one candidate session:** preserve the native effect boundary,
then collect callback work by its exact identity within the predeclared collection
budget. Join its owner against the captured before/after occurrences. Do not ask
for another gesture or demand that emission fall inside a fixed settling interval.
Missing, duplicate, wrong-owner and pre-completion callback events must still reject.

### HUMAN-03 — P1: Home checkpoint is mistaken for telemetry completion

Automatic coverage makes a writer checkpoint 1.2 seconds after Home and requires the
entire event file to equal that prefix. A valid later mapper event therefore
invalidates capture. Physical collection also checks that every View is inactive
immediately from its Home prefix, before its later local collection step. Its
background task protects the writer from suspension; it does not drain the SDK queue.

Source: [coverage checkpoint](../../../tools/multi-scene/automatic-coverage/human_variant.py#L34),
[EOF assertion](../../../tools/multi-scene/automatic-coverage/human_runtime.py#L367),
[physical Home](../../../tools/multi-scene/interactive-transitions/physical_capture.py#L178),
[early inventory check](../../../tools/multi-scene/interactive-transitions/physical_runtime.py#L227).
Offline controls retain a valid committed prefix, append the same-owner inactive
View and reproduce the coverage rejection. Delaying only the last inactive View
in the accepted physical behavioral stream also rejects; the full stream qualifies.

**Repair before either package:** record native Home once, retain its immutable
behavioral cutoff, and collect the finite required View/action inventory separately.
A writer checkpoint proves its bytes, not that future mapper work is impossible.
Preserve/classify later rows and seal only after required semantic evidence is present.
No immediate upload, synthetic Background view, session expiry or forced flush is
required. Missing evidence at the collection limit remains incomplete, not an SDK
regression and not a reason to repeat valid gestures.

### HUMAN-04 — P2: indexing growth aborts the fold backend exchange

The prepared Resource/Trace connector polls until COUNT reaches a minimum, then
fetches pages against that one count. A search containing more rows than that count
aborts the exchange; the outer handler publishes an error. It never retries a
complete inconsistent snapshot within the remaining collection budget. This is the
same class of changing-index failure retained in the
[F08 record](S2-F08-candidate-comparison.json), where later collection qualified the
saved behavior without repeating gestures.

Source: the frozen `resource-fold/runtime/generated/connector.js`, lines 18–65 and
98–104, and its bound `backend_adapter.py`, lines 97–108 and 149–165; exact paths and
hashes are in the review record. A tool-double control executes that actual gather
function with modeled indexing growth: COUNT 12/search 12 publishes, COUNT 12/search 13
aborts. No live backend growth or MCP request was measured by this control.

**Repair before fold admission:** preserve every raw exchange and use a bounded
full-inventory retry for indexing changes. Keep malformed, foreign, conflicting or
truncated evidence rejected. Never blindly deduplicate or restart the original
clock. If collection remains incomplete, retain valid local behavior for a separately
admitted backend-only continuation; human gestures need not repeat.

### HUMAN-05 — P2: advertised short sittings do not execute the S2 matrix

The current preparation is `AUTOMATIC_S2_RUNTIME`, containing twelve cells ordered
in 26.5-baseline/27.1-baseline/27.1-candidate triplets. The sitting scheduler only
supports the older `AUTOMATIC_HUMAN_SESSION` kind and adjacent baseline/candidate
pairs. The current runner bypasses its series claims and session finish path.
Passing the first S2 triplet to the existing selector rejects it as a split source
pair. The reviewed matrix asks for at least 396 prompted steps (33 per cell), plus
any Sidebar reveal or display restoration; it must not be presented as one short visit.

Source: [S2 kind/matrix](../../../tools/multi-scene/automatic-coverage/human_runtime.py#L60),
[legacy selector](../../../tools/multi-scene/automatic-coverage/human_sessions.py#L106),
[run/finish dispatch](../../../tools/multi-scene/automatic-coverage/human_runtime.py#L481).

**Repair before coverage admission:** support a finite S2 sitting with an explicit
selected subset and verified predecessors, preserving rebuild and SDK comparisons.
Test the actual prepared plan through pause, safe cleanup and a fresh continuation,
including stale readiness, a failed prior cell and duplicate claims. No accepted
cell may be rerun or assigned a renewed deadline.

## Scenario and admission decisions

| Package | Useful remaining human work | Before inviting the operator |
| --- | --- | --- |
| Automatic coverage — C07–C10/H14 | Twelve frozen source/build cells; ordinary tap/toggle/scroll/navigation and real Duo folds. Keep UIKit/SwiftUI View and Action conclusions separate and retain inherited omissions. | Close HUMAN-01/03/05. Select a bounded sitting; state its actual steps and require its page to be visible before starting. First planned baseline qualifies the input path. |
| Physical UIKit candidate — H11/H13 | One candidate only: four real cancel/finish transitions, six setup/return taps and Home. Reuse the accepted baseline. | Close HUMAN-02/03; retain the already-present failure release/idle guard and native coordinator/source checks. No baseline, SwiftUI or Home-only repeat. |
| Resource/Trace fold — T03/T08 | Four cells, two display changes each; held requests retain captured owners, metrics and trace correlation. Reuse navigation/rollover evidence. | Close HUMAN-04 and bind direct prompt publication/readiness. The current connector only forwards `human_input` through tool notifications; the operator page/acknowledgement is not integrated. Complete backend/auth preflight before asking the operator to wait. |
| S3 same-key setup — F03 M02/M03 | Human arrangement of concurrent windows, then automatic same-key operations; fresh release/idle proof before cleanup. | Bind a reviewed native wrapper selecting `human_setup=True` and `qualification=same_key_contract`, product/device identity and prompt delivery. The prepared CLI only exposes automatic execution. No equivalent automatic activation retry. |
| Residual S3 gesture matrix | Only combinations still missing after source/gate mapping. | No complete frozen executable session was supplied for this residual matrix; it is not ready for an invitation. Do not infer it from the same-key setup build. |

The S3 setup's 300-second API budget starts after validated setup readiness. Review
found no evidence that this automatic four-checkpoint bound is too short. Add a
late-checkpoint/cleanup control to its native wrapper; do not turn it into a gesture
timing test. Root-issued request-bound Ready/Released receipts are acceptable; their
free-text message field is not an end-user web command.

## Repair order and completion standard

Root owns repairs; `/root/c06_runtime_plan` reviews the consequential changes.
First fix release/idle safety and shared semantic collection (HUMAN-01–03), then
backend collection and S2 sitting selection (HUMAN-04/05), then finish the two prompt/
wrapper bindings. These are A02 execution prerequisites for existing gates, not new
release gates or numbered experiments. No SDK change is justified by this review.

Before another invitation, run the changed **actual prepared runner** end to end
with an in-process native/backend double: prompt delivered, gesture once, delayed
mapper, delayed/overlapping backend pages, Home, held-input failure and cleanup.
Retain all raw observations; wrong owners, stale run/request IDs, duplicate callback
work and absent required events must remain distinguishable. Refresh only changed
helper/fixture bindings, use the first needed native cell for mechanism qualification,
and preserve every accepted source/build/behavioral result. A green mocked run is
preparation evidence only.

The operator should see one unambiguous instruction and an explicit waiting state
after capture. Preparation and collection time must not consume a hidden gesture
window. Fixed operational limits still bound work and cleanup; if a limit expires,
stop safely and preserve what was captured. Do not promise a duration using the
maximum backend reservation or require the person to wait through backend polling.
