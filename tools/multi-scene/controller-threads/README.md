# Controller caller-thread compatibility

EXP-164 closes D09 using two SDK getter-spy regressions and this isolated runtime
fixture. Run from the repository root with explicit control and candidate commits:

```sh
python3 -B tools/multi-scene/controller-threads/run.py \
  --control <control-commit> --candidate <candidate-commit> --output <new-result.json>
```

The runner imports only package/extraction/hash/command helpers from the existing
baseline runner. It does not execute EXP-160 workloads or modify their frozen
fixtures. It extracts seven named production directories from each commit into a
fresh directory; no main Xcode project or local xcconfig is copied or opened.
It selects an available iOS 27 simulator and builds both complete Core/RUM apps
in Debug with testability and an iOS 15 deployment target. This is no proof of an
iOS 15 runtime or the final supported-platform build matrix.

The app mounts an actual UIViewController in an actual UIWindowScene. One peer
RUM branch is injected to discriminate routing; it is not a second native window.
The 19 required checks cover main-thread native targeting under contradictory
handoff, background representative/inferred routing, identity stops, peer
preservation, actual worker execution, zero background hierarchy reads and a
loaded Main Thread Checker library. SDK `currentSessionID` callbacks drain the
same context queue before observations; checks therefore run after the submitted
commands, without guessing from a delay. The app uses a dummy token and a loopback
endpoint. No Datadog backend claim follows.

The unchanged control must fail its hierarchy oracle. Each app gets a clean
installation and new run ID; the installed binary must match the frozen build.
Main Thread Checker is explicitly injected with stderr reporting and crash-on-
report disabled so the failing control can finish. Candidate acceptance requires
all 19 named checks to be true and no background-UIKit diagnostic. Missing scene,
checker or check inventory is inconclusive. Existing output paths, restored run
IDs, and changed sources/fixtures/binaries cannot pass.

Each invocation retains its own manifest, command/build/console locations and
hashes, individual checks, SDK/fixture/binary identities and failed controls.
Preserve INVALID setup/build attempts separately from semantic FAIL. Raw build
and console logs remain local; the experiment's durable summary contains only
sanitized checks and diagnostic headers. A revised fixture requires a new complete
control/candidate attempt. Existing accepted experiments are not rerun to resume.
