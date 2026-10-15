# Physical device prerequisites

[Acceptance router](../README.md) · Read only the procedure for the selected owning result.
Current admission and qualification live in that result; this procedure grants neither.

## Physical installed-code receipt

For a physical run, supply MULTISCENE_CODE_IDENTITY_RUN_ID and
MULTISCENE_CODE_IDENTITY_REVISION with the same fresh scenario identity. Retrieve
Documents/<run-id>.installed-code.json through the appDataContainer after a
normal launch. The receipt is created before SDK initialization and rejects a
reused file. Run acceptance/installed_code.py with --signed-app, --run-id,
--source-revision, --process-id and a fresh --output. It compares all installed
Mach-O files, including a Debug dylib, to the signed local inventory. No debugger
is needed. Keep native/backend/topology acceptance separate from this identity
check; a passing receipt alone closes no release gate.


### One-scene representative hardware sample

Use the separately frozen vitals.shared-process.single-scene-physical contract
for an ordinary iPhone. Keep the accepted serial contract and its source/capture
identities unchanged. The dedicated validate_physical_local entry point requires
one native readiness,17 expectations/eight ordered guards and exactly two final
inactive views (Home plus ApplicationLaunch). It rejects the serial manifest;
validate_local rejects the one-scene manifest. Both require the stop assertion's
owner to equal the final sampled owner and preserve exact mapper metric values.
The slow-frame configuration guard requires the actual factory to produce
ViewHitchesReader, not merely that a nonoptional factory exists.

Freeze fixture/oracle source before building. Discover the current physical
device and provisioning/signing material, verify unlock and real process/app
inventory, clean-install only the probe bundle and prove its prior absence.
Normal launch arguments are --probe-scenario followed by the exact variant ID,
--probe-run-id followed by a new run UUID, and --probe-run-mode clean. Supply the
matching installed-code receipt environment values. Compare every installed
Mach-O hash with that exact signed app and the independently observed process ID.
Keep the build/source, native records and receipt artifacts together.

Validate the native records with validate_physical_local, then query the complete
session through the same authenticated backend projections used by serial T13:
exactly two vitals_views and no peer_actions, resources, process_long_tasks,
errors or crashes. Use settled_views and validate_backend with that local result;
retain all raw exchanges, pagination/count provenance and exact integer metrics.
The original acceptance.py simulator runner intentionally accepts only the serial
T13 contract; do not pass the hardware variant to it or claim physical proof from
a pure oracle result. Independent device/build/install evidence is still required.
Verify test-app cleanup with fresh process inventory; a disconnected device is
unverified cleanup. A simulator mechanics pass checks this variant's implementation
but cannot discharge the representative-device requirement or H01–H16.


### EXP-194 native Replay coexistence

Use --scenario replay.native-recording.navigation-teardown-serial with the existing
acceptance runner and a freshly resolved iOS27 multi-window simulator. Four native
core-context checkpoints require counter growth before expansion, after B creation
and navigation, and after actual B disconnect plus A navigation. Each checkpoint
binds to independent RUM mapper ownership and live UIWindow geometry/activation.
The scenario contains no browser or injected Replay data.

The runner checks every installed Mach-O, exports native observations before the
oracle, joins the full session backend inventory, and verifies bundle/data cleanup.
Replay view bridge rows require view_id, session_id, name, run_id and has_replay.
Empty action/resource/error/crash queries still require complete query provenance.
A passed simulator slice does not close physical F05 and makes no scene-correct
Replay claim.

### Physical Replay timing

For a physical iPad that reveals A during B close, use `replay_contract.validate_physical_local`. It requires fresh A Home and an actual same-native foreground callback between the B close request and acknowledgement, old A Home stopped after actual background, B disconnect before navigation, and uninterrupted returned ownership. The simulator entrypoint retains explicit-reactivation timing. Both require the same six native/backend views and four real native record-growth checkpoints. The oracle alone never proves physical execution: retain signed build, exact device, all installed Mach-O receipts, complete backend inventory and cleanup. EXP-196 preserves the first timing rejection and requires a fresh run after the oracle freeze.

### Physical H01 precritical admission

The original same-key scenario supports `DD_PROBE_PHYSICAL_TOPOLOGY=1`. Before its first manual start it writes `Documents/<run>.physical-challenge.json` and waits at most five minutes. Arrange the two actual probe windows with native device controls. Start an independent screen recording and capture a screenshot showing both window contents. Retain the challenge, screenshot hash, capture UUID and exact run/process/native-scene/generation identities in a fresh receipt copied to `Documents/<run>.physical-admission.json`. Its capture timestamp must follow the challenge and be at most sixty seconds old. The fixture consumes it once, samples live scene attachment/visibility/lifecycle every fifty milliseconds, and guards before/after steps6–16; loss prevents subsequent mutations and produces INCONCLUSIVE.

Use `physical_same_key_contract.validate_local`, `validate_display` and `validate_backend`. The display proof must preserve the host receipt/challenge, native process identity, actual screenshot/video hashes and timings, and a review that both actual scene contents remained visible through the critical interval. Local frames, capability flags, or a terminal22/22 alone do not qualify. The backend check compares the complete session inventory to every native mapper view and Action/Resource ID, including the seven decisive pairs. The compact unit fixture explicitly contains fabricated topology and clocks; it is never physical evidence.

## Controlled app inventory preparation

`app_journey_inventory.py` supplies offline guards for the finite F08 app journeys.
It is not a scenario in the acceptance runner and grants no runtime or release
acceptance. It consumes decoded full RUM rows and query receipts. Account binding,
complete native phase capture and journey cleanup still need qualification.

The helper preserves raw IDs and available backend revisions, compares distinct
view occurrences and exact owner edges, and rejects incomplete pagination or
foreign query/session identity. Only a verified explicit SwiftUI occurrence may
normalize its process-dependent hash suffix. Browser source/service/SDK version
remain separate from native fields: a full application/session query must include
all partitions. Replay eligibility is required for a persisted container check;
active-at-dispatch ownership needs independent native evidence. Graph equality
still requires review of raw revisions and downstream non-owner values.

`app_journey_transport.py` decodes full MCP responses. Metadata `count` is the
query total even on the empty terminal page. Each page total, accumulated offsets,
exhausted pagination and an independent ungrouped COUNT must agree. Explicit or
textual truncation, stale request identity and partial captures fail closed. Preserve
raw SDK tags separately from exact compiled/installed version strings; do not
normalize build identity. Saved initial data qualifies transport, not a journey.

Run transport controls with `python3 -B -m unittest discover -s
tools/multi-scene/acceptance -p test_app_journey_transport.py`.

Run its offline controls with:

```sh
python3 -B -m unittest discover -s tools/multi-scene/acceptance -p test_app_journey_inventory.py
```

The [source oracle](../../../../DatadogRUM/MultiSceneSupport/Results/S2-F08-source-oracle.json)
owns remaining capture requirements. These controls do not reopen stopped runs.
