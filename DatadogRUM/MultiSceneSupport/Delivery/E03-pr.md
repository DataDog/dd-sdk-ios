### What and why?

A Resource that finishes after navigation or a session change can alter another view's action counters. A URLSession transfer that receives headers and then fails can also appear as a completed Resource.

### How?

Carry the Resource owner on completion commands and apply action updates only to that owner. Failed transfers produce one network Error on the owning view, preserving the HTTP status. Successful bodies, empty HEAD/204 responses and manual completions keep their existing behavior.

Reconciled with develop's new cache metrics. Local checks pass: 956 RUM test executions, nine metrics tests, nine native transfer cases, strict lint, and Swift/Objective-C API checks for all nine modules. The stopped-session case retains an existing precondition diagnostic. Backend ingestion is untested; current CI and maintainer review remain required.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG updated.
- [x] No public API or Objective-C interface changes.
- [x] API generation verified.
- [ ] Current CI and maintainer review.
