/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import OpenTracing

// TODO: RUMM-452 URLSessionHooks has incomplete whitelisting implementation

internal enum URLSessionHooks {
    static func tracingRequestInterceptor(domainWhitelist: Set<URL>, tracingFeature: TracingFeature) -> RequestInterceptor {
        let domainStrings = Set(domainWhitelist.compactMap { $0.domain })
        assert(domainStrings.count != domainWhitelist.count, "\(domainWhitelist) contains invalid domain(s)")

        return { originalRequest -> InterceptionResult? in
            guard let domain = originalRequest.url?.domain,
                domainStrings.contains(domain),
                let sharedTracer = Global.sharedTracer as? DDTracer else {
                    return nil
            }
            let spanContext = sharedTracer.createSpanContext(with: tracingFeature)
            let headersWriter = DDHTTPHeadersWriter()
            headersWriter.inject(spanContext: spanContext)
            let tracingHeaders = headersWriter.tracePropagationHTTPHeaders
            let httpHeaders = tracingHeaders.merging(originalRequest.allHTTPHeaderFields ?? [:]) { _, originalHeader -> String in
                return originalHeader
            }
            var modifiedRequest = originalRequest
            modifiedRequest.allHTTPHeaderFields = httpHeaders

            let observer: TaskObserver = tracingTaskObserver(
                tracer: sharedTracer,
                createdSpanContext: spanContext
            )
            return (request: modifiedRequest, taskPayload: observer)
        }
    }

    private static func tracingTaskObserver(tracer: DDTracer, createdSpanContext: DDSpanContext) -> TaskObserver {
        var previousEvent: TaskObservationEvent? = nil
        var startedSpan: OpenTracing.Span? = nil
        let observer: TaskObserver = { observedEvent in
            let previousEventValue = previousEvent?.rawValue ?? Int.min
            if observedEvent.rawValue <= previousEventValue {
                return
            }
            previousEvent = observedEvent

            switch observedEvent {
            case .starting:
                startedSpan = tracer.startSpan(with: createdSpanContext)
            case .completed:
                startedSpan?.finish()
            }
        }
        return observer
    }
}

private extension URL {
    var domain: String? {
        if let scheme = self.scheme, let host = self.host {
            return scheme + "://" + host
        }
        return nil
    }
}
