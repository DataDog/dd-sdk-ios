# Duo simulator evidence assessment

[EXP-192](Results/EXP-192-duo-simulator-fidelity.json) owns the protocol and
observations. This assessment does not estimate a physical-equivalence percentage:
there is no matched physical Duo run. Gate status remains in the
[finite register](release-gates.json).

## Evidence model

Apple documents Duo pose controls and inner-display Split View testing in Device
Hub. This supports using the simulator to exercise scene/layout behavior;
it does not establish identical physical scheduling or performance.
[Prepare your app for iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111461/).

New windows are available on the inner display only. An outer-display activation
failure must be classified against that platform restriction.
[Multiple displays and scenes on iPhone Duo](https://developer.apple.com/videos/play/tech-talks/111464/).

Confidence is recorded per capability: **observed** means exact native boundaries
and ownership assertions passed; **inferred** identifies a reason to expect the
same SDK logic on hardware; **unexecuted** and **inconclusive** remain explicit.
The first-party RUM source has no simulator conditional in the inspected tree,
but framework callback ordering and OS scheduling still require observation.
Core excludes battery/low-power subscriptions on Simulator; device CPU/RAM
metadata comes from the host process; crash image classification has a separate
simulator branch. Source parity therefore cannot certify the whole SDK.

Simulator graphics calls use the Mac GPU through translation. Frame timing,
thermal behavior, energy, memory pressure, launch timing and hardware crash
behavior remain physical evidence obligations; existing measured simulator
regression budgets are still useful within their original environment.
[Apple Metal simulator guidance](https://developer.apple.com/documentation/metal/developing-metal-apps-that-run-in-simulator).

## Finite simulator execution routing

All rows retain their original decisive gate oracle and dependencies. The SDK
implementer owns simulator execution; the device operator owns physical evidence.
No row is accepted from a scene-count declaration or an assertion made only after
the critical boundary.

| Existing gates | Simulator execution | Required discriminator | Physical residual |
| --- | --- | --- | --- |
| H01 | First, unchanged EXP-191 | Actual A/B overlap, distinct Compose owners, B-before-A stop, fresh Home IDs, complete backend | Matched hardware ownership/topology |
| H02, H05, H16 | Concurrent UIKit/SwiftUI, semantic/automatic and hosted parity | Native sessions visible together; independent exact destination chains | Hardware integration |
| H03, H04, H10 | Visible peer, focus and independent lifecycle | Genuine OS callbacks and peer continuity at each boundary | Scheduling/suspension on hardware |
| H06, H07 | Concurrent Operations and shared URLSession | Real overlap; captured A owner survives B join; exact span/resource contract | Hardware concurrency timing |
| H08, H09, H15 | Host removal, OS reconnect and restoration | Real detach/disconnect, fresh IDs, stale callbacks/run IDs rejected | Memory-pressure/OS restoration on device |
| H11, H12, H13 | Recognized interactive back/sheet transitions | Began/cancelled/completed recognizer path; unchanged/fresh owner as appropriate | Human physical gestures |
| H14 | Open/close/rotate/fold and adaptive split | Measured regular/compact transitions, exact semantic destination owners | Physical hinge and display transitions |
| F05 | Simulator coexistence if dependencies allow | Crash safety and stated scope only | Required physical Replay coexistence |

Current observed results are owned by the
[first capability record](Results/acceptance/exp192-52086984-e5e3-499a-afc8-cdc3f55c2e2c.json):
outer/inner/rotated dimensions and expected traits, stable native identity and
actual app background/foreground callbacks. These support simulator use for
geometry and lifecycle integration; they do not prove peer overlap or hardware
callback timing. The unchanged H01 run passed22 ownership checks while its
topology failed admission, demonstrating why those checks stay separate.

Concurrent visibility, real disconnect and interactive cancellation remain
unproven. Native calls and tool success responses alone did not establish them.
Bounded XCTest input calibration is in preparation. Original H/F release
obligations remain open until their own completion contracts are met.
