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


Use `pose.py status --attempt PATH` to locate the current native input boundary.
`pose.py before --attempt PATH --pose NAME` freezes its actual display/geometry;
perform the real Device Hub transition, then `pose.py ack` with the same arguments.
The helper checks active outer/inner display, foreground native geometry, scene
identity and chronology before releasing the test. It never changes the pose.
`comparison_prior_attempts` retains qualified cells from earlier collector-only
revisions, provided app and all SDK source fingerprints remain identical. Each
cell keeps its own manifest, build identity and raw evidence.


On Duo the final drain waits at `await-home`: use Device Hub's actual Home control,
then `pose.py home-ack --attempt PATH`. A fresh native app-background event must
precede that receipt. The earlier XCTest Home finalization failure stays preserved.
Regular cells keep their existing XCTest Home path. Frozen archived app/test
sources and all app/runner binaries are checked independently of later collector
edits in the working tree.

The separately defined eight-cell manifest-true follow-up uses
`manifest_variant.py --parent PATH`. It copies the SDK27 fixture products and
changes only UIApplicationSupportsMultipleScenes in Info.plist; every Swift source
and Mach-O stays identical. Runs hash the frozen/installed plist before and after
XCTest, distinguish that declaration from UIApplication's runtime capability,
and require exactly one actual native scene throughout. Keep its manifest separate
from the original32 cells; the analyzer rejects mixed declaration histories.

Duo old-app comparisons use the SDK27 collector with the genuine old application
paths and an independent collector identity. A fresh display transition with a
measured375x667 compact compatibility viewport is labeled `legacy_viewport_unchanged`
only for the genuineSDK26.5 arm. It still requires fresh native window inventory,
unchanged scene and a real display change before input. Duplicate-size windows
never count as a spatial resize. A missing native input remains unqualified.

`report.py ATTEMPT --device duo --output RESULT.json` generates the durable
accepted inventories, source/build/installed identities, geometry/pose evidence,
raw-artifact hashes, comparison classifications and retained input failures.
It evaluates the current strict oracle without rerunning any accepted native cell.

The bounded old-build Duo recovery is input-blocked: both modern XCTest probes
lose their runner after actual Open; the external CUA prototype cannot qualify
its initial native switch effect. Its rejected source and partial evidence are
referenced by the owning result. It is not a supported collector. Preserve the
34 qualified runs across the original matrix, manifest follow-up and replay;
resume only the eight missing original cells after a material input-environment
change. The EXP195-owned simulators were deleted after evidence collection.

A newly defined comparison can call `run.py prepare --definition DEFINITION.json`.
The definition must name its experiment, two complete commit hashes and a finite
matrix. EXP-210 freezes current develop versus E01; EXP-195 defaults and accepted
artifacts remain unchanged. Preparation archives committed sources and hashes the
frozen definition, host helpers, Swift fixtures and generated package. Build,
run and analysis reject identity drift. Native run IDs and bundle names use the
new experiment while the unchanged Swift collector keeps its original environment
variable names.

A custom definition rejects unlisted, already attempted and old-build Duo XCTest
cells before touching a device. The latter require the separately prepared human
collector; a failed input path is never retried to obtain a pass. Manifest-true
variants inherit their own frozen definition and change only the declaration.
These host controls do not alter the native-input or semantic ownership oracle,
and local mapper comparisons do not prove backend or active-work fold coverage.
