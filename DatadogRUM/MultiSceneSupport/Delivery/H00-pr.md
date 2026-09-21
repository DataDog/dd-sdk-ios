### What and why?

RUM view updates can omit unchanged hitch data. Reading only the terminal update can make the integration test miss an earlier hitch.

### How?

Reconstruct view state in version order. Full documents replace the baseline; delta omissions preserve prior values and explicit empty fields clear them. Disabled tracking must omit hitch data in every source document.

The two integration tests and a regression for recurring full baselines pass on iOS 17.5. Focused strict lint passes; workload, timing and thresholds stay unchanged. This changes one test file only.

### Review checklist

- [x] All three affected tests pass.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG not required for a test-only change.
- [x] No public API or Objective-C interface changes.
- [x] API generation not required.
- [ ] Current CI and maintainer review.
