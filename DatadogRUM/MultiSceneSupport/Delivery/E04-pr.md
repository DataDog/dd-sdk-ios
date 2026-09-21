### What and why?

A native view that stays open longer than the correlation cache's expiry can lose its association with delayed WebView events. Keep its entry while active, then start the existing expiry window when it becomes inactive.

### How?

Mark the exact view inactive on navigation or session termination and restore active entries when a session resumes. Preserve the 30-entry limit, timestamp ordering and Replay metadata filtering.

Regression tests cover long visits, delayed events, expiry and restoration. The RUM suite passes 946 executions, and three native bridge controls pass. Selected module suites, platform builds and lint pass locally. Integration checks use [hitch-assertion fix](https://github.com/DataDog/dd-sdk-ios/pull/3214) and retain existing QoS warnings. The bridge controls qualify cached correlation metadata, not retained host objects, real-browser timing or backend ingestion.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG updated.
- [x] No public API or Objective-C interface changes.
- [x] API generation not required.
- [ ] Current CI and maintainer review.
