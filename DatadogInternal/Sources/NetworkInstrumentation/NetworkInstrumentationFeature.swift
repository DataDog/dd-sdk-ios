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
///
/// Actor isolation replaces the previous `DispatchQueue` serialization for
/// the `interceptions` dictionary. Properties accessed synchronously from
/// swizzler callbacks (`handlers`, `swizzlers`, `registeredDelegateClasses`)
/// retain `@ReadWriteLock` because trace header injection in `interceptResume`
/// must complete before the original `resume()` returns.
internal actor NetworkInstrumentationFeature: DatadogFeature {
    /// The Feature name: "network-instrumentation".
    nonisolated static let name = "network-instrumentation"

    /// A no-op message bus receiver.
    nonisolated(unsafe) let messageReceiver: FeatureMessageReceiver

    nonisolated(unsafe) let networkContextProvider: NetworkContextProvider

    /// Lock protecting `_handlers`, `_swizzlers`, and `_registeredDelegateClasses`.
    /// These properties are accessed from both nonisolated context (synchronous header
    /// injection in swizzler callbacks) and actor-isolated context. NSLock provides
    /// thread-safe access without requiring actor isolation.
    nonisolated(unsafe) private let _lock = NSLock()
    nonisolated(unsafe) private var _handlers: [DatadogURLSessionHandler] = []
    nonisolated(unsafe) private var _swizzlers: [ObjectIdentifier: NetworkInstrumentationSwizzler] = [:]
    nonisolated(unsafe) private var _registeredDelegateClasses: [ObjectIdentifier: AnyClass] = [:]

    nonisolated var handlers: [DatadogURLSessionHandler] {
        get { _lock.lock(); defer { _lock.unlock() }; return _handlers }
        set { _lock.lock(); defer { _lock.unlock() }; _handlers = newValue }
    }

    nonisolated var swizzlers: [ObjectIdentifier: NetworkInstrumentationSwizzler] {
        get { _lock.lock(); defer { _lock.unlock() }; return _swizzlers }
        set { _lock.lock(); defer { _lock.unlock() }; _swizzlers = newValue }
    }

    nonisolated var registeredDelegateClasses: [ObjectIdentifier: AnyClass] {
        get { _lock.lock(); defer { _lock.unlock() }; return _registeredDelegateClasses }
        set { _lock.lock(); defer { _lock.unlock() }; _registeredDelegateClasses = newValue }
    }

    /// Maps `URLSessionTask` to its `TaskInterception` object.
    /// Protected by actor isolation (replaces the previous `DispatchQueue`).
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
    /// - Registered Delegate Mode (`configuration != nil`): Tracks tasks with registered delegate class.
    ///   Additionally swizzles delegate methods to capture detailed timing breakdown.
    ///
    /// - Parameter configuration: The configuration to use. If `nil`, enables Automatic Mode.
    ///   If provided, enables Registered Delegate Mode for the specified delegate class.
    nonisolated internal func bind(configuration: URLSessionInstrumentation.Configuration?) throws {
        // Prepare mode (validates prerequisites and returns identifier)
        guard let identifier = prepareMode(for: configuration) else {
            return // Validation failed or already enabled
        }

        let swizzler = NetworkInstrumentationSwizzler()
        swizzlers[identifier] = swizzler

        // Determine tracking mode based on configuration
        let trackingMode: TrackingMode = configuration?.delegateClass != nil ? .registeredDelegate : .automatic

        // Intercept when the task is started
        try swizzler.swizzle(
            interceptResume: { [weak self] task in
                guard let self = self else {
                    return
                }

                // Skip task types that declare standard URLSessionTask properties as
                // NS_UNAVAILABLE and throw NSGenericException at runtime when accessed
                // (e.g. AVAssetDownloadTask, AVAggregateAssetDownloadTask).
                guard task.isSupportedForInstrumentation else {
                    return
                }

                guard let currentRequest = task.currentRequest else {
                    return
                }

                // Skip Datadog's own intake requests to prevent infinite recursion
                if self.isDatadogIntakeRequest(currentRequest) {
                    return
                }

                // Determine if this swizzler should intercept this task based on the configuration
                guard self.shouldInterceptTask(task, for: configuration) else {
                    return
                }

                // Only perform interception if this swizzler should handle this task
                // This allows the swizzler chain to continue for tasks we don't handle
                var injectedTraceContexts = [RequestInstrumentationContext]()

                let configuredFirstPartyHosts = FirstPartyHosts(firstPartyHosts: configuration?.firstPartyHostsTracing) ?? .init()
                let (request, traceContexts) = self.intercept(request: currentRequest, additionalFirstPartyHosts: configuredFirstPartyHosts)
                task.dd.override(currentRequest: request)
                injectedTraceContexts = traceContexts

                // Capture values on the caller thread before crossing the actor boundary
                self.interceptTask(task, with: injectedTraceContexts, additionalFirstPartyHosts: configuredFirstPartyHosts, trackingMode: trackingMode)
            }
        )

        // With registered delegate (delegate class provided), swizzle delegate methods to capture data and metrics
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
                    self?.taskDidFinishCollecting(task, metrics: metrics)
                },
                interceptDidCompleteWithError: { [weak self] session, task, error in
                    self?.taskDidComplete(task, error: error)
                }
            )

            // Swizzle didReceive to capture response data with registered delegate
            // This ensures data is available for:
            // - ResourceAttributesProvider to access response body and add custom attributes
            // - GraphQL error detection (GraphQL errors are in response body, not HTTP status)
            try swizzler.swizzle(
                delegateClass: delegateClass,
                interceptDidReceive: { [weak self] session, task, data in
                    self?.taskDidReceive(task, data: data)
                }
            )
        }

        // Swizzle completion handlers for `URLSession.dataTask(with:completionHandler:)` methods
        //
        // In dual-mode (automatic + registered delegate), both modes swizzle completion handlers.
        // To prevent double-counting, automatic mode skips tasks with registered delegates.
        try swizzler.swizzle(
            interceptCompletionHandler: { [weak self] task, _, error in
                guard let self = self else {
                    return
                }

                // Determine if this swizzler should process this task
                if let delegateClass = configuration?.delegateClass {
                    // Registered delegate mode: only process if task has our registered delegate
                    guard let delegate = task.dd.delegate, delegate.isKind(of: delegateClass) else {
                        return
                    }
                    self.taskDidComplete(task, error: error)
                } else {
                    // Automatic mode: skip if task has a registered delegate
                    if let delegate = task.dd.delegate, self.isRegisteredDelegate(delegate) {
                        return
                    }
                    self.taskDidComplete(task, error: error)
                }
            }, didReceive: { [weak self] task, data in
                guard let self = self else {
                    return
                }

                // Determine if this swizzler should process this task
                if let delegateClass = configuration?.delegateClass {
                    // Registered delegate mode: only process if task has our registered delegate
                    guard let delegate = task.dd.delegate, delegate.isKind(of: delegateClass) else {
                        return
                    }
                    self.taskDidReceive(task, data: data)
                } else {
                    // Automatic mode: skip if task has a registered delegate
                    if let delegate = task.dd.delegate, self.isRegisteredDelegate(delegate) {
                        return
                    }
                    self.taskDidReceive(task, data: data)
                }
            }
        )

        // Swizzle `setState:` to detect completion for tasks without completion handlers
        // This is necessary because:
        // - Async/await APIs use internal delegates that cannot be swizzled
        // - Tasks without completion handlers and without delegates won't trigger any other callback
        try swizzler.swizzle(
            interceptSetState: { [weak self] task, state in
                self?.taskDidChangeToState(task, state: state)
            }
        )
    }

    /// Unswizzles `URLSessionTaskDelegate` methods for the given delegate class.
    /// - Parameter delegateClass: The delegate class to unswizzle.
    nonisolated internal func unbind(delegateClass: URLSessionDataDelegate.Type) {
        let identifier = ObjectIdentifier(delegateClass)
        swizzlers.removeValue(forKey: identifier)
        registeredDelegateClasses.removeValue(forKey: identifier)
    }

    nonisolated private func removeGraphQLHeadersFromRequest(_ request: URLRequest) -> URLRequest {
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
    /// - Parameter configuration: The configuration to prepare. If `nil`, prepares Automatic Mode. If provided, prepares Registered Delegate Mode.
    /// - Returns: The identifier for the swizzler, or `nil` if validation failed.
    nonisolated private func prepareMode(for configuration: URLSessionInstrumentation.Configuration?) -> ObjectIdentifier? {
        if let delegateClass = configuration?.delegateClass {
            return prepareRegisteredDelegateMode(for: delegateClass)
        } else {
            return prepareAutomaticMode()
        }
    }

    /// Prepares registered delegate mode for the specified delegate class.
    ///
    /// - Parameter delegateClass: The delegate class to register.
    /// - Returns: The identifier for the swizzler, or `nil` if validation failed.
    nonisolated private func prepareRegisteredDelegateMode(for delegateClass: URLSessionDataDelegate.Type) -> ObjectIdentifier? {
        // Require automatic mode to be enabled first
        let automaticModeIdentifier = ObjectIdentifier(NetworkInstrumentationFeature.self)
        guard swizzlers[automaticModeIdentifier] != nil else {
            DD.logger.error(
                """
                Duration breakdown requires automatic network instrumentation to be enabled first.
                Please enable RUM or Trace with `urlSessionTracking` parameter before enabling duration breakdown.
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
    nonisolated private func prepareAutomaticMode() -> ObjectIdentifier? {
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
    /// from processing tasks that should be handled by registered delegate mode.
    ///
    /// - Parameter delegate: The delegate to check
    /// - Returns: `true` if the delegate is a kind of any registered class, `false` otherwise
    nonisolated private func isRegisteredDelegate(_ delegate: AnyObject) -> Bool {
        return registeredDelegateClasses.values.contains { delegateClass in
            delegate.isKind(of: delegateClass)
        }
    }
}

// MARK: - Nonisolated entry points (called from swizzler callbacks)

extension NetworkInstrumentationFeature {
    /// Determines whether a task should be intercepted based on the tracking mode.
    ///
    /// - Registered delegate mode (delegate class configured): Only intercepts tasks with the registered delegate
    /// - Automatic mode (no delegate class): Intercepts all tasks except those with registered delegates
    ///
    /// This coordination prevents double-processing when both automatic and registered delegate modes are enabled.
    ///
    /// - Parameters:
    ///   - task: The URLSessionTask to check
    ///   - configuration: The instrumentation configuration
    /// - Returns: `true` if this swizzler should intercept the task, `false` otherwise
    nonisolated private func shouldInterceptTask( _ task: URLSessionTask, for configuration: URLSessionInstrumentation.Configuration?) -> Bool {
        if let delegateClass = configuration?.delegateClass {
            // Registered delegate mode: only intercept tasks with our registered delegate
            return task.dd.delegate?.isKind(of: delegateClass) == true
        } else {
            // Automatic mode: skip tasks with registered delegates
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
    nonisolated private func isDatadogIntakeRequest(_ request: URLRequest?) -> Bool {
        // Check for DD-REQUEST-ID header (present in all SDK upload requests, including custom endpoints)
        return request?.value(forHTTPHeaderField: URLRequestBuilder.HTTPHeader.ddRequestIDHeaderField) != nil
    }

    /// Helper structure that optionally contains a trace context and captured state, used to pass this
    /// information between calls.
    struct RequestInstrumentationContext: @unchecked Sendable {
        let traceContext: TraceContext?
        let capturedState: URLSessionHandlerCapturedState?
    }

    /// Intercepts the provided request by injecting trace headers based on first-party hosts configuration.
    ///
    /// Only requests with URLs that match the list of first-party hosts have tracing headers injected.
    /// This method is `nonisolated` because trace header injection must complete synchronously
    /// before the original `resume()` returns.
    ///
    /// - Parameters:
    ///   - request: The request to intercept.
    ///   - additionalFirstPartyHosts: Extra hosts to consider in the interception, used in conjunction with hosts defined in each handler.
    /// - Returns: A tuple containing the modified request and the list of injected TraceContexts, one or none for each handler. If no trace is injected (e.g., due to sampling),
    ///            the list will be empty.
    nonisolated func intercept(request: URLRequest, additionalFirstPartyHosts: FirstPartyHosts?) -> (URLRequest, [RequestInstrumentationContext]) {
        let headerTypes = firstPartyHosts(with: additionalFirstPartyHosts)
            .tracingHeaderTypes(for: request.url)

        guard !headerTypes.isEmpty else {
            return (request, [])
        }

        let networkContext = self.networkContextProvider.currentNetworkContext
        var request = request

        // TODO: RUM-13769 This code can be simplified since we never use more than one handler simultaneously.
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

    /// Captures values on the caller thread and dispatches the interception to the actor.
    ///
    /// This is `nonisolated` so that `currentRequest` and `startTime` are captured on the
    /// swizzler callback thread (for accurate timing), then the actor-isolated work is
    /// dispatched via `Task`.
    nonisolated func interceptTask(_ task: URLSessionTask, with instrumentationContexts: [RequestInstrumentationContext], additionalFirstPartyHosts: FirstPartyHosts?, trackingMode: TrackingMode) {
        // In response to https://github.com/DataDog/dd-sdk-ios/issues/1638 capture the current request object on the
        // caller thread and freeze its attributes through `ImmutableRequest`. This is to avoid changing the request
        // object from multiple threads:
        guard let currentRequest = task.currentRequest else {
            return
        }
        let request = ImmutableRequest(request: currentRequest)

        // Capture start time before crossing the actor boundary for more accurate timing.
        let startTime = Date()

        Task { [weak self] in
            await self?.recordInterception(
                task: task,
                request: request,
                startTime: startTime,
                instrumentationContexts: instrumentationContexts,
                additionalFirstPartyHosts: additionalFirstPartyHosts,
                trackingMode: trackingMode
            )
        }
    }

    /// Captures end time on the caller thread and dispatches metrics recording to the actor.
    nonisolated func taskDidFinishCollecting(_ task: URLSessionTask, metrics: URLSessionTaskMetrics) {
        Task { [weak self] in
            await self?.recordMetrics(task: task, metrics: metrics)
        }
    }

    /// Captures response data and dispatches to the actor.
    nonisolated func taskDidReceive(_ task: URLSessionTask, data: Data) {
        Task { [weak self] in
            await self?.recordData(task: task, data: data)
        }
    }

    /// Captures end time on the caller thread and dispatches completion recording to the actor.
    nonisolated func taskDidComplete(_ task: URLSessionTask, error: Error?) {
        let endTime = Date()
        Task { [weak self] in
            await self?.recordCompletion(task: task, error: error, endTime: endTime)
        }
    }

    /// Captures end time on the caller thread and dispatches state change recording to the actor.
    nonisolated func taskDidChangeToState(_ task: URLSessionTask, state: Int) {
        let endTime = Date()
        Task { [weak self] in
            await self?.recordStateChange(task: task, state: state, endTime: endTime)
        }
    }

    nonisolated private func firstPartyHosts(with additionalFirstPartyHosts: FirstPartyHosts?) -> FirstPartyHosts {
        handlers.reduce(.init()) { $0 + $1.firstPartyHosts } + additionalFirstPartyHosts
    }
}

// MARK: - Actor-isolated interception management

extension NetworkInstrumentationFeature {
    /// Records a new task interception. Actor-isolated to protect `interceptions` dictionary.
    private func recordInterception(
        task: URLSessionTask,
        request: ImmutableRequest,
        startTime: Date,
        instrumentationContexts: [RequestInstrumentationContext],
        additionalFirstPartyHosts: FirstPartyHosts?,
        trackingMode: TrackingMode
    ) {
        let firstPartyHosts = self.firstPartyHosts(with: additionalFirstPartyHosts)

        // Check if interception already exists for this task
        let isNewInterception = interceptions[task] == nil

        // In dual-mode (automatic + registered delegate), prevent automatic mode from overriding registered delegate mode
        // Registered delegate mode provides more detailed tracking, so it takes priority
        if let existingInterception = interceptions[task],
           existingInterception.trackingMode == .registeredDelegate && trackingMode == .automatic {
            return
        }

        let interception = interceptions[task] ??
            URLSessionTaskInterception(
                request: request,
                isFirstParty: firstPartyHosts.isFirstParty(url: request.url),
                trackingMode: trackingMode
            )

        interception.register(request: request)

        // Capture approximate start time for all modes
        // This enables Trace to work in automatic mode (where `URLSessionTaskMetrics` are unavailable)
        if interception.startDate == nil {
            interception.register(startDate: startTime)
        }

        if let traceContext = instrumentationContexts.compactMap({ $0.traceContext }).first {
            // ^ If multiple trace contexts were injected (one per each handler) take the first one. This mimics the implicit
            // behaviour from before RUM-3470.
            interception.register(trace: traceContext)
        }

        if let origin = request.ddOriginHeaderValue {
            interception.register(origin: origin)
        }

        interceptions[task] = interception

        // Only notify handlers when the interception is first created, not when it's reused
        // This prevents double notifications when both automatic and registered delegate modes are enabled
        if isNewInterception {
            handlers
                .forEach {
                    $0.interceptionDidStart(
                        interception: interception,
                        capturedStates: instrumentationContexts.compactMap({ $0.capturedState })
                    )
                }
        }
    }

    /// Records metrics for a task. Actor-isolated to protect `interceptions` dictionary.
    private func recordMetrics(task: URLSessionTask, metrics: URLSessionTaskMetrics) {
        guard let interception = interceptions[task] else {
            return
        }

        let resourceMetrics = ResourceMetrics(taskMetrics: metrics)
        interception.register(metrics: resourceMetrics)

        // Populate interception.responseSize for registered delegate mode
        captureResponseSize(for: interception, from: task, metrics: resourceMetrics)

        // Don't finish yet if task has completion handler - let completion handler finish after capturing data
        if interception.isDone && !task.dd.hasCompletion {
            // Registered delegate mode: `endDate` is `nil` because `URLSessionTaskMetrics` provides accurate timing
            finish(task: task, interception: interception, endDate: nil)
        }
    }

    /// Records received data for a task. Actor-isolated to protect `interceptions` dictionary.
    private func recordData(task: URLSessionTask, data: Data) {
        guard let interception = interceptions[task] else {
            return
        }
        interception.register(nextData: data)
    }

    /// Records task completion. Actor-isolated to protect `interceptions` dictionary.
    private func recordCompletion(task: URLSessionTask, error: Error?, endTime: Date) {
        guard let interception = interceptions[task] else {
            return
        }

        interception.register(
            response: task.response,
            error: error
        )

        if interception.isDone {
            finish(task: task, interception: interception, endDate: endTime)
        }
    }

    /// Records task state change. Actor-isolated to protect `interceptions` dictionary.
    private func recordStateChange(task: URLSessionTask, state: Int, endTime: Date) {
        guard let interception = interceptions[task] else {
            return
        }

        // Register the state change
        interception.register(state: state)

        // When task completes, also register the response/error if not already done
        // This ensures completion is recorded even for async/await or delegate-less tasks without completion handlers
        // Note: We wait for .completed rather than .canceling because task.error is only populated
        // after the task fully transitions to .completed state
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
            finish(task: task, interception: interception, endDate: endTime)
        }
    }

    private func finish(task: URLSessionTask, interception: URLSessionTaskInterception, endDate: Date?) {
        // Register `endDate` if provided.
        // Note: in registered delegate mode, `endDate` is `nil` because `URLSessionTaskMetrics` provides accurate timing.
        if let endDate {
            interception.register(endDate: endDate)
        }

        handlers.forEach { $0.interceptionDidComplete(interception: interception) }
        interceptions[task] = nil
    }

    /// Captures response size for an interception.
    ///
    /// In registered delegate mode, prefers the response size from URLSessionTaskMetrics.
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

        let metricsSize = metrics.responseBodySize?.decoded ?? 0
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
    nonisolated func flush() {
        let sem = DispatchSemaphore(value: 0)
        Task {
            await _drain()
            sem.signal()
        }
        sem.wait()
    }

    private func _drain() {
        // No-op: reaching this method means all previously enqueued
        // actor work has been processed.
    }
}
