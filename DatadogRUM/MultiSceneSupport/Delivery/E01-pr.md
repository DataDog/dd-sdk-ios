### What and why?

Repeated or concurrent `resume()` calls can instrument the same URLSession task more than once, rewriting its request and duplicating telemetry. Prepare each task once and preserve callbacks that arrive during preparation.

### How?

Coordinate preparation under a lock, buffer early callbacks in order, and forward native resume calls outside the lock. Weak terminal identities prevent repeat preparation without retaining completed tasks. A duplicate resume during preparation may run later on the preparing thread.

Unit and native checks cover concurrency, reentrancy, callback ordering, cancellation and release. Compatibility clients, platform builds and backend ownership checks pass locally. Integration runs retain existing QoS warnings.

This PR is stacked on [hitch-assertion fix](https://github.com/DataDog/dd-sdk-ios/pull/3214). Rebase and retarget it to develop after that PR merges.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG updated.
- [x] No public API or Objective-C interface changes.
- [x] API generation not required.
- [ ] Current CI and maintainer review.
