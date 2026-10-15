# Network benchmark follow-up

Status: preserved prototype for possible SDK testing-infrastructure integration.
This is optional follow-up work, not a prerequisite for shipping the E01 URLSession
correctness fix. The [follow-up](../../../DatadogRUM/MultiSceneSupport/NETWORK_BENCHMARK_FOLLOWUP.md)
owns scope and remaining work.

## What is preserved

- `fixture/`: the six byte-identical Swift/C inputs used by both qualified Release builds.
- `harness/`: current host/37 host controls, corrected evaluator/29 oracle controls,
  accepted reentrancy evidence and the real stopped timing input used by a regression control.
- `project-inputs/`: both generated Xcode project definitions, plists and dependency pins.
- `evidence/`: original measurement contract/reviews, correction records, both build
  receipts, all four native qualification records, frozen measurement plans and the
  exact three-file candidate production patch against its recorded baseline.
- Later evidence retains the41-control system-runner guard correction and the
  unexecuted continuation source/review. Its added controls were not run.
- `evidence/stopped-matrix-22-cells.tar.gz`:92 byte-verified raw records, including
  the22 valid cells and failed prelaunch slot. This is not a completed matrix.
- `manifest.json`: locators, SHA-256 values, sizes and checks for71 preserved files.

All copied files retain their original bytes. Historical paths, runtime IDs,
review bindings and deadlines inside them describe that experiment. They are not
portable execution instructions or new acceptance requirements. The stopped run is labeled explicitly; no incomplete matrix
is presented as a completed numeric verdict. Compiled apps, DerivedData, SDK
archives and dependency checkouts are excluded; their build inputs and binary
identities are preserved. No local xcconfig contents are included.

## Using this work later

Start with the follow-up's bounded integration tasks. Parameterize repository,
baseline/candidate revisions, toolchain and actual discovered destinations. Rebind
historical manifests to a new preparation instead of rewriting accepted records or
reusing their run identifiers. The archived host still contains experiment-specific
paths and admission checks, so it is not a turnkey CI command.

The offline host/evaluator tests are self-contained in `harness/`, using Python's
standard library and the adjacent preserved JSON inputs. On an idle host they can
be run from this directory with:

```sh
python3 -B -m unittest discover -s harness -p 'test_*.py'
```

Do not run these controls or native measurements alongside another accepted
performance run. Saving this archive did not rerun tests or launch a simulator.

The old numeric budgets are preserved to explain historical results, not adopted
as infrastructure policy. Future owners must choose useful workload sizes,
environments and thresholds before installing CI gates. Retain independent
negative controls for missing callbacks, skipped asynchronous allocations,
retained owners, stale output, changed binaries and assertions after deadlines.
