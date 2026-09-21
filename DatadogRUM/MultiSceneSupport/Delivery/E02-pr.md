### What and why?

If an app returns to the same view key while an older occurrence still has a pending Resource, new start/stop attributes can overwrite the older occurrence. Keep those attributes on the active occurrence while the Resource retains its original view.

### How?

Apply matching start/stop attributes only to an active view. Repeated starts on the current view and session restoration keep their existing behavior.

Regression tests reproduce the overwrite and check serialized full/delta events. RUM, selected module suites, platform builds and strict lint pass locally. Integration checks use [hitch-assertion fix](https://github.com/DataDog/dd-sdk-ios/pull/3214) and retain existing QoS warnings. These checks do not establish backend ingestion.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG updated.
- [x] No public API or Objective-C interface changes.
- [x] API generation not required.
- [ ] Current CI and maintainer review.
