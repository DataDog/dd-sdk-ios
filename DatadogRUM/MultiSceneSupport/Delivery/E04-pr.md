### What and why?

A native view that stays open longer than the cache expiry can lose correlation with delayed WebView events. Keep its entry active until that view becomes inactive, then start the existing expiry window once.

### How?

Mark exact view UUIDs inactive on navigation and session termination, preserve restoration, and purge expired entries under the existing write lock. Retain the cache capacity of 30, timestamp ordering and Replay filtering.

Validation reused for identical production/test contents: full RUM suite, 910 cases / 946 executions; three native bridge controls passed against the baseline ownership failures. Repository lint passed. The native fixture injects WebView messages and inspects serialized output; actual browser callbacks and backend ingestion remain separate. Source-matched teardown, expiry and restoration controls cover the changed cache/session lifetime paths; the cache adds no host or pending Resource reference. Eight additional complete iOS suites passed with1,972 passes and five predefined OS skips. Full Integration279/279 passed on the test-only hitch composition, preserving eight prior QoS warnings. All twelve affected-platform Debug/Release builds passed with144 complete architecture source lists. Full Replay still needs its inherited fixture prerequisite and candidate qualification; Trace-document drift, CI and human review remain in the packet.

### Review checklist

- [x] Feature or bugfix has appropriate unit and integration regressions; evidence and limits are recorded above.
- [ ] Each commit and PR mentions the real issue/Jira reference; ticket is pending.
- [x] Changelog updated for the customer-facing change.
- [x] No public API is added; no new Objective-C interface is required.
- [x] Public API source remains unchanged; API generation is not required for a new surface.
- [ ] Complete the packet's missing candidate checks and current required CI.
- [ ] Human review and separately authorized publication/merge.
