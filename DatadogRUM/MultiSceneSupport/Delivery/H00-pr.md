### What and why?

A stopped RUM view can omit unchanged hitch data from its final delta. The integration test currently treats that delta as a full document and can fail despite an earlier update recording the hitch.

### How?

Reconstruct the view in document-version order before checking its hitches. Omitted fields preserve prior values; explicit empty fields clear them. The workload, timing and hitch thresholds stay unchanged.

Both hitch integration tests pass on iOS 17.5, and strict repository lint passes. This changes test assertions only.

### Review checklist

- [x] Both affected integration tests pass.
- [ ] Issue reference or explicit waiver confirmed for publication.
- [x] CHANGELOG not required for a test-only change.
- [x] No public API or Objective-C interface changes.
- [x] API generation not required for a test-only change.
- [ ] Required CI and maintainer review.
