# Ordinary scene API availability

## EXP-225 — Implement the proposed compatibility and safety behavior

The user authorized full local implementation before the RFC decision. The
[owning result](../Results/EXP-225-api-availability.json) fixes scope, source,
environments, budgets and exact results. API approval and promotion remain separate.

Ordinary Swift scene/target calls now have iOS15 availability. Each family selects
its qualified scene capability on27 and otherwise forwards to its existing legacy
method once. Manual view routing stays consistent across a start/stop pair when
instrumentation is absent, bound late or released. Custom/NOP calls retain their
original parameters and callbacks without eagerly resolving a manual scene target.

The Objective-C target factory is nullable. Its factory and targeted selectors
reject background use before entering an actor or reading UIKit. Existing semantic
host/destination/metadata APIs retain iOS27 and the Observation compiler boundary.
Experimental exposure remains; a dedicated local validation condition enables the
Objective-C client in optimized Release without changing the shipping header.

## Qualified evidence

The four complete affected RUM test classes cover forwarding, fallback, owner
selection and handler lifetime. Both actual runtimes have passing evidence; the
older runtime explicitly skips the27-only instrumentation case. The initial new
assertion incorrectly expected no session context after view stop; its corrected
view-ID assertion passes separately. The original failure is retained.

Optimized mixed Swift/Objective-C clients target15 and pass on27 and17.5 with
automatic UIKit view tracking off and on. Decoded local intake proves exact
per-lane owners, Resource completion after view stop, error callbacks, Action and
Operation forms, flags, timings and attributes. Background calls leave telemetry,
active-view attributes and the continuous Action unchanged. Every accepted cell
passes evidence and task-only cleanup as well as its scenario.

The strict oracle rejected an unrelated automatic long task from the fixture's
blocking flush. That instrumentation was disabled. A restored task container,
a launch without a process handle, and a module-prefix error in the automatic
view matcher also remain INVALID in their original records. Source-supported
fixture corrections and separate restoration receipts preserve attribution;
none establishes an SDK regression. Accepted manual-mode cells were reused at
identical SDK bytes instead of rerun for an automatic-only matcher correction.

## Legacy runtime continuation

The [paired legacy result](../Results/EXP-225-legacy17-result.json) completes the
prototype's remaining17.5 baseline/current navigation and lifecycle obligation.
Both source arms use genuine SDK26.5 Release builds targeting15 without a scene
manifest. Automatic/manual navigation preserves Home, Detail and a fresh Home;
automatic backgrounding stops Home and creates a fresh occurrence, while manual
tracking retains its Home. Exact Action/Resource owners and notification order
match. All eight accepted cells and final restoration pass.

Four navigation results were reused with unchanged source, SDK, fixture, compiler,
product and raw-result identities. The original compiler-directory rejection
remains INVALID; its build was reclassified offline. A later baseline lifecycle
attempt emitted markers before actual activation because the fixture used a fixed
delay. That original INVALID also remains. The separately reviewed continuation
waits for real first/second activation and passes the four lifecycle cells without
changing the SDK or weakening the terminal oracle. These are fixture findings.

## Remaining boundary

No release gate closes. Local SPI/header validation is not normal public API
access or attributable RFC approval. The native clients have one scene; exact
simultaneous A/B same-key reverse-stop qualification, approved baselines, the full
final compatibility matrix and physical/human obligations remain. This experiment
adds no Datadog backend or iOS15/16 runtime claim. The
[runner procedure](../../../tools/multi-scene/api-availability/README.md) owns reuse,
raw capture, boundary sealing and cleanup requirements.
