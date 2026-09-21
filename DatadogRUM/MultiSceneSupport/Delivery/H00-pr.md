### What and why?

A stopped RUM view can omit unchanged hitch data from its final delta. The integration test treats that delta as a full document and can fail even though an earlier update recorded the hitch.

### How?

Reconstruct each view in document-version order before checking its hitches. Omitted fields preserve prior values; explicit empty fields clear them. The workload, timing and hitch thresholds stay unchanged.

Both affected integration tests pass on iOS 17.5, and strict repository lint passes. This changes test assertions only.

### Review checklist

- [x] Both affected integration tests pass.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG not required for a test-only change.
- [x] No public API or Objective-C interface changes.
- [x] API generation not required.
- [ ] Current CI and maintainer review.
