### What and why?

View-hitch integration assertions currently inspect the final RUM view update as if it were a full document. A stopped-view delta can omit unchanged frames, so the test fails even when the preceding update recorded the hitch correctly. Reconstruct the target view's full state before checking it.

### How?

Apply full and delta documents in document-version order. An omitted field preserves the previous value; an explicit empty value clears it. Keep the workload, timing and hitch thresholds unchanged. Missing-frame and appended-empty controls must still fail.

Validation: the original assertion failed on both develop and the URLSession candidate. Both histories reconstructed one stopped view with one hitch, and six malformed-history controls per arm rejected. The corrected test file then passed in the complete 278-test integration run on iOS 17.5. The standalone delivery now passes both changed-class tests on iOS 17.5, with no skips or structured runtime warnings, complete 41-file target compilation and verified cleanup. Repository strict lint passes all 734 source and 709 test files with zero violations. Current CI and human review remain pending. No production source changes.

### Review checklist

- [x] Feature or bugfix has appropriate tests: existing workload plus missing/empty negative controls.
- [ ] Each commit and the PR mention the real issue/Jira reference — pending ticket.
- [x] CHANGELOG: not applicable to this test-only correction.
- [x] Objective-C interface: not applicable; no public API changes.
- [x] API surface generation: not applicable; no public API changes.
