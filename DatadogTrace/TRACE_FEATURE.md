---
last_updated: 2026-07-27
sdk_version: 3.14.0
verified_against_commit: 15ecc130c
tracked_files:
  - DatadogTrace/Sources/Trace.swift
  - DatadogTrace/Sources/TraceConfiguration.swift
  - DatadogTrace/Sources/Tracer.swift
  - DatadogTrace/Sources/OpenTracing/OTTracer.swift
  - DatadogTrace/Sources/OpenTracing/OTSpan.swift
  - DatadogTrace/Sources/OpenTracing/OTFormat.swift
  - DatadogTrace/Sources/OpenTracing/OTTagValue.swift
  - DatadogTrace/Sources/OpenTelemetry/OTelTracerProvider.swift
  - DatadogTrace/Sources/Objc/Tracing/Trace+objc.swift
  - DatadogTrace/Sources/Objc/OpenTracing/OTTracer+objc.swift
  - DatadogTrace/Sources/Objc/OpenTracing/OTSpan+objc.swift
  - DatadogTrace/Sources/Objc/OpenTracing/OTSpanContext+objc.swift
  - DatadogTrace/Sources/Objc/Tracing/DDSpan+objc.swift
  - DatadogTrace/Sources/Objc/Tracing/DDSpanContext+objc.swift
  - DatadogTrace/Sources/Objc/Tracing/Propagation/HTTPHeadersWriter+objc.swift
  - DatadogTrace/Sources/Objc/Tracing/Propagation/W3CHTTPHeadersWriter+objc.swift
  - DatadogTrace/Sources/Objc/Tracing/Propagation/B3HTTPHeadersWriter+objc.swift
  - DatadogTrace/Sources/Objc/Tracing/Propagation/TraceContextInjection+objc.swift
  - DatadogInternal/Sources/NetworkInstrumentation/TracingHeaderType+objc.swift
  - DatadogTrace/Sources/Feature/TraceFeature.swift
  - DatadogTrace/Sources/Integrations/TracingURLSessionHandler.swift
---

# Trace (APM) Feature

## Overview

Trace records spans that are sent to Datadog APM. It supports manual instrumentation via the OpenTracing API or the OpenTelemetry API after `Trace.enable()`. 

Trace can also connect to automatic `URLSession` network instrumentation; for that automatic URLSession path, configured first-party hosts gate distributed tracing header injection and Trace's local URLSession span creation. Avoid enabling Trace `urlSessionTracking` and RUM `urlSessionTracking` for the same requests; if RUM owns resource tracking, use RUM `firstPartyHostsTracing` for APM correlation.

Trace requires initialization via `Datadog.initialize()` before enabling.

**Platform**: iOS, tvOS, watchOS, visionOS

## Quick Start Example

```swift
import Foundation
import DatadogCore
import DatadogTrace

// Replace this with the URLSession delegate class used by your app.
final class YourURLSessionDelegate: NSObject, URLSessionDataDelegate {}

// 1. Initialize Core SDK first
Datadog.initialize(
    with: Datadog.Configuration(
        clientToken: "<client_token>",
        env: "<environment>"
    ),
    trackingConsent: .granted
)

// 2. Configure and enable Trace
Trace.enable(
    with: Trace.Configuration(
        // Sampling rate for spans created with the default tracer
        // 100 = all spans kept, 0 = none kept
        // Default: 100.0
        sampleRate: 100.0,

        // Override the `service` value reported on spans
        // Default: nil (uses the SDK service value)
        service: "my-ios-app",

        // Global tags attached to every span created with the default tracer
        // Default: nil
        tags: [
            "team": "mobile",
            "build_flavor": "release"
        ],

        // Automatic URLSession network instrumentation with distributed tracing
        // Default: nil (disabled)
        urlSessionTracking: Trace.Configuration.URLSessionTracking(
            // Choose how distributed tracing headers are injected:
            //   .trace(hosts:sampleRate:traceControlInjection:)
            //     - Injects Datadog AND W3C `tracecontext` headers
            //   .traceWithHeaders(hostsWithHeaders:sampleRate:traceControlInjection:)
            //     - Injects only the header types you specify per host
            // sampleRate is the URLSession distributed tracing propagation rate (default: 100).
            // If RUM context is available, propagated trace context and RUM resources
            // use the composed rate (e.g. 50% RUM and 80% trace => 40%).
            // traceControlInjection: .sampled (only sampled first-party requests carry context)
            //                        or .all (every matching first-party request carries context).
            //                        Default: .sampled
            firstPartyHostsTracing: .trace(
                hosts: ["api.example.com", "example.com"],
                sampleRate: 100.0,
                traceControlInjection: .sampled
            ),

            // HTTP status codes whose `resource.name` span tag is replaced
            // with the status code string (e.g. "404"). An empty set disables
            // all redaction.
            // Default: [404]
            redactedStatusCodes: [404]
        ),

        // Enrich spans with sampled-in RUM session, view and action IDs when available
        // Default: true
        bundleWithRumEnabled: true,

        // Enrich every span and span log with network connection info
        // (reachability, connection type, mobile carrier, etc.)
        // Default: false
        networkInfoEnabled: false,

        // Custom mapper for span events: modify spans before upload.
        // Cannot drop spans — return the (modified) event.
        // Keep the implementation fast; do not assume the calling thread.
        // Default: nil
        eventMapper: { spanEvent in
            var modified = spanEvent
            // Scrub sensitive data, override tags, etc.
            modified.tags["redacted"] = "true"
            return modified
        },

        // Custom intake endpoint for spans
        // Default: nil (uses Datadog intake)
        customEndpoint: nil
    )
)

// 3. (Optional) Enable duration breakdown to capture detailed network timing
// (DNS, SSL, TTFB, ...) on URLSession requests. Call AFTER Trace.enable().
URLSessionInstrumentation.enableDurationBreakdown(
    with: .init(delegateClass: YourURLSessionDelegate.self)
)

// 4a. Use the OpenTracing-compatible Tracer for manual instrumentation
let tracer = Tracer.shared()

let span = tracer.startSpan(operationName: "load-products")
span.setTag(key: SpanTags.resource, value: "/v2/products")
span.setTag(key: "items.count", value: 42)
// On error:
span.setError(kind: "NetworkError", message: "Request timed out")
span.finish()

// Active-span propagation: child spans inherit the active span as parent
let parent = tracer.startSpan(operationName: "checkout").setActive()
let child = tracer.startSpan(operationName: "validate-cart") // parent = `parent`
child.finish()
parent.finish()

// Force-keep / force-drop a trace regardless of sampling
let root = tracer.startRootSpan(operationName: "critical-flow")
root.keepTrace() // or: root.dropTrace()
root.finish()

// 4b. Or use the OpenTelemetry API
import OpenTelemetryApi

OpenTelemetry.registerTracerProvider(tracerProvider: OTelTracerProvider())
let otelTracer = OpenTelemetry.instance.tracerProvider.get(
    instrumentationName: "",
    instrumentationVersion: nil
)
let otelSpan = otelTracer.spanBuilder(spanName: "load-products").startSpan()
otelSpan.end()

// 5. (Optional) Manual distributed-tracing header injection
let requestSpan = tracer.startSpan(operationName: "network-request")
let writer = HTTPHeadersWriter(traceContextInjection: .sampled) // Datadog headers
// Or: W3CHTTPHeadersWriter()                                   // W3C `tracecontext`
// Or: B3HTTPHeadersWriter(injectEncoding: .single)             // B3 single or multi
tracer.inject(spanContext: requestSpan.context, writer: writer)
var request = URLRequest(url: URL(string: "https://api.example.com/v2/products")!)
writer.traceHeaderFields.forEach { request.setValue($1, forHTTPHeaderField: $0) }
// Perform the request, then finish when it completes.
requestSpan.finish()
```

## Key Files

### Feature Entry Point
- **`DatadogTrace/Sources/Trace.swift`** — Main entry point. Call `Trace.enable(with:in:)` to activate the feature.

### Configuration
- **`DatadogTrace/Sources/TraceConfiguration.swift`** — All configuration options available to customers.
  - Sampling rate, service override, global tags
  - Automatic `URLSession` instrumentation and distributed tracing (`urlSessionTracking`)
  - RUM and network-info enrichment
  - Span event mapper, custom endpoint

### Public API — Manual Instrumentation
- **`DatadogTrace/Sources/Tracer.swift`** — Access point: `Tracer.shared(in:)` returns an `OTTracer`. Also defines `SpanTags` (`resource`, `operation`, `service`, `manualKeep`, `manualDrop`).
- **`DatadogTrace/Sources/OpenTracing/OTTracer.swift`** — OpenTracing tracer protocol (`Sendable`): `startSpan`, `startRootSpan`, `inject`, `extract`, `activeSpan`. Tag parameters use `[String: OTTagValue]?`. Initial tags passed here flatten dictionary values the same way as `setTag(key:value:)` below when Swift can type-check them as `OTTagValue` values; mixed-value dictionary literals still need to be added afterward with `setTag(key:value: [String: OTTagValue])`, because `[String: OTTagValue]` itself is not `Encodable` and cannot be nested inside the existing `tags` dictionary type. `DatadogTracer.startSpan` uses `mergeTags(global:user:)` (see the `OTTagValue.swift` entry below) to combine the tracer's default tags with the caller's, user tags winning on collision.
- **`DatadogTrace/Sources/OpenTracing/OTSpan.swift`** — OpenTracing span protocol (`Sendable`), two required tag-setting methods: `setTag(key:value: OTTagValue)` and `setTag(key:value: [String: OTTagValue])`; also `log(fields:)` (fields are `[String: Encodable & Sendable]`), `setBaggageItem`, `setActive`, `finish`, `setError`, `keepTrace`, `dropTrace`.
  - `setTag(key:value: [String: OTTagValue])` has a default implementation in the `OTSpan` extension — see its doc comment for why. The default fully flattens `value` itself (via `flattenedTagPairs(key:dict:)`) before forwarding each leaf to `setTag(key:value: OTTagValue)`, so a conformer relying on it gets full recursive flattening even if its own scalar `setTag` doesn't detect nested dictionaries itself. `DDSpan` overrides it with its own single-pass implementation anyway (extra invariants — see its doc comment); `DDNoOps`' `DDNoopSpan` overrides it as an empty method so no-op spans stay fully silent.
  - Both `setTag` overloads flatten a `Dictionary` value into dotted-key leaf tags instead of storing it as a single blob — e.g. `setTag(key: "key", value: ["a": "1", "b": "2"])` produces `"key.a"`/`"key.b"`, recursively for nested dictionaries. The `[String: OTTagValue]` overload exists only so dictionaries mixing concrete value types (e.g. `String` and `Int`) compile at all — `setTag(key:value: OTTagValue)` alone can't infer one concrete type for such a literal. Any non-`Dictionary` `Encodable` value (structs, arrays) is unaffected and still serializes as a single JSON-blob string tag.
  - ⚠️ **PENDING APPROVAL, do not treat as final:** the `[String: OTTagValue]` overload is new public API, added here without going through this repo's RFC review for new public API (see `AGENTS.md`). It shows up as a 2-line diff in `api-surface-swift` (the new protocol requirement plus its default implementation) — that diff is expected and deliberate, not a sign something leaked in; it's exactly the artifact this note exists to flag for review. Until this is explicitly approved or reverted, treat the overload's existence as provisional.
  - Flattening a dictionary tag replaces any pre-existing tag already stored at the container key: e.g. `setTag(key: "context", value: "old")` followed by `setTag(key: "context", value: ["foo": "bar"])` leaves only `context.foo = "bar"` set, not `context = "old"` alongside it — `DDSpan.storeFlattenedTags` drops the exact container key before merging the new flattened leaves, matching `setTag`'s general replace-on-same-key semantics.
  - Flattening cannot accidentally trigger the reserved `SpanTags.manualKeep`/`manualDrop` sampling override (see "Force keep / drop" below): e.g. `setTag(key: "manual", value: ["keep": true, "other": 5])` flattens to the literal key `"manual.keep"`, which would otherwise collide with that reserved tag. `DDSpan.setTag(key:value: OTTagValue)` checks the override hook once, against the caller's own key/value as given, before flattening — never against a synthesized leaf key. `DDSpan.setTag(key:value: [String: OTTagValue])` doesn't call the hook at all: its `value` parameter can never be the `Bool` the hook keys off of, so there's nothing for it to check. Either way, a dictionary tag stores as a normal tag and leaves sampling untouched, whether the collision arrives via a homogeneous or mixed-type dictionary.
  - Flattening a dictionary tag *can* produce the reserved `SpanTags.resource`/`.operation`/`.service` keys (`"resource.name"`/`"operation.name"`/`"service.name"`) — e.g. `setTag(key: "resource", value: ["name": "x"])` flattens to the literal `"resource.name"`. This is treated the same as if the caller had set that exact key directly (`setTag(key: SpanTags.resource, value: "x")`): `SpanTagsReducer` extracts it and applies it to the span's Resource/Operation/Service. The SDK emits a warning naming the special key, but stores the tag unchanged; flattening does not drop or rewrite special keys.
  - If flattening a single `setTag` call's dictionary produces two pairs with the same leaf key (e.g. a literal `"a.b"` key alongside an `"a": ["b": ...]` entry in the same dictionary), `DDSpan` warns once (`DD.logger.warn`, same mechanism as `warnIfFinished`) and deterministically keeps one of the two colliding values — see `flattenedTags(_:)`/`flattenedTagPairs(key:dict:)`'s key-sorting below for why the choice is deterministic rather than arbitrary.
- **`DatadogTrace/Sources/OpenTracing/OTTagValue.swift`** — `public typealias OTTagValue = Encodable & Sendable`. Also defines the internal flattening/merging primitives shared by `DDSpan` and `DatadogTracer`: `flattenedTagPairs(key:value:)` (recursive, one value → leaf pairs), `flattenedTagPairs(key:dict:)` (same, for a value already known to be a `Dictionary`, key-sorted for deterministic collision resolution), `flattenedTags(_:)` (applies the former across a whole tag dictionary, also key-sorted, and warns on same-call collisions the same way `DDSpan` does — this is `DatadogTracer`'s only entry point for flattening global/initial tags), and `mergeTags(global:user:)` (requires `global` already flattened — `DatadogTracer.init` does this once — and only flattens `user` before merging, user tags winning; see the `OTTracer.swift` entry above for why that order matters). `DatadogTracer.init` flattens its global `tags` once via `flattenedTags(_:)` instead of redoing it on every `startSpan` call.
- **`DatadogTrace/Sources/OpenTracing/OTFormat.swift`** — Format/carrier protocols for `inject` / `extract`.

### Public API — OpenTelemetry
- **`DatadogTrace/Sources/OpenTelemetry/OTelTracerProvider.swift`** — `OTelTracerProvider` to register with `OpenTelemetry.registerTracerProvider(...)` and use the standard OpenTelemetry `Tracer` / `SpanBuilder` API.

### Public API — Objective-C Bridge
- **`DatadogTrace/Sources/Objc/Tracing/Trace+objc.swift`** — Objective-C Trace entry point and configuration bridge (`DDTrace`, `DDTraceConfiguration`, `DDTraceURLSessionTracking`, `DDTracer`).
  - `+[DDTrace enableWith:instanceName:]` — enables Trace in a named SDK instance (mirrors Swift `Trace.enable(with:in:)`).
  - `+[DDTracer sharedWithInstanceName:]` — retrieves the tracer from a named SDK instance (mirrors Swift `Tracer.shared(in:)`).
- **`DatadogTrace/Sources/Objc/OpenTracing/OTTracer+objc.swift`**, **`OTSpan+objc.swift`**, **`OTSpanContext+objc.swift`** — Objective-C OpenTracing protocols and constants.
- **`DatadogTrace/Sources/Objc/Tracing/DDSpan+objc.swift`**, **`DDSpanContext+objc.swift`** — Objective-C wrappers around Datadog span and span context implementations.
- **`DatadogTrace/Sources/Objc/Tracing/Propagation/*+objc.swift`** — Objective-C wrappers for Datadog, W3C, B3 header writers and trace context injection.
- **`DatadogInternal/Sources/NetworkInstrumentation/TracingHeaderType+objc.swift`** — Objective-C tracing header type constants used by Trace URLSession configuration.

### Public API — Distributed Tracing Headers
Re-exported from `DatadogInternal` so they are available with `import DatadogTrace`:
- **`HTTPHeadersWriter`** — Datadog `x-datadog-*` headers
- **`W3CHTTPHeadersWriter`** — W3C `tracecontext` headers
- **`B3HTTPHeadersWriter`** — B3 single / multi headers
- **`TracingHeaderType`** — `.datadog`, `.b3`, `.b3multi`, `.tracecontext`
- **`TraceContextInjection`** — `.all`, `.sampled`

### Implementation
- **`DatadogTrace/Sources/Feature/TraceFeature.swift`** — Internal feature implementation. Shows how configuration translates to behavior.

## Configuration Categories

### Sampling
- **Spans (default tracer)**: `sampleRate` (default: 100%) — applies to spans created via `Tracer.shared()` / `OTelTracerProvider`.
- **Per-root-span override**: `tracer.startRootSpan(operationName:..., customSampleRate:)` overrides `sampleRate` for a specific root span.
- **URLSession distributed tracing**: `urlSessionTracking.firstPartyHostsTracing` carries its own `sampleRate`, separate from `Trace.Configuration.sampleRate`. It controls first-party URLSession distributed tracing propagation and the sampling decision recorded in injected contexts. When RUM context is available, propagated trace context and RUM resources use the RUM-composed sampler (`rum sessionSampleRate * firstPartyHostsTracing.sampleRate / 100`). Without RUM context, the configured first-party sample rate is used directly. This composed rate is not a blanket local `urlsession.request` span emission rate.
- **Force keep / drop**: `span.keepTrace()` and `span.dropTrace()` (or set `SpanTags.manualKeep` / `SpanTags.manualDrop` directly). Should be called on the root span immediately after creation.

### Automatic Network Instrumentation
Set `urlSessionTracking` to connect Trace to the shared automatic `URLSession` network instrumentation layer. The URLSession layer observes requests broadly; Trace uses the configured first-party hosts to decide where distributed tracing applies:
- **First-party hosts**: `.trace(hosts:sampleRate:traceControlInjection:)` injects Datadog AND W3C `tracecontext` headers. Use `.traceWithHeaders(hostsWithHeaders:...)` to pick header types per host (Datadog, B3, B3 multi, W3C).
- **Trace spans**: Trace records URLSession spans only for first-party requests when Trace owns automatic URLSession tracking. Avoid enabling Trace `urlSessionTracking` and RUM `urlSessionTracking` for the same requests; the overlap is a current limitation and can produce undefined or incorrect behavior. If RUM owns resource tracking, configure RUM `urlSessionTracking.firstPartyHostsTracing` so RUM resources carry trace context for APM correlation.
- **Sampling**: `firstPartyHostsTracing.sampleRate` is the URLSession distributed tracing propagation rate. If RUM context is available, propagation and RUM resources use the composed RUM session and first-party tracing decision; for example, `sessionSampleRate: 50` and `firstPartyHostsTracing.sampleRate: 80` produce a 40% propagated trace context rate.
- **Injection strategy**: `traceControlInjection` — `.sampled` (default) only injects context on sampled first-party requests; `.all` injects context, including drop decisions, on every matching first-party request.
- **Status-code redaction**: `redactedStatusCodes` (default `[404]`) replaces the `resource.name` tag with the status code string for matching responses. Pass an empty set to disable.
- **Duration breakdown**: For DNS / SSL / TTFB timing, also call `URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: YourURLSessionDelegate.self))` after `Trace.enable()`.
- **Duration sanitation**: automatic URLSession spans clamp their finish time so it is never earlier than their start time before computing foreground/background tags or finishing the span.

> Note: Automatic `URLSession` network instrumentation involves swizzling `URLSession` and `URLSessionTask` methods.

### Span Enrichment
- **Service**: `service` (default: SDK service value) — overrides the `service.name` tag.
- **Global tags**: `tags: [String: OTTagValue]?` — applied to every span from the default tracer. `OTTagValue` is `Encodable & Sendable`; any custom tag type must conform to both.
- **RUM bundling**: `bundleWithRumEnabled` (default: `true`) — adds `_dd.application.id`, `_dd.session.id`, `_dd.view.id`, `_dd.action.id` tags only when a RUM context exists and the RUM session is sampled in. Trace spans from sampled-out RUM sessions can still be sent according to Trace sampling, but they are not linked to RUM.
- **Network info**: `networkInfoEnabled` (default: `false`) — adds reachability, connection type, mobile carrier, etc. to every span and span log.

### Event Modification
- **`eventMapper`** — `@Sendable (SpanEvent) -> SpanEvent`. Modify spans before upload (e.g. scrub sensitive data, override tags). Cannot drop spans — must return an event. Runs on a background thread; keep it fast and `Sendable`-safe.

### Manual Header Propagation
For non-`URLSession` HTTP clients, build headers yourself:
- `HTTPHeadersWriter(traceContextInjection:)` — Datadog headers
- `W3CHTTPHeadersWriter()` — W3C `tracecontext` (all params have defaults)
- `B3HTTPHeadersWriter(injectEncoding:)` — B3 single or multi
- Pass a writer to `tracer.inject(spanContext:writer:)`, then read `writer.traceHeaderFields` and copy them into your request.

## Common Troubleshooting Patterns

### "No traces appearing"
1. Check `Datadog.initialize()` and `Trace.enable()` were called.
2. For manual spans, verify `Trace.Configuration.sampleRate` is > 0. For automatic URLSession network instrumentation, verify `firstPartyHostsTracing.sampleRate` is > 0; for propagated or RUM resource trace contexts, also verify any composed RUM session rate is > 0.
3. Verify spans are actually finished (`span.finish()`) — unfinished spans are not sent.
4. Check the `eventMapper` is not raising / corrupting the event.

### "Network requests not traced"
1. `urlSessionTracking` must be configured on `Trace.Configuration` — Trace is not connected to automatic URLSession instrumentation by default.
2. The request URL's host must match a host in `firstPartyHostsTracing` (no `http(s)://` prefix in the configured hosts).
3. Verify the URLSession distributed tracing sample rate (`firstPartyHostsTracing` `sampleRate`) is > 0. If debugging propagated headers or RUM resource trace context, also verify the composed RUM session and first-party tracing rate is > 0.
4. Avoid overlapping Trace `urlSessionTracking` and RUM `urlSessionTracking` for the same requests. If RUM owns resource tracking, configure RUM `urlSessionTracking.firstPartyHostsTracing` for APM correlation instead of also enabling Trace URLSession tracking for those requests.
5. `URLSessionInstrumentation.enableDurationBreakdown(...)` is only needed for DNS / SSL / TTFB timing, not for basic automatic URLSession tracing. For HTTP clients not covered by `URLSession` instrumentation, wrap the request in a manual span and, if the client exposes outbound header mutation, copy headers from `HTTPHeadersWriter` / `W3CHTTPHeadersWriter` / `B3HTTPHeadersWriter` into the client's request/header API.

### "Resource name shows just `404`"
This is the default `redactedStatusCodes: [404]` redaction. Pass an empty set on `URLSessionTracking(redactedStatusCodes:)` to disable, or pass a custom set to control which status codes get redacted.

### "Span not linked to RUM session"
1. Make sure `RUM.enable(...)` is called and a RUM session is active.
2. Verify the RUM session is sampled in (`RUM.Configuration.sessionSampleRate`); sampled-out RUM sessions do not add RUM linkage tags to spans.
3. Verify `bundleWithRumEnabled: true` (default).
4. Spans created before RUM is enabled or outside an active RUM view may miss some `_dd.*` tags.

### "Child span has no parent"
Child spans inherit the active span only when one is set. Either pass a parent context explicitly via `startSpan(operationName:childOf:)`, or call `parent.setActive()` before creating children in the same execution context.

### "Tracer.shared() returns no-op"
Returned when `Datadog.initialize()` was not called or `Trace.enable()` was not called. Errors are printed via `consolePrint` — check the console for `ProgrammerError` messages.

## Feature Interactions

- **RUM**: When `bundleWithRumEnabled` is `true` and the current RUM session is sampled in, spans are enriched with the current RUM view / session / action IDs so traces and RUM events can be correlated. For URLSession distributed tracing, an available RUM context also makes propagated trace context and RUM resource trace decisions deterministic by composing `firstPartyHostsTracing.sampleRate` with the RUM session sample rate.
- **Logs**: `OTSpan.log(...)` and `OTSpan.setError(...)` write through the Logs feature. If `DatadogLogs` is not enabled, logs attached to spans are dropped (with a warning); the span itself is still sent.
- **Crash Reporting**: Independent — crashes do not require Trace.
- **WebView Tracking**: Independent — see `DatadogWebViewTracking/Sources/WebViewTracking.swift`.
- **OpenTelemetry**: Use `OTelTracerProvider` to drive the standard OpenTelemetry API on top of Datadog Trace.

## Additional Context

- `Tracer.shared(in:)` returns the OpenTracing `OTTracer`; `OTelTracerProvider` returns the OpenTelemetry `Tracer`. Both are backed by the same internal tracer — choose whichever API fits your codebase.
- The default tracer's `sampleRate` decides which spans are kept; manual `keepTrace()` / `dropTrace()` overrides that decision for the whole trace, and should be called on the root span right after creation so that propagation carries the correct sampling priority.
- For the OpenTelemetry tracer provider, `instrumentationName`, `instrumentationVersion`, `schemaUrl` and `attributes` parameters are accepted for API compatibility but ignored — configure tags via `Trace.Configuration.tags`.
- Automatic `URLSession` network instrumentation relies on swizzling; if your app already swizzles `URLSession` itself, validate behavior in integration tests.
- Automatic URLSession spans sanitize inconsistent task timing by using `max(startTime, endTime)` for finish time, foreground duration ranges, and background-state lookup.
