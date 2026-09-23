# Ordinary scene API compatibility client

This fixture qualifies the local experimental API implementation for C06 and
F03 M02/M03. It does not approve F01, promote public API, query Datadog, or replace
human-input or physical acceptance. The bounded same-key continuation below provides
a separate native API ownership check.

The client targets iOS 15 without caller-side OS 27 guards for ordinary APIs.
Run it on an available ordinary iPhone 27 simulator and the iPad 17.5 simulator,
with automatic UIKit view tracking off and on. Actual iOS 15/16 execution is not
available. Semantic host APIs keep their separate iOS 27 availability.

## Build and admission

Read the owning experiment and discover current simulator identifiers first.
Use a new evidence directory for every changed set of build inputs:

```bash
python3 -B tools/multi-scene/api-availability/build.py prepare --root <new-root>
python3 -B tools/multi-scene/api-availability/build.py simulator --root <new-root>
python3 -B tools/multi-scene/api-availability/build.py device --root <new-root>
```

Preparation copies complete Core, Internal and RUM sources/private code/resources,
then freezes SDK and client files. The isolated package enables the provisional
Objective-C declarations with `DD_SCENE_API_VALIDATION`; both clients use optimized
Release and disable testability. The ordinary SDK Release configuration must be
checked separately to prove its shipping header still excludes these declarations.
Swift calls use the existing Experimental SPI. Neither client proves ordinary
public imports or approved API baselines.

Build receipts contain per-architecture compiler membership, Objective-C compiler
inputs, generated header hash, deployment target, and complete app fingerprints.
Verification rejects changes to frozen sources, fixture files or protected paths.
Never reuse a build merely because its version string matches.

## Run one cell

```bash
python3 -B tools/multi-scene/api-availability/run.py \
  --root <qualified-root> --device <discovered-udid> --os <27.0-or-17.5> \
  --automatic <off-or-on>
```

The first planned cell qualifies the mechanism. Execution has a fixed 300-second
budget and cleanup a separate 180-second budget. The runner creates a unique run
ID, starts a local intake, proves response publication and clean app absence,
installs and fingerprints the app, then waits for its atomic receipt. It removes
only this fixture's app, requires repeated container/file absence over six seconds,
and restores the cell's original simulator boot state. A separately admitted
continuation uses `--attempt <label>` and never overwrites a previous receipt.
There are no native gestures or fold operations.

Before API calls, the app requires its appeared controller, owned key window,
active scene and, when enabled, the automatic RUM owner. The three lanes exercise
legacy Swift, targeted Swift and all 20 Objective-C selectors, including errors,
three Resource forms with completion after view stop, Actions, Operations, flags,
timing, loading time and attribute mutation. Error callbacks must occur once.

The background lane checks the nullable factory and all 20 selectors. Rejected
calls must read no UIKit state, retain no synthetic scene argument, create no
telemetry, and preserve an existing view's attributes and continuous Action.
A real scene is supplied to the rejected factory; an instrumented NSObject
argument detects accidental scene access in early rejection. This is not proof
that an OS-owned UIWindowScene deallocates.

`Datadog.flush()` waits for queued writes and uploads in this SDK. A local intake
boundary receipt binds the exact event count to the run before background calls.
The app flushes again before publishing its result. The runner then proves the
app process absent, joins all intake workers, and seals the raw event inventory
before assertions. It preserves raw requests, decoded events and command outputs.
Automatic long-task tracking is disabled because the synchronous fixture flush
can itself cross the default threshold; the strict post-boundary oracle does not
allow unrelated events to pass.

## Verdict and failure handling

`summary.json` retains separate scenario, evidence and cleanup verdicts. Overall
acceptance is invalid if any required component is incomplete. Wrong owners,
missing or duplicate forms, unexpected background telemetry, changed parameters,
stale identities and late evidence fail closed. Preserve the original summary;
a correction uses a new root and separately recorded admission.

```bash
python3 -B -m unittest discover -s tools/multi-scene/api-availability -p test_contract.py
```

Offline negative controls exercise the same strict oracle. They qualify rejection
logic, not a simulator or SDK. Results and failed attempts belong in the experiment
record, not this procedure.

## Older legacy lifecycle comparison

`legacy17.py` runs the separately defined eight-cell baseline/current continuation
for C06. It uses the existing navigation/lifecycle ownership oracle with genuine
SDK26.5 Release builds targeting15 on the discovered17.5 iPad simulator. There is
no scene manifest. The first baseline navigation cell qualifies the mechanism
before the candidate build. Every cell has one attempt; a failed cell stops later
execution. This is separate from the ordinary API client above.

```bash
python3 -B tools/multi-scene/api-availability/legacy17.py --root <new-output>
```

Commit reviewed definition and helper inputs before admission. The runner freezes
complete source trees, exact Swift/C compiler membership, compiled objects, built
and installed products, and all protected workspace paths. Each fixture receipt
contains the launch PID and fresh run ID. Lifecycle readiness precedes the Settings
launch; actual background notification precedes reactivation of the same process.
Raw publications are retained before decoding. Exact ownership, counts and order
must match across the two arms.

Native cells have120 seconds, cleanup60 seconds and final restoration120 seconds;
builds have900 seconds each within the fixed5400-second stage. Cleanup retains its
independent budget after an expired work deadline. The runner removes only its task
app and restores the original simulator boot state. Scenario, evidence and cleanup
verdicts remain separate. No backend, iOS15/16 runtime, physical or RFC claim follows.

A classifier-only pre-native stop can use `--reuse-preparation <original-root>`
with a fresh output root. Admission requires zero prior cells, successful cleanup,
unchanged definition/source/protected files and only the reviewed classifier/test
helper delta. Original summaries and logs remain immutable; the build tree is
reused for remaining variants and reverified, including previously built products
and objects. This does not retry a native cell or renew an old deadline.

The four-cell lifecycle continuation uses `legacy17_lifecycle.py --root <new-root>
--accepted-navigation <qualified-navigation-root>`. It requires the separately
frozen lifecycle definition and the exact retained pre-active marker failure.
Readiness waits for the first actual active notification and emits its initial
markers afterward; resumed markers wait for the second active notification. The
strict terminal oracle is unchanged. Existing navigation results are reused only
with their complete source/build/compiler/product/result/cleanup bindings; only
two lifecycle products are built. The stage budget is3600 seconds.

## Concurrent same-key manual views

`same_key.py` extends this builder and runner with the defined EXP-225 two-cell
continuation. Read `Results/EXP-225-same-key-definition.json` and qualify its current
destination before admission. Use a fresh root with `prepare`, then `build`, then
`swift`, then `objc`, always passing `--root <root>`. The Objective-C cell requires
the first Swift cell to pass. A failed scene-activation mechanism stops this path;
there is no equivalent retry or system-preference change.

One optimized product targets15 with the same experimental Swift/local Objective-C
exposure as the ordinary client. UIKit creates the second scene normally. Both
actual scenes must be foreground-active, each with its exact appeared root and
owned key window. Complete window inventories admit auxiliary windows through
ownership assertions, never a window count or private class name.

Four flushed local-intake checkpoints are validated before their acknowledgments:
ready, both live, B stopped, A stopped. Both manual views use the same key; their
view IDs must be distinct and continuous. Three Actions, two Errors, isolated view
metadata and two delayed Resource completions must retain exact owners. Completing
a Resource after its view stops is expected; new targeted B work after B stops
must produce no event or mutation. The final receipt must repeat the exact fresh
acknowledgments and preserve topology. Raw checkpoint bodies, wire inventories,
command outputs, source/build/installed identities and separate cleanup verdicts
remain in the evidence root. This is simulator ownership evidence, not physical
co-visibility, RFC approval, normal public API or full final-matrix acceptance.

Native cells retain300-second execution and180-second cleanup budgets. Ordinary
scene activation has one30-second readiness interval; no accepted source or prior
runtime cells are rerun. `test_same_key.py` owns the focused positive/negative
controls for this phase oracle and transport identity.

## Full RUM module compatibility

`rum_suite.py` owns EXP225's finite RUM portion of the provisional F03 matrix.
It archives the selected SDK/test source, copies the unchanged protected project
as an explicit local input, and copies pinned dependencies into isolated output.
A scoped review binds those inputs before one build and two unfiltered runtime
runs. Exact case identifiers, parameter arguments, invocation counts, result-device
identity, all compiler inputs/products and owned-worker cleanup are required.
The fixed stage covers both runtimes; consumed attempts cannot be renewed.
This does not close the other F03 modules or promote the experimental public API.

`rum_suite_execution.py` continues an unexecuted suite from unchanged qualified
products under a separate definition, review and fixed stage. It preserves the
original failed admission and can reuse complete discovery only with exact
source/product/runtime binding and separate worker-quiescence proof. Each runtime
has one attempt; a failed runtime stops the matrix.

Process inventory retains its actual output and has a 15-second cap inside each
command's fixed 30-second cleanup reserve. An already reaped group needs one read.
Unproven native workers prevent simulator teardown. A timely, fully reaped XCTest
failure may read its fresh result bundle for diagnosis within the original deadline;
that evidence cannot repair the failed command. No physical device or human input
is required for the admitted 27.0 and 17.5 simulator cells.

`rum_suite_inventory.py` reconciles only the source-defined, methodless discovery
helper and retains the original raw verdict. `rum_suite_compatibility.py` owns the
separately defined test-runtime correction: `prepare`, scoped review, `build`,
`27.0`, then `17.5`, each with `--root <fresh-root>`. The only source overlay is the
affected class's runtime setup guard. The changed class must run completely on27;
the full17 target must report the exact predefined skips and reasons. Failure and
skip message children are retained separately from parameter executions. Unknown
schemas, changed test bodies or contradictory results fail closed. Do not edit
already frozen helpers or renew consumed runtime/build attempts.

For a reviewed selective continuation, `rum_suite_selection.py` validates enabled
and disabled lists as an exact partition of the frozen complete inventory. A
selected-class run permits only its predetermined complement to be disabled; the
full-suite path still permits none. Raw rows and their hashes remain in the receipt.
Use `prepare`, review, `27.0`, then `17.5` with its separate fresh root; reuse the
unchanged qualified build and retain every original discovery stop.
