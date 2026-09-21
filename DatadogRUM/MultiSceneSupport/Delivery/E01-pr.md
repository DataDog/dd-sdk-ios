### What and why?

Repeated or concurrent resume calls on one URLSession task can prepare instrumentation more than once, mutating its request again and duplicating telemetry. Prepare each task once, preserve callbacks that arrive during preparation, and release instrumentation state when the task finishes.

### How?

Synchronize the task preparation lifecycle, forward deferred native resume calls after preparation, buffer early callbacks, and remove strong terminal ownership. A duplicate resume during preparation may be forwarded later on the preparing thread; original caller-thread timing is not guaranteed.

This PR is stacked on the separate hitch-assertion correction for review. Its diff excludes that test. After the prerequisite merges, verify develop's actual content, drop the equivalent prerequisite and retarget to develop.

Validation uses the exact qualified source tree: complete affected Internal (455 cases / 491 executions), Core (815 passes, four OS skips), RUM (901 cases / 937 executions), Trace (141 passes), and integration (278/278) inventories; additional automatic/registered failure/cancellation lifetime controls pass 8/8. Debug and optimized reentrancy, ordinary/legacy/custom/NOP compatibility, 24 platform/configuration builds, five public-client runtime cells and unchanged API comparisons are recorded. Both candidate backend modes passed exact RUM/Trace inventories and ownership checks. Original failures, OS skips and warning limits remain in the evidence packet.

The inherited QoS warning also occurred on unchanged develop. Its captured stack is incomplete; neither harmlessness nor sanitizer/performance clearance is claimed. Full Logs, CrashReporting, WebViewTracking, Flags and Profiling suites add 544 passes with one predefined watchOS-only skip. Current CI and final release review remain open. Replay captured-content checks are excluded; crash safety and other-feature compatibility remain required.

### Review checklist

- [x] Feature or bugfix has appropriate unit, native integration and terminal-lifetime tests.
- [ ] Each commit and the PR mention the real issue/Jira reference — pending ticket.
- [x] Customer-facing CHANGELOG entry included.
- [x] Objective-C interface: not applicable; no new public API.
- [x] Existing Swift/Objective-C API surface comparisons pass without baseline changes.
