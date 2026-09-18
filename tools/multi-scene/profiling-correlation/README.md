# EXP-187 profile correlation fixture

This fixture exercises one native scene, three sequential manual views and two
overlapping Operations with the same name and distinct keys. Completion is B
then A. The [frozen contract](native-contract.json) owns the twelve native
assertions and physical/backend acceptance. It does not prove simultaneous
windows or scene-specific CPU attribution.

Continuous sampling is100% and application-launch sampling is0%. Sampled
Operations attach only to an already running profiler; they do not start a
standalone profile. Receipt schema2 observes real running context before the
first Operation and at each later checkpoint. The app remains foreground70s
after its final assertions so the normal60s timer can flush and upload. No
forced SDK flush or native testing starter is used.

The implementation lives in the existing BenchmarkTests Runner behind
MULTISCENE_PROFILING_ACCEPTANCE. The ordinary benchmark keeps its legacy
lifecycle and excludes the acceptance classes. No new dependency or existing
build script is changed.

## Repeatable simulator mechanics

Commit the fixture, runner and SDK sources first. Rediscover the simulator UUID
and Xcode installation through live tooling. Use a new nonexistent output path:

```sh
python3 -B tools/multi-scene/profiling-correlation/run_simulator.py \
  --repo /absolute/checkout \
  --developer-dir /Applications/Xcode_27.app/Contents/Developer \
  --device FRESH_SIMULATOR_UUID \
  --output /fresh/nonexistent/exp187-attempt
```

The runner verifies signed HEADs (records authorized unsigned local HEADs),
rejects uncommitted relevant sources, freezes the source inventory, builds
Release with a generated scene manifest, proves the old data container absent,
installs and compares executable hashes, supplies a fresh run UUID and committed
source identity, then checks the twelve assertions and native process ID.
Readiness is observed without consuming it; each assertion precedes its next
critical command. Actual native reference times and server offsets independently
determine exact serialized timestamps and durations, using the SDK's nearest
integer rounding with ties away from zero. The three manual views and the one
built-in ApplicationLaunch view must all be distinct, inactive and in one session;
no extra view or Operation is ignored.

The acceptance build generates an isolated xcconfig that includes the tracked
Benchmark Runner settings, then lets Xcode resolve the existing optional
Datadog.local.xcconfig include and maps CLIENT_TOKEN to DATADOG_CLIENT_TOKEN.
The runner never reads the local xcconfig. Do not include the full Example
Datadog.xcconfig chain: its Base.xcconfig overrides deployment settings on every
benchmark target. A post-build presence/UUID check
rejects unresolved credentials before install without recording values. Ordinary
build mode does not apply this override. The frozen source inventory includes
the native Mach profiler and the tracked configuration templates.

The app persists the receipt in Documents/<run-id>.json. The runner retains it,
build/command logs, source manifest and executable identity under the attempt
directory, and writes a compact durable result to the release Results/acceptance
directory. Failed/invalid attempts remain. Local configuration contents are
never inventoried or logged; the two protected paths are checked through the
existing acceptance helper, using metadata only for the local xcconfig.

To verify exclusion from ordinary Release builds, run a separate fresh attempt
with --ordinary-build-only and omit --device. It checks that acceptance symbols
and the scene manifest are absent. This is compile compatibility, not a new
legacy runtime result. Existing SDK tests are not rerun by either mode.

## Native receipt and actual attachment validation

```sh
python3 -B tools/multi-scene/profiling-correlation/validate.py \
  /actual/native-receipt.json \
  --run-id exp187-FRESH_UUID \
  --source-revision FROZEN_40_CHARACTER_REVISION \
  --attachment /actual/rum-mobile-events.json \
  --rum-response /actual/attempt/backend-raw.txt \
  --rum-counts /actual/attempt/backend-count.txt \
  --rum-end-response /actual/attempt/backend-end.txt \
  --profile-artifacts /actual/attempt \
  --output /fresh/nonexistent/attachment-summary.json
```

For the complete RUM comparison, add --rum-response, --rum-counts and
--rum-end-response with the unmodified full-session search, independent type
aggregate and exhausted-page responses. Query exactly the native session without
filtering event types or owners. The validator checks all12 events, every native
view/Operation ID, run/session identity and both aggregate start/end owners.
Step summary names may be backend URL defaults; authoritative view-event names
are checked by exact joined view ID. Profile correlation flags remain a separate
reported result and cannot certify the raw attachment.

An actual user-downloaded export is valid attachment input when MCP exposes
profiles but no raw download. Preserve the source export unchanged and record
its selected profile ID, provenance, file sizes and SHA-256 for the JSON and
pprof. Retain the unmodified attachment alongside the attempt artifacts. Never
use the receipt's expectedProfileVitals as an exported attachment. Preserve
profile/sample joins and RUM has_profile observations as separate evidence.

Use --allow-simulator only for mechanics evidence. The validator requires the
actual two start IDs and exact integer start_ns/duration_ns values; it does not
accept end IDs, swapped durations, collapsed keys or manufactured expected
attachments. Negative controls also reject stale identities, missing/duplicate
steps, wrong view/session owners, nonfinite clocks and late assertions.

```sh
python3 -B -m unittest discover -s tools/multi-scene/profiling-correlation -p 'test_*.py'
```

## Saved MCP profile inputs

The --profile-artifacts directory contains unmodified MCP response objects as
JSON. backend-query.json records the actual run_id, session, absolute UTC from/to,
rum_query (the full session) and profile_query (service:ios-benchmark). Retain the
query interval used during collection; do not reconstruct a relative window.

| File | Query/result role |
| --- | --- |
| backend-profileInventory.json | profile-id values for the complete service/time window |
| backend-sessionProfiles.json | profile-id values for that service/time window plus exact native session |
| backend-profileJoins.json | Eight ordered get_profiling_tag_values responses, listed below |
| backend-name.json | Continuous profile @vital.label values |
| backend-view.json | Continuous profile @view.name values |
| backend-sessionLabel.json | Continuous profile @session.id values |
| backend-profile.json | Continuous profile wall-time flamegraph, no attribute filter |
| backend-sampleA.json | Same profile/window, attribute=vital_id and exact start-A ID filter |
| backend-sampleB.json | Same profile/window, attribute=vital_id and exact start-B ID filter |

The eight joins are, in order: profile-id selected independently by start A;
profile-id selected independently by start B; launch profile operation;
launch profile @vital.id; launch profile @view.id; continuous profile operation;
continuous profile @vital.id; continuous profile @view.id. Scope every call to
the same service and absolute interval. Profile-specific calls use their actual
profile-id; preserve the launch profile separately from the matching continuous
profile. An unexpected or missing result fails the fixed inventory.

The checker joins the launch profile back to the actual RUM TTID/profile ID,
checks both start IDs and final process labels, and validates each flamegraph's
query/window/type/selection URL and nonempty samples. RUM link flags remain an
independent observation. Its output hashes every supplied profile response and
never treats sample values normalized per minute as exact Operation duration.
The native receipt and actual JSON attachment retain the exact integer oracle.

## Physical and backend boundary

The simulator runner deliberately keeps gate_status INCONCLUSIVE even when
native_validation is PASS. Physical execution requires a freshly discovered,
usable supported device, a frozen signed or authorized unsigned implementation,
clean-install proof, executable identity and the same native contract. A native
profile with nonempty wall-time stack samples and authenticated backend access are required.

Retrieve the complete RUM session and profile time/service inventory. Join all
four RUM steps to the exact native Vital IDs and owners, then compare the real
rum-mobile-events.json attachment with validate.py. Preserve the actual profile
identifier, sample evidence, labels and unexpected inventory. Profile labels
describe process context; they cannot establish per-view CPU ownership.

The receipt/attachment validator checks components only. Its output never
closes T14 by itself: complete backend inventory, physical samples and process
labels remain independent obligations. Missing profile access or attachment
visibility remains INCONCLUSIVE. Do not substitute test attachments, echoed
expectations, successful RUM authentication or simulator sampling for that proof.
