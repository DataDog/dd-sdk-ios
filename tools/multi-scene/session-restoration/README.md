# Session restoration acceptance

EXP-167 closes D05/D06 with controlled application/session/view tests and this
six-case runtime fixture in two native iPad simulator scenes.

```sh
python3 -B tools/multi-scene/session-restoration/run.py \
  --control <control-commit> --candidate <candidate-commit> --output <new-result.json>
```

The runner reuses baseline extraction, package and identity helpers. It extracts
seven explicit SDK source/resource directories into a fresh directory and never
opens the main project or local xcconfig. Both arms build the same fixture with
an iOS 15 deployment target. It discovers an available iOS 27 iPad, proves clean
installation, hashes the installed binary, and requires a fresh run ID and the
complete 47-check inventory. Source, fixture and executable identities are checked
again after execution. Dummy credentials and a loopback endpoint keep this local.

The app requests a second actual UIWindowScene and proves distinct scene IDs,
mounted controllers and an active application. Readiness is observed after the
activation callback with a bounded retry; it must not be consumed while UIKit
still reports an inactive application. Missing topology never counts as a pass.

For explicit stop, delayed inactivity timeout and delayed maximum duration, each
followed by source-less start or identity stop, the app checks navigation owners
before any marker can heal/select a missing peer. Session and view IDs must be
fresh; subsequent peer actions and Resources must have exact mapper owners, and
the outgoing new-session view set must exactly match the expected occurrences.
Heartbeats distinguish maximum duration from inactivity. All six old-SDK owner
checks must fail; the candidate must pass all 47. The separate 44-case unit matrix
covers explicit targeting, immediate expiration, background policy and legacy
scene-less behavior.

Expiration command times are controlled internally; native topology is real.
This does not establish physical OS lifecycle ordering, backend acceptance or
minimum-iOS runtime compatibility. Preserve invalid setup/build attempts and
semantic failures separately. A fixture change requires new frozen builds and a
complete control/candidate run.
