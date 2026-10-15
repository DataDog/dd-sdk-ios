# Retained reader remount acceptance

EXP-171 targets R04's remaining attachment boundary: remount through an existing
reader callback without an intervening body/source reconstruction.

```sh
python3 -B tools/multi-scene/retained-reader/run.py \
  --control <control-commit> --candidate <candidate-commit> --output <new-result.json>
```

The runner uses the existing isolated SDK/build/clean-install contract, eight
explicit SDK source/resource directories, local dummy credentials and loopback
endpoints. It freezes both arms and requires the exact 57-check inventory.
No protected project or local configuration contents are accessed.

Explicit and optional-capability hosts mount in a real native simulator scene
with a logical peer. The fixture captures the actual reader callback, removes
and retains the UIHostingController for200ms, and requires the source subscription
to end. A new source input while detached must not publish. Immediately before
readding the exact retained controller, it wraps the captured callback. At its
first invocation the source must still have zero observers, proving that no body
rebind repaired the boundary. The wrapper forwards the actual SDK callback and
submits Resource/Log markers before UIKit/SwiftUI can render again. The root value
is never reassigned. Missing interception or prior source rebind is inconclusive.

Require a fresh Latest occurrence with exact marker UUID/session, unchanged peer,
no duplicate mount, and unsubscription/suppression release at final teardown.
The unchanged SDK must fail the latest-owner check in both variants. Unit controls
also cover no-body reconnect, early rejected readers, released source/handler and
a body that explicitly withdraws the source. Genuine physical lifecycle, P03
registry retirement, R05 observer fan-out and D10 presentation remain separate.

Accepted first comparison: control `2da21c041` is43/57 and signed candidate
`4ba7179c6` is57/57. Two unit controls fail before repair; all318 affected tests
and strict changed-file lint pass after repair. Both native first callbacks prove
zero observers before delivery. R04 closes its bounded component review.
