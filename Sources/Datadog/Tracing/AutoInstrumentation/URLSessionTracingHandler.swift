/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class URLSessionTracingHandler: URLSessionInterceptionHandler {
    /// Listening to app state changes and use it to report `foreground_duration`
    let appStateListener: AppStateListening
    /// The Tracing sampler.
    let tracingSampler: Sampler

    init(appStateListener: AppStateListening, tracingSampler: Sampler) {
        self.appStateListener = appStateListener
        self.tracingSampler = tracingSampler
    }

    // MARK: - URLSessionInterceptionHandler

    func notify_taskInterceptionStarted(interception: TaskInterception) {
        /* no-op */
    }

    func notify_taskInterceptionCompleted(interception: TaskInterception) {
        if !interception.isFirstPartyRequest {
            return // `Span` should be only send for 1st party requests
        }
        guard let tracer = Global.sharedTracer as? Tracer else {
            DD.logger.warn(
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
        } else if tracingSampler.sample() {
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
            span.setTag(key: DDTags.resource, value: resourceUrl)
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
                    span.setTag(key: DDTags.resource, value: "404")
                }
            }
        }
        let appStateHistory = appStateListener.history.take(
            between: resourceMetrics.fetch.start...resourceMetrics.fetch.end
        )
        span.setTag(key: DDTags.foregroundDuration, value: appStateHistory.foregroundDuration.toNanoseconds)

        let didStartInBackground = appStateHistory.initialSnapshot.state == .background
        let doesEndInBackground = appStateHistory.currentSnapshot.state == .background
        span.setTag(key: DDTags.isBackground, value: didStartInBackground || doesEndInBackground)

        span.finish(at: resourceMetrics.fetch.end)
    }
}
