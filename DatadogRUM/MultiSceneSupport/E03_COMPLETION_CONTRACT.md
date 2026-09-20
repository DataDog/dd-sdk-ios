# E03 completion contract decision

This is a proposal, not an admitted production change. [EXP-214](Results/EXP-214-resource-action-design.json)
owns admission; [EXP-206](Experiments/EXP-206-resource-action-ownership.md) preserves all nine original tests and the red baseline.

## Recommended boundary

| Sequence | Proposed result |
| --- | --- |
| Automatic URLSession response plus error | Keep one Resource event, no standalone Resource-error event, and the owning view's current action resource/error counts 1/1 with error_tap. Carry an internal completion owner across the separate commands. |
| Automatic completion after view/session navigation | Preserve original Resource ownership; never increment the newer view/session's action. |
| Automatic success, same-view action replacement, then paired error | The replacement action in that same owning view receives the error according to its existing expiry rules; do not bind to the action from request start. |
| Manual start and one success/error stop | Look up the currently tracked Resource by key and update only its owning view's current action. Existing Resource emission, mapping and expiry remain. |
| Manual key reused after completion | A later terminal call addresses the currently tracked Resource under that key. The API has no handle for an older completed generation; do not invent that guarantee. |
| Manual success followed by a second error stop with no tracked Resource | Advance time/expiry, but do not mutate action counters or frustration. The historical action-only error increment is intentionally removed. A manual caller can report an error and response together using the existing single stopResourceWithError call. |
| Unknown/repeated terminal or metrics key | Advance expiry without changing unrelated action activity, counters or ownership. |

This preserves supported automatic paired telemetry without retaining an ever-growing
history of completed manual keys. No public API, schema, endpoint, dependency or
scene-routing change is proposed. The internal token contains value IDs only and
is released with the queued completion commands; no global map or scope/task/core
reference is proposed.

## Exact approval needed

The original ninth EXP-206 control sends an unannotated success and error directly
to the session scope. It represents the old automatic two-command sequence, but
also requires the same signal from a repeated manual stop after Resource removal.
Under the recommended boundary its unchanged assertion would fail. Therefore:

- Preserve its original source, baseline pass and interpretation permanently.
- Replace its candidate-acceptance role with an actual URLSession-handler response-plus-error test carrying the internal owner and asserting the same one Resource, zero Resource errors, 1/1 action counts and error_tap.
- Add an explicit public-manual repeated-stop control requiring no post-completion action mutation, plus current-key reuse and same-view action-transition controls.
- Keep the other eight original tests and both 100 ms expiry limits unchanged.

That is a deliberate compatibility/test-contract amendment requiring the user's
choice; it is not currently authorized by the original keep-all-nine requirement.
No test is edited or weakened before that decision. Exact added selectors and
production paths must still be frozen and independently reviewed before edits.

## Alternative

Preserve historical unannotated post-success errors across arbitrary action changes
and interleaved keys. This needs a separate reviewed completion-lifetime contract
or identity handle; a one-entry cache, arbitrary TTL, or per-action key ledger has
not been shown compatible. Storing all completed keys until a view ends introduces
unbounded growth in a long-lived view and is not an admitted shortcut. E03 remains
open until that alternative has a compatible design; other S1 packets continue.
