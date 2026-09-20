# Resource completion ownership design

## EXP-214 — Admit the E03 repair without losing valid action signals

Defined before implementation or new runtime work, after the EXP-213 checkpoint.
The user prioritizes this repair before further S2/S3 expansion. The
[owning result](../Results/EXP-214-resource-action-design.json) freezes the source,
original nine EXP-206 selectors, admission conditions and engineering checkpoint.
E03 remains open; the earlier token/ledger proposal is not approved.

The known defect changes another view or session's live action resource/error
counts and frustration, while Resource event ownership itself remains correct.
Preserve all four baseline failures and five controls without rerunning the red
arm merely to resume. The same-view response-plus-error control must still emit
one Resource, no standalone Resource error, action counts 1/1 and error_tap;
the two expiration controls retain their 100 ms deadline.

The admission review separates three contracts:

| Case | Required decision |
| --- | --- |
| Native automatic completion series | Carry its actual owner through metrics, response and error, including action/view/session transitions; do not pin an obsolete action. |
| Manual key reused after a completed Resource | Establish existing current-key behavior from source/public documentation; do not require an unobservable old-generation guarantee or invent a public handle. |
| Unannotated error after success removed the Resource | Distinguish supported paired completion from historical repeated-stop behavior, including action changes and interleaved keys. Any compatibility change must be explicit. |

A per-action ledger alone loses history across action changes and can grow while
other Resources keep an action alive. A fixed-capacity/TTL history is not assumed
compatible. Source review must resolve queue confinement, mappers, expiry, cleanup
and core isolation, then freeze exact paths and added tests before admitting edits.
The runtime budget and inventory will be defined only for an accepted design.

At the finite decision checkpoint, record admission or the exact missing contract
and maintainer decision. Continue the independent S1 delivery packets if input is
needed; do not substitute more S2 expansion or label E03 complete. No production
edit, new build/test or gate closure is claimed by this definition.

Source review resolves legal key reuse through the existing current-key rule;
it is not a reason to require a public generation handle. The remaining explicit
choice is [post-completion manual error behavior](../E03_COMPLETION_CONTRACT.md).
The recommended automatic-owner/manual-current-key contract requires amending the
ninth candidate discriminator, while preserving its original evidence and proving
the automatic 1/1 signal through the actual handler. That amendment awaits the
user's choice. No implementation, runtime or gate closure is admitted.
