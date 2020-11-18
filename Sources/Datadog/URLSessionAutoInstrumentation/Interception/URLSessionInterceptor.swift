/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// An object performing interception of requests sent from `URLSession`.
internal protocol URLSessionInterceptorType: class {
    /// Modifies the `URLRequest` before the `URLSessionTask` is started.
    /// Called from swizzled implementations of `URLSession.dataTask(...)` methods.
    /// It gets called for tasks created with `URLRequest` (prior to iOS 13.0 also for tasks created with `URL`).
    func modify(request: URLRequest) -> URLRequest

    /// Notifies the `URLSessionTask` creation for any task of every `URLSession`.
    /// Called from swizzled implementations of `URLSession.dataTask(...)` methods.
    func taskCreated(urlSession: URLSession, task: URLSessionTask)

    /// Notifies the `URLSessionTask` metrics collection for any task of every `URLSession` which uses `DDURLSessionDelegate`.
    /// Called from `DDURLSessionDelegate`.
    func taskMetricsCollected(urlSession: URLSession, task: URLSessionTask, metrics: URLSessionTaskMetrics)

    /// Notifies the `URLSessionTask` completion.
    /// Depending on the `URLSession` method used to produce the `task`, it may be called from:
    /// * `URLSession.dataTask(with:completion:)` completion block,
    /// * or `DDURLSessionDelegate` if the task was created with `URLSession.dataTask(with:)` and
    ///   the session uses `DDURLSessionDelegate`.
    func taskCompleted(urlSession: URLSession, task: URLSessionTask, error: Error?)
}

internal class URLSessionInterceptor: URLSessionInterceptorType {
    /// Filters first party `URLs` defined by the user.
    private let firstPartyURLsFilter: FirstPartyURLsFilter
    /// Filters internal `URLs` used by the SDK.
    private let internalURLsFilter: InternalURLsFilter
    /// Handles resources interception.
    /// Depending on which instrumentation is enabled, this can be either RUM or Tracing handler sending respectively: RUM Resource or tracing Span.
    internal let handler: URLSessionInterceptionHandler
    /// Whether or not to inject tracing headers to intercepted 1st party requests.
    /// Set to `true` if Tracing instrumentation is enabled (no matter o RUM state).
    internal let injectTracingHeadersToFirstPartyRequests: Bool
    /// Additional header injected to intercepted 1st party requests.
    /// Set to `x-datadog-origin: rum` if both RUM and Tracing instrumentations are enabled and `nil` in all other cases.
    internal let additionalHeadersForFirstPartyRequests: [String: String]?

    // MARK: - Initialization

    convenience init(
        configuration: FeaturesConfiguration.URLSessionAutoInstrumentation,
        dateProvider: DateProvider
    ) {
        let handler: URLSessionInterceptionHandler

        if configuration.instrumentRUM {
            handler = URLSessionRUMResourcesHandler(dateProvider: dateProvider)
        } else {
            handler = URLSessionTracingHandler()
        }

        self.init(configuration: configuration, handler: handler)
    }

    init(
        configuration: FeaturesConfiguration.URLSessionAutoInstrumentation,
        handler: URLSessionInterceptionHandler
    ) {
        self.firstPartyURLsFilter = FirstPartyURLsFilter(configuration: configuration)
        self.internalURLsFilter = InternalURLsFilter(configuration: configuration)
        self.handler = handler

        if configuration.instrumentTracing {
            self.injectTracingHeadersToFirstPartyRequests = true

            if configuration.instrumentRUM {
                // If RUM instrumentation is enabled, additional `x-datadog-origin: rum` header is injected to the user request,
                // so that user's backend instrumentation can further process it and count on RUM quota.
                self.additionalHeadersForFirstPartyRequests = [
                    TracingHTTPHeaders.originField: TracingHTTPHeaders.rumOriginValue
                ]
            } else {
                self.additionalHeadersForFirstPartyRequests = nil
            }
        } else {
            self.injectTracingHeadersToFirstPartyRequests = false
            self.additionalHeadersForFirstPartyRequests = nil
        }
    }

    // MARK: - URLSessionInterceptorType

    /// An internal queue for synchronising the access to `interceptionByTask`.
    private let queue = DispatchQueue(label: "com.datadoghq.URLSessionInterceptor", target: .global(qos: .utility))
    /// Maps `URLSessionTask` to its `TaskInterception` object.
    private var interceptionByTask: [URLSessionTask: TaskInterception] = [:]

    func modify(request: URLRequest) -> URLRequest {
        guard !internalURLsFilter.isInternal(url: request.url) else {
            return request
        }
        if injectTracingHeadersToFirstPartyRequests,
           firstPartyURLsFilter.isFirstParty(url: request.url) {
            return injectSpanContext(into: request)
        }
        return request
    }

    func taskCreated(urlSession: URLSession, task: URLSessionTask) {
        guard let request = task.originalRequest,
              !internalURLsFilter.isInternal(url: request.url) else {
            return
        }

        queue.async {
            let interception = TaskInterception(
                request: request,
                isFirstParty: self.firstPartyURLsFilter.isFirstParty(url: request.url)
            )
            self.interceptionByTask[task] = interception

            if let spanContext = self.extractSpanContext(from: request) {
                interception.register(spanContext: spanContext)
            }

            self.handler.notify_taskInterceptionStarted(interception: interception)
        }
    }

    func taskMetricsCollected(urlSession: URLSession, task: URLSessionTask, metrics: URLSessionTaskMetrics) {
        guard !internalURLsFilter.isInternal(url: task.originalRequest?.url) else {
            return
        }

        queue.async {
            guard let interception = self.interceptionByTask[task] else {
                return
            }

            interception.register(
                metrics: ResourceMetrics(taskMetrics: metrics)
            )

            if interception.isDone {
                self.finishInterception(task: task, interception: interception)
            }
        }
    }

    func taskCompleted(urlSession: URLSession, task: URLSessionTask, error: Error?) {
        guard !internalURLsFilter.isInternal(url: task.originalRequest?.url) else {
            return
        }

        queue.async {
            guard let interception = self.interceptionByTask[task] else {
                return
            }

            interception.register(
                completion: ResourceCompletion(response: task.response, error: error)
            )

            if interception.isDone {
                self.finishInterception(task: task, interception: interception)
            }
        }
    }

    // MARK: - Private

    private func finishInterception(task: URLSessionTask, interception: TaskInterception) {
        interceptionByTask[task] = nil
        handler.notify_taskInterceptionCompleted(interception: interception)
    }

    // MARK: - SpanContext Injection & Extraction

    private func injectSpanContext(into firstPartyRequest: URLRequest) -> URLRequest {
        guard let tracer = Global.sharedTracer as? Tracer else {
            return firstPartyRequest
        }

        let writer = HTTPHeadersWriter()
        let spanContext = tracer.createSpanContext()

        tracer.inject(spanContext: spanContext, writer: writer)

        var newRequest = firstPartyRequest
        writer.tracePropagationHTTPHeaders.forEach { field, value in
            newRequest.setValue(value, forHTTPHeaderField: field)
        }

        additionalHeadersForFirstPartyRequests?.forEach { field, value in
            newRequest.setValue(value, forHTTPHeaderField: field)
        }

        return newRequest
    }

    private func extractSpanContext(from request: URLRequest) -> DDSpanContext? {
        guard let tracer = Global.sharedTracer as? Tracer else {
            return nil
        }
        guard let headers = request.allHTTPHeaderFields else {
            return nil
        }

        let reader = HTTPHeadersReader(httpHeaderFields: headers)
        return tracer.extract(reader: reader) as? DDSpanContext
    }
}
