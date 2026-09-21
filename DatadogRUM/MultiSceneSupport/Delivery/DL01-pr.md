### What and why?

Releasing a RUM owner can leave its display-link observer and frame readers retained by the native display callback target. Use a private weak target so that the observer can release and invalidate its display link.

### How?

Keep frame forwarding, reader registration, invalidation and existing platform branches. The repair changes one internal RUM file and its Core tests. It preserves the public API and event formats.

Validation: standalone iOS 17.5 Core suite: 819 passed, four specified OS skips; RUM suite: 901 cases / 937 executions passed, no skips. Strict discovery, source/dependency identity and cleanup passed. The nine focused frame/lifetime controls include teardown after observed configuration delivery. This does not qualify early teardown or broader view/host lifetime. All twelve affected-platform Debug/Release build cells passed with complete production-source inventories and emitted modules; this is compilation evidence. Seven additional complete hostless suites passed: 1,157 executions and one predefined watchOS-only skip. Full Integration278/278 passed with the test-only hitch assertion correction; all other 1,863 source/build inputs match. Eight QoS warnings match a subset of preserved baseline evidence; this does not establish their root cause or harmlessness. Full Replay remains pending its inherited fixture prerequisite and candidate-specific qualification. Repository lint passed; inherited Trace-document drift is recorded in the packet.

### Review checklist

- [x] Feature or bugfix has appropriate unit and integration regressions; evidence and limits are recorded above.
- [ ] Each commit and PR mentions the real issue/Jira reference; ticket is pending.
- [x] Changelog updated for the customer-facing change.
- [x] No public API is added; no new Objective-C interface is required.
- [x] Public API source remains unchanged; API generation is not required for a new surface.
- [ ] Complete the packet's missing candidate checks and current required CI.
- [ ] Human review and separately authorized publication/merge.
