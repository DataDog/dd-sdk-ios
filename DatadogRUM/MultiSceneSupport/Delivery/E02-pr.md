### What and why?

When an app returns to a view key while an earlier occurrence still has a pending Resource, later start/stop attributes can overwrite that earlier occurrence. Apply matching view start/stop attributes only to the active occurrence; pending Resources keep their original view.

### How?

Add two active-view predicates and regressions for repeated-key navigation, action ownership, restoration and full/delta event serialization. Existing active duplicate-start behavior remains covered.

Validation reused for identical production/test contents: full RUM suite, 903 cases / 939 executions; two native public-monitor serialization controls passed against two baseline failures. Repository lint passed. Backend ingestion and native navigation callbacks are not established by the writer-level controls. Remaining iOS/platform checks and inherited Trace-document drift are recorded in the packet.

### Review checklist

- [x] Feature or bugfix has appropriate unit and integration regressions; evidence and limits are recorded above.
- [ ] Each commit and PR mentions the real issue/Jira reference; ticket is pending.
- [x] Changelog updated for the customer-facing change.
- [x] No public API is added; no new Objective-C interface is required.
- [x] Public API source remains unchanged; API generation is not required for a new surface.
- [ ] Complete the packet's missing candidate checks and current required CI.
- [ ] Human review and separately authorized publication/merge.
