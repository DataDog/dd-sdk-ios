### What and why?

Automatic URLSession spans can adopt the RUM view active when a request finishes. Preserve the RUM context captured at request preparation so reverse completion retains each request's owner, including an explicitly absent owner.

### How?

Carry the existing optional NetworkContext ownership through handler state into the span writer. Remove captures before completion guards, preserve non-RUM context and caller headers, and avoid treating a baggage-only write as trace-carrier ownership. Public APIs and wire formats are unchanged.

Validation reused for identical production/test contents: 154 full Trace tests and three native automatic-Trace controls passed. Lint and affected feature-document verification passed on this packet. Native qualification had automatic RUM Resources disabled; registered mode, terminal cleanup and backend ownership checks remain pending. The inherited QoS warning is recorded without a harmlessness claim. Broader baggage merging and partial-carrier policy are outside this repair.

### Review checklist

- [x] Feature or bugfix has appropriate unit and integration regressions; evidence and limits are recorded above.
- [ ] Each commit and PR mentions the real issue/Jira reference; ticket is pending.
- [x] Changelog updated for the customer-facing change.
- [x] No public API is added; no new Objective-C interface is required.
- [x] Public API source remains unchanged; API generation is not required for a new surface.
- [ ] Complete the packet's missing candidate checks and current required CI.
- [ ] Human review and separately authorized publication/merge.
