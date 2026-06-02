---
last_updated: 2026-06-02
sdk_version: 3.11.0
verified_against_commit: 6dbb01bba
tracked_files:
  - DatadogTrace/Sources/Trace.swift
  - DatadogTrace/Sources/TraceConfiguration.swift
  - DatadogTrace/Sources/Tracer.swift
  - DatadogTrace/Sources/OpenTracing/OTTracer.swift
  - DatadogTrace/Sources/OpenTracing/OTSpan.swift
  - DatadogTrace/Sources/OpenTracing/OTFormat.swift
  - DatadogTrace/Sources/OpenTelemetry/OTelTracerProvider.swift
  - DatadogTrace/Sources/Feature/TraceFeature.swift
  - DatadogTrace/Sources/Integrations/TracingURLSessionHandler.swift
---

# Trace (APM) Feature

## Overview

Trace records spans that are sent to Datadog APM. It supports manual instrumentation via the OpenTracing API or the OpenTelemetry API after `Trace.enable()`. Trace can also connect to automatic `URLSession` network instrumentation; for that automatic URLSession path, configured first-party hosts gate distributed tracing header injection and automatic network span creation. Trace requires initialization via `Datadog.initialize()` before enabling.

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

        // Automatic URLSession distributed tracing - provide config to enable
        // Default: nil (disabled)
        urlSessionTracking: Trace.Configuration.URLSessionTracking(
            // Choose how distributed tracing headers are injected:
            //   .trace(hosts:sampleRate:traceControlInjection:)
            //     - Injects Datadog AND W3C `tracecontext` headers
            //   .traceWithHeaders(hostsWithHeaders:sampleRate:traceControlInjection:)
            //     - Injects only the header types you specify per host
            // sampleRate is the distributed tracing sample rate (default: 100).
            // If RUM is active, the effective rate is composed with the
            // RUM session sample rate (e.g. 50% RUM and 80% trace => 40%).
            // traceControlInjection: .sampled (only sampled requests carry context)
            //                        or .all (every request carries context).
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

        // Enrich every span with the current RUM view, action and session IDs
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
let writer = HTTPHeadersWriter(traceContextInjection: .sampled) // Datadog headers
// Or: W3CHTTPHeadersWriter()                                   // W3C `tracecontext`
// Or: B3HTTPHeadersWriter(injectEncoding: .single)             // B3 single or multi
tracer.inject(spanContext: span.context, writer: writer)
var request = URLRequest(url: URL(string: "https://api.example.com/v2/products")!)
writer.traceHeaderFields.forEach { request.setValue($1, forHTTPHeaderField: $0) }
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
- **`DatadogTrace/Sources/OpenTracing/OTTracer.swift`** — OpenTracing tracer protocol: `startSpan`, `startRootSpan`, `inject`, `extract`, `activeSpan`.
- **`DatadogTrace/Sources/OpenTracing/OTSpan.swift`** — OpenTracing span protocol: `setTag`, `log`, `setBaggageItem`, `setActive`, `finish`, `setError`, `keepTrace`, `dropTrace`.
- **`DatadogTrace/Sources/OpenTracing/OTFormat.swift`** — Format/carrier protocols for `inject` / `extract`.

### Public API — OpenTelemetry
- **`DatadogTrace/Sources/OpenTelemetry/OTelTracerProvider.swift`** — `OTelTracerProvider` to register with `OpenTelemetry.registerTracerProvider(...)` and use the standard OpenTelemetry `Tracer` / `SpanBuilder` API.

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
- **URLSession distributed tracing**: `urlSessionTracking.firstPartyHostsTracing` carries its own `sampleRate`, separate from `Trace.Configuration.sampleRate`. It controls whether first-party URLSession requests are sampled and whether their sampling decision is propagated. When RUM context is active, the effective rate is composed with the RUM session sampler (`rum sessionSampleRate * firstPartyHostsTracing.sampleRate / 100`). Without RUM context, the configured first-party sample rate is used directly.
- **Force keep / drop**: `span.keepTrace()` and `span.dropTrace()` (or set `SpanTags.manualKeep` / `SpanTags.manualDrop` directly). Should be called on the root span immediately after creation.

### Automatic Network Instrumentation
Set `urlSessionTracking` to connect Trace to the shared automatic `URLSession` network instrumentation layer. The URLSession layer observes requests broadly; Trace uses the configured first-party hosts to decide where distributed tracing applies:
- **First-party hosts**: `.trace(hosts:sampleRate:traceControlInjection:)` injects Datadog AND W3C `tracecontext` headers. Use `.traceWithHeaders(hostsWithHeaders:...)` to pick header types per host (Datadog, B3, B3 multi, W3C).
- **Trace spans**: Trace records URLSession spans only for first-party requests, unless the request is already tracked as a RUM resource. In that case, the RUM backend creates the trace span on behalf of the resource.
- **Sampling**: `firstPartyHostsTracing.sampleRate` is the URLSession distributed tracing rate. If RUM is active, it is composed with the RUM session sample rate; for example, `sessionSampleRate: 50` and `firstPartyHostsTracing.sampleRate: 80` produce an effective 40% URLSession trace rate.
- **Injection strategy**: `traceControlInjection` — `.sampled` (default) only injects context on sampled requests; `.all` injects on every request, letting downstream services make sampling decisions.
- **Status-code redaction**: `redactedStatusCodes` (default `[404]`) replaces the `resource.name` tag with the status code string for matching responses. Pass an empty set to disable.
- **Duration breakdown**: For DNS / SSL / TTFB timing, also call `URLSessionInstrumentation.enableDurationBreakdown(with: .init(delegateClass: YourURLSessionDelegate.self))` after `Trace.enable()`.

> Note: Automatic `URLSession` network instrumentation involves swizzling `URLSession` and `URLSessionTask` methods.

### Span Enrichment
- **Service**: `service` (default: SDK service value) — overrides the `service.name` tag.
- **Global tags**: `tags` — applied to every span from the default tracer.
- **RUM bundling**: `bundleWithRumEnabled` (default: `true`) — adds `_dd.application.id`, `_dd.session.id`, `_dd.view.id`, `_dd.action.id` tags so spans are linked to the active RUM context.
- **Network info**: `networkInfoEnabled` (default: `false`) — adds reachability, connection type, mobile carrier, etc. to every span and span log.

### Event Modification
- **`eventMapper`** — `(SpanEvent) -> SpanEvent`. Modify spans before upload (e.g. scrub sensitive data, override tags). Cannot drop spans — must return an event. Runs on a background thread; keep it fast.

### Manual Header Propagation
For non-`URLSession` HTTP clients, build headers yourself:
- `HTTPHeadersWriter(traceContextInjection:)` — Datadog headers
- `W3CHTTPHeadersWriter()` — W3C `tracecontext` (all params have defaults)
- `B3HTTPHeadersWriter(injectEncoding:)` — B3 single or multi
- Pass a writer to `tracer.inject(spanContext:writer:)`, then read `writer.traceHeaderFields` and copy them into your request.

## Common Troubleshooting Patterns

### "No traces appearing"
1. Check `Datadog.initialize()` and `Trace.enable()` were called.
2. For manual spans, verify `Trace.Configuration.sampleRate` is > 0. For automatic URLSession network instrumentation, verify `firstPartyHostsTracing.sampleRate` and any composed RUM session rate are > 0.
3. Verify spans are actually finished (`span.finish()`) — unfinished spans are not sent.
4. Check the `eventMapper` is not raising / corrupting the event.

### "Network requests not traced"
1. `urlSessionTracking` must be configured on `Trace.Configuration` — Trace is not connected to automatic URLSession instrumentation by default.
2. The request URL's host must match a host in `firstPartyHostsTracing` (no `http(s)://` prefix in the configured hosts).
3. Verify the URLSession distributed tracing sample rate (`firstPartyHostsTracing` `sampleRate`) is > 0. If RUM is active, also verify the effective rate after composition with the RUM session sample rate is > 0.
4. For SDK-managed sessions, no extra delegate is required. For third-party HTTP clients, inject headers manually with `HTTPHeadersWriter` / `W3CHTTPHeadersWriter` / `B3HTTPHeadersWriter`.

### "Resource name shows just `404`"
This is the default `redactedStatusCodes: [404]` redaction. Pass an empty set on `URLSessionTracking(redactedStatusCodes:)` to disable, or pass a custom set to control which status codes get redacted.

### "Span not linked to RUM session"
1. Make sure `RUM.enable(...)` is called and a RUM session is active.
2. Verify `bundleWithRumEnabled: true` (default).
3. Spans created before RUM is enabled or outside an active RUM view will be missing some `_dd.*` tags.

### "Child span has no parent"
Child spans inherit the active span only when one is set. Either pass a parent context explicitly via `startSpan(operationName:childOf:)`, or call `parent.setActive()` before creating children in the same execution context.

### "Tracer.shared() returns no-op"
Returned when `Datadog.initialize()` was not called or `Trace.enable()` was not called. Errors are printed via `consolePrint` — check the console for `ProgrammerError` messages.

## Feature Interactions

- **RUM**: When `bundleWithRumEnabled` is `true`, every span is enriched with the current RUM view / session / action IDs so traces and RUM events can be correlated. For URLSession distributed tracing, an active RUM context also makes the tracing sample decision deterministic and composes `firstPartyHostsTracing.sampleRate` with the RUM session sample rate.
- **Logs**: `OTSpan.log(...)` and `OTSpan.setError(...)` write through the Logs feature. If `DatadogLogs` is not enabled, logs attached to spans are dropped (with a warning); the span itself is still sent.
- **Crash Reporting**: Independent — crashes do not require Trace.
- **WebView Tracking**: Independent — see `DatadogWebViewTracking/Sources/WebViewTracking.swift`.
- **OpenTelemetry**: Use `OTelTracerProvider` to drive the standard OpenTelemetry API on top of Datadog Trace.

## Additional Context

- `Tracer.shared(in:)` returns the OpenTracing `OTTracer`; `OTelTracerProvider` returns the OpenTelemetry `Tracer`. Both are backed by the same internal tracer — choose whichever API fits your codebase.
- The default tracer's `sampleRate` decides which spans are kept; manual `keepTrace()` / `dropTrace()` overrides that decision for the whole trace, and should be called on the root span right after creation so that propagation carries the correct sampling priority.
- For the OpenTelemetry tracer provider, `instrumentationName`, `instrumentationVersion`, `schemaUrl` and `attributes` parameters are accepted for API compatibility but ignored — configure tags via `Trace.Configuration.tags`.
- Automatic `URLSession` network instrumentation relies on swizzling; if your app already swizzles `URLSession` itself, validate behavior in integration tests.
