# S2 object lifetime qualification

## EXP-211 — audit S2 view and Resource lifetime

Owning definition, hashes and results: [EXP-211-s2-lifetime.json](../Results/EXP-211-s2-lifetime.json).

The 144-file selected-source audit maps 31 accepted outcomes to S2:P03. Collection
removal, weak object release, cache TTL and OS process cleanup prove different
things. E01 task lifetime remains qualified. E04 is a bounded value-entry
expiry/correlation issue, with at most 30 entries and no strong controller/scope
references; its exact two-file composition remains separate.

A real CADisplayLink retains its target. The inherited DisplayLinker passed itself
as that target, preventing deinit from invalidating the provider while active.
The reviewed repair introduces a private weak callback target; existing frame
handling, reader stop, provider invalidation and notification cleanup remain.
Local commit `a4be961d14c77c9a7787c9bfb55398784022d0f9` changes one source and one
test file in isolated `valpertui/s2-rum-lifetime`. Signing timed out; the authorized
local unsigned fallback succeeded. No push or S2 release selection occurred.

| Evidence | Outcome and boundary |
| --- | --- |
| D1 native diagnosis | Three iOS 17.5 tests: active owner/reader and real-core target checks fail; resign-active control passes. Three exact assertions, zero skips or structured runtime warnings. |
| D2 weak-target repair | Eight methods pass: direct active/inactive release, retained-provider callback safety and five existing frame/activity/registration controls. Real-core target still survives its original two-second observation. |
| D3 ownership discriminator | The same failing method observes Monitor, application scope, DisplayLinker and first-frame reader. All remain at two seconds; core proxy and RUMFeature release. |
| D4 explicit owner boundary | Source identifies the MessageBus five-second scheduled task as another legitimate owner of RUM receivers/Monitor. The test observes its actual configuration delivery before teardown, then retains the original two-second release assertions. |
| Corrected D4 | One pass: all nine nonnil-before weak witnesses release, including actual core and bus. No failures, skips or structured runtime warnings. |

The first D1 attempt stopped before build/launch because the new worktree lacked
its ignored package lock. Original D4 completed body assertions but crashed in
the suite's cleanup guard: CoreTests and TestUtilities have separate module-local
`temporaryCoreDirectory` values. Its correction deletes the fixture's own
directory in outer defer after critical assertions; the original deadline and
release oracle are unchanged. The invalid run and its exact cleanup are retained.

A source-review mismatch was also corrected without semantic code changes:
selected `652ce169` and develop `62f64d7b` already contain the AppKit branches; the unrelated
experimental checkout differs. Exact git blobs verify that the repair changes
only target ownership. Final production differs from that reviewed proposal only
by the required `@objc` newline formatting. Both review dispositions remain.

Final qualification composes eight byte-identical D2 method bodies with the
corrected D4 pass, not a fresh 9/9 invocation. Strict scoped source/test lint passes.
Source, dependencies, pins, frameworks, protected paths and hostless cleanup pass.
The independent final review qualifies the focused repair only. No broad P03,
unbounded Monitor/core leak, early-teardown, sanitizer, numeric memory/CPU,
other-platform runtime, physical Duo or full-release claim follows. The S2
release freeze remains E01-only pending a separate composition/source audit.
