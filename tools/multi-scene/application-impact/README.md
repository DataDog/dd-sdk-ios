# Application-impact preparation

[EXP-224](../../../DatadogRUM/MultiSceneSupport/Results/EXP-224-application-impact.json)
owns the finite S3:P01 workload, source pair, physical environment, thresholds and
budgets. No command in this directory currently installs or launches an app.

`build.py prepare --root <fresh-directory>` freezes SDK archives, client/helper
bytes, local config metadata, generated projects and the toolchain.
`build.py build --root <directory> --key A-device` (then `B-device`) checks exact
Swift compiler membership, objects and all product files for unsigned Release
arm64 iOS apps. SDK and fixture testability are disabled. Physical signing requires
a separate product manifest; this compiler result is not install/runtime proof.

`python3 -B -m unittest discover -s tools/multi-scene/application-impact` runs the
comparison controls. `contract.py` compares directional pairs without hiding a
failure in a mean, and rejects invalid metrics. The native scenario validator is
provisional: its focused controls and actual first-baseline qualification remain.

The clients exercise deterministic local UIKit and SwiftUI navigation with normal
Core/RUM uploads. They emit run-bound signposts and local process CPU/footprint
samples. Programmatic application navigation supplies a performance workload,
not interactive-gesture acceptance. No external content download is involved.

Before any physical execution, complete the trace adapter and strict controls for
source/process/run joins, table presence and whole-interval coverage, readiness,
clean installation, signing and cleanup. Required actual rendered FPS, hitch and
hang evidence comes from the physical trace. Never treat missing tables as zeros
or use a nominal display interval as rendered FPS. No native acceptance command
is provided until those prerequisites qualify.
