/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct TracingURLSessionHandler: DatadogURLSessionHandler {
    /// Integration with Core Context.
    let contextReceiver: ContextMessageReceiver
    /// Distributed trace sampler. Used for spans created through network instrumentation.
    let distributedTraceSampler: Sampler
    /// First party hosts defined by the user.
    let firstPartyHosts: FirstPartyHosts
    /// Trace context injection configuration to determine whether the trace context should be injected or not.
    let traceContextInjection: TraceContextInjection

    weak var tracer: DatadogTracer?

    init(
        tracer: DatadogTracer,
        contextReceiver: ContextMessageReceiver,
        distributedTraceSampler: Sampler,
        firstPartyHosts: FirstPartyHosts,
        traceContextInjection: TraceContextInjection
    ) {
        self.tracer = tracer
        self.contextReceiver = contextReceiver
        self.distributedTraceSampler = distributedTraceSampler
        self.firstPartyHosts = firstPartyHosts
        self.traceContextInjection = traceContextInjection
    }

    func modify(request: URLRequest, headerTypes: Set<DatadogInternal.TracingHeaderType>) -> (URLRequest, TraceContext?) {
        guard let tracer = tracer else {
            return (request, nil)
        }

        // Use the current active span as parent if the propagation
        // headers support it.
        let parentSpanContext = tracer.activeSpan?.context as? DDSpanContext
        let spanContext = tracer.createSpanContext(
            parentSpanContext: parentSpanContext,
            using: distributedTraceSampler
        )
        let injectedSpanContext = TraceContext(
            traceID: spanContext.traceID,
            spanID: spanContext.spanID,
            parentSpanID: spanContext.parentSpanID,
            sampleRate: spanContext.sampleRate,
            isKept: spanContext.isKept
        )

        var request = request
        var hasSetAnyHeader = false
        headerTypes.forEach {
            let writer: TracePropagationHeadersWriter
            switch $0 {
            case .datadog:
                writer = HTTPHeadersWriter(samplingStrategy: .headBased, traceContextInjection: traceContextInjection)
            case .b3:
                writer = B3HTTPHeadersWriter(
                    samplingStrategy: .headBased,
                    injectEncoding: .single,
                    traceContextInjection: traceContextInjection
                )
            case .b3multi:
                writer = B3HTTPHeadersWriter(
                    samplingStrategy: .headBased,
                    injectEncoding: .multiple,
                    traceContextInjection: traceContextInjection
                )
            case .tracecontext:
                writer = W3CHTTPHeadersWriter(
                    samplingStrategy: .headBased,
                    tracestate: [:],
                    traceContextInjection: traceContextInjection
                )
            }

            writer.write(traceContext: injectedSpanContext)

            writer.traceHeaderFields.forEach { field, value in
                // do not overwrite existing header
                if request.value(forHTTPHeaderField: field) == nil {
                    hasSetAnyHeader = true
                    request.setValue(value, forHTTPHeaderField: field)
                }
            }
        }

        return (request, hasSetAnyHeader ? injectedSpanContext : nil)
    }

    func interceptionDidStart(interception: DatadogInternal.URLSessionTaskInterception) {
        // no-op
    }

    func interceptionDidComplete(interception: DatadogInternal.URLSessionTaskInterception) {
        guard
            interception.isFirstPartyRequest, // `Span` should be only send for 1st party requests
            interception.origin != "rum", // if that request was tracked as RUM resource, the RUM backend will create the span on our behalf
            let tracer = tracer,
            let resourceMetrics = interception.metrics,
            let resourceCompletion = interception.completion
        else {
            return
        }

        let span: OTSpan

        if let trace = interception.trace {
            let context = DDSpanContext(
                traceID: trace.traceID,
                spanID: trace.spanID,
                parentSpanID: trace.parentSpanID,
                baggageItems: .init(),
                sampleRate: trace.sampleRate,
                isKept: trace.isKept
            )

            span = tracer.startSpan(
                spanContext: context,
                operationName: "urlsession.request",
                startTime: resourceMetrics.fetch.start
            )
        } else if distributedTraceSampler.sample() {
            // Span context may not be injected on iOS13+ if `URLSession.dataTask(...)` for `URL`
            // was used to create the session task.
            span = tracer.startSpan(
                operationName: "urlsession.request",
                startTime: resourceMetrics.fetch.start
            )
        } else {
            return
        }

        let url = interception.request.url?.absoluteString ?? "unknown_url"

        if let requestUrl = interception.request.url {
            var urlComponent = URLComponents(url: requestUrl, resolvingAgainstBaseURL: true)
            urlComponent?.query = nil
            let resourceUrl = urlComponent?.url?.absoluteString ?? "unknown_url"
            span.setTag(key: SpanTags.resource, value: resourceUrl)
        }
        let method = interception.request.httpMethod ?? "unknown_method"
        span.setTag(key: OTTags.httpUrl, value: url)
        span.setTag(key: OTTags.httpMethod, value: method)

        if let error = resourceCompletion.error {
            span.setError(error, file: "", line: 0)
        }

        if let httpResponse = resourceCompletion.httpResponse {
            let httpStatusCode = httpResponse.statusCode
            span.setTag(key: OTTags.httpStatusCode, value: httpStatusCode)
            if let error = httpResponse.asClientError() {
                span.setError(error, file: "", line: 0)
                if httpStatusCode == 404 {
                    span.setTag(key: SpanTags.resource, value: "404")
                }
            }
        }

        if let history = contextReceiver.context.applicationStateHistory {
            let appStateHistory = history.take(
                between: resourceMetrics.fetch.start...resourceMetrics.fetch.end
            )

            span.setTag(key: SpanTags.foregroundDuration, value: appStateHistory.foregroundDuration.toNanoseconds)

            let didStartInBackground = appStateHistory.initialSnapshot.state == .background
            let doesEndInBackground = appStateHistory.currentSnapshot.state == .background
            span.setTag(key: SpanTags.isBackground, value: didStartInBackground || doesEndInBackground)
        }

        span.finish(at: resourceMetrics.fetch.end)
    }
}

private extension HTTPURLResponse {
    func asClientError() -> Error? {
        // 4xx Client Errors
        guard statusCode >= 400 && statusCode < 500 else {
            return nil
        }
        let message = "\(statusCode) " + HTTPURLResponse.localizedString(forStatusCode: statusCode)
        return NSError(domain: "HTTPURLResponse", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
