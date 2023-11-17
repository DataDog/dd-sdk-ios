/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The Network Instrumentation Feature that can be registered into a core if
/// any hander is provided.
///
/// Usage:
///
///     let core: DatadogCoreProtocol
///
///     let handler: DatadogURLSessionHandler = CustomURLSessionHandler()
///     core.register(urlSessionInterceptor: handler)
///
/// Registering multiple interceptor will aggregate instrumentation.
internal final class NetworkInstrumentationFeature: DatadogFeature {
    /// The Feature name: "trace-propagation".
    static let name = "network-instrumentation"

    /// Network Instrumentation serial queue for safe and serialized access to the
    /// `URLSessionTask` interceptions.
    private let queue = DispatchQueue(
        label: "com.datadoghq.network-instrumentation",
        target: .global(qos: .utility)
    )

    /// A no-op message bus receiver.
    internal let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()

    /// The list of registered handlers.
    ///
    /// Accessing this list will acquire a read-write lock for fast read operation when mutating
    /// a `URLRequest`
    @ReadWriteLock
    internal var handlers: [DatadogURLSessionHandler] = []

    @ReadWriteLock
    internal var swizzlers: [ObjectIdentifier: URLSessionSwizzler] = [:]

    /// Maps `URLSessionTask` to its `TaskInterception` object.
    ///
    /// The interceptions **must** be accessed using the `queue`.
    private var interceptions: [URLSessionTask: URLSessionTaskInterception] = [:]

    /// Swizzles `URLSessionTaskDelegate`, `URLSessionDataDelegate`, and `URLSessionTask` methods
    /// to intercept `URLSessionTask` lifecycles.
    ///
    /// - Parameter configuration: The configuration to use for swizzling.
    /// Note: We are only concerned with type of the delegate here but to provide compile time safety, we
    ///      use the instance of the delegate to get the type.
    internal func bindIfNeeded(configuration: URLSessionInstrumentation.Configuration) throws {
        let configuredFirstPartyHosts = FirstPartyHosts(firstPartyHosts: configuration.firstPartyHostsTracing) ?? .init()

        let identifier = ObjectIdentifier(configuration.delegateClass)

        let swizzler = URLSessionSwizzler()
        swizzlers[identifier] = swizzler

        if #available(iOS 13, tvOS 13, *) {
            try swizzler.swizzle(
                interceptResume: { [weak self] task in
                    guard let self = self else {
                        return
                    }

                    if let currentRequest = task.currentRequest {
                        let request = self.intercept(request: currentRequest, additionalFirstPartyHosts: configuredFirstPartyHosts)
                        task.dd.override(currentRequest: request)
                    }

                    if task.dd.isDelegatingTo(klass: configuration.delegateClass) {
                        self.intercept(task: task, additionalFirstPartyHosts: configuredFirstPartyHosts)
                    }
                }
            )
        } else {
            try swizzler.swizzle(
                interceptRequest: { [weak self] request in
                    self?.intercept(request: request, additionalFirstPartyHosts: configuredFirstPartyHosts) ?? request
                },
                interceptTask: { [weak self] task in
                    if let self = self, task.dd.isDelegatingTo(klass: configuration.delegateClass) {
                        self.intercept(task: task, additionalFirstPartyHosts: configuredFirstPartyHosts)
                    }
                }
            )
        }

        try swizzler.swizzle(
            delegateClass: configuration.delegateClass,
            interceptDidReceive: { [weak self] session, task, data in
                self?.task(task, didReceive: data)
            }
        )

        try swizzler.swizzle(
            delegateClass: configuration.delegateClass,
            interceptDidFinishCollecting: { [weak self] session, task, metrics in
                self?.task(task, didFinishCollecting: metrics)

                // iOS 16 and above, didCompleteWithError is not called hence we use task state to detect task completion
                // while prior to iOS 15, task state doesn't change to completed hence we use didCompleteWithError to detect task completion
                if #available(iOS 15, tvOS 15, *) {
                    self?.task(task, didCompleteWithError: task.error)
                }
            },
            interceptDidCompleteWithError: { [weak self] session, task, error in
                // prior to iOS 15, task state doesn't change to completed
                // hence we use didCompleteWithError to detect task completion
                self?.task(task, didCompleteWithError: task.error)
            }
        )
    }

    /// Unswizzles `URLSessionTaskDelegate`, `URLSessionDataDelegate`, `URLSessionTask` and `URLSession` methods
    /// - Parameter delegateClass: The delegate class to unswizzle.
    internal func unbind(delegateClass: URLSessionDataDelegate.Type) {
        let identifier = ObjectIdentifier(delegateClass)
        swizzlers.removeValue(forKey: identifier)
    }
}

extension NetworkInstrumentationFeature {
    /// Tells the interceptors to modify a URL request.
    ///
    /// - Parameters:
    ///   - request: The request to intercept.
    ///   - additionalFirstPartyHosts: Extra hosts to consider in the interception
    /// - Returns: The modified request.
    func intercept(request: URLRequest, additionalFirstPartyHosts: FirstPartyHosts?) -> URLRequest {
        let headerTypes = firstPartyHosts(with: additionalFirstPartyHosts)
            .tracingHeaderTypes(for: request.url)

        guard !headerTypes.isEmpty else {
            return request
        }

        return handlers.reduce(request) {
            $1.modify(request: $0, headerTypes: headerTypes)
        }
    }

    /// Tells the interceptors that a task was created.
    ///
    /// - Parameters:
    ///   - task: The created task.
    ///   - additionalFirstPartyHosts: Extra hosts to consider in the interception.
    func intercept(task: URLSessionTask, additionalFirstPartyHosts: FirstPartyHosts?) {
        queue.async { [weak self] in
            self?._intercept(task: task, additionalFirstPartyHosts: additionalFirstPartyHosts)
        }
    }

    private func _intercept(task: URLSessionTask, additionalFirstPartyHosts: FirstPartyHosts?) {
        guard let request = task.currentRequest else {
            return
        }

        let firstPartyHosts = self.firstPartyHosts(with: additionalFirstPartyHosts)

        let interception = self.interceptions[task] ??
            URLSessionTaskInterception(
                request: request,
                isFirstParty: firstPartyHosts.isFirstParty(url: request.url)
            )

        interception.register(request: request)

        if let trace = self.extractTrace(firstPartyHosts: firstPartyHosts, request: request) {
            interception.register(traceID: trace.traceID, spanID: trace.spanID, parentSpanID: trace.parentSpanID)
        }

        if let origin = request.value(forHTTPHeaderField: TracingHTTPHeaders.originField) {
            interception.register(origin: origin)
        }

        self.interceptions[task] = interception
        self.handlers.forEach { $0.interceptionDidStart(interception: interception) }
    }

    /// Tells the interceptors that metrics were collected for the given task.
    ///
    /// - Parameters:
    ///   - task: The task whose metrics have been collected.
    ///   - metrics: The collected metrics.
    func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        queue.async { [weak self] in
            self?._task(task, didFinishCollecting: metrics)
        }
    }

    private func _task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let interception = self.interceptions[task] else {
            return
        }

        interception.register(
            metrics: ResourceMetrics(taskMetrics: metrics)
        )

        if interception.isDone {
            self.finish(task: task, interception: interception)
        }
    }

    /// Tells the interceptors that the task has received some of the expected data.
    ///
    /// - Parameters:
    ///   - task: The task that provided data.
    ///   - data: A data object containing the transferred data.
    func task(_ task: URLSessionTask, didReceive data: Data) {
        queue.async { [weak self] in
            self?.interceptions[task]?.register(nextData: data)
        }
    }

    /// Tells the interceptors that the task did complete.
    ///
    /// - Parameters:
    ///   - task: The task that has finished transferring data.
    ///   - error: If an error occurred, an error object indicating how the transfer failed, otherwise NULL.
    func task(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async { [weak self] in
            self?._task(task, didCompleteWithError: error)
        }
    }

    private func _task(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let interception = self.interceptions[task] else {
            return
        }

        interception.register(
            response: task.response,
            error: error
        )

        if interception.isDone {
            self.finish(task: task, interception: interception)
        }
    }

    private func firstPartyHosts(with additionalFirstPartyHosts: FirstPartyHosts?) -> FirstPartyHosts {
        handlers.reduce(.init()) { $0 + $1.firstPartyHosts } + additionalFirstPartyHosts
    }

    private func finish(task: URLSessionTask, interception: URLSessionTaskInterception) {
        handlers.forEach { $0.interceptionDidComplete(interception: interception) }
        interceptions[task] = nil
    }

    private func extractTrace(firstPartyHosts: FirstPartyHosts, request: URLRequest) -> (traceID: TraceID, spanID: SpanID, parentSpanID: SpanID?)? {
        guard let headers = request.allHTTPHeaderFields else {
            return nil
        }

        let tracingHeaderTypes = firstPartyHosts.tracingHeaderTypes(for: request.url)

        let reader: TracePropagationHeadersReader
        if tracingHeaderTypes.contains(.datadog) {
            reader = HTTPHeadersReader(httpHeaderFields: headers)
        } else if tracingHeaderTypes.contains(.b3) || tracingHeaderTypes.contains(.b3multi) {
            reader = B3HTTPHeadersReader(httpHeaderFields: headers)
        } else {
            reader = W3CHTTPHeadersReader(httpHeaderFields: headers)
        }
        return reader.read()
    }
}

extension NetworkInstrumentationFeature: Flushable {
    /// Awaits completion of all asynchronous operations.
    ///
    /// **blocks the caller thread**
    func flush() {
        queue.sync { }
    }
}
