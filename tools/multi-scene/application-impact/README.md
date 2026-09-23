# Application-impact preparation

[EXP-224](../../../DatadogRUM/MultiSceneSupport/Results/EXP-224-application-impact.json)
owns the finite S3:P01 workload, source pair, physical environment, thresholds and
budgets. Build preparation is separate from the physical runner admission.

`build.py prepare --root <fresh-directory>` freezes SDK archives, client/helper
bytes, local config metadata, generated projects and the toolchain.
`build.py build --root <directory> --key A-device` (then `B-device`) checks exact
Swift compiler membership, objects and all product files for unsigned Release
arm64 iOS apps. SDK and fixture testability are disabled. Physical signing requires
a separate product manifest; compiler results are not install/runtime proof.

`python3 -B -m unittest discover -s tools/multi-scene/application-impact` runs 58
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
The physical CoreDevice identity and displayId bind its native geometry. The renderer's integer display
ID remains an unjoined diagnostic; multiple render display IDs are invalid. A
present, empty hitch-render table is valid because the modeler emits only hitches.
Absent tables never mean zero. The numeric A/B thresholds remain unchanged.

`physical.py prepare --root <fresh-signed-directory> --build-root <directory>
--profile <existing-profile> --certificate <SHA1> --device <CoreDevice-ID>
--udid <physical-UDID>` copies and signs the four reviewed static-code fixtures.
It binds the existing profile, signed Mach-O bytes, full products and physical
hardware. It does not install or launch. No automatic provisioning is used.

`physical.py wave --root <signed-directory>` admits the one fixed eight-cell wave.
Each cell proves fresh task installation and pre-SDK installed code, attaches the
four instruments, consumes one run-unique recorder notification, publishes the
complete admission then nonce marker, and captures the unchanged workload.
No recurring transfers occur during measurement. The recorder and admission use
the original deadline; it cannot be extended. Each app is removed before export.

The first planned UIKit baseline qualifies actual trace formats, full capture
and cleanup. An invalid cell stops the wave; unexecuted cells remain unrun.
Separate scenario, evidence and immutable cleanup verdicts feed one durable final
summary. A late receipt or later restoration never repairs an original failure.
A successful uninstall plus exact empty app/PID inventories prove physical task
removal; generic CoreDevice container errors alone do not. Native performance and
release acceptance require the actual complete paired results.

Current native qualification is INVALID: Instruments could not attach to the
verified launched baseline PID before readiness. All task apps were removed;
no measured workload ran. Do not rerun `wave` without a separately justified
changed capture prerequisite. The owner preserves both earlier preconditions and
the transport correction; no old deadline or result is reusable as acceptance.
