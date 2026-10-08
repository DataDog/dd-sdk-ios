/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct TracingURLSessionHandler: DatadogURLSessionHandler {
    /// Captured state containing the active span, if any, at the time of the request modification for instrumentation,
    /// obtained synchronously.
    struct TracingURLSessionHandlerCapturedState: URLSessionHandlerCapturedState {
        /*
         Read the comments inside the modify(…), interceptionDidStart(…) and interceptionDidComplete(…)
         for details on the problem this solves, and how.
         */

        /// The active span at the time of request instrumentation, if any, `nil` otherwise.
        let activeSpan: OTSpan?
        /// Whether GraphQL headers were detected in the request
        let hasGraphQLHeaders: Bool
        /// The RUM context resolved synchronously when the request was modified.
        let rumContext: RUMCoreContext?
        /// The RUM session snapshot read when the request was modified, or `nil` if no session was active.
        let sessionDecision: SessionSamplingDecision?
    }

    /// Integration with Core Context.
    let contextReceiver: ContextMessageReceiver
    /// First party hosts defined by the user.
    let firstPartyHosts: FirstPartyHosts
    /// Value between `0.0` and `100.0`, where `0.0` means NO trace will be sent and `100.0` means ALL trace and spans will be sent.
    let samplingRate: SampleRate
    /// Trace context injection configuration to determine whether the trace context should be injected or not.
    let traceContextInjection: TraceContextInjection
    /// Telemetry interface for tracking SDK usage
    let telemetry: Telemetry
    /// HTTP status codes whose `resource.name` span tag will be replaced with the status code string.
    /// Defaults to `Trace.Configuration.URLSessionTracking.defaultRedactedStatusCodes` for backward compatibility.
    let redactedStatusCodes: Set<Int>
    /// Synchronous access to the RUM session.
    ///
    /// Safe to store: it holds the core weakly and resolves the RUM feature on every call, so a
    /// session created after `Trace.enable()` is still seen.
    let sessionSampler: SessionSampler?

    weak var tracer: DatadogTracer?

    /// Helper structure, used to collect elements for creating new contexts.
    /// See ``TracingURLSessionHandler.makeElementsForNewSpanContext(tracer:parentSpanContext:sessionDecision:)``
    /// for more details.
    private struct NewSpanElements {
        let spanID: SpanID
        let parentSpanID: SpanID?
        let sampleRate: SampleRate
        let traceID: TraceID
        let samplingPriority: SamplingPriority
        let samplingDecisionMaker: SamplingMechanismType
        let baggage: BaggageItems

        /// A copy whose sampling decision drops the span. The span gets its own decision from these
        /// values, so a parent's `SamplingDecision`, which is shared by reference, is never changed.
        func droppingTheSpan() -> NewSpanElements {
            NewSpanElements(
                spanID: spanID,
                parentSpanID: parentSpanID,
                sampleRate: sampleRate,
                traceID: traceID,
                samplingPriority: .autoDrop,
                samplingDecisionMaker: .agentRate,
                baggage: baggage
            )
        }
    }

    private struct CapturedRUMContext {
        let rumContext: RUMCoreContext?
        let sessionDecision: SessionSamplingDecision?
    }

    @ReadWriteLock
    private var capturedRUMContexts: [UUID: CapturedRUMContext] = [:]

    init(
        tracer: DatadogTracer,
        contextReceiver: ContextMessageReceiver,
        samplingRate: SampleRate,
        firstPartyHosts: FirstPartyHosts,
        traceContextInjection: TraceContextInjection,
        telemetry: Telemetry,
        redactedStatusCodes: Set<Int> = Trace.Configuration.URLSessionTracking.defaultRedactedStatusCodes,
        sessionSampler: SessionSampler? = nil
    ) {
        self.tracer = tracer
        self.contextReceiver = contextReceiver
        self.samplingRate = samplingRate
        self.firstPartyHosts = firstPartyHosts
        self.traceContextInjection = traceContextInjection
        self.telemetry = telemetry
        self.redactedStatusCodes = redactedStatusCodes
        self.sessionSampler = sessionSampler
    }

    func modify(request: URLRequest, headerTypes: Set<TracingHeaderType>, networkContext: NetworkContext?) -> (URLRequest, TraceContext?, URLSessionHandlerCapturedState?) {
        guard let tracer = tracer else {
            return (request, nil, nil)
        }

        // Read the RUM session from its store, on this thread. Both `networkContext` and
        // `contextReceiver.context` are fed by the message bus, which can still be empty here; a
        // request modified in that window used to be sampled at random and injected with no RUM
        // session ID, which is the early-request gap this closes.
        let sessionDecision = currentSessionSnapshot()

        let deliveredRUMContext: RUMCoreContext?
        if let networkContext {
            deliveredRUMContext = networkContext.rumContext
        } else {
            deliveredRUMContext = contextReceiver.context.rumContext
        }

        // The message bus delivers the RUM context after the session store has changed, so right after
        // a session change or stop it can still describe the previous session. It owns the span only when
        // it belongs to the session injected in this request; otherwise the span gets no RUM tags, rather
        // than being linked to a different session than its request.
        let requestTimeRUMContext = deliveredRUMContext?.sessionID == sessionDecision?.sessionID ? deliveredRUMContext : nil

        // Use the current active span as parent if the propagation headers support it.
        let newSpanElements = makeElementsForNewSpanContext(
            tracer: tracer,
            parentSpanContext: tracer.activeSpan?.context as? DDSpanContext,
            sessionDecision: sessionDecision
        )

        let injectedSpanContext = TraceContext(
            traceID: newSpanElements.traceID,
            spanID: newSpanElements.spanID,
            parentSpanID: newSpanElements.parentSpanID,
            sampleRate: newSpanElements.sampleRate,
            samplingPriority: newSpanElements.samplingPriority,
            samplingDecisionMaker: newSpanElements.samplingDecisionMaker,
            rumSessionId: sessionDecision?.sessionID,
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
                    hasSetAnyHeader = hasSetAnyHeader || field != W3CHTTPHeaders.baggage
                    request.setValue(value, forHTTPHeaderField: field)
                }
            }
        }

        /*
         A note about how the active span context is registered: the order these three methods
         is called is modify(…) (synchronously), followed by interceptionDidStart(…) and
         interceptionDidComplete(…), both asynchronously.

         Modify (this method) is where the TraceContext is created and may be returned from.
         However, if the span is not sampled, and TraceContextInjection is configured for .sampled
         (the default config at the time of writing), there is no propagation through headers nor
         injected context, so modify returns nil.

         Therefore, there is the need to keep track of the active span, if any, in a different
         way, so we can associate the child span created in this session handler, and treat
         it properly (usually that means setting the same sampling priority as the parent and
         in the case the parent is dropped, drop the new span as well).

         The first step is to obtain it here, in the only session handler function that runs
         synchronously with the request. Although it's true users may change the active span
         from any other thread, this is the most accurate place to obtain it, and we have to
         assume a user that is interesting in tracing a process that includes this request will
         not change the active span while this runs.

         We then return it as captured state. We cannot return this in the TraceContext because
         if a request is not traced, there is no TraceContext.

         Read the comment in interceptionDidStart(…) to know how this information propagates.
         */

        // Detect GraphQL requests by checking for GraphQL headers
        let hasGraphQLHeaders = request.hasGraphQLHeaders

        // Return captured state with active span, GraphQL detection and request-time RUM ownership.
        let capturedState = TracingURLSessionHandlerCapturedState(
            activeSpan: tracer.activeSpan,
            hasGraphQLHeaders: hasGraphQLHeaders,
            rumContext: requestTimeRUMContext,
            sessionDecision: sessionDecision
        )

        return (
            request,
            hasSetAnyHeader ? injectedSpanContext : nil,
            capturedState
        )
    }

    func interceptionDidStart(interception: DatadogInternal.URLSessionTaskInterception, capturedStates: [any URLSessionHandlerCapturedState]) {
        /*
         Read the comment inside the modify(…) method to know where the captured state comes from.

         If there is an captured state with the active span at the time the request was instrumented,
         it's registered in the interception, so it can be obtained from the interceptionDidComplete
         method.

         Note this method (interceptionDidStart) runs on a background thread, so obtaining the active
         span here would be inaccurate, as this method can run much later, even after the request
         is finished.

         The comment inside the interceptionDidComplete(…) method explains how the registered active
         span is used.
         */
        // TODO: RUM-13769 This code can be simplified since we never use more than one handler simultaneously.
        let capturedState = capturedStates.compactMap({ $0 as? TracingURLSessionHandlerCapturedState }).first

        if let capturedState {
            _capturedRUMContexts.mutate { contexts in
                guard contexts[interception.identifier] == nil else {
                    return
                }
                contexts[interception.identifier] = CapturedRUMContext(
                    rumContext: capturedState.rumContext,
                    sessionDecision: capturedState.sessionDecision
                )
            }
        }

        capturedState?.activeSpan.map {
            interception.register(activeSpanContext: $0.context)
        }

        // Check if GraphQL was detected in the captured state
        // Only send telemetry if the request is not already tracked by RUM (to avoid duplicates)
        if interception.origin != "rum",
           let capturedState = capturedState,
           capturedState.hasGraphQLHeaders {
            telemetry.usage(event: .addGraphQLRequest)
        }
    }

    func interceptionDidComplete(interception: DatadogInternal.URLSessionTaskInterception) {
        var capturedRUMContext: CapturedRUMContext?
        _capturedRUMContexts.mutate {
            capturedRUMContext = $0.removeValue(forKey: interception.identifier)
        }

        guard
            interception.isFirstPartyRequest, // `Span` should be only send for 1st party requests
            interception.origin != "rum", // if that request was tracked as RUM resource, the RUM backend will create the span on our behalf
            let tracer = tracer,
            let startTime = interception.fetchStartDate,
            let endTime = interception.fetchEndDate,
            let resourceCompletion = interception.completion
        else {
            return
        }

        let span: OTSpan
        var isStatsOnly = false

        /*
         Read the comments inside the modify(…) and interceptionDidStart(…) methods to know where
         and how the information used below is obtained.

         We need to create a new span here. Some of the span specifics depends on what
         happen before, in the modify(…) and interceptionDidStart(…) methods.

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
                startTime: startTime,
                eventWriter: capturedRUMContext.map {
                    LazySpanWriteContext(featureScope: tracer.featureScope, rumContext: .some($0.rumContext))
                }
            )
        } else {
            // No trace context was injected. Either the task never went through `modify(…)`, for example
            // when `URLSession.dataTask(...)` was created from a `URL` on iOS 13+, or `modify(…)` injected
            // nothing: with `.sampled` injection a dropped request gets no headers, and headers the request
            // already carried are never overwritten. A sampler pre-check runs, then the decision below,
            // and the span is uploaded only when both keep it.
            //
            // Client-side stats must not change which spans are uploaded, so the pre-check keeps its
            // existing effect. When it rejects the request and stats is enabled, the span is still built:
            // `DDSpan.finish()` hands every finished span to the stats concentrator and gates only the
            // upload on the sampling decision, so skipping it would leave the request out of the
            // aggregate, and `_dd.compute_stats=0` stops the backend from compensating. That span is
            // dropped, so it is never uploaded.
            let passesPreCheck = Sampler(samplingRate: samplingRate).sample()
            guard passesPreCheck || tracer.onSpanFinished != nil else {
                return
            }

            // Reuse the session read when the request was modified, so the span is sampled by the same
            // session as its RUM tags even if the session changed while the request was in flight. A task
            // that never went through `modify(…)` has no captured state, so its session is read now.
            let sessionDecision: SessionSamplingDecision?
            if let capturedRUMContext {
                sessionDecision = capturedRUMContext.sessionDecision
            } else {
                sessionDecision = currentSessionSnapshot()
            }
            let decidedSpanElements = makeElementsForNewSpanContext(
                tracer: tracer,
                parentSpanContext: interception.activeSpanContext as? DDSpanContext,
                sessionDecision: sessionDecision
            )
            let newSpanElements = passesPreCheck ? decidedSpanElements : decidedSpanElements.droppingTheSpan()
            isStatsOnly = !passesPreCheck

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
                startTime: startTime,
                eventWriter: capturedRUMContext.map {
                    LazySpanWriteContext(featureScope: tracer.featureScope, rumContext: .some($0.rumContext))
                }
            )
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

        // A span that exists only for client-side stats gets just the error tag, which is enough for it to
        // count as an error. `setError` would also send an error log, independently of the upload decision,
        // for a request that is not traced.
        let setError: (Error) -> Void = { error in
            if isStatsOnly {
                span.setTag(key: OTTags.error, value: true)
            } else {
                span.setError(error, file: "", line: 0)
            }
        }

        if let error = resourceCompletion.error {
            setError(error)
        }

        if let httpResponse = resourceCompletion.httpResponse {
            let httpStatusCode = httpResponse.statusCode
            span.setTag(key: OTTags.httpStatusCode, value: httpStatusCode)
            if let error = httpResponse.asClientError() {
                setError(error)
            }

            // Redaction is intentionally independent of error classification: a status code can be
            // redacted regardless of whether it is a client error (4xx), server error (5xx), or any other code.
            if redactedStatusCodes.contains(httpStatusCode) {
                span.setTag(key: SpanTags.resource, value: String(httpStatusCode))
            }
        }

        // Ensure `endTime >= startTime` before constructing the range below.
        let safeEndTime = max(startTime, endTime)

        if let history = contextReceiver.context.applicationStateHistory {
            let fetchDuration = startTime...safeEndTime
            // Users sometimes see spans for requests that take hours, even days, which is unexpected.
            // This happens when a request starts, the application is suspended (as in, the OS suspends
            // the process for a reason like a user sending the application to the background on an
            // iPhone), and later resumed. When resuming, the ongoing request will fail, and the span
            // will only finish then.
            // We want to measure here the time the application could not be suspended, as in the
            // process was actually running on the CPU, so users can understand why a span took an
            // unexpected long time.
            // This is usually the same as foregroundDuration in iOS (hence the historical name),
            // but not on macOS, where applications in the background keep running normally, and
            // are only suspended during the periods the Mac is sleeping.
            let foregroundDuration = history.applicationNotSuspendedDuration(during: fetchDuration)
            span.setTag(key: SpanTags.foregroundDuration, value: foregroundDuration.dd.toNanoseconds)

            #if os(macOS)
            span.setTag(key: SpanTags.isBackground, value: false)
            #else
            let didStartInBackground = history.state(at: startTime) == .background
            let doesEndInBackground = history.state(at: safeEndTime) == .background
            span.setTag(key: SpanTags.isBackground, value: didStartInBackground || doesEndInBackground)
            #endif
        }

        span.finish(at: safeEndTime)
    }

    /// Creates a helper struct with collected elements from a possible parent span context.
    ///
    /// The purpose of this method is to aggregate the same logic used in two different places in a common implementation.
    ///
    /// - parameters:
    ///    - tracer: The used tracer.
    ///    - parentSpanContext: If the span created by the session handler should be related to a parent span, pass
    ///    the parent span context here, otherwise, pass `nil`.
    ///    - sessionDecision: The RUM session sampling snapshot read for this request, or `nil` when no
    ///    session is active. Passed in rather than read here so that one request makes exactly one
    ///    read, and its session-derived decision cannot disagree with the injected session ID. An
    ///    active parent span still takes precedence to preserve the parent trace's decision.
    /// - returns: A ``TracingURLSessionHandler.NewSpanElements`` helper struct.
    private func makeElementsForNewSpanContext(tracer: DatadogTracer, parentSpanContext: DDSpanContext?, sessionDecision: SessionSamplingDecision?) -> NewSpanElements {
        let traceID = parentSpanContext?.traceID ?? tracer.traceIDGenerator.generate()
        let sampled = isSampled(sessionDecision: sessionDecision, traceID: traceID.idLo)
        let samplingDecision = parentSpanContext.map { $0.samplingDecision } ?? SamplingDecision(
            from: sampled ? .autoKeep : .autoDrop,
            decisionMaker: .agentRate
        )

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

    /// Reads the current RUM session snapshot, on the calling thread.
    ///
    /// `firstPartyHostsTracing`'s rate applies on top of the sessions RUM already keeps, so the two
    /// rates are composed: a 20% tracing rate inside a 10% RUM session traces 2% of requests.
    private func currentSessionSnapshot() -> SessionSamplingDecision? {
        sessionSampler?.decision(for: .combinedWithSessionRate, rate: samplingRate)
    }

    /// Determines whether the current request should be sampled.
    ///
    /// When a RUM session is active, the snapshot already carries the decision: the session rate and
    /// the trace sampling rate are composed, since `firstPartyHostsTracing`'s rate is a share of the
    /// sessions RUM keeps. Otherwise, falls back to a deterministic sample seeded by the trace ID, or
    /// a random sample if no trace ID is available.
    ///
    /// - Parameters:
    ///   - sessionDecision: The current RUM session sampling snapshot, if a session is active.
    ///   - traceID: The trace ID used as a deterministic seed when no RUM session is present.
    /// - Returns: `true` if the request should be sampled.
    private func isSampled(sessionDecision: SessionSamplingDecision?, traceID: UInt64?) -> Bool {
        if let sessionDecision {
            return sessionDecision.isSampled
        }

        // No RUM session: fall back to Knuth on traceID or random sampler.
        if let traceID {
            return DeterministicSampler(seed: traceID, samplingRate: samplingRate).sample()
        }

        return Sampler(samplingRate: samplingRate).sample()
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
