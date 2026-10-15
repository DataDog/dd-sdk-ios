# Semantic reconnect acceptance

EXP-170 closes D08 at signed SDK `66d1ccb02`: three failing controls,
seven focused and314 affected tests, plus the mounted comparison below.

```sh
python3 -B tools/multi-scene/reconnect-acceptance/run.py \
  --control <control-commit> --candidate <candidate-commit> --output <new-result.json>
```

The runner freezes eight explicit SDK source/resource directories, the fixture,
package, binaries and installed executables. It discovers an iOS27 iPhone
simulator, proves clean installation, assigns fresh run IDs and requires all51
checks. Dummy credentials and loopback endpoints keep it local; the protected
project and local xcconfig are not accessed. The baseline package helpers are
shared; the added Logs target uses its actual Sources directory only.

Both explicit and optional-capability variants mount the actual RUMNavigationHost
and its real reader/authority registry. A filtering automatic predicate enables
the registry without inventing an automatic destination. Posted notifications
supply a deterministic disconnect/reconnect sequence while UIKit retains its
scene and inherited trait. The fixture clears onMount before reconstructing the
root and requires SwiftUI to rebind it, proving the stale rendering boundary ran.
A rejected reader must acquire no suppression or view. A valid reconnect must
start one fresh Home; Resource and Log calls are submitted immediately after the
reader callback, before any await, render or navigation. Their mapper UUID/session
must match the accepted Home and the logical peer must keep its own owner.

The same hosting controller is then detached for200ms and remounted with a new
body value. Three unique Home occurrences and one peer are required; duplicate
reader callbacks cannot create another view. ApplicationLaunch is the only
permitted startup view. The accepted control is39/51 and incorrectly sends both
reconnect markers to Peer; the candidate is51/51. Marker inspection occurs after
queue drain, but marker submission always precedes that drain.

Attempt1's nonexistent Logs Resources directory and attempt2's missing registry
and artificial nil UI handoff remain in the durable result. These lifecycle
callbacks have no UI-event scope, so the corrected fixture uses ordinary APIs and
the documented process fallback. It does not claim source-specific Log targeting
inside another UI event, backend, minimum-runtime or physical H09 acceptance.
R04 remains open for a retained-reader remount without body/source rebind. P03
registry retirement and R05 observer fan-out also remain separate.
