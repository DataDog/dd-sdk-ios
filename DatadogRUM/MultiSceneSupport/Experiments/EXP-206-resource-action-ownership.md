# Source-less Resource completion and live action ownership

## EXP-206 — Discriminate foreign Resource action counters

**Reproduced; repair boundary blocked; E03 remains open.** Unchanged remotely
verified develop `62f64d7b` fails exactly four ownership tests and passes five
preservation controls on iOS17.5/21F79 with Xcode27.1/27A9269. The
[owning result](../Results/EXP-206-resource-action-ownership.json),
[independent artifact audit](../Results/EXP-206-baseline-audit.json) and
[durable reproducer](../Results/EXP-206-baseline-reproduction.patch) preserve identity.

A late H1 success increments H2's live action Resource count. A late H1 error
increments H2's action error count and adds error_tap. Both reproduce after
navigation and explicit session stop. The Resource/error event's original
view/session UUIDs and supplied metrics remain correct. Four failed tests contain
six assertion failures; there are no missing tests, unexpected failures or skips.

The original eight-test definition was amended before execution with one
same-view response-plus-error preservation control. The automatic handler can
emit metrics, success and then error. Baseline produces one Resource and no
standalone Resource-error event, while the action retains resource/error counts
of1/1 and error_tap. This ninth test and the other four preservation controls pass.
The two foreign-command expiry controls preserve the original100ms deadline.

The first invocation compiled zero tests because two new timing assertions used
optional loadingTime in arithmetic. That failure is retained. A recorded,
independently reviewed correction only adds throwing XCTUnwrap to those two
operands; the1ns tolerance and all nine scenarios remain unchanged. One corrected
invocation completed at05:47:13.843242Z, before the original06:24:03.630360Z cutoff.
No production change or green-arm invocation occurred.

All1,864 source input identities, package/framework pins, simulator binding and
protected workspace metadata remain unchanged. The164-member product manifest
and exact result tree are retained. Strict test lint passes with the inherited
rule-deprecation warning. Console retains227 warning lines and59 duplicate-class
messages; empty structured runtimeWarnings and omitted verbose test archives do
not establish a clean diagnostics or sanitizer result.

The [source/design review](../Results/EXP-206-ownership-design-review.json) proves
why dictionary membership alone is unsafe: success removes the key, so the next
error cannot be distinguished from a foreign completed key. Accepting unknown
keys leaks ownership; rejecting them removes the valid error signal. An action
ledger alone also loses ownership across action changes and can confuse key reuse.
A larger internal ownership-token/ledger design is only an unadmitted proposal:
its manual-command, generation, confinement and footprint risks remain unresolved.

Keep E03 independent from E01/E02. Retain this red proof while reviewing a
compatible design; continue other finite candidates. Native/public-monitor,
performance and release qualification have not been established for E03. The
isolated checkout retains only the two intentional reproducer test edits.
