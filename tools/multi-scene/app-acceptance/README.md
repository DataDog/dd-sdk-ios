# Controlled app acceptance capture

This validation-only patch serves the existing S2:F08 J01–J04 journeys. The
[capture definition](capture-definition.json) freezes its scope before implementation.
It adds no SDK changes or dependencies. Existing accepted
app builds and earlier failed Home runs keep their original verdicts.

Capture uses the app’s existing navigation delegate and scene/window hooks. It
preserves controller classes, custom predicate results, all mapper results (including
filtered errors), and the original `trackRUMView` expression. Native delegate,
SwiftUI lifecycle, mapper and asynchronously received core-context observations are
separate evidence. None is relabelled as a different callback or a synchronous owner.

Raw controlled-session mapper and Browser data stays in local artifacts. Copy only
sanitized summaries to the repository; never print configuration or token values.
The Browser observer returns false and does not mutate messages or replace handlers.

No build or native execution is admitted by this preparation. After offline controls
and review, create separately identified symmetric app builds. Qualify capture in
the first planned baseline journey of the ordered human session. Do not add an
extra input diagnostic or reopen an old deadline.

Build and capture helpers are separate from native admission:

- `capture_build.py` freezes all app/SDK sources, target membership, dependencies and
  generated compiler inputs. Copied module maps require an exact, reviewed umbrella
  path relocation; dependency Git metadata and Tuist workspace state are classified
  separately. It reuses the accepted direct Xcode build with no Tuist regeneration.
- `capture_product.py` checks and fingerprints the full bundle, Mach-O inventory,
  final link command and resolved SDK archives. A launcher hash alone is insufficient.
- `capture_io.py` publishes fresh requests and preserves actual writer receipts and
  stream bytes before decoding. Concurrent callbacks may follow a snapshot before
  its checkpoint; the actual snapshot remains the boundary. Before a human prompt,
  a full readback validation rejects consumed readiness or incomplete observations.

Every failed preparation and closed deadline remains immutable. Changed build
inputs require fresh copies and admission. A checker correction can re-evaluate
valid saved outputs without rebuilding or extending the original deadline.
These helpers do not replace native, backend or cleanup verdicts.

## Simulator signing prerequisite

Authentication depends on the app’s source-declared Keychain access group. Do not
build this fixture with `CODE_SIGNING_ALLOWED=NO`: the app can receive successful
HTTP responses while Keychain rejects credentials/profile storage with `-34018`.
A Services permission shell may therefore reflect missing local user state.
Qualify Xcode’s resolved simulator entitlements and the installed product before
account setup. Preserve original deficient products/results; use fresh build
outputs and leave authentication code and SDK sources unchanged.

`simulator_signing.py` retains the qualified build guards and changes only Xcode’s
signing flag. `signing_product.py` binds both the code-signature and simulated
entitlement planes, including XML and DER in the actual launcher. Simulator
capabilities may live in `__TEXT` while `codesign` reports empty entitlements.
Require the resolved application identity, Keychain group and app group; reject
undeclared capabilities. Verify source/compiler/archive identity and the full
product, including executable and resource-bundle signatures. An offline checker
reassessment keeps its first failed verdict and revalidates saved producer evidence;
it does not rebuild or renew the original deadline.

For in-place simulator updates, stop the exact main executable. OS-hosted app
extensions are not input workers. The installer may refresh a data-container UUID;
retain its actual migration evidence instead of treating path equality as data
continuity. Do not claim byte-for-byte preservation without a before/after inventory.
Neither successful signing nor a clean startup qualifies authenticated Services.

## Simulator QR login

The user-requested image input adds **Choose QR Code Image** to the existing QR
scanner in both comparison builds. The user reports a 30-second QR validity window.
Finish build, recorder and session preparation first. During the live sign-in step,
open the QR screen and arm `qr_image_import.py` for the confirmed screenshot folder
(Desktop). Only then refresh the QR code and take one screenshot. The helper imports
it directly into simulator Photos; open **Choose QR Code Image** and select it.
No chat upload or model/tool round trip belongs inside that validity window.
A fresh QR code is needed only when authentication is required. Account setup is
separate from measured navigation and should be reused once qualified. It is not a
timing measurement or SDK acceptance criterion.
The system picker exposes only the selected image. A bounded, off-main decoder
rejects unreadable images or multiple codes, then uses the existing URL login
handler. Authentication validation is unchanged; image data and decoded credentials
are never added to diagnostic messages. Cancellation submits no login.

The importer binds the current authentication prompt, device, generation and
deadline. It ignores pre-existing images, rejects ambiguity and changed/symlinked
input, and stops when the prompt closes. There is one bounded import with no retry.
The private transfer copy is removed; the user's original and imported Photos image
remain. Offline controls and review precede the first planned baseline qualification.

For one-time setup outside a journey, use `--account-setup` with its separate
admission and actual QR-screen receipt. The guard requires the original live app
process, owned screenshot/hash, fresh generation and no cleanup. The same one-shot
transfer rules apply; setup cannot grant test evidence or release credit. Let the
user enable the needed Services/APM and dashboard read permissions in consent.
A permission-error shell is not a loaded list. Retain the installed app/account
when requested; never export credentials. A signed-in journey requires its own
reviewed mode and fresh capture/session identity. The existing login mode cannot
be repurposed by skipping steps or reusing an expired plan.

`qr_image_patch.py` changes an existing LoginUI source file; it adds no project
member. `QRCodeImageDecoderControls.swift` checks synthetic screenshots, rotation,
downsampling, corrupt/ambiguous input and cancellation. The compiler input change
requires fresh symmetric builds; the host-only product-reuse transition does not
apply. The first planned baseline qualifies native selection and authentication.

## Retained authenticated journeys

Use the separately defined `signed-in-smoke` mode after corrected signed account
setup proves the selected profile, organization and real Services row. Keep the
ordinary `smoke` mode unchanged. Signed-in mode omits only its three login phases
and subdomain-login action; the eight Services/dashboard/lifecycle boundaries and
all telemetry ownership checks remain. Search may hide the Services title: finish
search and close its field before the ready boundary; a heading alone never qualifies.

The first planned baseline binds non-null user/organization IDs as salted comparison
digests before service-detail input. Candidate identity must match. Raw capture stays
private; plans, prompts and summaries never contain account credentials or raw user
IDs. Setup without the recorder is not mistaken for captured RUM identity.

Install the exact qualified products in place, after stopping only the known main
process. Preserve Keychain/account data and unrelated Documents; archive only
verified recorder-owned files. Each arm still gets a fresh run, nonce, process and
RUM session. Cleanup seals capture, stops the owned process and proves retained
product, non-task app inventory and display state. Never use the ordinary uninstall
cleanup for this mode. Native admission follows focused controls, designated review,
source/product reuse checks and fresh operator readiness.

Dashboard navigation pushes a source-defined wrapper, with the labelled dashboard
as its child. Require reciprocal current containment and the wrapper's latest
completed navigation callback; never relax Services/detail navigation to arbitrary
ancestors. The signed-in dashboard interaction changes its unique native duration
button from `1h` to `15 minutes`. Its displayed `15m` follows the WebView-confirmed
interval under the source's consistent-timeframe setting. Retain the same attached
dashboard/WebView and exact telemetry owners; do not reuse labels from another widget.

The native one-hour initializer does not guarantee the ready dashboard range:
WebView-confirmed intervals replace it, and a retained account can reopen at `15m`.
For signed-in mode, `prepare_dashboard` leaves a source-owned `1h` control alone or
requests one captured `15m` → `1 hour` setup. Unknown or ambiguous values stop before
input. The setup must preserve the actual refreshed prompt, writer snapshots,
owned controller/view/WebView and confirmed `1h` effect before the unchanged
`1h` → `15 minutes` comparison. Preserve setup telemetry in the complete inventory
and identify that extra input in the final paired review; it cannot replace the
measured interaction or close a gate by itself.

After a stopped candidate, verify its installed candidate manifest and process
absence before restoring the frozen baseline product in place without launch.
Preserve account, Documents, unrelated apps/display and the failed capture. The
ordinary candidate installation guard still expects the verified baseline product;
never validate the installed candidate against a baseline manifest.

Native dashboard appearance can precede WebView URL assignment and Browser startup.
Wait for the source-owned attachment, loaded URL and valid preceding Browser inventory
inside the original readiness deadline. Preserve each pending snapshot; wrong ownership
or malformed evidence is invalid. A later cleanup snapshot cannot repair a missed boundary.

The fixture records resign-active, background and become-active callback pairs.
Require those exact ordered pairs and bind Home to the recorded background exit;
do not require an uninstrumented foreground callback. Keep the oracle inventory
checked against the producer source. A separate saved-evidence reassessment may
correct an oracle error without changing the original failed run or its deadlines.
Validate reviewed native admission before consuming output or starting the supervisor.

For a completed baseline stopped by that oracle error, `saved_baseline.py` can bind
separately reviewed local/backend evidence as the predecessor of one candidate-only
plan. It preserves the original failed summary and requires its timely cleanup,
quiescent workers, retained account, exact products and selected journey. An explicit
reviewed receipt binds any host-helper or authorized documentation transition.
The candidate gets fresh run/process/session identities and fresh operator admission;
the saved packet never becomes a synthetic baseline pass or closes a release gate.

Browser duration vitals remain an incidental partition with typed identities and
ownership checks. They neither supply required view/action/resource coverage nor
introduce metric-quality acceptance. An absent anonymous ID is permitted only in
the startup prefix before the first stable ID and before any Browser dispatch.

After a failed prompted step, preserve the failed native prefix, request an explicit
`Released` reply, then capture fresh same-PID owned foreground topology without an
active transition before teardown. The separate cleanup request uses the original
cleanup budget; it cannot renew the scenario. If release or idle proof is missing,
leave the app retained and cleanup incomplete for separate restoration. This tap-only
journey does not claim direct gesture-state capture. A late reply never retroactively
authorizes an earlier teardown.

## Recorder setup

The validation recorder initializes JSON encoding with source-bound specimens of
all five concrete SDK event types before wrapping the app's mappers. Specimens never
enter RUM or the event stream. One run/process-bound setup receipt records the
specimen hashes and timings separately. This prepares a correctness fixture; it
cannot support a cold-launch or production-performance claim.

Setup-file presence is not readiness. The existing serial writer must finish
initialization, every observation and the exact request checkpoint before the host
can publish a prompt. Missing, failed, foreign or incomplete setup remains invalid.
All real events retain their original timing observations. Future correctness smoke
reports historical cost thresholds separately; strict timing is not an acceptance
criterion under the project measurement rule. Structural capture, readiness, owners
and bounded execution remain mandatory.
Timed callbacks capture current controller identity and relationships; complete
readiness snapshots additionally discover class/bundle provenance. No controller
metadata cache or deferred event encoding is used.

Preparation rejects products whose compiled recorder bytes differ from the current
source. Recorder changes require fresh symmetric builds and a separately admitted
baseline qualification. Earlier stopped attempts retain their original verdicts.

## Runtime journeys

`journey_workflow.py prepare` binds the existing complete products to the finite
[journey definition](journey-definition.json). Preparation never admits execution.
`journey_session.py` reuses the existing human operator page and owned-process
supervisor for one reviewed arm. Fresh operator, account and environment receipts
are required; `journey_connector.js` exchanges only a published backend request.
The [owning record](../../../DatadogRUM/MultiSceneSupport/Results/S2-F08-source-oracle.json)
contains current identities, controls and remaining prerequisites.

The transport freezes absolute UTC dates for each broad/native query pair; later
polls may see delayed uploads, but COUNT and every page keep the same query dates.
F08 alone accepts the MCP's explicit next-offset pagination notice when the JSON
array is complete and its displayed count/offset agree. Independent COUNT, stable
totals, unique event IDs, sequential receipt offsets and an empty terminal page are
still mandatory. Raw response parts are retained in batches of at most eight
independent writes before sealing; every sibling result is inspected. A complete
saved-session fetch qualifies transport only, never the stopped native scenario.

The driver proves actual input effects, native attachment and mapper owners before
each step. Complete refresh observations can trigger a fresh snapshot within the
original prompt deadline; a refresh is never substituted for native readiness.
Browser payloads retain their own service/version and view IDs. J03 separately
checks the still-active native owner beyond the existing retention interval.

After the final Home step, the original process stays alive in background until
complete backend evidence is retained. The driver then stops it, requires the
sealed stream to equal the frozen inventory, and rechecks only saved responses.
It issues no query after termination. Any new tail, incomplete inventory, late
publication or failed cleanup keeps the original acceptance INVALID.

A complete baseline mechanism can permit the planned candidate. Final occurrence,
Browser and incidental-event source classifications remain separate release work;
mechanism qualification alone cannot close F08. All raw controlled-session data
and account selections stay in private local artifacts.

## S2 smoke mode

Use `journey_workflow.py prepare --mode smoke` for the narrowed
[smoke definition](smoke-definition.json). It revalidates and reuses both compiled
capture products. The original journey definition and its historical results stay
separate; preparation does not admit native execution.

The sequence covers login/subdomain/Back, Services list/detail/Back, one actual
read-only dashboard control, and one same-process background/foreground cycle.
There is no extra Home drain or timed cache-expiry wait; T10 owns expiry coverage.
Expected named views and the subdomain action are bound to app source before any
baseline run. Native account and control readiness still qualify in the first
planned baseline; a failed mechanism does not admit the candidate.

The final foreground writer checkpoint freezes the behavior prefix. Leave the app
on Services while its normal uploader runs. Complete backend queries must contain
the captured event IDs and owners. A later captured revision may represent the same
view; a different event with the same name cannot replace a missing event. Later
capture bytes are retained separately and cannot expand the behavior prefix. No
forced flush, tracking change, extra gesture or deadline extension is used.

The smoke comparator preserves raw payloads and checks view/action/resource/browser
identity, ownership, lifecycle and existing trace links. Incidental metadata and
reducer updates remain available for review without requiring session closure or
complete payload equality. Browser container claims require observed Replay
eligibility; absent coverage is reported explicitly. There is no Replay-content
check. Final paired source review still owns F08 closure.

Backend view reducers match the captured occurrence's ID, date, name and URL.
Their document version, activity and user enrichment are retained separately;
local capture owns lifecycle and revision history. Reducer witnesses use the frozen
behavior capture, or the first capture of a delivery-only occurrence, so later
updates cannot change the final join. Native operations cross-check indexed start/
end vital IDs, names and owners; this is backend consistency, not independent native
step capture. Browser operations bind a captured start. CPU/memory batches
are session-scoped; vitals retain their captured owner where required by source.
These incidental families never satisfy ordinary event, view or container coverage.

The correctness smoke publishes separate semantic and recorder-cost verdicts. A
cost overrun alone does not block candidate comparison or F08 closure; complete
paired native/backend evidence and source review must still resolve any concrete
observer-induced ownership or capture ambiguity. Original stopped attempts retain
their original invalid verdicts. No performance qualification is implied.

A reviewed host-only policy change can reuse unchanged products with
`prepare --runtime-transition <manifest.json>`. The manifest binds exact old/new
helper hashes to the scoped review and controls. Compiler/recorder/app/SDK sources,
dependencies and all product files remain exact. The legacy binder stays strict;
new plans freeze the transition and revalidate it before execution and cleanup.
