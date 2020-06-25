/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class TracingAutoInstrumentation {
    static var instance: TracingAutoInstrumentation?

    let tracedHosts: Set<URL>
    let swizzler: URLSessionSwizzler

    init?(tracedHosts: Set<URL>) {
        if tracedHosts.isEmpty {
            return nil
        }
        do {
            self.tracedHosts = tracedHosts
            self.swizzler = try URLSessionSwizzler()
        } catch {
            userLogger.warn("🔥 Network requests won't be traced automatically for \(String(describing: tracedHosts)): \(error)")
            developerLogger?.warn("🔥 Network requests won't be traced automatically for \(String(describing: tracedHosts)): \(error)")
            return nil
        }
    }

    func apply() {
        let interceptor = TracingRequestInterceptor.build(with: tracedHosts)
        swizzler.swizzle(using: interceptor)
    }
}

internal enum TracingRequestInterceptor {
    static func build(with tracedHosts: Set<URL>) -> RequestInterceptor {
        let interceptor: RequestInterceptor = { urlRequest in
            guard let tracer = Global.sharedTracer as? DDTracer,
                let someURL = urlRequest.url,
                tracedHosts.allows(someURL),
                HTTPHeadersWriter.canInject(to: urlRequest) else {
                    return nil
            }
            let spanContext = tracer.createSpanContext()
            let headersWriter = HTTPHeadersWriter()
            headersWriter.inject(spanContext: spanContext)
            let tracingHeaders = headersWriter.tracePropagationHTTPHeaders
            var modifiedRequest = urlRequest
            tracingHeaders.forEach { modifiedRequest.setValue($1, forHTTPHeaderField: $0) }

            let observer: TaskObserver = tracingTaskObserver(tracer: tracer, spanContext: spanContext)
            return InterceptionResult(modifiedRequest: modifiedRequest, taskObserver: observer)
        }
        return interceptor
    }

    static func tracingTaskObserver(
        tracer: DDTracer,
        spanContext: DDSpanContext
    ) -> TaskObserver {
        var startedSpan: OTSpan? = nil
        let observer: TaskObserver = { observedEvent in
            switch observedEvent {
            case .starting(let request):
                if let ongoingSpan = startedSpan {
                    userLogger.warn("\(String(describing: request)) is starting a new trace but it's already started a trace before: \(ongoingSpan)")
                    developerLogger?.warn("\(String(describing: request)) is starting a new trace but it's already started a trace before: \(ongoingSpan)")
                }
                let span = tracer.startSpan(
                    spanContext: spanContext,
                    operationName: "urlsession.request"
                )
                let url = request?.url?.absoluteString ?? "unknown_url"
                let method = request?.httpMethod ?? "unknown_method"
                span.setTag(key: DDTags.resource, value: url)
                span.setTag(key: OTTags.httpUrl, value: url)
                span.setTag(key: OTTags.httpMethod, value: method)
                startedSpan = span
            case .completed(let response, let error):
                guard let completedSpan = startedSpan else {
                    break
                }
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    completedSpan.setTag(key: OTTags.httpStatusCode, value: statusCode)
                }
                if let someError = error {
                    completedSpan.handleError(someError)
                }
                completedSpan.finish()
            }
        }
        return observer
    }
}

private extension Set where Element == URL {
    func allows(_ url: URL) -> Bool {
        return self.contains {
            return (url.scheme == $0.scheme) && (url.host == $0.host)
        }
    }
}

private extension OTSpan {
    func handleError(_ error: Error) {
        setTag(key: DDTags.errorStack, value: String(describing: error))
        let nsError = error as NSError
        let errorKind = "\(nsError.domain) - \(nsError.code)"
        setTag(key: DDTags.errorType, value: errorKind)
        let errorMessage = nsError.localizedDescription
        setTag(key: DDTags.errorMessage, value: errorMessage)
    }
}
