# S2 source selection and evidence reuse

## EXP-209 — Freeze the smallest S2 candidate

Defined before the audit in the [owning result](../Results/EXP-209-s2-source-audit.json).
The selected source is current develop `62f64d7b` plus E01 production `1bdc9286`,
qualified at test/documentation head `652ce169`. No additional extraction or
experimental multi-scene code is included. This is a local qualification choice,
not release or distribution authorization.

The bounded source audit owns S2:F07 and P01 source non-applicability. It also maps
accepted S1 evidence to unchanged S2 invariants. The decisive proof compares every
shipping source blob, inventories all tracked changes and examines transitive
callers, API, wire, storage and dependency boundaries. The budget is 40 engineering
minutes, zero SDK/test edits, zero builds and zero native launches. Unexpected
dependencies block qualification before any repair. One independent reviewer
checks consequential exclusions and evidence reuse.

Historical EXP-195 used baseline `92f021ba` and the experimental reference. Current
develop differs in 88 source entries across Core/Internal/RUM/Trace. Its Duo results
remain valid only for those original sources; current candidate and old-build Duo
comparisons remain open. Unchanged source cannot substitute for actual active-work
folds, backend ownership, or native gesture/input qualification.

The independent review qualifies F07 and P01 source non-applicability. The inventory
covers 709 Datadog module source entries plus 156 auxiliary test/tool/benchmark
entries. Exactly three production files differ from develop; all production equals
the qualified E01 source. All 12 tracked changes are enumerated, with no project,
dependency, API, generated-model, wire, storage or availability change.

C01–C06, narrow P04, F02, composed F03 and bounded A01 reuse the accepted S1 records
under their original source/runtime limits. F03 combines EXP-201 at `925b9326` and
the separately qualified 8-test terminal follow-up at `652ce169`; it is not one
new full-matrix invocation. A01 is the completed exact backend workflow, not a
portable CI or Duo acceptance claim. No tests were rerun.

The reviewer rejected direct S1:P03 reuse: task/interception lifetime does not
prove the broader S2 view/resource/cache/scene lifetime contract. P03, all automatic
Duo, interactive, active-work, app-journey and final-delivery gates remain open.
Inherited E02/E03/E04/E05 behavior and EXP-204's incomplete diagnostic remain
explicit. The original overbroad source-count label and contradictory reviewer
path diagnostic were corrected before qualification, with both original records
preserved. The result points to byte-verified evidence outside temporary storage.
