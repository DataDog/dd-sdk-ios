/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class TracingAutoInstrumentation {
    static var instance: TracingAutoInstrumentation?

    let swizzler: URLSessionSwizzler
    let interceptor: RequestInterceptor

    init?(tracedHosts: Set<String>) {
        if tracedHosts.isEmpty {
            return nil
        }
        do {
            /// pattern = "^(.*\\.)*tracedHost1|^(.*\\.)*tracedHost2|..."
            let regex = tracedHosts
                .map {
                    let escaped = NSRegularExpression.escapedPattern(for: $0)
                    return "^(.*\\.)*\(escaped)$"
                }
                .joined(separator: "|")
            self.interceptor = TracingRequestInterceptor.build(with: regex)
            self.swizzler = try URLSessionSwizzler()
        } catch {
            userLogger.warn("🔥 Network requests won't be traced automatically for \(String(describing: tracedHosts)): \(error)")
            developerLogger?.warn("🔥 Network requests won't be traced automatically for \(String(describing: tracedHosts)): \(error)")
            return nil
        }
    }

    func apply() {
        swizzler.swizzle(using: interceptor)
    }
}

private enum TracingRequestInterceptor {
    static func build(with tracedHostsRegex: String) -> RequestInterceptor {
        let interceptor: RequestInterceptor = { urlRequest in
            guard let tracer = Global.sharedTracer as? DDTracer,
                urlRequest.allowed(by: tracedHostsRegex),
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

    private static func tracingTaskObserver(
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
                if let someError = error {
                    completedSpan.handleError(someError)
                }
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    completedSpan.setTag(key: OTTags.httpStatusCode, value: statusCode)
                    if (400..<500).contains(statusCode) {
                        completedSpan.setTag(key: OTTags.error, value: true)
                    }
                    if statusCode == 404 {
                        completedSpan.setTag(key: DDTags.resource, value: "404")
                    }
                }
                completedSpan.finish()
            }
        }
        return observer
    }
}

private extension URLRequest {
    func allowed(by tracedHostsRegex: String) -> Bool {
        if let url = self.url, let host = url.host {
            return host.range(of: tracedHostsRegex, options: .regularExpression) != nil
        } else {
            return false
        }
    }
}

private extension OTSpan {
    func handleError(_ error: Error) {
        setTag(key: OTTags.error, value: true)
        setTag(key: DDTags.errorStack, value: String(describing: error))
        let nsError = error as NSError
        let errorKind = "\(nsError.domain) - \(nsError.code)"
        setTag(key: DDTags.errorType, value: errorKind)
        let errorMessage = nsError.localizedDescription
        setTag(key: DDTags.errorMessage, value: errorMessage)
    }
}
