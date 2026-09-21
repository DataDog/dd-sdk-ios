### What and why?

Repeated or concurrent `resume()` calls can instrument the same URLSession task more than once, rewriting its request and duplicating telemetry. Prepare each task once, preserve callbacks that arrive during preparation, and release preparation state when the task finishes.

### How?

Coordinate preparation under a lock, buffer early callbacks in order, and forward native resume calls outside the lock. Weak terminal identities prevent a completed task from being prepared again without retaining it. A duplicate resume during preparation may run later on the preparing thread.

This PR targets the separate hitch-assertion correction for review. After that correction merges, it must be rebased and retargeted to develop with the prerequisite removed from its history.

Unit and native integration checks cover repeated, concurrent and reentrant resume, failure, cancellation, callback ordering and release. Ordinary, legacy, custom/NOP and Swift 5/Swift 6/Objective-C clients pass. Platform builds and unchanged public API comparisons pass. Automatic and registered-delegate backend checks preserve request ownership. Existing QoS warnings remain.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [ ] Issue reference or explicit waiver confirmed for publication.
- [x] CHANGELOG updated.
- [x] No new public API requiring an Objective-C interface.
- [x] Public APIs unchanged.
- [ ] Required CI and maintainer review.
