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
///     core.register(urlSessionHandler: handler)
///
/// Registering multiple handlers will aggregate instrumentation.
internal final class NetworkInstrumentationFeature: DatadogFeature {
    /// The Feature name: "network-instrumentation".
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

    /// Tracks delegate classes registered in metrics mode.
    /// Used to prevent automatic mode from processing tasks that are handled by metrics mode.
    /// Maps ObjectIdentifier to the actual class type for isKind(of:) checks.
    @ReadWriteLock
    private var registeredDelegateClasses: [ObjectIdentifier: AnyClass] = [:]

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

    /// Configures network instrumentation for the specified tracking mode.
    ///
    /// This method supports two modes:
    /// - Automatic Mode (`configuration == nil`): Tracks all tasks without requiring delegate registration.
    ///   Uses setState and completion handler swizzling. Does not capture `URLSessionTaskMetrics`.
    /// - Metrics Mode (`configuration != nil`): Tracks tasks with registered delegate class.
    ///   Additionally swizzles delegate methods to capture detailed timing breakdown.
    ///
    /// - Parameter configuration: The configuration to use. If `nil`, enables Automatic Mode.
    ///   If provided, enables Metrics Mode for the specified delegate class.
    internal func bind(configuration: URLSessionInstrumentation.Configuration?) throws {
        // Prepare mode (validates prerequisites and returns identifier)
        guard let identifier = prepareMode(for: configuration) else {
            return // Validation failed or already enabled
        }

        let swizzler = NetworkInstrumentationSwizzler()
        swizzlers[identifier] = swizzler

        // Determine tracking mode based on configuration
        let trackingMode: TrackingMode = configuration?.delegateClass != nil ? .metrics : .automatic

        // Intercept when the task is started
        try swizzler.swizzle(
            interceptResume: { [weak self] task in
                guard let self = self else {
                    return
                }

                // Skip Datadog's own intake requests to prevent infinite recursion
                if self.isDatadogIntakeRequest(task.currentRequest) {
                    return
                }

                // Determine if this swizzler should intercept this task based on the configuration
                guard shouldInterceptTask(task, for: configuration) else {
                    return
                }

                // Only perform interception if this swizzler should handle this task
                // This allows the swizzler chain to continue for tasks we don't handle
                var injectedTraceContexts: [TraceContext]?

                let configuredFirstPartyHosts = FirstPartyHosts(firstPartyHosts: configuration?.firstPartyHostsTracing) ?? .init()
                if let currentRequest = task.currentRequest {
                    let (request, traceContexts) = self.intercept(request: currentRequest, additionalFirstPartyHosts: configuredFirstPartyHosts)
                    task.dd.override(currentRequest: request)
                    injectedTraceContexts = traceContexts
                }

                self.intercept(task: task, with: injectedTraceContexts ?? [], additionalFirstPartyHosts: configuredFirstPartyHosts, trackingMode: trackingMode)
            }
        )

        // In Metrics Mode (delegate class provided), swizzle delegate methods to capture data and metrics
        if let delegateClass = configuration?.delegateClass {
            // Swizzle delegate methods for metrics collection and completion detection:
            // - didFinishCollecting: Captures `URLSessionTaskMetrics` for detailed timing information
            // - didCompleteWithError: Detects completion on pre-iOS 15 where setState doesn't fire
            //
            // Completion detection strategy:
            // For tasks WITHOUT completion handlers:
            //   - iOS 15+: setState swizzling detects completion (didCompleteWithError is not called by URLSession)
            //   - Pre-iOS 15: didCompleteWithError delegate detects completion (setState doesn't change to completed)
            // For tasks WITH completion handlers:
            //   - All iOS versions: Completion handler swizzling detects completion
            try swizzler.swizzle(
                delegateClass: delegateClass,
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

            // Swizzle didReceive to capture response data in metrics mode
            // This ensures data is available for:
            // - ResourceAttributesProvider to access response body and add custom attributes
            // - GraphQL error detection (GraphQL errors are in response body, not HTTP status)
            try swizzler.swizzle(
                delegateClass: delegateClass,
                interceptDidReceive: { [weak self] session, task, data in
                    self?.task(task, didReceive: data)
                }
            )
        }

        // Swizzle completion handlers for `URLSession.dataTask(with:completionHandler:)` methods
        //
        // In dual-mode (automatic + metrics), both modes swizzle completion handlers.
        // To prevent double-counting, automatic mode skips tasks with registered delegates.
        try swizzler.swizzle(
            interceptCompletionHandler: { [weak self] task, _, error in
                guard let self = self else {
                    return
                }

                // Determine if this swizzler should process this task
                if let delegateClass = configuration?.delegateClass {
                    // Metrics mode: only process if task has our registered delegate
                    guard let delegate = task.dd.delegate, delegate.isKind(of: delegateClass) else {
                        return
                    }
                    self.task(task, didCompleteWithError: error)
                } else {
                    // Automatic mode: skip if task has a delegate registered in metrics mode
                    if let delegate = task.dd.delegate, self.isRegisteredDelegate(delegate) {
                        return
                    }
                    self.task(task, didCompleteWithError: error)
                }
            }, didReceive: { [weak self] task, data in
                guard let self = self else {
                    return
                }

                // Determine if this swizzler should process this task
                if let delegateClass = configuration?.delegateClass {
                    // Metrics mode: only process if task has our registered delegate
                    guard let delegate = task.dd.delegate, delegate.isKind(of: delegateClass) else {
                        return
                    }
                    self.task(task, didReceive: data)
                } else {
                    // Automatic mode: skip if task has a delegate registered in metrics mode
                    if let delegate = task.dd.delegate, self.isRegisteredDelegate(delegate) {
                        return
                    }
                    self.task(task, didReceive: data)
                }
            }
        )

        // Swizzle `setState:` to detect completion for tasks without completion handlers
        // This is necessary because:
        // - Async/await APIs use internal delegates that cannot be swizzled
        // - Tasks without completion handlers and without delegates won't trigger any other callback
        try swizzler.swizzle(
            interceptSetState: { [weak self] task, state in
                self?.task(task, didChangeToState: state)
            }
        )
    }

    /// Unswizzles `URLSessionTaskDelegate` methods for the given delegate class.
    /// - Parameter delegateClass: The delegate class to unswizzle.
    internal func unbind(delegateClass: URLSessionDataDelegate.Type) {
        let identifier = ObjectIdentifier(delegateClass)
        swizzlers.removeValue(forKey: identifier)
        registeredDelegateClasses.removeValue(forKey: identifier)
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

    // MARK: - Mode Preparation

    /// Prepares the tracking mode by validating prerequisites and determining the swizzler identifier.
    ///
    /// - Parameter configuration: The configuration to prepare. If `nil`, prepares Automatic Mode. If provided, prepares Metrics Mode.
    /// - Returns: The identifier for the swizzler, or `nil` if validation failed.
    private func prepareMode(for configuration: URLSessionInstrumentation.Configuration?) -> ObjectIdentifier? {
        if let delegateClass = configuration?.delegateClass {
            return prepareMetricsMode(for: delegateClass)
        } else {
            return prepareAutomaticMode()
        }
    }

    /// Prepares Metrics Mode for the specified delegate class.
    ///
    /// - Parameter delegateClass: The delegate class to register for metrics tracking.
    /// - Returns: The identifier for the swizzler, or `nil` if validation failed.
    private func prepareMetricsMode(for delegateClass: URLSessionDataDelegate.Type) -> ObjectIdentifier? {
        // Require automatic mode to be enabled first
        let automaticModeIdentifier = ObjectIdentifier(NetworkInstrumentationFeature.self)
        guard swizzlers[automaticModeIdentifier] != nil else {
            DD.logger.error(
                """
                Metrics mode requires automatic network instrumentation to be enabled first.
                Please enable RUM or Trace with `urlSessionTracking` parameter before enabling metrics mode.
                """
            )
            return nil
        }

        // Use delegate class as identifier
        let identifier = ObjectIdentifier(delegateClass)

        // Register this delegate class so automatic mode can skip processing its tasks
        registeredDelegateClasses[identifier] = delegateClass

        // If already instrumented, unswizzle the previous instance
        if let existingSwizzler = swizzlers[identifier] {
            DD.logger.warn(
                """
                The delegate class \(delegateClass) is already instrumented.
                The previous instrumentation will be disabled in favor of the new one.
                """
            )
            existingSwizzler.unswizzle()
        }

        return identifier
    }

    /// Prepares Automatic Mode.
    ///
    /// - Returns: The identifier for the swizzler, or `nil` if already enabled.
    private func prepareAutomaticMode() -> ObjectIdentifier? {
        // Use sentinel identifier for Automatic mode
        let identifier = ObjectIdentifier(NetworkInstrumentationFeature.self)

        if swizzlers[identifier] != nil {
            DD.logger.debug("Automatic network instrumentation is already enabled.")
            return nil
        }

        return identifier
    }

    /// Checks if a delegate is a kind of any registered delegate class.
    /// Uses `isKind(of:)` to properly handle subclasses, preventing automatic mode
    /// from processing tasks that should be handled by metrics mode.
    ///
    /// - Parameter delegate: The delegate to check
    /// - Returns: `true` if the delegate is a kind of any registered class, `false` otherwise
    private func isRegisteredDelegate(_ delegate: AnyObject) -> Bool {
        return registeredDelegateClasses.values.contains { delegateClass in
            delegate.isKind(of: delegateClass)
        }
    }
}

extension NetworkInstrumentationFeature {
    /// Determines whether a task should be intercepted based on the tracking mode.
    ///
    /// - Metrics mode (delegate class configured): Only intercepts tasks with the registered delegate
    /// - Automatic mode (no delegate class): Intercepts all tasks except those with delegates registered in metrics mode
    ///
    /// This coordination prevents double-processing when both automatic and metrics modes are enabled.
    ///
    /// - Parameters:
    ///   - task: The URLSessionTask to check
    ///   - configuration: The instrumentation configuration
    /// - Returns: `true` if this swizzler should intercept the task, `false` otherwise
    private func shouldInterceptTask( _ task: URLSessionTask, for configuration: URLSessionInstrumentation.Configuration?) -> Bool {
        if let delegateClass = configuration?.delegateClass {
            // Metrics mode: only intercept tasks with our registered delegate
            return task.dd.delegate?.isKind(of: delegateClass) == true
        } else {
            // Automatic mode: skip tasks with delegates registered in metrics mode
            if let delegate = task.dd.delegate, isRegisteredDelegate(delegate) {
                return false
            }
            return true
        }
    }

    /// Checks if a URLRequest is an SDK internal request that should not be tracked
    ///
    /// - Parameter request: The URLRequest to check.
    /// - Returns: `true` if the request is an SDK internal request, `false` otherwise.
    private func isDatadogIntakeRequest(_ request: URLRequest?) -> Bool {
        // Check for DD-REQUEST-ID header (present in all SDK upload requests, including custom endpoints)
        return request?.value(forHTTPHeaderField: URLRequestBuilder.HTTPHeader.ddRequestIDHeaderField) != nil
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
    internal func intercept(request: URLRequest, additionalFirstPartyHosts: FirstPartyHosts?) -> (URLRequest, [TraceContext]) {
        let headerTypes = firstPartyHosts(with: additionalFirstPartyHosts)
            .tracingHeaderTypes(for: request.url)

        guard !headerTypes.isEmpty else {
            return (request, [])
        }

        let networkContext = self.networkContextProvider.currentNetworkContext
        var request = request
        var traceContexts: [TraceContext] = [] // each handler can inject distinct trace context
        for handler in handlers {
            let (nextRequest, nextTraceContext) = handler.modify(request: request, headerTypes: headerTypes, networkContext: networkContext)
            request = nextRequest
            if let nextTraceContext = nextTraceContext {
                traceContexts.append(nextTraceContext)
            }
        }

        // Remove GraphQL headers before returning the modified request
        request = removeGraphQLHeadersFromRequest(request)

        return (request, traceContexts)
    }

    /// Intercepts the provided URLSession task by creating an interception object and notifying all handlers that the interception has started.
    ///
    /// - Parameters:
    ///   - task: The URLSession task to intercept.
    ///   - injectedTraceContexts: The list of trace contexts injected into the task's request, one or none for each handler.
    ///   - additionalFirstPartyHosts: Extra hosts to consider in the interception, used in conjunction with hosts defined in each handler.
    ///   - trackingMode: The tracking mode to use for this interception (automatic or metrics).
    internal func intercept(task: URLSessionTask, with injectedTraceContexts: [TraceContext], additionalFirstPartyHosts: FirstPartyHosts?, trackingMode: TrackingMode) {
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

            // Check if interception already exists for this task
            let isNewInterception = self.interceptions[task] == nil

            // In dual-mode (automatic + metrics), prevent automatic mode from overriding metrics mode
            // Metrics mode provides more detailed tracking, so it takes priority
            if let existingInterception = self.interceptions[task],
               existingInterception.trackingMode == .metrics && trackingMode == .automatic {
                return
            }

            let interception = self.interceptions[task] ??
                URLSessionTaskInterception(
                    request: request,
                    isFirstParty: firstPartyHosts.isFirstParty(url: request.url),
                    trackingMode: trackingMode
                )

            interception.register(request: request)

            // Capture approximate start time for all modes
            // This enables Trace to work in automatic mode (where `URLSessionTaskMetrics` are unavailable)
            if interception.startDate == nil {
                interception.register(startDate: Date())
            }

            if let traceContext = injectedTraceContexts.first {
                // ^ If multiple trace contexts were injected (one per each handler) take the first one. This mimics the implicit
                // behaviour from before RUM-3470.
                interception.register(trace: traceContext)
            }

            if let origin = request.ddOriginHeaderValue {
                interception.register(origin: origin)
            }

            self.interceptions[task] = interception

            // Only notify handlers when the interception is first created, not when it's reused
            // This prevents double notifications when both automatic and metrics modes are enabled
            if isNewInterception {
                self.handlers.forEach { $0.interceptionDidStart(interception: interception) }
            }
        }
    }

    /// Tells the interceptors that metrics were collected for the given task.
    ///
    /// - Parameters:
    ///   - task: The task whose metrics have been collected.
    ///   - metrics: The collected metrics.
    internal func task(_ task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        queue.async { [weak self] in
            guard let self = self, let interception = self.interceptions[task] else {
                return
            }

            let resourceMetrics = ResourceMetrics(taskMetrics: metrics)
            interception.register(metrics: resourceMetrics)

            // Populate interception.responseSize for metrics mode
            self.captureResponseSize(for: interception, from: task, metrics: resourceMetrics)

            // Don't finish yet if task has completion handler - let completion handler finish after capturing data
            if interception.isDone && !task.dd.hasCompletion {
                self.finish(task: task, interception: interception)
            }
        }
    }

    /// Tells the interceptors that the task has received some of the expected data.
    ///
    /// - Parameters:
    ///   - task: The task that provided data.
    ///   - data: A data object containing the transferred data.
    internal func task(_ task: URLSessionTask, didReceive data: Data) {
        queue.async { [weak self] in
            guard let self = self, let interception = self.interceptions[task] else {
                return
            }
            interception.register(nextData: data)
        }
    }

    /// Tells the interceptors that the task did complete.
    ///
    /// - Parameters:
    ///   - task: The task that has finished transferring data.
    ///   - error: If an error occurred, an error object indicating how the transfer failed, otherwise NULL.
    internal func task(_ task: URLSessionTask, didCompleteWithError error: Error?) {
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
        // Capture approximate end time for all modes
        // This enables Trace to work in automatic mode (where `URLSessionTaskMetrics` are unavailable)
        interception.register(endDate: Date())

        handlers.forEach { $0.interceptionDidComplete(interception: interception) }
        interceptions[task] = nil
    }

    /// Tells the interceptors that the task's state has changed.
    ///
    /// - Parameters:
    ///   - task: The task whose state has changed.
    ///   - state: The new state of the task (maps to URLSessionTask.State: 0=running, 1=suspended, 2=canceling, 3=completed).
    internal func task(_ task: URLSessionTask, didChangeToState state: Int) {
        queue.async { [weak self] in
            guard let self = self, let interception = self.interceptions[task] else {
                return
            }

            // Register the state change
            interception.register(state: state)

            // When task completes, also register the response/error if not already done
            // This ensures completion is recorded even for async/await or delegate-less tasks without completion handlers
            // Note: We wait for .completed rather than .canceling because task.error is only populated
            // after the task fully transitions to completed state
            if state == URLSessionTask.State.completed.rawValue && interception.completion == nil {
                interception.register(
                    response: task.response,
                    error: task.error
                )

                // Also capture response size for automatic mode (when data is not available)
                // This provides the "size" component of "duration, status, size, errors" tracking
                if interception.responseSize == nil {
                    interception.register(responseSize: task.countOfBytesReceived)
                }
            }

            // Check if the interception is now complete and finish if needed.
            // However, if the task has a completion handler, wait for it to fire instead of finishing here.
            // This ensures we capture the response data through completion handler swizzling before finishing.
            // The completion handler will call finish() after capturing the data.
            if interception.isDone && !task.dd.hasCompletion {
                self.finish(task: task, interception: interception)
            }
        }
    }

    /// Captures response size for an interception.
    ///
    /// For metrics mode, prefers the response size from URLSessionTaskMetrics.
    /// Falls back to task.countOfBytesReceived when metrics don't have the size
    /// (e.g., upload tasks where URLSessionTaskMetrics reports 0).
    ///
    /// - Parameters:
    ///   - interception: The interception to populate.
    ///   - task: The task to get countOfBytesReceived from.
    ///   - metrics: The metrics containing responseSize from URLSessionTaskMetrics.
    private func captureResponseSize(
        for interception: URLSessionTaskInterception,
        from task: URLSessionTask,
        metrics: ResourceMetrics
    ) {
        guard interception.responseSize == nil else {
            return
        }

        let metricsSize = metrics.responseSize ?? 0
        let responseSize = metricsSize > 0 ? metricsSize : task.countOfBytesReceived

        if responseSize > 0 {
            interception.register(responseSize: responseSize)
        }
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
