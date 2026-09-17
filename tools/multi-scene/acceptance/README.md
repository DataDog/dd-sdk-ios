# Multi-scene acceptance workflow

This runner admits two finite contracts: EXP-161/A01 long-running actions and
EXP-176/T03 captured Resource starts. It does not certify simultaneous visibility,
real scene teardown, interactive gestures or hardware-only scenarios.

The Python runner records commit signature status and performs environment and
authentication preflight, a fresh probe build with all current tests (at least167 for Resources), frozen source
and binary identity, proven uninstall, clean install, scenario launch,
native-scene/mapper ownership checks, complete
backend inventory, app termination and a sanitized durable result. Unsupported
scenarios and reused output directories are rejected. No credentials are read
from local configuration or written to artifacts.

Sign commits when the agent is available. If it is unavailable, continue with
unsigned local commits using explicit paths. Local acceptance accepts unsigned
HEADs and records `UNSIGNED`; an existing signature must still verify. Signing is
required before pushing, and this runner never pushes. Frozen revision, source,
fixture and installed-build identity checks apply to both commit types.

## One invocation with the authenticated connector

Read the repository handoff/runbook first. Resolve an available iOS27 simulator
from live tooling. The driver takes an explicit repository path and simulator
UUID; the Python preflight verifies the destination again. No Xcode interaction
session is needed for this CLI-driven scenario.

From the tool orchestrator, read this trusted checkout's `connector_driver.js`
with `exec_command`, then await:

```javascript
await new Function("tools", "notify", "device", "repo", "scenario", source)(
  tools, notify, freshlyResolvedSimulatorUUID, absoluteRepositoryPath,
  "resources.explicit-start.captured-owner-cross-scene-serial"
);
```

The driver calls the installed Datadog aggregate/search tools itself and supplies
source fields to the oracle. It polls intake, paginates detailed rows and binds
each response to a fresh request nonce, exact query and request hash. It never
accepts a manually supplied PASS. Tool names are the current Datadog connector
contract; if that contract changes, revise the bridge and validate it before
claiming acceptance.

Each attempt gets a new temporary directory/run ID and a unique sanitized file
under `DatadogRUM/MultiSceneSupport/Results/acceptance/`. The temporary directory
contains raw logs, xcresult, binary identity and screenshot; these must not be
committed. The durable JSON contains counts, exact synthetic event owners,
source/build identity, stage verdicts and artifact locators. It contains neither
credentials nor raw intake bodies. Preserve INVALID/INCONCLUSIVE attempts.

The shell entry point below is useful with another bridge implementation, but it
waits for authenticated responses under `OUTPUT/bridge`; running it alone does
not complete backend acceptance:

```sh
python3 tools/multi-scene/acceptance/acceptance.py \
  --repo /absolute/checkout --device FRESH_SIMULATOR_UUID \
  --output /fresh/nonexistent/attempt \
  --durable-output /durable/sanitized/results
```

## Contract and negative controls

`scenario-contract.json` pins the complete expected fixture, including timelines,
completion conditions, driver steps and runtime options. Source hashes include
that contract and all runner files. Editing any frozen file during a run makes the
attempt invalid. The installed executable must match the fresh build hash.

Occurrence1 is the first mapper Home UUID for each logical scene. Native mapper
action envelopes do not contain a semantic occurrence field; exact UUID equality
and an independent session-only view inventory establish ownership. Seven action
IDs, final names, source native scenes, stop timestamps, durations, three view IDs
and zero error/crash events must agree locally and in Datadog. An app PASS alone
cannot override a wrong owner. Assertions must occur inside their actual critical
call interval; a later settled marker cannot replace callback-boundary evidence.

Run the operational controls without Xcode or backend access:

```sh
python3 -B -m unittest discover -s tools/multi-scene/acceptance -p 'test_*.py'
node --test tools/multi-scene/acceptance/test_connector.js
```

Controls cover stale contract/build/run IDs, missing/duplicate/reordered records,
reused readiness, native schema, wrong exact/native owners, wrong final name,
early completion, inactive prerequisites, late assertions, restored backend run
IDs, pagination/completeness, wrong stop order, yielded helper-command completion,
unsigned local commits and invalid existing signatures. The EXP-142 late-boundary
lesson is retained as a negative discriminator; that historical scenario is not claimed
as a fresh runtime acceptance by this runner.

After recording experiment dispositions, refresh gate progress with:

```sh
python3 -B tools/multi-scene/release_checklist.py --update
```

Without `--update`, the command checks required gate fields, dependencies/cycles,
telemetry completion modes, closed-gate evidence and PLAN/register agreement.

## Resource contract (EXP-176/T03)

`resource-scenario-contract.json` pins six actual Swift/Objective-C target starts,
one legacy fallback, two paused URLSession tasks and a new-session peer action.
`resource_contract.py` requires22 app expectations plus independent strict checks:
native Home mapper owners before starts, all starts before navigation/renewal,
zero completion before release, five Resources and four expected network errors
on the original owners, exact request/status/method/size/duration fields, and zero
old Resource/error counts on the fresh peer action. Session-only queries inventory
all seven views and all Resource/error events across both sessions; no run filter
can conceal restored metadata or extra events. The separate crash count stays zero.

The custom URLProtocol holds actual instrumented tasks, then delivers a successful
response or response headers/body followed by failure. It makes no external network
request. Success is observed before the error is released, preserving the declared
serial completion timeline. The SDK's independent unit checks cover missing targets,
completed-key reuse and compatibility fallback; native acceptance executes all six
experimental entry points in real UIWindowScenes.

The operational suite now includes50 Python tests (23 Resource tests, with further
backend mutation subcases) and three connector tests. A passing SDK/probe unit build
alone does not close T03. Commit the fixture/runner before acceptance and retain all
failed native/backend attempts alongside the final durable result.
