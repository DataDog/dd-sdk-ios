# S2 Resource and Trace validation

## EXP-221 — Compare active-work ownership on the selected S2 composition

Defined before implementation for S2:T03/T08. Compare baseline `62f64d7b` with
selected production `c9faed81` (E01+DL01+E04) on the existing prebooted Duo27.1.
The [owning definition and results](../Results/EXP-221-s2-resource-trace.json) freeze
three boundaries: navigation, explicit session rollover and actual Duo fold, each
in automatic and registered URLSession modes for both source arms. No SDK change.

The initial four navigation cells reuse EXP202's eight Swift files and qualified
semantic oracle. Native tasks cross a real Home-to-Detail view transition; exact
Resource start ownership, metrics/errors and Trace parent/header/sampling values
must satisfy the existing contract. The inherited Resource/action count1/0 and
automatic Trace completion-time correlation remain explicit baseline limits.
Candidate Detail must stop; baseline terminal-view behavior remains an observation.

The first cell also qualifies the adapted host end to end. No separate smoke run
or accepted-test rerun is due. Source/build/installed identities, one-use startup
TTID release, complete backend inventories and task-only cleanup remain required.
Session and fold cells require their exact source/oracle amendment before they can
be implemented or run. Navigation alone cannot close either release gate or the
Datadog-app and automatic-tracking obligations.

Both Release products remain frozen and qualified against actual compiler inputs,
objects and complete products. The oracle changes three identity constants and one
reviewed trace-inventory comparison: validated detail span IDs are sorted, retaining
duplicates and every ownership/value/cardinality assertion. Fifty-seven controls
pass. The owning result preserves the original host/control stops and corrections.

All four navigation cells now qualify the native Resource/Trace predicates and
cleanup on the selected source. A registered cell required an order-only offline
re-audit. The registered candidate required one later whole-session RUM inventory:
ApplicationLaunch then matched its local inactive state, supporting delayed backend
reduction. That composed result retains original startup/APM evidence and does not
claim a contemporaneous snapshot. Both original failures remain immutable.

Each candidate mode stops Detail correctly; the known baseline terminal-view
behavior remains an observation. Exact Resource start ownership, native metrics,
parent/header/sampling values and inherited action/correlation limits are preserved.
No native run was repeated. Session/fold definitions and integrated-app acceptance
remain; navigation alone closes no release gate.
