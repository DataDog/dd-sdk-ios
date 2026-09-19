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
| F05 | EXP-194 passes on regular iPad27.0 | Four native recorder checkpoints, real disconnect, six exact backend views and zero errors/crashes; serial topology | Required physical Replay coexistence; this is not Duo execution |

Current observed results are owned by the
[first capability record](Results/acceptance/exp192-52086984-e5e3-499a-afc8-cdc3f55c2e2c.json):
outer/inner/rotated dimensions and expected traits, stable native identity and
actual app background/foreground callbacks. These support simulator use for
geometry and lifecycle integration; they do not prove peer overlap or hardware
callback timing. The unchanged H01 run passed22 ownership checks while its
topology failed admission, demonstrating why those checks stay separate.

Concurrent visibility and real disconnect remain unproven. Two bounded XCTest
pairing attempts do not establish the required input. The corrected attempt
finalizes with its visibility assertion failing; its primary-screen captures are
black and outer-sized while the inner display is active. This limits this input
path, not the platform's documented capability.

Adaptive geometry is now observed through both actual display switching and a
native resizable display. Nil selection remains nil with no Detail owner. Real
selection exposed an obsolete fixture route/ownership path; EXP-193 qualifies the
current accepted-state integration before H14 ownership can be accepted. The
resizable display is a synthetic layout environment, separate from a physical
hinge transition. Original H/F release obligations remain open.

EXP-193 preserves another execution boundary: appResize produces real native
geometry, but the Resizable app surface is black in Device Hub and explicit
display capture. Ending the headless resize session backgrounds the scene.
Separate pose/selection acceptance from callback-driven resize ownership; the
latter requires live native geometry before dispatch and makes no visible-layout
or input-parity claim. Both original incomplete attempts remain attributable.

EXP-193 now accepts the guarded resize slice: native5 phases and16 exact custom
Action/Resource events match the complete3-view backend inventory with0 errors.
The selected Detail occurrence stays unchanged through900×675 regular,
400×700 compact and900×675 regular. XCTest delivers the native prefix through
explicit collector handshakes and passes1/1; app/runner/resize cleanup is verified.
This is strong evidence for SDK ownership across those measured native geometry
callbacks. The10-phase pose sequence remains pending and physical hinge behavior
is still uncalibrated.

Q5 now records two actual outer-display XCTest edge drags after a compact-layout
fixture repair. Both runs prove visible secondary-2, fresh code/run identity and
live compact geometry before input. Neither short nor long drag produces a native
interactive began/resolved callback, destination or work. Their1/1 UI-test results
prove collection only. Equivalent UIKit retries stop; SwiftUI and presentation
input remain unexecuted because the prerequisite path is unqualified. This limits
the tested input/fixture combination, not documented platform capability. Both
app/runner pairs are removed and physical human H11–H13 obligations remain.
