# Automatic tracking compatibility comparison

The current [S2 preparation](../../../DatadogRUM/MultiSceneSupport/Results/S2-capture-contract-preparation.json)
selects12 Duo cells across UIKit/SwiftUI stack/split, each with baseline26.5,
baseline27.1 and candidate27.1. It binds six refreshed products: only the passive
observer and ordered writer changed in copies of the three original source/compiler pairs. Ordinary
UI, RUM configuration and SDK bytes are unchanged. Reuse the products bound by
the current preparation; superseded observer builds cannot qualify changed capture.
Preparation admits no input. The reviewed Home-only correction has separate native
qualification; the owning result records which mechanism each build qualifies.

To prepare a changed observer, use `human_fixture_refresh.py prepare --original
FROZEN_BUILD_ROOT --root NEW_REFRESH_ROOT`, then its `build` action once for each
key: `baseline-26.5`, `baseline-27.1`, `candidate-27.1`. Runtime preparation uses
`human_runtime.py prepare-s2 --original FROZEN_BUILD_ROOT --refresh-builds
QUALIFIED_REFRESH_ROOT --root NEW_MASTER_ROOT`. The master cannot be staged directly.
Use `human_sessions.py prepare-s2 --original MASTER_ROOT --root NEW_SITTING_ROOT
--series NEW_SERIES --cells 1` for the first complete cell. The owner pins that
series; reviewed later sittings select one to three cells with `--previous
COMPLETED_SITTING_ROOT`. A failed or incomplete predecessor cannot continue.

The reviewed `human_candidate.py` opt-in prepares only the pending UIKit stack
candidate after a capture-mechanism change. It binds an accepted SDK26.5 baseline
and a separately reviewed SDK27.1 offline comparison through `--accepted` and
`--offline`, plus the qualified Home result through `--home`. `--original` is the
new master, `--root` a fresh sitting and `--series` a fresh one-cell ledger. Existing
claims stay consumed. Neither reference populates native inheritance; its separate
`candidate-complete.json` records candidate capture and comparisons with no automatic
release credit. The standard selector and completed-predecessor rules stay intact.

The frozen native oracle removes only recorder-duration upper bounds. The collector
preserves Home's committed prefix, then collects inactive View revisions and exact
Action counts/owners; it does not equate a writer checkpoint with end of SDK work.
Successful cleanup requires request-bound native Home/input-idle proof. Failure
requires Released acknowledgement and fresh native idle before task-app removal.
Home arms one bounded background task before its prompt. Native geometry/input idle
and the first writer checkpoint precede a host-validated finite inventory. A one-shot
`background.finish` binds that exact request, process, owner and prefix; the native
writer publishes its final checkpoint and `END_REQUESTED` marker. The host validates
again and consumes `home-final-events.jsonl`. The marker is not an SDK queue-drain
promise: late active Views, foreign events, expiration or missing proof fail closed.
The1.2s allowance is diagnostic; original operational budgets remain fixed.

Original attempts and verdicts remain. Baseline and candidate telemetry differences
require classification; incidental timing/brightness fields are not coverage criteria.


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


## Current composition human collector

EXP210's `human_current_composition` owns the finite source/build and runtime
contracts. `human_build.py prepare --root FRESH` freezes four genuine SDK/source
arms; `build --root ROOT --key baseline-27.1` consumes that arm's fixed build
admission. Each app target must compile its exact source set. This build workflow
never installs or launches an app. Keep rejected and corrected builds separate.

The copied observer preserves the original UIKit/SwiftUI UI and RUM configuration.
UIKit receipt counters use the identified UILabel.text field; SwiftUI counters use
the accessibility label. These observations are distinct and never substitute for
each other. A tap/toggle counter must be readable before publishing its prompt;
a callback still needs exactly one source-defined increment afterward.
It adds passive callbacks, existing-pan observations and requested public window/
accessibility snapshots. Requests and ordered file writes run off-main. Each
snapshot/callback has a bound measured-cost receipt; missing or malformed receipts
invalidate the comparison, while duration is diagnostic. Exact sequence/byte-count/hash checkpoints establish
persisted prefixes before readiness is consumed. This is a paced fixture comparison,
not an uninstrumented production performance measurement.

`human_journey.py` retains the original ordered flows. `human_capture.py` connects
fresh requests, durable prefixes, actual screenshots, native effects, fold geometry
and background capture. `human_runtime.py prepare --root BUILD_ROOT` verifies the
four qualified builds and prepares the same40 cells and manifest-only product
copies. It performs no build or native work. Full runtime review and controls must
bind the resulting plan before `stage` can consume fresh environment and operator
readiness receipts. A stage and every child have fixed execution/cleanup clocks.

`human_operator.py --directory RUNTIME/operator --seconds SECONDS` serves a local
prompt page. Its request-bound Ready/Released buttons acknowledge human setup or
release; they never synthesize native input or acceptance. Fresh session readiness
also binds the live page instance, plan, device and user message. Each actual
screenshot belongs to the current unexpired prompt; old generations cannot be
shown after the step changes. The runner captures native effects and advances the
page itself. It preserves child output before parsing and keeps cleanup prompts
available when a cell is interrupted. It sends no native input.

`human_runtime.py run --root BUILD_ROOT` consumes the admitted matrix in adjacent
baseline/candidate pairs. The first planned baseline qualifies the changed input
mechanism. Any failed mechanism stops this path without a diagnostic retry; a
source-pair difference stops expansion for classification. Preserved cells must
still match their stage, source/product binding and complete artifact inventory.
The existing comparison oracle retains occurrence owners and unchanged limitations.
The comparison report closes no gate by itself and retains the regular27.0 versus
Duo27.1 OS-patch confound. Input witnesses prove observed native effects, not
independent human causality. The current owning record distinguishes attempted qualification from accepted cells.

## Legacy pair sittings

The current S2 triplets use `prepare-s2 --cells` above. The commands in this section
retain the earlier pair matrix only; they do not select the current S2 release slice.

`human_sessions.py prepare --original BUILD_ROOT --root FRESH --series NEW_SERIES
--pairs 1` prepares the first existing pair without building or running it. The
owning result pins the canonical series before admission. Review and controls bind
the new `FRESH/runtime` plan; existing `human_runtime.py stage/run --root FRESH`
consume fresh environment/readiness and fixed sitting clocks. Only required devices
are preflighted. The exact original frozen native oracle serves this fixture family.

For a later sitting, use a new root plus `--previous COMPLETED_ROOT` and the same
original build root. The runner validates completed predecessors in place and
selects only the next untouched complete pairs. It never copies results into new
cells or resets old clocks. Each cell has one append-only canonical admission claim;
a failed/partial sitting or claim publication stops continuation. New operator
readiness is required. First-baseline input qualification and final full-matrix
source classification remain separate from this offline scheduling preparation.
