# Device interaction and cleanup

Read when an admitted scenario needs installation, native input or cleanup.
[Environment](ENVIRONMENT.md) owns connection/toolchain readiness;
[evidence](EVIDENCE.md) owns source and semantic acceptance.

## Prepare before opening a session

Read the live Xcode-provided interaction instructions. Export any required skill
to a fresh absolute path and inspect it before interaction. Follow the live tool
schema and any required delegation: the same owner must start, install, capture
and end its session. Keys are scoped to the creating context. Missing supported
interaction instructions are a workflow limit; do not invent commands.

Finish source review, scenario choice, expected results and input strategy first.
Start a workspace session with a fresh identifier, use the returned key exactly,
and preserve each live parameter spelling (`interactionSessionKey` versus
`interactSessionKey`). Do not start a replacement merely because a key looks
human-readable. Confirm invalid/expired state through an actual call first.

A physical CoreDevice/Xcode destination need not support tool interaction. If session
setup rejects it and offers only simulators, preserve the error and stop that path.
Use the prepared human contract; do not cycle selectors or infer session creation/absence.

## Clean installation and launch

1. Resolve the exact target and probe bundle; qualify physical connection/signing
   before mutation.
2. Terminate only its running process, uninstall only that bundle, and prove app
   and data-container absence before install. A session opened to discover the
   target does not itself contaminate this boundary.
3. Install the frozen binary and compare its complete installed Mach-O inventory.
4. Launch with inherited arguments plus `--probe-scenario <id>`,
   `--probe-run-id <fresh-id>` and `--probe-run-mode clean|restoration`. Do not edit
   shared schemes for a run. Existing output/receipt identities must be rejected.
5. Confirm actual process, run ID, configuration and scenario readiness before
   the first critical action. Retain raw records from process start.

Restoration uses its defined predecessor/data container, not this clean sequence.
A clean app container may leave SwiftUI window-server values: normalize telemetry
run IDs to this launch while preserving routed values only for window identity.
Check every view in the resulting session. An unexpected initial scene is INVALID;
do not rename it to the expected one. Use a separately admitted fresh target or
proven window cleanup. A stale `get_app_container` path after reboot needs path-
existence evidence, scoped uninstall and absent app/data lookup before installation.

## Physical signing and installed identity

The probe can compile with signing disabled. Before uninstalling, require a valid
Apple Development identity in the actual user's keychain, a device-granted profile,
command-local team selection and an `arm64` build. Restricted-context zero identities
must be checked in user context before declaring credentials unavailable.
Verify app signature and embedded profile before install; do not commit signing
material or change accounts, credentials or persistent build settings.

If scheme-wide signing contaminates package targets, the local fallback is an exact
unsigned build copied to a fresh directory. Use an existing profile/certificate
that grants this device and bundle; derive minimal concrete entitlements, inventory
nested Mach-O code, sign depth-first then the outer bundle, and perform strict/deep
verification. Do not use `--deep` to create signatures. Preserve signed and unsigned
copies and independent team/certificate/device/app-ID checks. Creating or replacing
credentials requires user involvement. An unsigned install rejection is not SDK
execution; verify app/process absence and retain the original logs.

CoreDevice app-data transfer does not expose the bundle. Use the fixture's
pre-SDK installed-code receipt with `MULTISCENE_CODE_IDENTITY_RUN_ID` and
`MULTISCENE_CODE_IDENTITY_REVISION`, then compare it using
[installed_code.py](../../../tools/multi-scene/acceptance/installed_code.py).
Require exact run/revision, process, bundle/executable and all Mach-O hashes,
including the Debug dylib. A reused/malformed receipt prevents initialization.
A generic arm64 build is acceptable only when declared; install/run proof must
still come from the exact physical device. Do not suspend acceptance to attempt
an unverified LLDB file transfer.

`devicectl ... --console --log-output` may put only launcher status in that file.
Capture actual console separately and verify the durable JSONL before ending.
Command exit 0 does not establish attachment, console capture or app success.

## Input and readiness boundaries

For interactive scenarios capture live hierarchy, confirm the expected identifier
and hit point/visible bounds, send the prepared input, then collect native effects,
hierarchy and screenshots. Activate the observed bundle when necessary. Do not
reuse guessed coordinates, alter layout to make input pass, or substitute a
programmatic gesture. Use the exact admitted drag duration and retry policy.

Prepare the receiver and evidence-transfer format before capturing a time-bounded
UI snapshot. Retain the complete raw text losslessly; transfer and persistence count
against its original freshness limit. A stale snapshot stops before mutation. Shorten
the handoff and review a separate continuation rather than extending that limit.
For a reviewed scripted input, inspect the runner's current readiness image first;
keep fresh tool capture, exact semantic/owner checks, dispatch and publication in
one awaited sequence. Inspect the actual result afterward. Freeze selectors before
execution, bind coordinates to the new hierarchy, and preserve actual responses
and pending local helper handles on failure. A dispatch intent alone proves neither
input delivery nor quiescence; never relabel attempted input as a zero-action stop.

Bind AX readiness to the observed role and attribute namespace: a SwiftUI text-field
placeholder may appear in `AXValue` with a null `AXLabel`. Require the exact unique
field and heading, preserving negative controls for wrong or ambiguous elements.
Before a coordinate tap during a form animation, observe stable target geometry
inside the original effect deadline. A command success alone proves no UI outcome.

Serialize input authorization with cleanup. A completed UI call and persisted
post-input evidence must establish quiescence before pose changes or app removal.
Post-dispatch failures remain uncertain; defer cleanup explicitly. Reject new input
once cleanup starts, and recheck any conditional cleanup input before uninstall.
A late terminal receipt cannot turn a failed run into acceptance.
If the one admitted mechanism qualification or continuation misses publication,
stop that automated path. Prepare the ordered human-input session with runner-owned
capture/assertions; do not add equivalent input diagnostics or a larger retry budget.

Fully automated signal-driven scenarios do not need `Synthesize` to advance.
Accessibility collection can block them; collect after terminal unless earlier
visual proof is part of the contract. Preserve a failed capture before admitting
any changed-configuration comparison. No general retry permission follows.

`open-window` consumes its `scene-ready` acknowledgement. Do not wait for that same
signal twice. For a later occurrence use an after-index/fresh-occurrence condition;
a stale earlier event can satisfy a poorly placed wait. A short marker can occur
before subscription: prefer terminal evidence when it already proves that marker.
A delayed task is not an exact stop clock; explicitly gate work before stop and
after the newly revealed destination. Neither sleeps nor later assertions repair
missing precritical readiness.

An expired session before input proves no gesture. A fresh session can retain the
clean boundary only if logs prove no install, launch or state mutation occurred
since it; otherwise repeat the complete admitted clean setup with a new run ID.
Preserve any partial attempt rather than merging it into a later pass.

Finish helper preparation before opening the interaction session. Bind the actual
returned key and verify it with a live capture near input; a successful StartSession
receipt does not prove later liveness. If the first capture reports a missing
session, retain that zero-input result. Close or prove session absence before app
cleanup. A fresh-session comparison needs a new identity; repeated disappearance
is an environment blocker, not an SDK finding. SwiftUI automatic coverage requires
its [supported capture prerequisite](../../../tools/multi-scene/automatic-coverage/README.md); a compiled reader or restoration graph cannot qualify a new launch.

For the controlled Datadog app, use the [F08 capture overlay](../../../tools/multi-scene/app-acceptance/README.md)
in identified validation builds, preserving predicates, controller classes and mapper
filtering. Navigation, SwiftUI lifecycle, Browser payloads and asynchronous context
receipts have separate meanings. Consume durable prefixes before readiness; exclude
unknown auxiliary content. Preserve original builds. After failed human input, retain
capture and require explicit release then fresh same-PID idle topology before teardown.
Missing proof means incomplete cleanup; record later restoration separately.

## Duo display and input

Verify the active inner display and actual window geometry/lifecycle. Use observed
Device Hub pose controls, then require fresh display and native geometry readback.
The supplied platform restricts new Duo windows to the inner display. An AX tree,
requested orientation or successful tap/drag alone cannot prove visible pairing,
a fold or an interactive transition. A black inactive-display capture is not
layout evidence; select the actual active-display ID for direct capture. The sidebar
icon can retain a previous pose: use it only as observed UI data, never as pose
proof. Bind the exact selected device and actual control to independent display
and native geometry evidence.

A single scene may expose additional windows. Inventory their public identity,
scene, key/hidden/alpha, level, frame, root controller and screen before classifying
them. Total window count alone cannot identify a peer or harmless auxiliary window;
do not accept an earlier callback after a newer ambiguous sample. Capture current
geometry and complete inventory together on the main queue at each critical
boundary: a window can appear without another geometry callback. A later class
observation cannot identify an earlier unrecorded window.
Class names are diagnostic metadata. Use source-supported fixture ownership and
public framework provenance for auxiliary windows, with exact owned scene/window/
controller/root/key identities. Never hardcode private classes or an arbitrary
allowed window count; unknown ownership remains a failure.

Use a dedicated file for `devicectl --json-output`; stdout may also contain a
human-readable summary. Preserve both streams and validate the structured command
identity before joining display and native geometry. Qualify the actual capture
function before installing a fixture.

For `appResize`, distinguish no active session (`24004` in the recorded preflight)
from unsupported capability. Keep the owned resize process alive through the
sweep, record display size separately from app bounds, and end only that session.
Cleanup may background the scene; export before that boundary and do not claim
uninterrupted ownership across it. A black resize capture limits visible claims.

Require accepted route and fresh native geometry before work; materialization is
an observation, not a route commit. Use lifecycle/scene-ready/geometry receipts,
not later assertions that copy geometry. Admit each phase only after the preceding
resource/end pair. Join declared custom actions by exact IDs and `action.type`;
automatic actions can inherit marker attributes and must remain separate.

Native gesture readiness requires compact geometry, active destination and an
actual transition coordinator. Element existence is weaker than hittability;
follow the observed overlay/Back control and prove the intended native effect.
A switch needs callback plus value change, and a scroll must actually move content.
Successful tool delivery without recognized begin/resolution is inconclusive.
Stop at the admitted equivalent-attempt limit; preserve unexecuted prerequisites.

For simultaneous visibility retain both scene identities, geometry and activation
through the critical interval, with suitable continuous visual evidence. Two
registered fullscreen scenes with one backgrounded do not satisfy the requirement.
[Simulator fidelity](../DUO_SIMULATOR_ASSESSMENT.md) and each gate retain physical
limits; no tool workaround waives them.

## Cleanup and interruption

`simctl listapps` can emit an OpenStep property list. Decode saved output through
Apple's `plutil` before applying exact bundle-absence checks; Python plistlib does
not support that representation. Preserve a failed cleanup verdict separately from
later proof of app, data, simulator and process absence. Persist terminal state even
when cleanup raises, so an earlier running-state receipt cannot become the cursor.

A reaped driver PID does not prove its command descendants are gone. Keep native
commands in the owned cell group, prove worker quiescence before task teardown,
and require a final group-absence receipt before overall acceptance. Preserve the
child result separately from the supervisor verdict. Retire the actionable human
prompt immediately on cleanup entry; publish any restoration gesture as a separate
cleanup request. EOF can precede process exit: wait within the original cleanup
budget before escalation, and never relabel a late absence receipt as timely.

For human input, host-worker absence does not prove the operator has released a
gesture. A failure must retire the prompt, request release and stop, and require
operator acknowledgement plus native idle/terminal evidence before app teardown.
If either is unavailable within the original cleanup budget, defer teardown and
retain that unresolved verdict. Never terminate a held gesture merely because
evidence transfer or an observer failed.

The physical transition runner publishes a request-bound `human-release/request.json`.
After an actual operator reply, record it with `physical_release.py --request <path>
--user-message <reply>`; never infer release from elapsed time. The runner then
captures a new checkpoint from the same process/window, requiring zero touches,
idle public pan recognizers and no transition coordinator. A suspended task first
requires preserved preactivation bytes and actual same-PID/executable activation
after release. Verify the prefix is unchanged and keep the later idle stream
separate; no scenario/backend evidence may come from cleanup reactivation. Use the
existing idle/cleanup deadline, with no extension or replacement process.
That cleanup-only proof does not discard earlier failure rows or qualify the scenario. Expiry leaves the
app installed and cleanup incomplete; later restoration is a separate record.

Interactive sheet pans can begin before a controller transition is observable.
The reviewed EXP223 correction resolves only from actual recognizer callbacks,
retaining the public coordinator inventory at every lookup. Unrelated content
pans cannot satisfy the chain; exact source-bound endpoints, live interactivity,
registration before interaction change and actual completion remain required.
Capture actual terminal values and the public controller graph before validation,
with distinct failure reasons. A modal transition container can disappear after
completion or cancellation; its lifetime does not establish the surviving owner.
Preserve actual nil values and require original endpoints/request/callback order,
the returning key window/scene and the appropriate public presentation graph at
terminal and after settling. A different nonnull container remains invalid.
Presentation getters can inherit an ancestor's relationship: select reciprocal
presenter/presented ownership before uniqueness, retaining the complete inventory.
Do not infer extra presentations from inherited aliases or hardcode class names.
An ordinary iPad can omit the Duo `active` field. Select its single lit primary
integrated display with a scoped parser and preflight it before installation; do
not invent response fields or relax the Duo fold parser.
For public accessibility inventories, visual UIView ancestry and accessibility
container paths are distinct evidence. Retain both; compute view hidden/alpha from
its owned physical hierarchy, and require exact identifiers before target input.
The separate simulator capture qualification retains complete current UI-tool
returns plus their exact returned artifacts. It cannot promote a human, candidate
or physical-device gate, and its cleanup must finish before a successor cell.
A workspace-free capture can report `NotRun` while naming the running app in its
hierarchy. Bind actual bundle/PID to the native launch before input; retain the
scalar state unchanged. Start a waiting host runner before session creation so it
can consume the actual ready receipt and dispatch directly; another model/tool
handoff can outlive readiness. Start the fixed setup budget before simulator boot;
require a fresh device/plan-bound boot-completion receipt before publishing the
session request, then verify actual session creation follows that receipt. Check
boot completion again before installation-state reads. Failed boot must publish no
input request; restore the owned boot state even if no session was created. Keep
original setup failure and later restoration separate; successful boot alone does
not explain or repair a failed capture.
A failed empty capture may prove zero-action quiescence only with its complete return and explicit worker stop. Uncertain action delivery
cannot authorize teardown.

A physical evidence copy may recover once from the specifically qualified
CoreDevice7000/POSIX60 socket failure. Require the failed command's exact device
binding, preserve each destination and response, and keep the original deadline.
Any other failure or late response stops the read; cached bytes cannot replace it.

A real background notification does not prove that a delayed writer ran before
suspension. When finalization is required, the fixture must retain its existing
allowance inside a bounded background task and validate the final View/Action
inventory against actual writer and END_REQUESTED receipts. This is not an SDK
queue-drain promise. Qualify the Home-only mechanism before repeating operator
gestures; later foreground activation or restoration cannot repair the old run.

Export app JSONL, runner checkpoints/hierarchy/images, console and partial xcresult
before uninstall. Bind each to this run and contiguous sequence. Preserve raw
bytes even if parsing fails; ignore foreign receipts and reject symlinks. Cleanup
must run after attempted boot/install, including preparation failures, and retain
capture errors alongside the primary failure.

Reap matched task processes, remove only task bundles, prove absence and restore
owned state. Keep failed cleanup and later restoration separate. During cleanup
reactivation, a same-owner inactive snapshot stays pending within the fixed budget;
only active topology plus native-input idle permits teardown, never Home credit.
Preserve errors and stable identity; only declared inventory usage/size may vary.

After reconnecting a physical device, resolve its installed bundle and fresh PID.
A reused PID alone does not identify the old run. Verify a different process before
termination, then read a fresh inventory proving absence. Transport loss leaves
cleanup unverified; continue cleanup after reconnection without repeating a passing
capture. Restore temporarily authorized system preferences, and stop only the
owned keep-awake process at the agreed boundary.

On pause, preserve source/definition/helpers/controls and the original deadline.
Close the attempt, release the host and write the sole next action in the cursor.
A later execution needs fresh discovery and a separate bounded admission; it does
not silently extend the old run or repeat accepted tests.

For generic accessibility objects, retain exact public identifier provenance. A
nonconforming object may expose the documented getter: verify selector support and
object-return ABI before invoking it, then accept only an actual string. Labels,
frames, private selectors and KVC cannot replace a missing fixture identifier.
Fixture compilation and mock controls remain separate from native qualification.

An explicitly reviewed physical supported-input mode uses remote PID/executable
identity and actual device/session observations. Never reuse simulator process
checks or invent operator readiness. Its [fixture procedure](../../../tools/multi-scene/interactive-transitions/README.md)
binds every ordered effect and independently completed worker before collection.
The final Home may follow native idle only as a contact-free command; failed input
needs separate cleanup-only idle proof. Uncertain delivery defers teardown.
