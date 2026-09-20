# Active native view cache lifetime

## EXP-207 — Retain delayed WebView containers after long native visits

E04 extraction eligibility is qualified on current develop `62f64d7b`.
The [owning result](../Results/EXP-207-active-view-cache.json) retains the definition,
fixed 75-minute deadline, every attempt, input identities and independent reviews.
Production commit `cc83c850` changes two internal RUM files; test checkpoint
`a3d34069` contains the three unchanged regression fixtures. Both local commits
used the authorized unsigned fallback after a signing timeout or refusal. No push.

The defect is independent of scene routing. Inserting B after a long visit to A
purges A by its start time, so a delayed browser event loses A's native container.
Lookup-only stale entries and uncached restored view IDs expose the other lifetime
boundaries. The repair keeps active entries, starts the full retention window at
inactivity, and makes deactivation idempotent. Session end, release and restoration
use exact view UUIDs. Legacy insertion defaults, strict time boundaries, Replay
filtering, newest-first ordering and the capacity limit remain intact.

The first invocation failed to compile the receiver fixture and ran zero tests.
Independent review admitted exactly two fixture corrections: a testable helper
import and the declared application-scope initializer. A fresh baseline then
executed all 13 frozen tests: eight failures at the predicted assertions and five
preservation passes, with no skips. No production change preceded that result.
The [baseline audit](../Results/EXP-207-baseline-audit.json) retains the original
failure and correction. All assertions stayed fixed afterward.

The reviewed candidate passes the complete RUM target: 910 cases, 946 executions,
no failures, skips or retries. All 13 controls pass once. The
[source review](../Results/EXP-207-source-review.json) covers the two-file boundary,
atomic cache mutation, value-only retention, session teardown and all callers.
UUID values are compared before formatting strings, avoiding new conversions on
every command. The [unit audit](../Results/EXP-207-unit-audit.json) binds results to
source, dependencies and compiled products.

The same three-test native bridge slice fails only the two delayed-A container
assertions on develop, then passes 3/3 on the candidate. Both versions preserve
browser/native/application/session identities, Replay context, corrected dates,
post-expiry omission and current B ownership. The
[paired audit](../Results/EXP-207-native-pair-audit.json) verifies both builds,
identical tests, fresh installations and cleanup. The candidate finished at
06:51:35 UTC, over 24 minutes before the original deadline. An audit reader initially
mistook the per-test summary failure list for an assertion list; the detailed tree
and console independently retain both expected failures. No test was rerun for it.

These are controlled-clock, injected WKWebView/controller messages and feature-writer
JSON. They do not qualify real browser callback timing, initial launch-clock behavior,
backend delivery, physical Duo, or numerical performance. Replay context is injected.
The native fixture's SDK-init context date differs from its A/B clock; this does not
change the exercised cache selection but does not establish launch timing behavior.

Warnings remain visible: 239 unit and 251 native warning lines, plus 59 duplicate-class
messages per run; baseline/candidate diagnostic sets match within each comparison.
Verbose XCTest archives were omitted symmetrically using the documented option.
There is no clean-sanitizer claim. Lookup now uses a write-lock mutation; existing
performance gates remain required for this candidate before release. Default cache
capacity remains 30; expiry physically removes entries on the next cache operation.
E01 release gates and historical multi-scene findings are unchanged.
