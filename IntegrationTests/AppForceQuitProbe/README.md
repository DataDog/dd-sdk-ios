# App force quit evidence probe

This is an isolated experiment, outside all shipping SDK targets. It links KSCrash 2.5.1 using the
shipping SDK's monitor configuration and sends no telemetry. `candidate` means a raw evidence tuple passed the experimental
classifier. It does not mean a gesture was proven or the feature is ready to ship.

`ForceQuitUIKit` uses a UIKit app/scene delegate with SwiftUI controls. `ForceQuitSwiftUI` uses a
SwiftUI `App` and `WindowGroup` with a probe-only application delegate adapter. Both support iPad
multiwindow. They share automatic scene notifications, earliest and post-connection `openSessions`,
and a separate explicit `didDiscardSceneSessions` result. No swizzling is used.

Build 0.1/3 adds a third `reporterLifecycle` hypothesis. It requires reporter installation on both
runs, an empty readable report store, no KSCrash prior-crash flag, a foreground exit, a termination
callback within 15 seconds, compatible source/build and a relaunch within 60 seconds. Retained scenes
do not veto this separate heuristic. The original two verdicts remain available. No third-verdict
candidate enters action preparation. Raw reports are archived locally before pending reports are
removed. Missing, unmatched or unreadable crash reports remain unknown.

On iOS 27+, a retained `MetricManager` archives individual diagnostics, including memory exceptions.
JSON exports include receipt time, event interval and optional process ID. This collector is passive;
absence of a diagnostic does not establish a clean previous run. Older systems omit this collector.
The probe does not use daily aggregate metrics as per-run evidence.

Build 0.1/4 adds three responsive broken journeys: **Infinite loader**, **Back does not navigate**,
and **Empty page**. Assign a host trial ID, select a journey, then tap **Check UI responds**. For the
Back journey, also tap **Back** and confirm that the page stays visible. These local controls make no
network requests. Their counters and journey label survive in the previous-run checkpoint after a
manual switcher removal and relaunch; they are context and never affect classification. A new process
returns to the normal probe controls. **Return to probe controls** exits a journey without killing it.
This build is a separate source/build cohort from earlier trials.

The target behavior is force kill followed by quick relaunch after a user cannot progress. Run the
three responsive journeys first. Test `fatal_hang` separately, then manually remove and quickly reopen
the probe. That is a manual recovery positive. A blocked main thread may prevent the lifecycle
callbacks this hypothesis requires. A normal removal followed by a relaunch after more than 60
seconds is a negative.

The background URLSession cancellation-reason option is documented in the root evidence notes and
deferred. This probe does not create a background session, transfer, endpoint or background capability.

`Verify reporter read refusal` runs the real filesystem reader against a dedicated file where a
directory is expected. It does not modify the live report directory. `Restore startup reporter
evidence` restores the launch observation. The launch argument `--probe-verify-reporter-failure`
exercises the same failure fixture for a host-owned smoke capture; it is never a physical positive.

From this directory:

```bash
swift test
swiftlint lint --config .swiftlint.yml --strict
xcodegen generate
xcodebuild -project AppForceQuitProbe.xcodeproj -scheme ForceQuitUIKit \
  -configuration Release -sdk iphonesimulator -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project AppForceQuitProbe.xcodeproj -scheme ForceQuitSwiftUI \
  -configuration Release -sdk iphonesimulator -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

For a physical device, use a locally authorized development team. The device must be paired,
unlocked, and have Developer Mode enabled. A development-signed Release build can be launched from
the Home Screen without a debugger. Xcode 27.1 successfully compiled this app for iOS 15+ and signed
both variants for the connected iOS 27.2 phone. App Store submission dates are irrelevant to this
local experiment.

```bash
xcodebuild -project AppForceQuitProbe.xcodeproj -scheme ForceQuitUIKit \
  -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build-device \
  DEVELOPMENT_TEAM=YOUR_TEAM -allowProvisioningUpdates build
xcrun devicectl device install app --device YOUR_DEVICE \
  build-device/Build/Products/Release-iphoneos/ForceQuitUIKit.app
```

Repeat with scheme/app `ForceQuitSwiftUI`. To stamp exact sources, compute the source hash with the
root evidence tool before building and pass `PROBE_SOURCE_SHA=THE_HASH` to `xcodebuild`.
Record the same hash and the resulting executable SHA256 in the host trial. A default build records
`unattested`; do not silently include it in an acceptance denominator.

Open the probe, assign the externally reserved trial label, and leave it visible before the manual
gesture. After relaunch, export JSON through the share sheet or use the root `tools/capture.py`.
The JSON and current checkpoint are also in Files under the app's `ForceQuitProbe` directory.
Inspection/export does not change classifier inputs. Fault controls first record the request, then
require an explicit confirmation. A control label is not evidence of the OS terminal outcome.

`memory` allocates and touches 16 MiB blocks until termination or **Stop memory pressure**. A process
death may be an allocator crash rather than jetsam. A fatal hang may stay alive indefinitely.
Externally verify the actual outcome; manually removing a hung probe is a user removal, not proof
of watchdog termination. A bounded five-second hang is available separately.

The checkpoint uses a dirty marker, file synchronization, atomic rename and directory synchronization.
A failed/interrupted transaction fails closed. Export writes run on a serial queue, and the latest
report can be lost at process death; the copied checkpoint remains the classifier's state source.
Per-event enqueue/completion stamps measure the checkpoint, not total callback occupancy. Physical
callback performance and retention policies must be established before any SDK integration. Probe
history is retained for trials; export it, then delete this dedicated app to clear its state.

`applicationWillTerminate` is recorded as a callback fact, independently of normal termination.
The first physical switcher trial delivered that callback and preserved its scene ID on relaunch.
That trial did not produce a candidate. See the root evidence `RESULTS.md` for limitations and the
pending matrix. `ProbeReturnPath` only prepares local custom-action ownership data with durable
consume-before-write behavior. It does not exercise the SDK writer or backend view updates.
