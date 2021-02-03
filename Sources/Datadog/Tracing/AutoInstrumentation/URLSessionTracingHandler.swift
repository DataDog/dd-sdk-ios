/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class URLSessionTracingHandler: URLSessionInterceptionHandler {
    // MARK: - URLSessionInterceptionHandler

    func notify_taskInterceptionStarted(interception: TaskInterception) {
        /* no-op */
    }

    func notify_taskInterceptionCompleted(interception: TaskInterception) {
        if !interception.isFirstPartyRequest {
            return // `Span` should be only send for 1st party requests
        }
        guard let tracer = Global.sharedTracer as? Tracer else {
            userLogger.warn(
                """
                `URLSession` request was completed, but no `Tracer` is registered on `Global.sharedTracer`. Tracing auto instrumentation will not work.
                Make sure `Global.sharedTracer = Tracer.initialize()` is called before any network request is send.
                """
            )
            return
        }
        guard let resourceMetrics = interception.metrics,
              let resourceCompletion = interception.completion else {
            return
        }

        let span: OTSpan

        if let spanContext = interception.spanContext {
            span = tracer.startSpan(
                spanContext: spanContext,
                operationName: "urlsession.request",
                startTime: resourceMetrics.fetch.start
            )
        } else {
            // Span context may not be injected on iOS13+ if `URLSession.dataTask(...)` for `URL`
            // was used to create the session task.
            span = tracer.startSpan(
                operationName: "urlsession.request",
                startTime: resourceMetrics.fetch.start
            )
        }

        let url = interception.request.url?.absoluteString ?? "unknown_url"
        let method = interception.request.httpMethod ?? "unknown_method"
        span.setTag(key: DDTags.resource, value: url)
        span.setTag(key: OTTags.httpUrl, value: url)
        span.setTag(key: OTTags.httpMethod, value: method)

        if let error = resourceCompletion.error as NSError?, !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) {
            span.setTag(key: OTTags.error, value: true)

            let dderror = DDError(error: error)
            span.setTag(key: DDTags.errorType, value: dderror.title)
            span.setTag(key: DDTags.errorMessage, value: dderror.message)
            span.setTag(key: DDTags.errorStack, value: dderror.details)
        }

        if let httpResponseStatusCode = resourceCompletion.httpResponse?.statusCode {
            span.setTag(key: OTTags.httpStatusCode, value: httpResponseStatusCode)

            if httpResponseStatusCode >= 400 && httpResponseStatusCode < 500 {
                span.setTag(key: OTTags.error, value: true)
                if httpResponseStatusCode == 404 {
                    span.setTag(key: DDTags.resource, value: "404")
                }
            }
        }

        span.finish(at: resourceMetrics.fetch.end)
    }
}
