# Native callback observation

## EXP-220 — Observe selector callback ownership during native UIKit input

The [definition and checkpoint](../Results/EXP-220-native-input-callback.json)
implement the separately reviewed callback-side design for the original EXP210
regular-iPhone input discrepancy. Baseline SDK-on/off arms remain unexecuted.
The prepared observer keeps the original UIKit controls and gestures, records
selector entry/callback/return in bounded memory, and classifies a successful
native effect without matching ownership evidence as observer-inconclusive.
It does not require ended-touch ancestry or a value transition inside sendAction.

The user requested a laptop restart during preparation. Source/oracle review and
four positive/twenty-five negative oracle controls are complete. No SDK archive,
host runner, build, simulator or native launch exists. The prepared files and
review are hashed in the durable preparation checkpoint. Both protected paths and
all eight user API documents are unchanged. The owned caffeinate process is stopped.

The original preparation attempt is closed without gate credit. After restart,
verify its hashes, rediscover the environment and finish the host runner, exact
source/compiler/binary guards and cleanup controls. A separate bounded execution
admission and review are required before building or running; do not extend the
original deadline or repeat EXP218. The existing CI-flake repair restriction and
Duo environment stop remain in force.
