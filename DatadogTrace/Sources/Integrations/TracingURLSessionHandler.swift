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
    /// First party hosts defined by the user.
    let firstPartyHosts: FirstPartyHosts
    /// Value between `0.0` and `100.0`, where `0.0` means NO trace will be sent and `100.0` means ALL trace and spans will be sent.
    let samplingRate: SampleRate
    /// Trace context injection configuration to determine whether the trace context should be injected or not.
    let traceContextInjection: TraceContextInjection

    weak var tracer: DatadogTracer?

    init(
        tracer: DatadogTracer,
        contextReceiver: ContextMessageReceiver,
        samplingRate: SampleRate,
        firstPartyHosts: FirstPartyHosts,
        traceContextInjection: TraceContextInjection
    ) {
        self.tracer = tracer
        self.contextReceiver = contextReceiver
        self.samplingRate = samplingRate
        self.firstPartyHosts = firstPartyHosts
        self.traceContextInjection = traceContextInjection
    }

    func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>, networkContext: NetworkContext?) -> (URLRequest, TraceContext?) {
        guard let tracer = tracer else {
            return (request, nil)
        }

        // Use the current active span as parent if the propagation headers support it.
        let parentSpanContext = tracer.activeSpan?.context as? DDSpanContext
        let traceID = parentSpanContext?.traceID ?? tracer.traceIDGenerator.generate()
        let sampler = sampler(sessionID: contextReceiver.context.rumContext?.sessionID, traceID: traceID.idLo)

        let injectedSpanContext = TraceContext(
            traceID: traceID,
            spanID: tracer.spanIDGenerator.generate(),
            parentSpanID: parentSpanContext?.spanID,
            sampleRate: parentSpanContext?.sampleRate ?? samplingRate,
            isKept: parentSpanContext?.isKept ?? sampler.sample(),
            rumSessionId: contextReceiver.context.rumContext?.sessionID
        )

        var request = request
        var hasSetAnyHeader = false
        headerTypes.forEach {
            let writer: TracePropagationHeadersWriter
            switch $0 {
            case .datadog:
                writer = HTTPHeadersWriter(traceContextInjection: traceContextInjection)
            case .b3:
                writer = B3HTTPHeadersWriter(
                    injectEncoding: .single,
                    traceContextInjection: traceContextInjection
                )
            case .b3multi:
                writer = B3HTTPHeadersWriter(
                    injectEncoding: .multiple,
                    traceContextInjection: traceContextInjection
                )
            case .tracecontext:
                writer = W3CHTTPHeadersWriter(
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
        } else if Sampler(samplingRate: samplingRate).sample() {
            // Span context may not be injected on iOS13+ if `URLSession.dataTask(...)` for `URL`
            // was used to create the session task.
            span = tracer.startSpan(
                operationName: "urlsession.request",
                startTime: resourceMetrics.fetch.start
            )
        } else {
            return
        }

        span.setTag(key: SpanTags.kind, value: "client")

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
            let fetchDuration = resourceMetrics.fetch.start...resourceMetrics.fetch.end
            let foregroundDuration = history.foregroundDuration(during: fetchDuration)
            span.setTag(key: SpanTags.foregroundDuration, value: foregroundDuration.toNanoseconds)

            let didStartInBackground = history.state(at: resourceMetrics.fetch.start) == .background
            let doesEndInBackground = history.state(at: resourceMetrics.fetch.end) == .background
            span.setTag(key: SpanTags.isBackground, value: didStartInBackground || doesEndInBackground)
        }

        span.finish(at: resourceMetrics.fetch.end)
    }

    private func sampler(sessionID: String?, traceID: UInt64?) -> Sampling {
        if let sessionID,
           // for a UUID with value aaaaaaaa-bbbb-Mccc-Nddd-1234567890ab
           // we use as the base id the last part : 0x1234567890ab
            let seed = sessionID
            .split(separator: "-")
            .last
            .flatMap({ UInt64($0, radix: 16) }) {
            return DeterministicSampler(seed: seed, samplingRate: samplingRate)
        } else if let traceID {
            return DeterministicSampler(seed: traceID, samplingRate: samplingRate)
        }

        return Sampler(samplingRate: samplingRate)
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
