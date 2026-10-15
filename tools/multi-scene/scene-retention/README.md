# Scene registry retention acceptance

Runs EXP-172 / P03 against explicit frozen control and candidate revisions.
It archives only the SDK source paths listed by the existing baseline harness;
the main Xcode project and local xcconfig are never read. The baseline protocol
prefix is pinned by hash, with the original 20 warm-up +100+100 lifetimes and
64KiB/16KiB limits unchanged.

```sh
python3 tools/multi-scene/scene-retention/run.py \
  --control a76133570f05a8db0de282efc2fe04ebf96349f5 \
  --candidate 4653e0a72eb9cd832792e9f02c2cbbe1dc36e1a1 \
  --output /tmp/exp172-new-attempt.json
python3 -m unittest discover -s tools/multi-scene/scene-retention -p 'test_*.py'
```

The runner discovers both available simulator runtimes, creates fresh isolated
projects, compiles Release with `-O`, checks the full watchOS Release RUM product,
and runs control/candidate/candidate/control on each runtime. Every launch
proves clean uninstall, installed executable identity, an absent result before
launch, a fresh matching run ID, exactly one native scene, and complete workload.
Ordinary automatic/manual Home–Detail–Home apps use the unchanged baseline app
and ownership oracle; no dispatch performance rerun is included.

The isolated handler receives posted logical scene lifetimes, with real weak
controller references. All directly owned collections are inspected after every
batch. The candidate constructor injects an empty initial inventory; the old
control already starts empty. This single recorded argument is the only arm
adaptation. Neither arm includes the fixture application's externally owned live
scene in the isolated workload. Genuine mounted SwiftUI release remains the
accepted EXP-168/171 prerequisite; physical H08/H09 remain separate.

The summary retains source/fixture/binary hashes, every raw heap and collection
sample, commands, negative control outcomes, and invalid attempts. All four
candidate lifetime runs must pass; all four controls must reproduce the regression;
all eight ordinary compatibility runs must pass. Missing/malformed evidence is
inconclusive. No thresholds are inferred from the candidate output.
