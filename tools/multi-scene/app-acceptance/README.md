# Controlled app acceptance capture

This validation-only patch serves the existing S2:F08 J01–J04 journeys. The
[capture definition](capture-definition.json) freezes its scope before implementation.
It adds no SDK changes, app routes, interactions or dependencies. Existing accepted
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

## Recorder setup

The validation recorder initializes JSON encoding with source-bound specimens of
all five concrete SDK event types before wrapping the app's mappers. Specimens never
enter RUM or the event stream. One run/process-bound setup receipt records the
specimen hashes and timings separately. This prepares a correctness fixture; it
cannot support a cold-launch or production-performance claim.

Setup-file presence is not readiness. The existing serial writer must finish
initialization, every observation and the exact request checkpoint before the host
can publish a prompt. Missing, failed, foreign or incomplete setup remains invalid.
All real events, including the first action, keep the original timing limits.
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
