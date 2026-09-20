# E03 completion contract

The [user's Resource-completion decision](E03_RESOURCE_COMPLETION_DECISION.md) approves the automatic outcome below. Implementation is not yet admitted. [EXP-214](Results/EXP-214-resource-action-design.json) owns design and test admission; [EXP-206](Experiments/EXP-206-resource-action-ownership.md) preserves all nine original test bodies and their baseline evidence.

## Approved automatic outcome

| Native completion | Required outcome |
| --- | --- |
| HTTP headers plus transport error before required body completes, including partial-body failure | One owning network Error, zero completed Resources; retain received status through existing error.resource fields. In the controlled active-action fixture, resource/error counts are 0/1 and existing error frustration applies. |
| Transport error without HTTP response | Preserve the existing network Error path without an invented response status. |
| Complete nonempty body, no transport error | Preserve the completed Resource path. |
| Legitimate empty body, including HEAD/204, no transport error | Preserve the completed Resource path; size zero is not an error discriminator. |
| Complete HTTP 4xx/5xx response, no transport error | Preserve existing HTTP-status behavior. |
| Completion after navigation or session change | The Resource/Error retains its captured owning view/session and cannot mutate another live action. Expiry and mapper rules still apply. |

The smallest design candidate chooses the error terminal before a success terminal and resolves tracked ownership before action mutation. It must preserve metrics, attributes, header handling, mappers, current-action timing and clock-driven expiration. No completion token or historical-key ledger is required solely to preserve the retired automatic dual-terminal behavior.

## Manual compatibility boundary

The new decision does not authorize changing unrelated manual repeated-stop, unknown-key or key-reuse behavior. Existing keys identify the currently tracked Resource; the API does not identify an older completed generation. Review whether command-scoped tracked-owner resolution can isolate known completions while retaining the current no-tracked-owner behavior. The independent automatic-marker proposal still needs to close the original unannotated foreign-owner controls. Resolve known ownership for both origins; preserve unknown manual behavior and suppress unknown automatic terminal action mutation. Do not admit this refinement until its per-core queue, action transitions, expiry and cleanup have been reviewed.

The earlier asynchronous question combined this manual change with an obsolete automatic 1/1 premise. That automatic premise is now superseded. Do not treat the new product decision as approval to ignore every repeated manual stop. If the repair can preserve manual behavior, no such change is needed; otherwise present the precise remaining decision separately.

## Test amendment and admission

- Preserve all nine original EXP-206 bodies, the original patch and baseline results. The ninth records historical unannotated success-then-error behavior; it no longer defines the desired automatic failed-transfer outcome. It may remain a manual-compatibility witness if that exact behavior is preserved.
- Keep the four foreign view/session regressions and four ordinary/expiry controls; both expiry limits remain 100 ms.
- Freeze actual-handler controls for response-plus-error, no-response error, complete response and legitimate empty response. The failed-transfer fixture requires one Error, zero Resources, action counts 0/1, exact owner and received status.
- Freeze a bounded native URLSession headers-then-body-failure reproduction, successful body and legitimate empty-body controls. Require callback evidence and serialized telemetry; no prevalence inference from a synthetic fixture.
- Cover same-view action replacement, manual/current-key reuse, mapper/drop behavior, separate cores and cleanup without unbounded owner history. Exact selectors, production/test paths and runtime budgets must be admitted before edits.

[E03-FOLLOWUP-FAILED-RESOURCE-VISIBILITY](E03_RESOURCE_COMPLETION_DECISION.md#deferred-follow-up-failed-resource-visibility-alongside-its-error) records the later product enhancement. It does not add a Resource event, schema/API change or S1 blocker now.
