### What and why?

`CADisplayLink` retains its target. When the RUM observer is that target, releasing the SDK can leave the observer and its frame readers alive.

### How?

Use a private callback target with a weak reference to the observer. Frame callbacks still reach a live observer. When the observer deinitializes, it invalidates the display link. Reader registration and platform behavior stay unchanged.

Focused tests cover real display-link ownership, frame forwarding, invalidation and SDK release after queued work finishes. Core/RUM, selected module suites, platform builds and lint pass locally. Integration checks use [hitch-assertion fix](https://github.com/DataDog/dd-sdk-ios/pull/3214) and retain existing QoS warnings.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG updated.
- [x] No public API or Objective-C interface changes.
- [x] API generation not required.
- [ ] Current CI and maintainer review.
