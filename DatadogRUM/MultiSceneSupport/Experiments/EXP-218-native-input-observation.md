# Native input observation

## EXP-218 — Observe the missing switch effect

The [definition](../Results/EXP-218-native-input-observation.json) freezes a one-hour,
one-build diagnostic before implementation. The original failure was UIKit stack
on a regular iPhone 17 simulator running iOS 27.0/24A434, built with SDK 27.1.
It was not a Duo-specific failure. Baseline SDK source remains unchanged.

Two fixed SDK-on/off launches observe only the existing Home button and switch
inputs. A bounded in-memory application event probe records assigned touch
ancestry and pre/post dispatch state; existing native callbacks and receipts own
the input outcome. Failure is frozen before the probe flush or any later input.
No control layout, hit testing, gesture or SDK implementation changes are allowed.

Independent source/oracle admission is required before native execution. Both
passing would leave the earlier intermittent failure unresolved. A difference
between the two arms is an observed association, not proof of SDK causality.
The pair provides no automatic-coverage, Duo, backend or release-gate pass.

## Checkpoint

**Native execution completed; diagnostic oracle rejected.** One baseline SDK-on
case passes XCTest with zero skips or runtime warnings. Both existing callbacks
fire once, the receipt advances from 0 to 1 to 2, and the switch changes from 0 to
1 before the frozen observation boundary. This is no SDK-on/off comparison: the
SDK-off arm remains unrun under the observer-integrity stop rule.

The passive probe records the switch's began touch with `home.toggle` in its
assigned ancestry. The ended touch has the same identifier but an empty ancestry.
All four switch dispatch snapshots still contain `value=false`; the original
callback arrives about 1.06 ms after the last `sendEvent` after-snapshot. The
frozen oracle therefore rejects its required complete target/dispatch witness.
It was not weakened after the result. The callback/receipt observation is valid,
but neither the old input failure nor SDK causality is explained.

Before that launch, Xcode rejected `-test-iterations 1` with exit64 and zero
executed tests. Its result bundle, command, discovery, admission and cleanup
remain under `pre-execution-rejection` in the durable artifact root. Independent
review admitted removing only that unsupported option: the same build, app/test
sources, oracle, two unused launch slots and original deadline remained. A fresh
simulator, output directory and run ID were used. This was a command correction
before native execution, not a native retry.

One build compiled all 387 expected Swift inputs across five source lists. The
391 baseline SDK files and protected workspace paths remained unchanged. Four
positive and thirteen negative oracle controls passed before execution. Compiler
output retains 29 warning-line occurrences; the single native result reports no
runtime warnings. Both task simulators and their app data were removed. Cleanup
and the checkpoint completed before the original 13:00:19 UTC deadline.

The [owning result](../Results/EXP-218-native-input-observation.json) binds source,
build, installed binary, complete native rows, receipts, rejection and independent
review hashes. There is no backend query, SDK edit, Duo/SwiftUI/physical result or
release-gate closure. A future callback-side in-memory witness needs a separate
pre-result admission; do not run the skipped arm or repeat this pair. Continue
independent release preparation.
