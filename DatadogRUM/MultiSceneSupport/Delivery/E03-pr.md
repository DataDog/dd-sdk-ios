### What and why?

A Resource that finishes after navigation or a session change can alter another view's action counters. A URLSession transfer that receives headers and then fails can also appear as a completed Resource.

### How?

Snapshot the views that own the resource key before dispatching its completion. This keeps a late completion from changing another view's action, even when the starting session has stopped. Unknown manual completions retain their existing behavior.

Failed transfers produce one network Error on the owning view, preserving the HTTP status. Successful transfers, including empty HEAD/204 responses, keep their existing behavior.

Local validation covers 956 RUM test executions, nine cache-metrics tests, nine native transfer cases, strict lint and nine-module Swift/Objective-C API checks. The test-name cleanup preserves the assertions and timing and passes lint and syntax checks. The stopped-session case retains an existing precondition diagnostic. Backend ingestion is untested; current CI and maintainer review remain required.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG updated.
- [x] No public API or Objective-C interface changes.
- [x] API generation verified.
- [ ] Current CI and maintainer review.
