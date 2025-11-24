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

    /// Helper structure, used to collect elements for creating new contexts.
    /// See ``TracingURLSessionHandler.makeElementsForNewSpanContext(tracer:parentSpanContext:)``
    /// for more details.
    private struct NewSpanElements {
        let spanID: SpanID
        let parentSpanID: SpanID?
        let sampleRate: SampleRate
        let traceID: TraceID
        let samplingPriority: SamplingPriority
        let samplingDecisionMaker: SamplingMechanismType
        let baggage: BaggageItems
    }

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
        let newSpanElements = makeElementsForNewSpanContext(tracer: tracer, parentSpanContext: tracer.activeSpan?.context as? DDSpanContext)

        let injectedSpanContext = TraceContext(
            traceID: newSpanElements.traceID,
            spanID: newSpanElements.spanID,
            parentSpanID: newSpanElements.parentSpanID,
            sampleRate: newSpanElements.sampleRate,
            samplingPriority: newSpanElements.samplingPriority,
            samplingDecisionMaker: newSpanElements.samplingDecisionMaker,
            rumSessionId: contextReceiver.context.rumContext?.sessionID,
            userId: contextReceiver.context.userInfo?.id,
            accountId: contextReceiver.context.accountInfo?.id
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
        /*
         A note about how the active span context is registered: the order these three methods
         is called is modify(…), immediately followed by interceptionDidStart(…) (synchronously) and
         later interceptionDidComplete(…), asynchronously, after the session task completes.

         Modify(…) is where the TraceContext is created and may be returned from. However, if the
         span is not sampled, and TraceContextInjection is configured for .sampled (the default
         config at the time of writing), there is no propagation through headers not injected
         context, so modify returns nil.

         Therefore, there is the need to keep track of the active span, if any, in a different
         way, so we can associate the child span created in this session handler, and treat
         it properly (usually that means setting the same sampling priority as the parent and
         in the case the parent is dropped, drop the new span as well).

         To do that, we register a possible active span context in the interception from here.
         The comment inside the interceptionDidComplete(…) method explains how this is used.
         */
        tracer?.activeSpan.map {
            interception.register(activeSpanContext: $0.context)
        }
    }

    func interceptionDidComplete(interception: DatadogInternal.URLSessionTaskInterception) {
        // TODO: RUM-13455 - Add support for automatic mode in tracing
        // Currently, tracing requires metrics mode because spans need accurate timing (fetch start/end).
        // Automatic mode doesn't capture timing without URLSessionTaskMetrics.
        // Investigate if we want to support automatic mode for Tracing.
        guard
            interception.isFirstPartyRequest, // `Span` should be only send for 1st party requests
            interception.origin != "rum", // if that request was tracked as RUM resource, the RUM backend will create the span on our behalf
            let tracer = tracer,
            let resourceMetrics = interception.metrics, // Currently requires metrics mode for accurate timing
            let resourceCompletion = interception.completion
        else {
            return
        }

        let span: OTSpan

        /*
         We need to create a new span here. Some of the span specifics depends on what
         happen before, in the modify and interceptionDidStart(…) methods. Read the comment
         in interceptionDidStart(…) for an introduction.

         The first case is when we have a trace context in the interception. This means
         we propagated information through the headers of the request. In that case, we
         use the data in that trace context to create the span that tracks this request.
         Given the implementation in the modify method, if there is an active span at
         the time the requests starts, its information is stored in the context and will
         be used to relate the span created here.

         The second case is when we do not have a trace context, which means we did not
         propagate the trace. This also implicitly means we decided to drop the span,
         either because we have an active dropped span, or the sampler decided this
         request should not be sampled. We still need to relate the newly created span
         to it so we can propagate the decision and drop both. Otherwise, we could be
         creating a new span here that is effectively the child of an active dropped span.

         The following is/else block implements both cases.
         */
        if let trace = interception.trace {
            let context = DDSpanContext(
                traceID: trace.traceID,
                spanID: trace.spanID,
                parentSpanID: trace.parentSpanID,
                baggageItems: .init(),
                sampleRate: trace.sampleRate,
                samplingDecision: SamplingDecision(
                    from: trace.samplingPriority,
                    decisionMaker: trace.samplingDecisionMaker
                )
            )

            span = tracer.startSpan(
                spanContext: context,
                operationName: "urlsession.request",
                startTime: resourceMetrics.fetch.start
            )
        } else if Sampler(samplingRate: samplingRate).sample() {
            // Span context may not be injected on iOS13+ if `URLSession.dataTask(...)` for `URL`
            // was used to create the session task.
            let newSpanElements = makeElementsForNewSpanContext(tracer: tracer, parentSpanContext: interception.activeSpanContext as? DDSpanContext)

            let context = DDSpanContext(
                traceID: newSpanElements.traceID,
                spanID: newSpanElements.spanID,
                parentSpanID: newSpanElements.parentSpanID,
                baggageItems: newSpanElements.baggage,
                sampleRate: newSpanElements.sampleRate,
                samplingDecision: SamplingDecision(
                    from: newSpanElements.samplingPriority,
                    decisionMaker: newSpanElements.samplingDecisionMaker
                )
            )

            span = tracer.startSpan(
                spanContext: context,
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
            span.setTag(key: SpanTags.foregroundDuration, value: foregroundDuration.dd.toNanoseconds)

            let didStartInBackground = history.state(at: resourceMetrics.fetch.start) == .background
            let doesEndInBackground = history.state(at: resourceMetrics.fetch.end) == .background
            span.setTag(key: SpanTags.isBackground, value: didStartInBackground || doesEndInBackground)
        }

        span.finish(at: resourceMetrics.fetch.end)
    }

    /// Creates a helper struct with collected elements from a possible parent span context.
    ///
    /// The purpose of this method is to aggregate the same logic used in two different places in a common implementation.
    ///
    /// - parameters:
    ///    - tracer: The used tracer.
    ///    - parentSpanContext: If the span created by the session handler should be related to a parent span, pass
    ///    the parent span context here, otherwise, pass `nil`.
    /// - returns: A ``TracingURLSessionHandler.NewSpanElements`` helper struct.
    private func makeElementsForNewSpanContext(tracer: DatadogTracer, parentSpanContext: DDSpanContext?) -> NewSpanElements {
        let traceID = parentSpanContext?.traceID ?? tracer.traceIDGenerator.generate()
        let sampler = sampler(sessionID: contextReceiver.context.rumContext?.sessionID, traceID: traceID.idLo)
        let samplingDecision = parentSpanContext.map { $0.samplingDecision } ?? SamplingDecision(sampling: sampler)

        return NewSpanElements(
            spanID: tracer.spanIDGenerator.generate(),
            parentSpanID: parentSpanContext?.spanID,
            sampleRate: parentSpanContext?.sampleRate ?? samplingRate,
            traceID: traceID,
            samplingPriority: samplingDecision.samplingPriority,
            samplingDecisionMaker: samplingDecision.decisionMaker,
            baggage: parentSpanContext?.baggageItems ?? .init()
        )
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
