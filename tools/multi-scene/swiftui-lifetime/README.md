# Keyed SwiftUI lifetime acceptance

EXP-168 validates D03 with actual mounted SwiftUI and SDK teardown. It contributes
host-lifetime evidence to P03; disconnected-registry retirement remains separate.

```sh
python3 -B tools/multi-scene/swiftui-lifetime/run.py \
  --control <control-commit> --candidate <candidate-commit> --output <new-result.json>
```

The runner uses the existing baseline extraction/package helpers, copies seven
explicit SDK source/resource paths from each revision, and builds one immutable
app per arm. It discovers current iOS 27 and 26.5 iPhone simulators and runs both
arms on both. Clean install, a new run ID, installed binary identity, the complete
37-check inventory and unchanged SDK/fixture/binary hashes are mandatory. The main
Xcode project and local xcconfig are never read. Dummy credentials and a loopback
endpoint keep telemetry local. `--control-only` records reproduction before repair.

Each run uses a real UIWindowScene, automatic UIKit instrumentation and a keyed
SwiftUI modifier. Five warm-up plus twenty measured mounts prove a registration
and exact RUM destination existed before removing the hosting controller. Sources
are deliberately retained beyond removal. Read-only reflection captures weak
registration/state references from the real source; no SDK lifetime hook is added.
Weak reader and controller references distinguish the SDK cycle from UIKit
retention. Bounded main-queue draining precedes each survivor count.

After releasing the SDK core, weak instrumentation, handler and arbiter references
must clear. The fixture reads, but never replaces, the real implementations of
`viewDidAppear:`, `viewDidDisappear:` and `sendEvent:`: all three must change during
SDK instrumentation and return to the exact original implementation after stop.
The arbiter must exist on iOS 27 and be absent on 26.5, matching its SDK availability.

The unchanged control must fail registration release, instrumentation release and
method restoration on both runtimes. The candidate requires all 37 checks on both.
Preserve setup/availability mistakes separately from SDK failures. The initial
fixture incorrectly required a 27-only arbiter on 26.5; its inconclusive attempt
is retained alongside the corrected complete comparison. No physical lifecycle,
backend, minimum-runtime, RSS or disconnected-history acceptance follows from this
bounded lifetime run. A changed fixture requires new frozen builds and both arms.
