# Application-impact preparation

[EXP-224](../../../DatadogRUM/MultiSceneSupport/Results/EXP-224-application-impact.json)
owns the finite S3:P01 workload, source pair, physical environment, thresholds and
budgets. No command in this directory installs or launches an app.

`build.py prepare --root <fresh-directory>` freezes SDK archives, client/helper
bytes, local config metadata, generated projects and the toolchain.
`build.py build --root <directory> --key A-device` (then `B-device`) checks exact
Swift compiler membership, objects and all product files for unsigned Release
arm64 iOS apps. SDK and fixture testability are disabled. Physical signing requires
a separate product manifest; compiler results are not install/runtime proof.

`python3 -B -m unittest discover -s tools/multi-scene/application-impact` runs 38
focused comparison, native-scenario and trace-decoder controls. Phase boundaries
and CPU reads share one serial queue. Explicit boundary samples must cover the
entire phase, and the terminal snapshot drains and seals the sampler. A native
ready boundary precedes work and proves the owned foreground window fills one
unchanged display. Missing boundaries, stale identities, reversed counters,
thermal changes and incomplete samples are invalid.

The clients exercise deterministic local UIKit and SwiftUI navigation with normal
Core/RUM uploads. They emit run-bound signposts and process CPU/footprint samples.
Programmatic navigation supplies a performance workload, not gesture acceptance.
No external content download is involved.

`trace_contract.py` prepares decoding of six exported tables. `trace-schemas.json`
freezes their complete installed Xcode 27.1 column names, order and engineering types.
XML identity references are resolved strictly; unknown schemas, partial rows,
missing tables and incomplete coverage are rejected. The full trace and original
exports must remain available. Synthetic XML controls do not qualify native export.

Apple's Core Animation FPS instrument exposes a display-driver estimate, not exact
app-rendered frame counts. Hitch render processes belong to the window server;
never filter those rows by the app PID. Compare global display FPS/hitches during
the exact app Workload interval, and bind Hangs, CPU and footprint to the app PID.
The physical display UUID joins to native geometry. The renderer's integer display
ID remains an unjoined diagnostic; multiple render display IDs are invalid. A
present, empty hitch-render table is valid because the modeler emits only hitches.
Absent tables never mean zero. The numeric A/B thresholds remain unchanged.

Before physical execution, complete installed-code proof, recorder readiness,
bounded capture/export/cleanup orchestration, signing and clean-install admission.
The first planned UIKit baseline must qualify actual trace formats, full capture
and cleanup. No physical result or release gate is implied by these preparations.
