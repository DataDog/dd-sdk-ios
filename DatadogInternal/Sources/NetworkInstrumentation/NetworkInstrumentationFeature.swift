/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The Network Instrumentation Feature that can be registered into a core.
/// Interceptions are forwarded to registered `handlers` (`DatadogURLSessionHandler`).
///
/// Usage:
///
///     let core: DatadogCoreProtocol
///
///     let feature = NetworkInstrumentationFeature()
///     core.register(feature: feature)
///
///     feature.handlers.append(urlSessionHandler)
///
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
    private var swizzlers: [ObjectIdentifier: NetworkInstrumentationSwizzler] = [:]

    /// Maps `URLSessionTask` to its `TaskInterception` object.
    ///
    /// The interceptions **must** be accessed using the `queue`.
    private var interceptions: [URLSessionTask: URLSessionTaskInterception] = [:]

    /// Telemetry interface for sending instrumentation errors.
    private let telemetry: Telemetry

    init(telemetry: Telemetry) {
        self.telemetry = telemetry
    }

    /// Swizzles `URLSessionTaskDelegate`, `URLSessionDataDelegate`, and `URLSessionTask` methods
    /// to intercept `URLSessionTask` lifecycles.
    ///
    /// - Parameters:
    ///   - configuration: The configuration to use for swizzling.
    ///   - telemetry: Telemetry instance to notify with any errors in swizzlings.
    /// Note: We are only concerned with type of the delegate here but to provide compile time safety, we
    ///      use the instance of the delegate to get the type.
    internal func bind(configuration: URLSessionInstrumentation.Configuration, telemetry: Telemetry) throws {
        let configuredFirstPartyHosts = FirstPartyHosts(firstPartyHosts: configuration.firstPartyHostsTracing) ?? .init()

        let identifier = ObjectIdentifier(configuration.delegateClass)

        if let swizzler = swizzlers[identifier] {
            DD.logger.warn(
                """
                The delegate class \(configuration.delegateClass) is already instrumented.
                The previous instrumentation will be disabled in favor of the new one.
                """
            )

            swizzler.unswizzle()
        }

        let swizzler = NetworkInstrumentationSwizzler(telemetry: telemetry)
        swizzlers[identifier] = swizzler

        /// Determines if given `task` should be intercepted or not.
        /// We skip any processing of tasks that come from sessions not instrumented with Datadog.
        func shouldIntercept(task: URLSessionTask) -> Bool {
            return task.dd.delegate?.isKind(of: configuration.delegateClass) == true // intercept task if delegate match
        }

        try swizzler.swizzle(
            interceptResume: { [weak self] task in
                guard let self = self, shouldIntercept(task: task) else {
                    return // skip, intercepting task from not instrumented session
                }

                if let currentRequest = task.currentRequest {
                    let request = self.intercept(request: currentRequest, additionalFirstPartyHosts: configuredFirstPartyHosts)
                    task.dd.override(currentRequest: request)
                }

                self.intercept(task: task, additionalFirstPartyHosts: configuredFirstPartyHosts)
            }
        )

        try swizzler.swizzle(
            delegateClass: configuration.delegateClass,
            interceptDidFinishCollecting: { [weak self] session, task, metrics in
                guard shouldIntercept(task: task) else {
                    return // skip, intercepting task from not instrumented session
                }

                self?.task(task, didFinishCollecting: metrics)

                if #available(iOS 15, tvOS 15, *) {
                    // iOS 15 and above, didCompleteWithError is not called hence we use task state to detect task completion
                    // while prior to iOS 15, task state doesn't change to completed hence we use didCompleteWithError to detect task completion
                    self?.task(task, didCompleteWithError: task.error)
                }
            },
            interceptDidCompleteWithError: { [weak self] session, task, error in
                guard shouldIntercept(task: task) else {
                    return // skip, intercepting task from not instrumented session
                }

                self?.task(task, didCompleteWithError: error)
            }
        )

        try swizzler.swizzle(
            delegateClass: configuration.delegateClass,
            interceptDidReceive: { [weak self] session, task, data in
                guard shouldIntercept(task: task) else {
                    return // skip, intercepting task from not instrumented session
                }

                self?.task(task, didReceive: data)
            }
        )

        try swizzler.swizzle(
            interceptCompletionHandler: { [weak self] task, _, error in
                guard shouldIntercept(task: task) else {
                    return // skip, intercepting task from not instrumented session
                }

                self?.task(task, didCompleteWithError: error)
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
    ///
    /// **Note:** This method must be only called for tasks instrumented with Datadog.
    func intercept(task: URLSessionTask, additionalFirstPartyHosts: FirstPartyHosts?, file: StaticString = #fileID, line: UInt = #line) {
        queue.async { [weak self] in
            guard let self = self, let request = task.currentRequest else {
                return
            }

            if self.interceptions[task] != nil { // sanity check, we don't expect an existing interception for task that was just created
                telemetry.error(
                    "Creating interception for task which is already being intercepted",
                    kind: "NetworkInstrumentationError",
                    stack: "Called from \(file):\(line)"
                )
            }

            let firstPartyHosts = self.firstPartyHosts(with: additionalFirstPartyHosts)

            let interception = URLSessionTaskInterception(
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
    }

    /// Tells the interceptors that metrics were collected for the given task.
    ///
    /// - Parameters:
    ///   - task: The task whose metrics have been collected.
    ///   - metrics: The collected metrics.
    ///
    /// **Note:** This method must be only called for tasks instrumented with Datadog.
    func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        queue.async { [weak self] in
            guard let self = self, let interception = interceptions[task] else {
                return // we may end up with no `interception` if instrumentation was enabled after the task was resumed
            }

            interception.register(
                metrics: ResourceMetrics(taskMetrics: metrics)
            )

            if interception.isDone {
                self.finish(task: task, interception: interception)
            }
        }
    }

    /// Tells the interceptors that the task has received some of the expected data.
    ///
    /// - Parameters:
    ///   - task: The task that provided data.
    ///   - data: A data object containing the transferred data.
    ///
    /// **Note:** This method must be only called for tasks instrumented with Datadog.
    func task(_ task: URLSessionTask, didReceive data: Data) {
        queue.async { [weak self] in
            guard let self = self, let interception = self.interceptions[task] else {
                return // we may end up with no `interception` if instrumentation was enabled after the task was resumed
            }

            interception.register(nextData: data)
        }
    }

    /// Tells the interceptors that the task did complete.
    ///
    /// - Parameters:
    ///   - task: The task that has finished transferring data.
    ///   - error: If an error occurred, an error object indicating how the transfer failed, otherwise NULL.
    ///
    /// **Note:** This method must be only called for tasks instrumented with Datadog.
    func task(_ task: URLSessionTask, didCompleteWithError error: Error?) {
        queue.async { [weak self] in
            guard let self = self, let interception = self.interceptions[task] else {
                return // we may end up with no `interception` if instrumentation was enabled after the task was resumed
            }

            interception.register(
                response: task.response,
                error: error
            )

            if interception.isDone {
                self.finish(task: task, interception: interception)
            }
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
