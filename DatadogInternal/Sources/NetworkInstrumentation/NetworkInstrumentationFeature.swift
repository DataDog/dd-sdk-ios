/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The Network Instrumentation Feature that can be registered into a core if
/// any handler is provided.
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
    let messageReceiver: FeatureMessageReceiver

    let networkContextProvider: NetworkContextProvider

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

    init(
        networkContextProvider: NetworkContextProvider,
        messageReceiver: FeatureMessageReceiver
    ) {
        self.networkContextProvider = networkContextProvider
        self.messageReceiver = messageReceiver
    }

    /// Swizzles `URLSessionTaskDelegate`, `URLSessionDataDelegate`, and `URLSessionTask` methods
    /// to intercept `URLSessionTask` lifecycles.
    ///
    /// - Parameter configuration: The configuration to use for swizzling.
    /// Note: We are only concerned with type of the delegate here but to provide compile time safety, we
    ///      use the instance of the delegate to get the type.
    internal func bind(configuration: URLSessionInstrumentation.Configuration) throws {
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

        let swizzler = NetworkInstrumentationSwizzler()
        swizzlers[identifier] = swizzler

        try swizzler.swizzle(
            interceptResume: { [weak self] task in
                // intercept task if delegate match
                guard let self = self, task.dd.delegate?.isKind(of: configuration.delegateClass) == true else {
                    return
                }

                var injectedTraceContexts = [RequestInstrumentationContext]()

                if let currentRequest = task.currentRequest {
                    let (request, traceContexts) = self.intercept(request: currentRequest, additionalFirstPartyHosts: configuredFirstPartyHosts)
                    task.dd.override(currentRequest: request)
                    injectedTraceContexts = traceContexts
                }

                self.intercept(task: task, with: injectedTraceContexts, additionalFirstPartyHosts: configuredFirstPartyHosts)
            }
        )

        try swizzler.swizzle(
            delegateClass: configuration.delegateClass,
            interceptDidFinishCollecting: { [weak self] session, task, metrics in
                self?.task(task, didFinishCollecting: metrics)

                if #available(iOS 15, tvOS 15, *), !task.dd.hasCompletion {
                    // iOS 15 and above, didCompleteWithError is not called hence we use task state to detect task completion
                    // while prior to iOS 15, task state doesn't change to completed hence we use didCompleteWithError to detect task completion
                    self?.task(task, didCompleteWithError: task.error)
                }
            },
            interceptDidCompleteWithError: { [weak self] session, task, error in
                self?.task(task, didCompleteWithError: error)
            }
        )

        try swizzler.swizzle(
            delegateClass: configuration.delegateClass,
            interceptDidReceive: { [weak self] session, task, data in
                self?.task(task, didReceive: data)
            }
        )

        try swizzler.swizzle(
            interceptCompletionHandler: { [weak self] task, _, error in
                self?.task(task, didCompleteWithError: error)
            }, didReceive: { [weak self] task, data in
                self?.task(task, didReceive: data)
            }
        )
    }

    /// Unswizzles `URLSessionTaskDelegate`, `URLSessionDataDelegate`, `URLSessionTask` and `URLSession` methods
    /// - Parameter delegateClass: The delegate class to unswizzle.
    internal func unbind(delegateClass: URLSessionDataDelegate.Type) {
        let identifier = ObjectIdentifier(delegateClass)
        swizzlers.removeValue(forKey: identifier)
    }

    private func removeGraphQLHeadersFromRequest(_ request: URLRequest) -> URLRequest {
        var modifiedRequest = request

        // Remove all GraphQL information
        modifiedRequest.setValue(nil, forHTTPHeaderField: GraphQLHeaders.operationName)
        modifiedRequest.setValue(nil, forHTTPHeaderField: GraphQLHeaders.operationType)
        modifiedRequest.setValue(nil, forHTTPHeaderField: GraphQLHeaders.variables)
        modifiedRequest.setValue(nil, forHTTPHeaderField: GraphQLHeaders.payload)

        return modifiedRequest
    }
}

extension NetworkInstrumentationFeature {
    /// Helper structure that optionally contains a trace context and captured state, used to pass this
    /// information between calls.
    struct RequestInstrumentationContext {
        let traceContext: TraceContext?
        let capturedState: URLSessionHandlerCapturedState?
    }

    /// Intercepts the provided request by injecting trace headers based on first-party hosts configuration.
    ///
    /// Only requests with URLs that match the list of first-party hosts have tracing headers injected.
    ///
    /// - Parameters:
    ///   - request: The request to intercept.
    ///   - additionalFirstPartyHosts: Extra hosts to consider in the interception, used in conjunction with hosts defined in each handler.
    /// - Returns: A tuple containing the modified request and the list of injected TraceContexts, one or none for each handler. If no trace is injected (e.g., due to sampling),
    ///            the list will be empty.
    func intercept(request: URLRequest, additionalFirstPartyHosts: FirstPartyHosts?) -> (URLRequest, [RequestInstrumentationContext]) {
        let headerTypes = firstPartyHosts(with: additionalFirstPartyHosts)
            .tracingHeaderTypes(for: request.url)

        guard !headerTypes.isEmpty else {
            return (request, [])
        }

        let networkContext = self.networkContextProvider.currentNetworkContext
        var request = request
        var instrumentationContexts: [RequestInstrumentationContext] = [] // each handler can inject distinct instrumentation context
        for handler in handlers {
            let (nextRequest, nextTraceContext, capturedState) = handler.modify(request: request, headerTypes: headerTypes, networkContext: networkContext)
            request = nextRequest
            instrumentationContexts.append(.init(traceContext: nextTraceContext, capturedState: capturedState))
        }

        // Remove GraphQL headers before returning the modified request
        request = removeGraphQLHeadersFromRequest(request)

        return (request, instrumentationContexts)
    }

    /// Intercepts the provided URLSession task by creating an interception object and notifying all handlers that the interception has started.
    ///
    /// - Parameters:
    ///   - task: The URLSession task to intercept.
    ///   - injectedTraceContexts: The list of trace contexts injected into the task's request, one or none for each handler.
    ///   - additionalFirstPartyHosts: Extra hosts to consider in the interception, used in conjunction with hosts defined in each handler.
    func intercept(task: URLSessionTask, with instrumentationContexts: [RequestInstrumentationContext], additionalFirstPartyHosts: FirstPartyHosts?) {
        // In response to https://github.com/DataDog/dd-sdk-ios/issues/1638 capture the current request object on the
        // caller thread and freeze its attributes through `ImmutableRequest`. This is to avoid changing the request
        // object from multiple threads:
        guard let currentRequest = task.currentRequest else {
            return
        }
        let request = ImmutableRequest(request: currentRequest)

        queue.async { [weak self] in
            guard let self = self else {
                return
            }

            let firstPartyHosts = self.firstPartyHosts(with: additionalFirstPartyHosts)

            let interception = self.interceptions[task] ??
                URLSessionTaskInterception(
                    request: request,
                    isFirstParty: firstPartyHosts.isFirstParty(url: request.url)
                )

            interception.register(request: request)

            if let traceContext = instrumentationContexts.compactMap({ $0.traceContext }).first {
                // ^ If multiple trace contexts were injected (one per each handler) take the first one. This mimics the implicit
                // behaviour from before RUM-3470.
                interception.register(trace: traceContext)
            }

            if let origin = request.ddOriginHeaderValue {
                interception.register(origin: origin)
            }

            self.interceptions[task] = interception
            self.handlers
                .forEach {
                    $0.interceptionDidStart(
                        interception: interception,
                        capturedStates: instrumentationContexts.compactMap({ $0.capturedState })
                    )
                }
        }
    }

    /// Tells the interceptors that metrics were collected for the given task.
    ///
    /// - Parameters:
    ///   - task: The task whose metrics have been collected.
    ///   - metrics: The collected metrics.
    func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        queue.async { [weak self] in
            guard let self = self, let interception = self.interceptions[task] else {
                return
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
            guard let self = self, let interception = self.interceptions[task] else {
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
    }

    private func firstPartyHosts(with additionalFirstPartyHosts: FirstPartyHosts?) -> FirstPartyHosts {
        handlers.reduce(.init()) { $0 + $1.firstPartyHosts } + additionalFirstPartyHosts
    }

    private func finish(task: URLSessionTask, interception: URLSessionTaskInterception) {
        handlers.forEach { $0.interceptionDidComplete(interception: interception) }
        interceptions[task] = nil
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
