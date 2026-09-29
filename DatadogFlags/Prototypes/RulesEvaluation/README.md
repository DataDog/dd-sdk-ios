# Swift Rules Evaluator Prototype

An isolated, evaluation-only experiment for the mobile offline/dynamic-context RFC.
This package is **not linked into DatadogFlags or shipped to customers**. The
standalone package/local benchmark pod pins SwiftProtobuf 1.38.1; the shipping SDK
does not gain this dependency. Generated types and evaluators are internal. The
public Objective-C facade exists only to connect the companion RN benchmark app.
There is no networking, production configuration cache, or telemetry in this
package. The adapter can persist temporary fixture bytes for hydration experiments
and export benchmark reports to the app's Documents directory. CryptoKit supplies MD5
for the assignment protocol, not for security.

Tracking: [FFL-3347](https://datadoghq.atlassian.net/browse/FFL-3347).
Design context: [mobile RFC](https://docs.google.com/document/d/17PM3RoFPH-XM9zEUvoMAYZUfo5nwUi982rM-6RMZU8w/edit).

## Client Protobuf and RN Comparison

`ProtobufRulesEvaluator` evaluates an immutable generated client UFC message.
`FlagsBenchmark` (`DDFlagsBenchmark` in Objective-C) accepts binary or ProtoJSON
configuration installation, context-dependent reads, decoder/native-direct timing
controls, an echo control, and environment metadata. The RN adapter must serialize
access to installation and evaluation; the facade itself is not thread-safe.
Parsing happens on installation, not on every read.

### Persisted Hydration Follow-Up

The benchmark-only facade also accepts `persistBinary`, `readCachedBinary`,
`readCachedJson`, and `evaluateCachedBinary`. It writes fixture bytes to a unique
temporary file per facade instance and removes that file on deinitialization.
These operations are not a production cache API or an offline provider lifecycle.
The RN caller serializes them using the same adapter as the original placements.

The companion RN harness compares an asynchronous native file read followed by
JS decoding/evaluation, native decoding with a ProtoJSON handoff, or native
decoding/evaluation with only the result returned. Files are created before timing
and the OS cache is warm. The last path intentionally decodes on each hydration
sample; ordinary installed-snapshot reads still decode only on installation.
Tests check persisted bytes, both decoded representations, configuration
replacement, evaluation metadata, and isolation between facade instances.

The RN follow-up separately measures the existing native tracking pipeline;
no tracking code is added to this Swift package. See the companion
[results summary](https://github.com/DataDog/dd-sdk-reactnative/blob/sameerank/mobile-flags-benchmarks/benchmarks/src/flags/RESULTS.md)
for the saved measurements, provenance, and limitations.

This evaluator deliberately supports only the synthetic RN benchmark subset:
boolean variations, static allocations, string membership/negation, numeric
comparisons, all/any condition groups, attribute presence, time windows, and MD5
splits. Unsupported evaluated operators and feature levels return explicit errors.
This is not a production provider or a full client-UFC conformance implementation.
The broader server-JSON experiment below is separate and is not used for RN timing.

The companion `dd-sdk-reactnative` branch is
`sameerank/mobile-flags-benchmarks`; its `benchmarks/src/flags/README.md` documents
the four decoder/evaluator placements, sync/async reads, exact timing boundaries,
and physical-device reproduction. The local pod is linked only when its
`DD_FLAGS_PROTOTYPE_PATH` option is supplied during `pod install`.

`Tests/RulesEvaluationPrototypeTests/Fixtures/client-benchmark.json` contains two
configurations with 64 evaluations each, expected results from published
`@datadog/flagging-core@3.1.1`, and SHA-256 payload checksums. Tests evaluate both
binary and ProtoJSON installations, compare metadata except wall-clock timestamps,
and check context changes, replacement, malformed inputs, and controls. Regenerate
from the RN repo's `benchmarks` directory:

```sh
yarn flags:compile-fixture
node scripts/export-flags-fixture.cjs \
  ../../dd-sdk-ios/DatadogFlags/Prototypes/RulesEvaluation/Tests/RulesEvaluationPrototypeTests/Fixtures/client-benchmark.json
```

### Schema Generation

`proto/ufc.proto` is copied unchanged from `DataDog/openfeature-js-client` commit
`fb8e9f7618768e9d34032049ab91cfa98eb21b95`, `packages/core/proto/ufc.proto`.
Generated Swift is committed with internal visibility. With Buf installed and
Xcode 26.2 / Swift 6.2 available, run from this package directory:

```sh
swift package resolve
swift build --package-path .build/checkouts/swift-protobuf \
  -c release --product protoc-gen-swift
PATH="$PWD/.build/checkouts/swift-protobuf/.build/release:$PATH" buf generate
```

The dependency's tooling requires Swift 6.2; this experiment does not change the
shipping SDK's supported toolchain. `Package.resolved` pins the dependency revision.

## Earlier Server-JSON Experiment

The prototype loads a subset of the UFC v1 `SERVER` JSON configuration into an
immutable snapshot. The JSON input is a benchmark/conformance input, **not** the
client endpoint's protobuf response or the portable configuration wire envelope.
Configuration decoding, validation, and timestamp preparation happen once.
Evaluations receive their context and timestamp explicitly and have no side effects.

Supported:

- Boolean, string, integer, numeric, and JSON variation values.
- Ordered allocations; OR between rules, AND between conditions.
- `ONE_OF`, `NOT_ONE_OF`, `IS_NULL`, `LT`, `LTE`, `GT`, and `GTE`.
- Allocation time windows with inclusive starts and exclusive ends.
- MD5 percentage splits, UTF-8 input, multiple shards, and half-open shard ranges.
- Missing versus empty targeting keys, the `id` alias, and context changes without reloading.
- Value, reason, variant, allocation key, split serial ID, exposure eligibility,
  evaluation timestamp, and full-evaluation-data policy in the result.
- Per-flag failure isolation. Unsupported operators return `PARSE_ERROR` with an
  explicit preparation diagnostic; they do not silently match or fall through.

Not implemented in the server-JSON evaluator: protobuf/wire decoding, regex, semver, obfuscated/SHA-256
conditions, configuration fetching/storage, OpenFeature adapters, tracking hooks,
or an OpenFeature provider. Do not use this to evaluate arbitrary production configurations.

The implementation is a candidate, not a full cross-SDK conformance claim. In
particular, exotic numeric-to-string formatting is not yet JavaScript-compatible;
Swift dictionary keys use native Unicode equality; invalid date strings are
rejected; custom JavaScript objects are outside the JSON context model. These
need resolution before broadening the supported workloads or shipping anything.
Validation is performed at preparation time, which must be accounted for when
comparing against an evaluator that validates during each read.

## Correctness

From the `dd-sdk-ios` repository root:

```sh
swift test --package-path DatadogFlags/Prototypes/RulesEvaluation
```

Tests include 168 unchanged evaluation cases for 29 selected flags from
[ffe-system-test-data](https://github.com/DataDog/ffe-system-test-data/tree/b469cb917d7f5df1cdc35723ba7da54c3ee53208).
The missing-flag cases intentionally reference an absent flag. Configuration
entries and cases were selected without rewriting their expected results;
`Tests/RulesEvaluationPrototypeTests/Fixtures/provenance.json` records the source
revision and selected files/flags. The JavaScript SDK consumes the same upstream
fixtures in `packages/core/test/evaluation/flags-v1.spec.ts`.

Additional tests cover context A -> B -> A, metadata, missing/empty targeting
keys, explicit `id` overrides, strict numeric coercion, time/shard boundaries,
unsupported operators, and invalid-flag isolation. Time is fixed within the
shared fixtures' active allocation windows, rather than depending on today's date.

The ordinary SDK test schemes/CI do not run this standalone package. Run its
tests explicitly while iterating on the experiment.

## Initial Benchmark Harness

```sh
DD_FLAGS_BENCHMARK=1 swift test -c release \
  --package-path DatadogFlags/Prototypes/RulesEvaluation
```

The opt-in XCTest harness prints JSON rows with p50/p95/p99 in microseconds:

- Warm evaluation: static numeric, boolean targeting, numeric comparisons, and
  JSON percentage splits. Each workload cycles through its shared fixture
  contexts, warms up for 1,000 calls, then records 20,000 individual calls.
- JSON decode and preparation: 200 samples, with file reading outside the timer.
- A clock-pair baseline to make measurement overhead visible. It is not subtracted.

Results are consumed outside the timed region. Evaluation timing includes the
small fixture adapter/context construction, but excludes configuration parsing,
wall-clock acquisition, tracking, I/O, and JS/native transport. The preparation
measurement uses this fixture subset, including deliberately invalid flags; it
is not a production payload-size or startup benchmark.

`swift test` runs on the host Mac. Those numbers validate the harness, **not iOS
device performance or a JavaScript/native architecture decision**. Debug builds
skip the benchmark. No performance thresholds are asserted in tests.

## Evidence and Remaining Work

Use the companion RN benchmark for optimized physical-device measurements.
A faster direct Swift call does not establish that native evaluation is faster
for an RN caller, and an echo control does not substitute for a real evaluator.
Release simulator and iPhone 16 Pro placement measurements are now available.
Both favor local JS repeated reads from an RN caller's perspective, while direct
native decoding/evaluation controls are faster. The device reported serious
thermal conditions at completion, so it is exploratory evidence rather than a
nominal-temperature latency baseline. Simulator follow-ups measured warm-file
hydration and real native tracking with a loopback collector.

Simulator data can inform architecture and expose transfer/blocking costs; it
does not establish phone energy, thermal, or flash behavior. Host Swift tests are
not mobile performance results. Android, true cold startup, broader conformance,
incremental package size, isolated memory attribution, and production cache
policy remain open. Do not pool device and simulator samples or infer a fastest
possible JSI/shared-memory design from the tested ProtoJSON transfer.
