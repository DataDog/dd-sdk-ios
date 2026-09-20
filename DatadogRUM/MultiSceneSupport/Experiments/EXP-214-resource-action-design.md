# Resource completion ownership design

## EXP-214 — Admit the E03 repair with the approved transfer outcome

Defined before implementation or new runtime work after the EXP-213 checkpoint. The [owning result](../Results/EXP-214-resource-action-design.json) retains the original source, nine EXP-206 selectors, reviews and engineering checkpoint. E03 remains open and no implementation/runtime is admitted.

The original known defect mutates another view/session's action counts and frustration. The ninth control also exposed a response-first path: success removes the Resource scope before its paired error can produce an Error event. Its original one-Resource/no-Error/1:1 action result remains historical evidence.

The subsequent [user decision](../E03_RESOURCE_COMPLETION_DECISION.md) changes the automatic contract. A failed required-body transfer, even with received HTTP headers or partial bytes, must produce one network Error and no completed Resource. Retain received status through existing Error resource fields. In the controlled live-action case, resource/error counts are 0/1 and existing error frustration applies. Successful nonempty bodies and legitimate empty HEAD/204 responses remain Resources; ordinary HTTP-status, cancellation, mapping and expiry rules remain.

The [active contract](../E03_COMPLETION_CONTRACT.md) therefore reassesses a single error terminal and bounded ownership resolution. A token/ledger solely for the old automatic dual-terminal signal is no longer required. The independent reviewer is checking the smallest source-compatible design, including manual current-key and repeated-stop behavior; the automatic decision does not approve unrelated manual changes.

All nine original test bodies and the red baseline remain preserved. The ninth no longer defines automatic failed-transfer acceptance, and may remain an unchanged manual compatibility witness. Keep the other eight controls and both100ms expiry boundaries. Before edits, freeze exact paths/selectors for actual-handler and native headers-then-body-failure controls, successful and legitimate empty responses, action/view/session transitions, mappers, manual reuse and cleanup. No synthetic test establishes production prevalence.

The original design checkpoint records the changed product premise and pending source admission, without extending any runtime allowance. Continue independent S1 delivery checks while design review completes. The separately documented failed-Resource visibility enhancement is deferred and does not block E03.
