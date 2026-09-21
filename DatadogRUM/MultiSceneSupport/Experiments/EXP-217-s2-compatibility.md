# S2 composed-source compatibility

## EXP-217 — Qualify the composed compatibility matrix

The [owning result](../Results/EXP-217-s2-compatibility.json) freezes selected
production c9faed81 at signed documentation/test head 7604da24. It closes only
S2:F03 if every admitted M01–M11 obligation passes. No SDK, test, dependency or
build-script change is admitted. The two-hour deadline is fixed in the result.

M01 requires new composed-source execution across ten non-Replay schemes because
shared TestUtilities includes RUM. The corrected source-bound inventory contains 3,162 raw cases,
3,152 selected cases / 3,224 executions and five predefined OS skips. Ten Replay-only
slot/layout, record-content and privacy/capability assertions are excluded before
execution, not counted as passes or skips. Fresh discovery must independently
match each source-bound count before test admission. RUM metadata, ownership and
other-feature coexistence assertions remain required.

M02/M03 require the five existing Swift5/Swift6 Debug/Release and Objective-C
Release clients against the composition. M04–M08 require ten complete package
builds; M09 requires RUM/Internal Debug/Release on macOS, with exact E01 source
closure reuse for the six unaffected products. M10 requires strict lint and
nine-module Swift/Objective-C API verification. M11 reuses the current F02 result.

The first reviewer used the older five-product macOS reference; its receipt is
retained and rejected before execution credit. Candidate Makefile and Package
support seven products including RUM at macOS 12.0. The corrected admission review binds
that source and the exact selected-case oracle. Preparation-only membership
serialization assertions are retained separately; no test failed or passed there.

M01 passes all ten selected suites: 3,219 successful executions and five predefined
OS skips. Eight Integration QoS warnings remain recorded for source-aware review.
Original preparation/discovery stops are preserved: the historical Internal count
omitted four already-committed terminal tests, and Swift Testing ignored normalized
method exclusions. Whole-suite exclusions were independently enumerated before any
Internal assertion ran. The same-candidate accepted Core run was reused unchanged.
No SDK/test edit, native assertion retry or deadline extension occurred.

All M01–M11 obligations now pass with independent review. Five public clients
pass; twelve new platform builds produce 144 complete architecture source lists and
933 hashed product files. Twelve macOS receipts for six unchanged products and
current F02 documentation are reused with exact source/dependency identity. Strict
lint covers 734 source and 709 test files with zero violations. Nine-module Swift
and Objective-C API output equals the committed baselines.

Before client/lint/API execution, source inventory and simulator runtime checks
were strengthened. The original definitions remain preserved; extra, missing,
changed and symlinked source controls reject. All cleanup and identity checks pass
within the original deadline.

This closes only S2:F03 for the selected composition. Duo/app/backend, active-work
ownership and final release requirements stay separate. No SDK/test edit, Replay
capture, full test-ios-all or numerical performance claim follows. All original
skips, warnings and failures remain.
