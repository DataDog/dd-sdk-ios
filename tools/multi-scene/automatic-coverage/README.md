# Automatic tracking compatibility comparison

EXP-195 compares four existing-public-API tracking families under C07–C10.
The owning definition is `DatadogRUM/MultiSceneSupport/Results/EXP-195-automatic-tracking.json`.
No SDK implementation or local configuration is changed.

The fixed32 cells are two Datadog revisions × genuine SDK26.5/27.1 builds ×
regular iPhone27.0/Duo27.1 × UIKit/native SwiftUI stack/split. The fixture targets
iOS16 because NavigationStack/NavigationSplitView are existing16 APIs; this is
not the separate SDK deployment15 gate. Both apps declare multiple scenes false.
SwiftUI also enables the UIKit action predicate for UIKit-backed controls and
scrolls, as ordinary automatic configuration does. There are no manual view/action
calls, semantic hosts, experimental APIs or renamed default predicates.

`run.py prepare` archives only the existing baseline helper's seven explicit SDK
source/private/resource directories and generates isolated XcodeGen projects.
`build --attempt PATH --build candidate-27.1` builds one of four arms.
`devices --attempt PATH` creates task-owned regular/Duo simulators; preserve and
remove only those exact devices at completion.
`run --attempt PATH --build KEY --device regular|duo --framework UIKit|SwiftUI
--layout stack|split [--poses]` performs clean install, full Mach-O identity
comparison, real XCTest input, collection and scoped cleanup.

The UI collector requires native tap/toggle effects and actual scroll displacement
before judging automatic coverage. A real Home/background boundary drains the
last automatic action; immediate termination can falsely look like a missing tap.
SwiftUI switch input targets the observed control's trailing switch, then asserts
the actual value/native callback. Tapping a discovered element is not enough.

Duo pose phases wait for external real Device Hub input. The runner's fresh
Documents/RUN_ID directory publishes await-open/close/reopen receipts. Release
each with a run-bound JSON containing the fresh native geometry sequence and
actual display evidence only after the requested transition. Never use a remembered
control index, run ID, command file or geometry receipt. No artificial resize can
be labeled a real open/close.

`analyze.py ATTEMPT --output RESULT` verifies identities, input completeness and
chronology before comparing unique view occurrences and automatic action owners.
Application-start actions and view updates remain in raw evidence but are not
extra user interactions. Names and occurrence ordinals are compared; UUIDs vary
between processes. Differences require explicit classification. Existing gaps
remain visible; an identical generic fallback is not promoted to exact semantics.
Cross-device comparisons match the initial phase and retain the27.0/27.1 OS-patch
confound. Same-device old/new build comparisons isolate rebuild changes.

All RUM events are synthetic, observed locally through pass-through mappers with
a dummy token and loopback upload endpoint. No backend ingestion claim is made.
