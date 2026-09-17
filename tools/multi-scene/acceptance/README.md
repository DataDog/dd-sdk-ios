# Multi-scene acceptance workflow

This runner closes only A01 for the admitted EXP-159 long-running-action scenario.
It does not certify other telemetry families, simultaneous visibility, real scene
teardown, interactive gestures or hardware-only scenarios. Its reuse of the
accepted scenario validates the acceptance workflow under EXP-161.

The Python runner performs signature/environment/authentication preflight, a fresh
probe build with all166 tests, frozen source and binary identity, proven uninstall,
clean install, scenario launch, native-scene/mapper ownership checks, complete
backend inventory, app termination and a sanitized durable result. Unsupported
scenarios and reused output directories are rejected. No credentials are read
from local configuration or written to artifacts.

## One invocation with the authenticated connector

Read the repository handoff/runbook first. Resolve an available iOS27 simulator
from live tooling. The driver takes an explicit repository path and simulator
UUID; the Python preflight verifies the destination again. No Xcode interaction
session is needed for this CLI-driven scenario.

From the tool orchestrator, read this trusted checkout's `connector_driver.js`
with `exec_command`, then await:

```javascript
await new Function("tools", "notify", "device", "repo", source)(
  tools, notify, freshlyResolvedSimulatorUUID, absoluteRepositoryPath
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
IDs, pagination/completeness, wrong stop order and yielded helper-command completion. The EXP-142 late-boundary lesson
is retained as a negative discriminator; that historical scenario is not claimed
as a fresh runtime acceptance by this one-scenario runner.

After recording experiment dispositions, refresh gate progress with:

```sh
python3 -B tools/multi-scene/release_checklist.py --update
```

Without `--update`, the command checks required gate fields, dependencies/cycles,
telemetry completion modes, closed-gate evidence and PLAN/register agreement.
