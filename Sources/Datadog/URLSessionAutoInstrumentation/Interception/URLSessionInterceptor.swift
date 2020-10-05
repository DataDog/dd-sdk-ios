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

    private let tracingHandler: URLSessionTracingHandlerType

    // MARK: - Initialization

    convenience init(configuration: FeaturesConfiguration.URLSessionAutoInstrumentation) {
        self.init(
            configuration: configuration,
            tracingInterceptionHandler: URLSessionTracingHandler()
        )
    }

    init(
        configuration: FeaturesConfiguration.URLSessionAutoInstrumentation,
        tracingInterceptionHandler: URLSessionTracingHandlerType
    ) {
        self.firstPartyURLsFilter = FirstPartyURLsFilter(configuration: configuration)
        self.internalURLsFilter = InternalURLsFilter(configuration: configuration)
        self.tracingHandler = tracingInterceptionHandler
        self.queue = DispatchQueue(label: "com.datadoghq.URLSessionInterceptor", target: .global(qos: .utility))
    }

    // MARK: - URLSessionInterceptorType

    /// An internal queue for synchronising the access to `interceptionByTask`.
    private let queue: DispatchQueue
    /// Maps `URLSessionTask` to its `TaskInterception` object.
    private var interceptionByTask: [URLSessionTask: TaskInterception] = [:]

    func modify(request: URLRequest) -> URLRequest {
        guard !internalURLsFilter.isInternal(url: request.url) else {
            return request
        }
        if let tracer = Global.sharedTracer as? Tracer {
            if firstPartyURLsFilter.isFirstParty(url: request.url) {
                return injectSpanContext(into: request, using: tracer)
            }
        }
        return request
    }

    func taskCreated(urlSession: URLSession, task: URLSessionTask) {
        guard let request = task.originalRequest,
              !internalURLsFilter.isInternal(url: request.url) else {
            return
        }

        // TODO: RUMM-732 Modify this check. It's only temporary as in Tracing we intercept only some requests
        // while in RUM we will be intercepting all (excluding the SDK internal ones).
        if firstPartyURLsFilter.isFirstParty(url: request.url) {
            queue.async {
                let interception = TaskInterception(request: request)
                self.interceptionByTask[task] = interception
            }
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

            interception.register(metrics: metrics)

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

            interception.register(response: task.response, error: error)

            if interception.isDone {
                self.finishInterception(task: task, interception: interception)
            }
        }
    }

    // MARK: - Private

    private func finishInterception(task: URLSessionTask, interception: TaskInterception) {
        interceptionByTask[task] = nil

        if let tracer = Global.sharedTracer as? Tracer {
            tracingHandler.sendSpan(for: interception, using: tracer)
        }
    }

    // MARK: - SpanContext Injection

    private func injectSpanContext(into request: URLRequest, using tracer: Tracer) -> URLRequest {
        let writer = HTTPHeadersWriter()
        let spanContext = tracer.createSpanContext()

        tracer.inject(spanContext: spanContext, writer: writer)

        var newRequest = request
        writer.tracePropagationHTTPHeaders.forEach { field, value in
            newRequest.setValue(value, forHTTPHeaderField: field)
        }
        return newRequest
    }
}
