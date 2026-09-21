# Resource completion and upstream cache metrics

## EXP-219 — Reconcile E03 with current develop

[Draft #3218](https://github.com/DataDog/dd-sdk-ios/pull/3218) conflicts with
upstream `9a8a66c3`, which replaced `local_cache_hit` with `delivery_type` and
`transfer_size` after E03 qualified on `62f64d7b`. Preserve the original signed
candidate and its evidence. Apply the same change to a fresh current-develop
checkout, retaining upstream metrics and E03's Error1/Resource0, HTTP status,
Resource/action owner and legacy manual contracts.

The [definition](../Results/EXP-219-upstream-resource-integration.json) freezes
a two-hour limit, existing path allowlist, one affected RUM suite, one upstream
metrics class and the unchanged nine native cases before implementation.
Inventories and source/build identities must freeze before assertions. No
Replay captured-content test, backend query, dependency upgrade or generated-model
edit is admitted. Existing strict ownership assertions and the exact inherited
stopped-session diagnostic retain their recorded boundaries.

The reconciliation is qualified and published in [#3218](https://github.com/DataDog/dd-sdk-ios/pull/3218).
Signed source `b3c60b7b9` preserves upstream cache metadata and the E03 contract;
signed documentation `1b2bff3e7` records it. Eight of the ten source/test files are
byte-identical to the earlier E03 candidate. The handler and its metrics fixtures
are reconciled, with one added success-metrics discriminator.

| Check | Result |
| --- | --- |
| Affected RUM suite | 920 cases / 956 executions passed |
| Upstream ResourceMetrics | 9/9 passed |
| Unchanged native transfers | 9/9 passed; serialized ownership/boundary audit passed |
| Runtime inventory | No skips or structured runtime warnings |
| Source/build guards | 1,864 inputs, 266 artifact entries, exact compiler membership; 26 offline controls passed |
| Static checks | Strict lint, nine-module Swift/Objective-C API against current develop, five feature docs and registry passed |
| Review / cleanup | Independent review passed; app removed, owned simulator deleted, protected paths unchanged |

Two preparation stops remain preserved: an ANSI-colored patch rejected before
application, and strict package resolution with a missing ignored lockfile. The
reviewed corrections changed command formatting and copied the exact qualified
lockfile. Neither ran assertions, changed dependencies or extended the deadline.
All execution completed within the original two-hour limit, without assertion retries.

The native stopped-session case retains the separately reviewed inherited
precondition diagnostic. No telemetry-free, backend, physical-device or broad
platform qualification follows. Earlier module/platform results remain tied to
their original source. Current-head CI, maintainer review and separately authorized
merge remain open. The original signed checkout and all prior failures are intact.
