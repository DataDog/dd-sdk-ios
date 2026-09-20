# Ordinary view and host lifetime

## EXP-213 — Qualify the remaining P03 ownership boundaries

Defined before test edits on signed composition `c9faed81`. The [owning result](../Results/EXP-213-view-host-lifetime.json) binds each source freeze, review, invocation and diagnostic. Production is unchanged and P03 remains open. Only the two accepted unit tests are committed, in signed local `ef9d9732`.

Both unit tests pass once on actual iPad17.5/21F79: success and failure each repeat three stopped-view/pending-Resource lifetimes, preserve the exact old event owner and active peer, and release the completed view and Resource. These accepted tests are not rerun.

Preexecution review caught private-state access and an unavailable cross-target directory helper. Both were corrected before execution without changing existing tests. The first native build then failed before running tests because the fixture used the obsolete Swift name `makeKeyWindow()`. That zero-test result remains invalid. A separately defined and reviewed one-line `makeKey()` correction preserved the original deadline and waits.

The corrected native invocation ran all three selectors once and failed 30 assertions across six cycles. UIKit, automatic SwiftUI and manual SwiftUI hosts and their content witnesses remain alive at the two-second boundary; each final RUM view also survives completion. Positive creation, active owner, explicit stopped state, exact Resource URL/view ownership and Resource weak release have no assertion failures. The compound wait failure alone does not establish that the view stayed active. Source/dependency/product identity and cleanup pass; there are no structured runtime warnings, while compiler and duplicate-class diagnostics remain recorded.

This is observed retention in the fixture, not an SDK leak finding. Source inspection identifies `RUMApplicationScope.lastActiveView` as a single strong restoration owner; that may explain the surviving RUM scope but not the native host. The SDK-off control observes actual appearance and disappearance in all four mode/cycle rows, but all four hosts/content remain under synchronous observation. A separately defined async MainActor control keeps the same construction/removal/callbacks and five-/two-second limits: all four hosts/content release. The changed waiting boundary is material; a specific UIKit retaining path is not established. Neither diagnostic enables the SDK, so neither qualifies SDK-on lifetime.

Independent final review supports the two unit tests only. It also corrects the distinction between three native test executions and six cycles, and preserves the synchronous control as the async comparator. All original/corrected source snapshots, failed attempts, raw results, products, reviews and the signed commit receipt are byte-verified in the durable evidence mirror: 1,511 files, 1,078,830,919 bytes. The native scaffolds are retained there and the task-owned integration test path is restored exactly; the candidate is clean. There is no push.

No production repair, timeout widening, accepted-test rerun or release gate closure follows from these failures. The next SDK-on slice uses async lifecycle observation and explicitly advances or witnesses the restoration owner before testing old-scope release. The source-aware candidate promotion and remaining WebView/backend/Duo obligations stay separate.
