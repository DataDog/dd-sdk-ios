# Environment and access

Read this page when preparing a new execution or diagnosing its environment.
The [runbook](../TOOLING_RUNBOOK.md) supplies the common rules. This page does
not admit a run or renew a stopped attempt.

## Rediscover the toolchain and workspaces

1. Verify the actual branch, HEAD, signature and working-tree/index state. Record
   protected paths without exposing configuration values. Recheck the frozen
   source and helper manifests before reusing a build.
2. Read `xcode-select -p` and `xcodebuild -version`; pin `DEVELOPER_DIR` for build,
   simulator and device commands. Do not change the user's default selection.
3. Discover the SDK workspace and separate probe workspace through live Xcode MCP.
   Open the intended workspace if discovery needs its approval handshake, then
   list again. Perform a useful read, such as schemes or test discovery. A running
   bridge or configured server alone does not prove access.
4. Resolve workspace IDs, schemes, destinations and test inventory from the new
   connection. Bind a tool handle to the absolute project path from the actual
   workspace list; keep that handle separate from source-path identity. If a path
   is rejected, retain the response and verify the supported handle before effects.
   Cache identifiers only within that verified connection. `DatadogRUM` is
   the RUM scheme; do not invent `DatadogRUMiOS`.
5. Compare the bridge's destination SDK with CLI discovery. An old bridge can
   survive an Xcode selection change. Stop rather than launch through a mismatch.
6. Discover Datadog tools and make an authenticated read for the intended
   organization/application. RUM access does not prove Logs, Trace or Profiling
   access. Use [backend preflight](BACKEND.md#access-and-query-scope) for each family.

Evidence paths identify old artifacts; old workspace, interaction, simulator and
request identifiers are not authority for a fresh execution. A restart alone does
not invalidate unchanged source, finalized tests or binary evidence.

## Runtime and device qualification

Record build SDK, compiler, deployment target, runtime version/build, device type
and actual destination separately. Deployment 15 compatibility is distinct from
executable coverage: the user-provided debugging environment starts at 17, with
an iPad 17.5 simulator made available. Rediscover availability before execution;
never report 17.x execution or compilation as an iOS 15/16 runtime pass.

The supplied Duo 27.1 simulator requires **Xcode 27.1**, not the 27.0 or 27.2
installations. Pin the discovered 27.1 developer directory and verify bridge/CLI
agreement. Device type alone proves neither active inner display nor simultaneous
windows. The [Duo assessment](../DUO_SIMULATOR_ASSESSMENT.md) owns the measured
limits; [device procedures](DEVICE_INTERACTION.md#duo-display-and-input) own input.

For a legacy-lifecycle host, establish whether its genuine build SDK permits
launch on the selected runtime. Preserve a bundle/PID/time/UUID-matched platform
startup crash before selecting another admitted control. Never patch Mach-O SDK
metadata or suppress the platform check. A passing readiness slice does not close
C03's paired matrix. Exact qualification history belongs to
[EXP-189](../Results/EXP-189-legacy-build-sdk.json) and
[EXP-190](../Results/EXP-190-minimum-runtime.json); unchanged unavailable catalog
requests are not useful retries.

Filter CoreDevice inventories by `hardwareProperties.reality == physical` before
claiming hardware availability. For older devices also inspect the relevant
Xcode's `xcdevice` inventory. A simulator listed by CoreDevice is not hardware.
Before mutating a physical device require paired/connected transport, awake and
unlocked state, successful app and process inventories, and one repeated inventory
that proves the tunnel remains usable. Record hardware UDID and CoreDevice ID
separately. A cable report plus only `localNetwork` transport needs independent USB
enumeration; a disconnected paired record does not qualify installation.

## Semantic boot and process readiness

Require terminal `Finished`, no `Data Migration Failed` text, and a nonempty native
Home accessibility tree before installing a controlled app. `bootstatus` exit 0
alone is insufficient. Freeze toolchain/runtime/device-type and AXe identities.
A finished boot does not establish remote automation access. A failed Home-tree
session stops installation/assertions; retain the error and do not retry on the
same environment merely because the build or boot succeeded.
Scope migration logs to the owned simulator and actual boot interval; preserve
unavailable log access without assigning a cause. The
[stopped Duo checks](../Results/S2-Duo-environment-readiness.json) need a materially
changed environment and a separate admission before another equivalent attempt.

A scene activation callback is a signal to inspect readiness. Require actual
public application-active state and the intended foreground-active scene before
scenario work. If the candidate requires Core's launch observer before launch
notifications, initialize only Core at the declared early boundary; activate the
rest of the fixture after both active-state checks. A bootstrap enum is not proof
of a background scenario or a cold/nonprewarmed launch.

A Main Thread Checker claim requires proof that the checker loaded. For controller
API compatibility, combine getter spies with mounted main/off-main calls; a logical
peer is not another visible native window. See [EXP-164](../Results/EXP-164-controller-threads.json).

## Configuration and local dependencies

The user authorizes use of `Datadog.local.xcconfig` when needed. Preserve its bytes
and index entry, avoid logging values, and exclude client tokens/application IDs
from public commits. Prefer Xcode's existing optional include and configuration
validity booleans. Authorization is not a reason to read it during unrelated work.
A successful placeholder build is not a configured telemetry app; fail before
native actions if required configuration is absent.

Use the accepted probe application ID with a distinct service for authorized
controlled Datadog-app journeys. Those runs do not represent live customer traffic.
Normal app launch is required: existing XCTest paths skip observability bootstrap.

Keep dependency resolution frozen. Check exact package revisions, archive checksums,
extracted framework inventories and architecture metadata before building. A fresh
worktree can lack ignored `Package.resolved` and Carthage OpenTelemetryApi binaries;
copy only qualified inputs with matching hashes. A pin alone does not establish
that the installed binary is the intended dependency. No automatic updates or
persistent Git/build-setting changes are implied.

For benchmark configuration, use the tracked Benchmark Runner template plus the
existing optional local include and map `CLIENT_TOKEN` to `DATADOG_CLIENT_TOKEN`.
Do not include the full Example configuration chain: its global deployment settings
can invalidate the benchmark's existing newer-API sources. Let Xcode expand values;
keep resolved credentials out of command arguments and summaries.

For controlled app builds, resolve the verified SwiftGen executable before build
admission. `DD_SKIP_LOCAL_BUILD_TOOLS` does not disable SwiftGen installation
fallback. Freeze literal generator commands, templates, resources and generated
outputs; keep empty comment-only files distinct from compiled inputs. Redact
credential literals in compiler source excerpts as well as resolved settings.
Exact historical tool versions and build receipts belong to the
[app preparation record](../Results/S2-F08-app-preparation.json).

## Unavailable desktop or transport

If the Mac locks, retain and clean any incomplete UI run, keep one pending unlock
request, and continue useful source, documentation or offline work. Caffeinate
cannot unlock the Mac. Start it only for a user-authorized duration, record the
owned PID/deadline and verify assertions; stop only that process. Do not implicitly
renew it or change persistent lock preferences.

An inaccessible device after a successful capture leaves cleanup unverified.
Preserve passing components, then reconnect to verify only the exact app/process
cleanup; do not repeat the capture. Failures before install/launch are environment
results, not SDK behavior. Follow [cleanup](DEVICE_INTERACTION.md#cleanup-and-interruption).
