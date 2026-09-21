### What and why?

An automatic URLSession span can adopt the RUM view active when the request finishes. Capture RUM context during request preparation so out-of-order completions keep each request's original owner. Requests started without a RUM owner remain ownerless.

### How?

Carry the captured context through the URLSession handler into the span writer, then release it on completion. Preserve other span context and caller headers. A baggage-only write must not claim ownership of trace headers it did not inject.

All 154 Trace tests pass. Native automatic and registered-delegate requests complete in reverse order with the expected backend RUM/span owners. These scenarios disable automatic RUM Resources. Selected module suites, platform builds and lint pass locally. Integration checks use [hitch-assertion fix](https://github.com/DataDog/dd-sdk-ios/pull/3214) and retain existing QoS warnings.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [x] Ticket reference waived for these drafts.
- [x] CHANGELOG updated.
- [x] No public API or Objective-C interface changes.
- [x] API generation not required.
- [ ] Current CI and maintainer review.
