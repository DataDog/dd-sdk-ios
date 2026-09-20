# E03 completion contract

The [user's Resource-completion decision](E03_RESOURCE_COMPLETION_DECISION.md) approves the automatic outcome below. The reviewed six-file repair is signed in an isolated checkout. Full RUM925/961 and nine native XCTest cases pass; the exact owner contract is qualified with an inherited session-precondition diagnostic retained. Metrics preserve fixed action-start-based expiry and leave counters unchanged; the private activity timestamp has no reader. Final candidate compatibility and delivery review remain pending. [EXP-214](Results/EXP-214-resource-action-design.json) owns design and test admission; [EXP-206](Experiments/EXP-206-resource-action-ownership.md) preserves all nine original test bodies and their baseline evidence.

## Approved automatic outcome

| Native completion | Required outcome |
| --- | --- |
| HTTP headers plus transport error before required body completes, including partial-body failure | One owning network Error, zero completed Resources; retain received status through existing error.resource fields. In the controlled active-action fixture, resource/error counts are 0/1 and existing error frustration applies. |
| Transport error without HTTP response | Preserve the existing network Error path without an invented response status. |
| Complete nonempty body, no transport error | Preserve the completed Resource path. |
| Legitimate empty body, including HEAD/204, no transport error | Preserve the completed Resource path; size zero is not an error discriminator. |
| Complete HTTP 4xx/5xx response, no transport error | Preserve existing HTTP-status behavior. |
| Completion after navigation or session change | The Resource/Error retains its captured owning view/session and cannot mutate another live action. Expiry and mapper rules still apply. |

The admitted six-file repair chooses the error terminal before a success terminal and resolves tracked ownership before action mutation. It must preserve metrics, attributes, header handling, mappers, current-action timing and clock-driven expiration. No completion token or historical-key ledger is required solely to preserve the retired automatic dual-terminal behavior.

## Manual compatibility boundary

The new decision does not authorize changing unrelated manual repeated-stop, unknown-key or key-reuse behavior. Existing keys identify the currently tracked Resource; the API does not identify an older completed generation. Command-scoped tracked-owner resolution isolates known completions for both origins, preserves unknown manual behavior and suppresses unknown automatic terminal action mutation. Source review accepted queue confinement, action transitions, expiry-before-filtering and matching Resource/TNS settlement. The metadata uses nil for unresolved and an empty array for resolved-unowned; the automatic marker distinguishes that case from manual fallback. No retained history is added.

The earlier asynchronous question combined this manual change with an obsolete automatic 1/1 premise. That automatic premise is now superseded. Do not treat the new product decision as approval to ignore every repeated manual stop. If the repair can preserve manual behavior, no such change is needed; otherwise present the precise remaining decision separately.

## Test amendment and admission

- Preserve all nine original EXP-206 bodies, the original patch and baseline results. The ninth records historical unannotated success-then-error behavior; it no longer defines the desired automatic failed-transfer outcome. It may remain a manual-compatibility witness if that exact behavior is preserved.
- Keep the four foreign view/session regressions and four ordinary/expiry controls; both expiry limits remain 100 ms.
- Freeze actual-handler controls for response-plus-error, no-response error, complete response and legitimate empty response. The failed-transfer fixture requires one Error, zero Resources, action counts 0/1, exact owner and received status.
- Freeze a bounded native URLSession headers-then-body-failure reproduction, successful body and legitimate empty-body controls. Require callback evidence and serialized telemetry; no prevalence inference from a synthetic fixture.
- Cover same-view action replacement, manual/current-key reuse, mapper/drop behavior, separate cores and cleanup without unbounded owner history. Exact selectors, production/test paths and runtime budgets must be admitted before edits.

[E03-FOLLOWUP-FAILED-RESOURCE-VISIBILITY](E03_RESOURCE_COMPLETION_DECISION.md#deferred-follow-up-failed-resource-visibility-alongside-its-error) records the later product enhancement. It does not add a Resource event, schema/API change or S1 blocker now.

## Historical implementation and coverage

The user-requested historical review found explicit support for network Errors carrying a received HTTP status, including the public response-bearing stop-with-error API and the existing Resource-scope status500 assertion. It did not establish intent to emit both success and error terminals. Both independent handler branches date to b6a1c4489c6, while ResourceScope already ended after either terminal. Old handler tests exercised success and failure separately; their two-command expectation meant metrics plus one terminal. The shared ServerMock success/failure enum cannot represent headers followed by a body-transfer error. The explicit paired-signal witness was added in EXP206 and cannot establish older product intent.

This supports treating the failed-body case as an uncovered edge case; author intent and customer prevalence remain unproven. The original results stay intact. The current error-first outcome comes from the user's decision, with additional failed-Resource visibility still deferred.
