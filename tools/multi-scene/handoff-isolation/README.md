# SDK-scoped handoff acceptance

EXP-166 closes D04 and P02 only when its consumer/lifetime tests and the frozen
EXP-160 allocation budget both pass. The workload, timing limits, allocation
calibration and full-context reentrancy oracle come from the original baseline
fixtures. Those accepted files are never edited.

Run from the repository root, keeping build/test/profile activity out of the
measurement window:

```sh
python3 tools/multi-scene/handoff-isolation/run.py prepare
# Use the fresh attempt path printed by prepare for each following command.
python3 tools/multi-scene/handoff-isolation/run.py build --attempt ATTEMPT
python3 tools/multi-scene/handoff-isolation/run.py focused-build --attempt ATTEMPT
python3 tools/multi-scene/handoff-isolation/platforms.py
# Wait for all builds and module tests to finish before measurement.
python3 tools/multi-scene/handoff-isolation/run.py run --attempt ATTEMPT
python3 tools/multi-scene/handoff-isolation/run.py focused-run --attempt ATTEMPT
python3 tools/multi-scene/handoff-isolation/run.py report --attempt ATTEMPT
```

`prepare` archives the pre-scene baseline and freezes the candidate's seven
explicit SDK source/private/resource directories, including current uncommitted
changes. It records HEAD, source hashes and the candidate patch identity. It
never reads the user's project or local configuration. Copied fixtures differ
only in scoped SPI lookup/owner arguments; both timing arms use identical copied
sources. `focused-build` makes a separately identified assertion-only binary.

`run` rediscovers both installed simulator destinations, proves uninstall before
each install, generates fresh run IDs, checks binary identity at launch, executes
complete ABBA quartets, and captures every sample. `verify` checks archived SDK
sources, copied fixtures, the original fixture and protocol, and every measured
binary. `report` uses the unchanged baseline evaluator, preserves all fixed
thresholds and excludes diagnostic-only probes. The resulting `summary.json`
and `manifest.json` bind timing, calibrated allocations, reentrancy, custom/NOP
behavior, identities and commands. Publish compact summaries and numeric samples;
keep raw console/compiler logs local.

The optional `probe` stage runs one candidate process for allocation diagnosis.
It cannot establish a timing or release acceptance result. Start a fresh attempt
after any SDK change. The first EXP-166 diagnostic measured 1 allocation / 112
bytes; the smaller resolver reached 1 / 64 before the final ABBA run. The initial
pure TaskLocal candidate also failed the synchronous-snapshot control, and was
repaired before these measurements.

`platforms.py` independently freezes source into a fresh directory and compiles
complete watchOS RUM and macOS Core products in Debug and Release. Its result
records source/module/log identities. Deployment compilation is not execution
on a minimum supported OS. The simulator measurements do not close physical
multi-window, lifetime-retention, backend ownership, or final release gates.
