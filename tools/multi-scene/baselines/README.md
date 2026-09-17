# EXP-160 baseline runner

This fixture compares pre-scene SDK `92f021ba7` with accepted EXP-159
`af63657f0`. The fixed protocol and thresholds are in
`DatadogRUM/MultiSceneSupport/BASELINES.md`.

Run from the repository root:

```sh
python3 tools/multi-scene/baselines/run.py all --output RESULT.json
# The first line prints the fresh attempt directory.
# Re-evaluate retained evidence without running apps:
python3 tools/multi-scene/baselines/analyze.py ATTEMPT --output RESULT.json
python3 -m unittest discover -s tools/multi-scene/baselines -p 'test_*.py'
```

For coordination with other build/runtime work, use `prepare`, `build`, and
`run --workload compatibility|performance --attempt ATTEMPT` separately. Do not
accept performance runs while another build/test/profile workload is active.
The complete command also builds a separately identified legacy variant for real
OS background/foreground on iOS 26.5, and a separately identified full-context
reentrancy variant on both runtimes. To finish a staged run, use:

```sh
python3 tools/multi-scene/baselines/lifecycle.py all --attempt ATTEMPT
python3 tools/multi-scene/baselines/focused.py all --attempt ATTEMPT
python3 tools/multi-scene/baselines/run.py verify --attempt ATTEMPT --output RESULT.json
```

Both arms use identical fixture sources, Release optimization, testability,
Swift 5 language mode, arm64 simulator binaries and an iOS 15 minimum deployment
target. A generated minimal local package describes only the original Core,
Internal and RUM sources and their existing private targets/resources. It does
not fetch external dependencies or modify production source. This is a focused
component baseline, not the repository's complete package/CI build matrix.

The runner archives only seven explicit source/private/resource directories from
commits into a fresh temporary directory. It never opens local configuration,
uses repository project files, or copies credentials. XcodeGen generates two
standalone application targets: ordinary single-scene and legacy UIApplication
lifecycle without a scene manifest. SDK upload uses a dummy token and loopback
endpoint. Mapper events prove local compatibility; no backend claim is made.

Each launch uses a fresh identifier and proves uninstall/container removal
before installation. Automatic and manual Home → Detail → fresh Home flows are
checked for exact occurrence, action and Resource ownership. A valid count alone
cannot pass. The evaluator's negative controls cover wrong owners, reused UUIDs,
duplicate/missing events and threshold violations.

Timing uses ABBA arm order on each runtime, one discarded warm-up plus seven
20,000-operation batches per process, and 2,000 individual event samples for
median/p95. Raw samples are retained. The UIKit empty-event workload measures
actual UIApplication dispatch with SDK disabled/enabled. A separate internal
workload exercises the real touch-command factory with a scene-bearing moved
(filtered) touch and original dispatch, comparing the prior action-only callback
with the candidate interceptor. It also measures enabled handoff against the actual initialized monitor and verifies a live view context. Neither
workload is a physical touch latency or whole-application throughput claim.

Allocation recording starts after timing. The fixture-only `malloc_logger`
observer counts successful heap allocation operations and requested bytes on the
workload thread; realloc counts as one allocation. The ABI is documented by
[Apple's libmalloc source](https://github.com/apple-oss-distributions/libmalloc/blob/main/src/malloc.c).
It refuses an already occupied logger and must observe exactly three operations
and 165 requested bytes for malloc/calloc/realloc calibration before reporting a
measurement. This is heap allocation churn, not resident or live heap memory;
it excludes VM allocations and unrelated threads. Ordinary and enabled-handoff allocation counts are both reported against the same baseline. The observer is never linked
into a shipping SDK target.

Retained-heap readings are separately labeled `malloc_zone_statistics` live
bytes. The focused lifetime fixture sends connect/appear/disconnect to the real
handler with unique injected scene identifiers, checks weak controller release,
and counts remaining handler registry entries using reflection. This cannot
prove genuine OS scene teardown or SwiftUI host release. Such evidence remains
required even if the focused test passes.

The full-context variant checks actual initialized Home application/session/view
identity using all `RUMCoreContext` fields, plus pending/excluded-action and scene
fields. B intentionally carries an authoritative nil RUM context. Early false
return and thrown-scope restoration are checked, followed by an empty outer
scope. It is an assertion-only extension, with a separate fixture hash and binary;
it does not change or repeat the timed workload.

`verify` rehashes the original archived SDK files, both copied timing fixtures and
all measured binaries; it also records actual Mach-O deployment metadata and
installed runtimes. The evaluator requires complete ABBA order, exact sample and
batch counts, no fixture failures, and consistent identities. Missing evidence
is INCONCLUSIVE. The final JSON contains gate results, environment, build identity
and command history; `-samples.json` preserves numeric samples, calibration,
sanitized local ownership events and invalid attempts separately. Compiler and
generator logs stay in the local attempt with hashes/locators in the result;
raw console logs and complete crash reports are never copied into the repository.
An iOS 27 legacy launch trap is recorded as inconclusive, and an unavailable iOS
15 runtime remains blocked even when minimum-deployment compilation succeeds.
