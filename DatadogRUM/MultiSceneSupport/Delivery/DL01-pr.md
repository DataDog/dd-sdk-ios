### What and why?

`CADisplayLink` retains its target. When the RUM display-link observer is that target, releasing the SDK can leave the observer and its frame readers alive.

### How?

Use a private callback target with a weak reference to the observer. Frame callbacks still reach a live observer, and releasing it can invalidate the display link. Reader registration and platform-specific behavior stay unchanged.

Focused tests cover real display-link ownership, frame forwarding, invalidation and SDK release after queued configuration work finishes. Core/RUM and the remaining selected module suites pass on iOS 17.5. Integration validation used the independent hitch-assertion correction and retains existing QoS warnings. Debug and Release platform builds and strict lint pass.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [ ] Issue reference or explicit waiver confirmed for publication.
- [x] CHANGELOG updated.
- [x] No new public API requiring an Objective-C interface.
- [x] Public APIs unchanged.
- [ ] Required CI and maintainer review.
