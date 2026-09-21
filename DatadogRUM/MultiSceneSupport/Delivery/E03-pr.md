### What and why?

A Resource that finishes after navigation or a session change can alter another view's active-action counters. A URLSession transfer that receives headers and then fails can also appear as a completed Resource.

Resolve the Resource's owner before applying completion effects. Report a failed transfer as one network Error on its owning view, retaining the received HTTP status.

### How?

Carry owner identifiers on the completion command and restrict action updates to that owner. Preserve current-action behavior within the owning view, successful bodies, empty HEAD/204 responses and existing manual completion behavior.

The full RUM suite passes 961 executions. Nine native URLSession cases cover ownership, partial failures and successful or empty responses. Remaining selected module suites, twelve platform builds and strict lint pass. Integration validation used the independent hitch-assertion correction. Existing stopped-session diagnostics and QoS warnings remain; backend ingestion is not established by these checks.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [ ] Issue reference or explicit waiver confirmed for publication.
- [x] CHANGELOG updated.
- [x] No new public API requiring an Objective-C interface.
- [x] Public APIs unchanged.
- [ ] Required CI and maintainer review.
