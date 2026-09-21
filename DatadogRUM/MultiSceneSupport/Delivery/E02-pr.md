### What and why?

If an app returns to the same view key while an older occurrence still has a pending Resource, new start/stop attributes can overwrite the older occurrence. Keep those attributes on the active occurrence while the pending Resource retains its original view.

### How?

Require an active view before applying matching start or stop attributes. Preserve repeated starts on the current view, action ownership and session restoration.

Regression tests reproduce the old overwrite and verify serialized full/delta events after navigation. The RUM suite and remaining selected module suites pass on iOS 17.5. Integration validation used the independent hitch-assertion correction and retains existing QoS warnings. Debug and Release platform builds and strict lint pass. The ownership checks inspect serialized SDK output; backend ingestion remains untested.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [ ] Issue reference or explicit waiver confirmed for publication.
- [x] CHANGELOG updated.
- [x] No new public API requiring an Objective-C interface.
- [x] Public APIs unchanged.
- [ ] Required CI and maintainer review.
