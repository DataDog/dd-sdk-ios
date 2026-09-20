# E03 Resource completion decision

Status: user-approved product direction, recorded 2026-09-20. Implementation and runtime qualification remain pending.

This decision supersedes the automatic response-plus-error preservation requirement in the current [E03 proposal](E03_COMPLETION_CONTRACT.md), [S1 delivery plan](S1_DELIVERY_PLAN.md), [delivery queue](Results/S1-delivery-queue.json) and [EXP-214 definition](Experiments/EXP-214-resource-action-design.md). The main session owns reconciliation of those active documents. Historical EXP-206 evidence remains unchanged.

## User decision

> As a RUM User, I expect a RUM Resource to be reported first as an Error if the body was never received due to an error (not talking about empty body responses).
> A RUM Resource is Headers + body (if any), not just headers.
> If the future it would be great to find a way to report those failing resources even with status code on top of the error, but that's a followup you should document

## Current S1 / E03 contract

An HTTP response object proves that status and headers were received. Its presence alone must not cause a failed transfer to be reported as a successfully completed Resource.

For a native completion containing an HTTP response and a transport error that prevented delivery of the required body, report the failure through the existing RUM network Error path. Do not first emit a completed Resource, remove its scope, and consequently lose that Error. An additional representation of the failed request as a Resource is deferred below.

Preserve the available HTTP status and existing request/error metadata through the Error event's existing resource fields. That does not require the deferred additional Resource event or a new schema.

Do not classify failure by empty Data, zero received bytes, a missing size field or status code alone. Valid empty-body responses remain normal completed Resources when the transfer succeeds. The completion error and actual transfer outcome determine failure.

| Completion scenario | Required current behavior |
| --- | --- |
| HTTP headers received; transport error prevents any required body from arriving | One network Error for the owning Resource; no completed Resource event for this failed transfer. Retain available HTTP status. |
| HTTP headers and part of the required body received; transfer then fails | Apply the same failure treatment. This is the implementation interpretation of the user's headers-plus-body definition; partial bytes do not establish successful completion. |
| No HTTP response; transport error | Preserve existing network Error behavior and absence of a received HTTP status. |
| Required body fully received; no transport error | Preserve completed Resource behavior. |
| Legitimate empty body; no transport error, including HEAD or 204 | Preserve completed Resource behavior. Do not mistake an empty body for a failed download. |
| Complete HTTP error response, such as a 4xx/5xx status, with no transport error | Preserve the existing HTTP-status policy. This decision does not redefine server errors or introduce new success/failure status ranges. |

Existing mapper, sampling, action expiration and cancellation policies still apply. The decision does not require counting an expired or absent action.

## Effect on E03 design and tests

The previous same-view requirement—one Resource, zero standalone Resource errors, resource/error action counts 1/1 and error_tap—captured existing behavior. It is no longer the desired automatic response-plus-error contract for a failed body transfer.

- Preserve the original ninth EXP-206 control, its source and its baseline result as historical evidence. Record that the candidate acceptance requirement is deliberately superseded by this user decision; do not rewrite the history as a passing fix.
- Define the new automatic-handler discriminator before implementing. For the controlled same-view failure case with an active action and no mapper drop, require one network Error, zero completed Resources, action resource/error counts 0/1 and the applicable network-error frustration behavior.
- Keep the four foreign view/session ownership regressions and the other four ordinary/expiry controls. Preserve both original 100 ms expiry boundaries.
- Prove response-plus-error behavior through the actual handler, and obtain a bounded real URLSession headers-then-body-failure reproduction. Keep a successful non-empty transfer and valid empty-body responses as controls. Record callback fields and serialized telemetry; headers alone are not a pass.
- After navigation or session changes, the Error retains the Resource's original ownership and does not increment the unrelated current view's action counters.
- Reassess the smallest implementation now that the native completion need not emit a success command followed by an error command. Selecting a single terminal error before considering success is a design candidate for review, not an implementation admitted by this document.
- A token/ledger that exists only to preserve the old native dual-terminal signal is no longer a requirement. Any remaining ownership state must be justified by the reviewed command paths and lifetime needs.
- Manual repeated-stop behavior, key reuse and compatibility still need an explicit source-based decision. This product clarification does not silently approve every manual API change proposed in EXP-214.

No native reproduction or production prevalence has yet been established by the synthetic ninth control. Zero matching RUM Error events cannot measure a path whose current Error event is discarded. Do not claim a customer frequency without an appropriate observation.

## Deferred follow-up: failed Resource visibility alongside its Error

Local tracking label: E03-FOLLOWUP-FAILED-RESOURCE-VISIBILITY. This is not a Jira identifier or an additional S1 release gate.

| Field | Follow-up definition |
| --- | --- |
| Owner | RUM product and SDK maintainers; main session records it in the existing follow-up register |
| Goal | Let users inspect a failed request as a Resource, including any received HTTP status, alongside its associated Error, without implying that the required body was successfully delivered |
| Dependencies | E03's error-first terminal outcome and ownership repair; a reviewed cross-SDK event/UI and counting contract |
| Scope to evaluate | Correlation between Error and failed Resource, received status/headers, available timing and partial-transfer information; distinguish complete, partial and absent bodies using actual evidence |
| Decisive acceptance | A controlled HTTP 200 response whose body transfer fails remains visible as an Error and has an explicitly failed, correlated Resource representation; no false success, duplicate request/action counts or unrelated view attribution; successful and legitimately empty-body controls remain unchanged |
| Required environment | Controlled native URLSession fixtures plus serialized-event/backend/UI validation for the eventual design; cross-SDK/schema review if its representation requires changes |
| Release effect | Deferred product enhancement; does not block the S1 E03 fix or the independent S1 PRs |

No representation, new public API, event schema, endpoint, dependency, extra production event or app-side diagnostic instrumentation is approved or implemented by documenting this follow-up.

## Main-session handoff

Apply this decision to the active E03 proposal, EXP-214 admission criteria, S1 delivery queue, affected release gate and restart notes at the next safe checkpoint. Replace the obsolete automatic 1/1 preservation requirement, record the historical-test amendment explicitly, and keep the manual-contract question accurately scoped. Continue the separate S1 PR preparation.

This side-conversation change is documentation only. It neither edits SDK/tests nor authorizes a push, PR publication or merge.
