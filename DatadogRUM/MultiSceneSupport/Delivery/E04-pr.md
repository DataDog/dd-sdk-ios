### What and why?

A native view that stays open longer than the correlation cache's expiry can lose its association with delayed WebView events. Keep an active view's entry until it becomes inactive, then start the existing expiry window once.

### How?

Mark the exact view inactive on navigation or session termination and restore active entries when a session resumes. Purge expired entries under the existing write lock. Preserve the 30-entry limit, timestamp ordering and Replay metadata filtering.

Regression tests cover long visits, delayed events, repeated deactivation, expiry and restoration. The RUM suite passes 946 executions, and three native bridge controls pass. Remaining selected module suites, Debug/Release platform builds and strict lint pass. Integration validation used the independent hitch-assertion correction and retains existing QoS warnings. Bridge controls inject messages and inspect serialized output; they do not qualify real-browser timing or backend ingestion.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [ ] Issue reference or explicit waiver confirmed for publication.
- [x] CHANGELOG updated.
- [x] No new public API requiring an Objective-C interface.
- [x] Public APIs unchanged.
- [ ] Required CI and maintainer review.
