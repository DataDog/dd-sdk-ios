### What and why?

A Resource that finishes after navigation or a session change can alter another view's action counters. A URLSession transfer that receives headers and then fails can also appear as a completed Resource.

### How?

Carry the Resource owner on completion commands and apply action updates only to that owner. Report failed transfers as one network Error on the owning view, preserving the received HTTP status. Successful bodies, empty HEAD/204 responses and manual completion behavior stay unchanged.

The RUM suite passes 961 test executions. Nine native cases cover ownership and successful, empty or failed transfers. Selected module suites, platform builds and lint pass locally. Integration checks use [hitch-assertion fix](https://github.com/DataDog/dd-sdk-ios/pull/3214); existing diagnostics and QoS warnings remain. Backend ingestion is untested. Current CI must also cover the Resource-cache changes recently merged into develop.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG updated.
- [x] No public API or Objective-C interface changes.
- [x] API generation not required.
- [ ] Current CI and maintainer review.
