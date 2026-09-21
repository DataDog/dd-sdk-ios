### What and why?

An automatic URLSession span can adopt the RUM view active when the request finishes. Capture the existing RUM context during request preparation so out-of-order completions keep each request's original owner. A request started without a RUM owner must remain ownerless.

### How?

Carry the captured context through the URLSession handler into the span writer, and release it before completion guards. Preserve other span context and caller headers. A baggage-only write must not claim ownership of trace headers it did not inject.

All 154 Trace tests pass. Native automatic and registered-delegate requests preserve separate owners through reverse completion, including an ownerless request. Backend RUM/span inventories confirm those owners. Remaining selected module suites, twelve platform builds and strict lint pass. Integration validation used the independent hitch-assertion correction and retains existing QoS warnings. Native ownership scenarios disable automatic RUM Resources; they do not cover every networking configuration.

### Review checklist

- [x] Unit and integration coverage matches the change.
- [ ] Issue reference or explicit waiver confirmed for publication.
- [x] CHANGELOG updated.
- [x] No new public API requiring an Objective-C interface.
- [x] Public APIs unchanged.
- [ ] Required CI and maintainer review.
