# SDK-on native view lifetime

## EXP-215 — Complete the three native P03 ownership checks

Defined before edits on signed test checkpoint `ef9d9732`, production `c9faed81`.
The [owning result](../Results/EXP-215-native-view-lifetime.json) freezes exactly
three SDK-on cases, two cycles each, unchanged appearance/release limits and a
new fixed one-hour admission. No production path is admitted.

Use the qualified async observation boundary from EXP-213 with actual UIKit or
SwiftUI appearance/disappearance. Keep pending Resource ownership and the SDK
alive across host/content release; advance a live manual peer through a real
command before requiring the old restoration-owned RUM view to release. Require
the original Resource event owner and unchanged active peer after completion.
Accepted unit/task/core/cache evidence is reused. Original EXP-213 failures remain.

Independent source/oracle review and exact discovery pass: all282 identifiers match,
three selected cases are enabled and all41 target source files compile. Each test
runs once and passes, producing six exact mode/cycle receipts. There are no skips
or structured runtime warnings. Real appearance/disappearance, pending Resource
ownership, host/content release before completion, old-view/Resource release within
two seconds of completion, exact event owner and unchanged active peer/SDK all pass.
Source, dependency, SPM artifact, product, protected-state, cleanup and deadline
guards pass. One positive/19 negative receipt controls and strict test lint pass.

Preexecution review corrected the observation order so serialized-event reads
cannot extend the two-second terminal release window. The original snapshot remains.
The initial dependency-cache search missed the durable cache; corrected discovery
verified pins and the checksum-qualified artifact tree before any build. Runtime
ran once without a failure or retry. Build diagnostics retain three compiler/tool
warning lines and59 duplicate-class lines; no blanket warning-free claim follows.

Final review6127f656 accepts the bounded composition evidence. Test-only commit
`1aa71d7f` preserves the exact qualified bytes; signing timed out and the authorized
local unsigned fallback succeeded. No production file changed or push occurred.
The durable evidence root retains raw results, products, source snapshots, controls,
reviews and commit receipts. The [owning result](../Results/EXP-215-native-view-lifetime.json)
binds every full hash.

The pending Resource is an SDK RUM scope, not a new live URLSession qualification.
This result applies to production `c9faed81` (E01+DL01+E04), whose six changed
shipping files match their independently qualified component bytes;859 other
shipping-source entries match develop. It cannot qualify the currently selected
E01-only candidate by implication. A separate source-aware promotion review is next;
P03 and unrelated gates remain unchanged. Replay content tests were not run.
