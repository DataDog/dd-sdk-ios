/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
@_spi(Internal)
import DatadogInternal

internal extension RUMMethod {
    init(httpMethod: String?) {
        if let someMethod = httpMethod,
           let someCase = RUMMethod(rawValue: someMethod.uppercased()) {
            self = someCase
        } else {
            self = .get
        }
    }
}

internal extension RUMResourceType {
    /// Determines the `RUMResourceType` based on a given `URLRequest`.
    /// Returns `nil` if the kind cannot be determined with only `URLRequest` and `HTTPURLRespones` is needed.
    ///
    /// - Parameters:
    ///   - request: the `URLRequest` for the resource.
    init?(request: URLRequest) {
        let nativeHTTPMethods: Set<String> = ["POST", "PUT", "DELETE"]

        if let requestMethod = request.httpMethod?.uppercased(),
            nativeHTTPMethods.contains(requestMethod) {
            self = .native
        } else {
            return nil
        }
    }

    /// Determines the `RUMResourceType` based on the MIME type of given `HTTPURLResponse`.
    /// Defaults to `.other`.
    ///
    /// - Parameters:
    ///   - response: the `HTTPURLResponse` of the resource.
    init(response: HTTPURLResponse) {
        if let mimeType = response.mimeType {
            let components = mimeType.split(separator: "/")
            let type = components.first?.lowercased()
            let subtype = components.last?.split(separator: ";").first?.lowercased()

            switch (type, subtype) {
            case ("image", _): self = .image
            case ("video", _), ("audio", _): self = .media
            case ("font", _): self = .font
            case ("text", "css"): self = .css
            case ("text", "javascript"): self = .js
            default: self = .native
            }
        } else {
            self = .native
        }
    }
}

internal typealias RUMErrorSourceType = RUMErrorEvent.Error.SourceType

internal extension RUMErrorSourceType {
    static func extract(from attributes: inout [AttributeKey: AttributeValue]) -> RUMErrorSourceType? {
        return attributes
            .removeValue(forKey: CrossPlatformAttributes.errorSourceType)?
            .dd.decode()
            .flatMap {
                RUMErrorEvent.Error.SourceType(rawValue: $0)
            }
    }
}

internal enum RUMInternalErrorSource: String, Decodable {
    case custom
    case source
    case network
    case webview
    case logger
    case console

    init(_ errorSource: RUMErrorSource) {
        switch errorSource {
        case .custom: self = .custom
        case .source: self = .source
        case .network: self = .network
        case .webview: self = .webview
        case .console: self = .console
        case .logger: self = .logger
        }
    }
}

/// A mobile-specific category of the error. It provides a high-level grouping for different types of errors.
internal typealias RUMErrorCategory = RUMErrorEvent.Error.Category

/// Exposes monitor state for readers that operate outside the `RUMCommand` pipeline
/// (e.g. the timer-driven `TimeseriesSessionCollector`), which otherwise have no access to
/// `command.globalAttributes`, the scope tree's active view, or `RUMSessionScope`'s own session
/// lifetime rules.
internal protocol RUMActiveContextReader: AnyObject {
    /// The current global attributes set through `addAttribute(forKey:value:)` / `addAttributes(_:)`.
    /// Conformers must guarantee this is safe to read from any thread.
    var globalAttributes: [AttributeKey: AttributeValue] { get }
    /// The currently active view, if any. Conformers must guarantee this is safe to read from any thread.
    var activeView: (id: String?, path: String?, name: String?) { get }
    /// The most recently observed `DatadogContext.hasReplay` value, or `nil` if no command has been
    /// processed yet. Conformers must guarantee this is safe to read from any thread.
    var hasReplay: Bool? { get }
    /// Whether the session identified by `sessionID` has expired (exceeded its max duration or inactivity
    /// timeout) as of `date`, evaluated against a live, single source of truth instead of a shadow copy of
    /// that state. Returns `false` if `sessionID` doesn't match the currently active session (e.g. a session
    /// transition is still propagating), so callers should treat that as "skip the check for now", not
    /// "not expired". Conformers must guarantee this is safe to call from any thread.
    func isSessionExpired(sessionID: String, at date: Date) -> Bool
}

internal class Monitor: RUMCommandSubscriber {
    /// RUM feature scope.
    var rumContextHandoffOwner: RUMContextHandoff.Owner? {
        (featureScope as? RUMContextHandoffOwnerProviding)?.rumContextHandoffOwner
    }

    let featureScope: FeatureScope
    let applicationScope: RUMApplicationScope
    let dateProvider: DateProvider

    @ReadWriteLock
    private(set) var debugging: RUMDebugging? = nil

    @ReadWriteLock
    private var attributes: [AttributeKey: AttributeValue] = [:]

    @ReadWriteLock
    private var activeViewSnapshot: (id: String?, path: String?, name: String?) = (nil, nil, nil)

    @ReadWriteLock
    private var representativeRUMContextSnapshot: RUMCoreContext?

    @ReadWriteLock
    private var rumContextSnapshotsByScene: [RUMSceneIdentifier: RUMCoreContext] = [:]

    @ReadWriteLock
    private var sessionActivitySnapshot: (sessionID: String?, sessionStartTime: Date?, lastInteractionTime: Date?) = (nil, nil, nil)

    @ReadWriteLock
    private var hasReplaySnapshot: Bool? = nil

    /// Updates the replay state snapshot exposed through `RUMActiveContextReader`. Called both from
    /// `process(command:)` and from `HasReplayMessageReceiver`, since Session Replay toggles `hasReplay`
    /// through the core context bus, not through a `RUMCommand`.
    func update(hasReplay: Bool?) {
        hasReplaySnapshot = hasReplay
    }

    private let fatalErrorContext: FatalErrorContextNotifying
    private let rumUUIDGenerator: RUMUUIDGenerator
    private let telemetry: Telemetry

    #if os(iOS)
    /// Per-scene navigation owner for future explicitly targeted manual views.
    /// Kept weak so the monitor cannot extend instrumentation lifetime.
    private weak var sceneTargetedManualViewHandler: (any RUMSceneTargetedManualViewHandling)?
    #endif

    init(
        dependencies: RUMScopeDependencies,
        dateProvider: DateProvider
    ) {
        self.featureScope = dependencies.featureScope
        self.applicationScope = RUMApplicationScope(dependencies: dependencies)
        self.dateProvider = dateProvider
        self.fatalErrorContext = dependencies.fatalErrorContext
        self.rumUUIDGenerator = dependencies.rumUUIDGenerator
        self.telemetry = dependencies.telemetry
    }

    #if os(iOS)
    func bind(
        sceneTargetedManualViewHandler: any RUMSceneTargetedManualViewHandling
    ) {
        self.sceneTargetedManualViewHandler = sceneTargetedManualViewHandler
    }
    #endif

    func process(command: RUMCommand) {
        guard command.target != .none else {
            (command as? RUMAddCurrentViewErrorCommand)?.completionHandler()
            return
        }
        var command = command
        command.globalAttributes = attributes
        // process command in event context
        featureScope.eventWriteContext { [weak self] context, writer in
            guard let self = self else {
                (command as? RUMAddCurrentViewErrorCommand)?.completionHandler()
                return
            }

            let transformedCommand = self.transform(command: command)
            let previousSessionID = self.sessionActivitySnapshot.sessionID

            _ = self.applicationScope.process(command: transformedCommand, context: context, writer: writer)

            if self.applicationScope.dependencies.timeseriesCollector != nil {
                let currentSessionID = self.applicationScope.activeSession?.sessionUUID.toRUMDataFormat
                // If a session boundary was just crossed, `context.hasReplay` still reflects the previous
                // session's Session Replay decision (SR hasn't recomputed it for the new session yet), so
                // carrying it over would leak stale replay state into the new session.
                let didStartNewSession = previousSessionID != nil && currentSessionID != previousSessionID
                self.update(hasReplay: didStartNewSession ? nil : context.hasReplay)
            }

            if let debugging = self.debugging {
                debugging.debug(applicationScope: self.applicationScope)
            }

            if let activeSession = self.applicationScope.activeSession {
                let representativeView = activeSession.activeView
                let viewContext = representativeView?.context ?? activeSession.context
                self.activeViewSnapshot = (
                    id: viewContext.activeViewID?.toRUMDataFormat,
                    path: viewContext.activeViewPath,
                    name: viewContext.activeViewName
                )
                self.sessionActivitySnapshot = (
                    sessionID: activeSession.sessionUUID.toRUMDataFormat,
                    sessionStartTime: activeSession.sessionStartTime,
                    lastInteractionTime: activeSession.lastInteractionTime
                )
                self.representativeRUMContextSnapshot = self.makeCoreContext(
                    session: activeSession,
                    view: representativeView
                )

                var contextsByScene: [RUMSceneIdentifier: RUMCoreContext] = [:]
                for view in activeSession.viewScopes where view.isActiveView {
                    if let sceneIdentifier = view.sceneIdentifier {
                        contextsByScene[sceneIdentifier] = self.makeCoreContext(
                            session: activeSession,
                            view: view
                        )
                    }
                }
                self.rumContextSnapshotsByScene = contextsByScene
            } else {
                self.activeViewSnapshot = (nil, nil, nil)
                self.sessionActivitySnapshot = (nil, nil, nil)
                self.representativeRUMContextSnapshot = nil
                self.rumContextSnapshotsByScene = [:]
            }
        }

        // update the core context with rum context
        featureScope.set(
            context: { [weak self] () -> RUMCoreContext? in
                guard let self = self else {
                    return nil
                }

                guard let activeSession = self.applicationScope.activeSession else {
                    return nil
                }

                let activeViewScope = activeSession.activeView
                let context = activeViewScope?.context ?? activeSession.context

                return RUMCoreContext(
                    applicationID: context.rumApplicationID,
                    sessionID: context.sessionID.toRUMDataFormat,
                    sessionSampler: activeSession.sampler,
                    viewID: context.activeViewID?.toRUMDataFormat,
                    userActionID: context.activeUserActionID?.toRUMDataFormat,
                    viewServerTimeOffset: activeViewScope?.serverTimeOffset,
                    viewPath: context.activeViewPath,
                    viewName: context.activeViewName
                )
            }
        )
    }

    private func makeCoreContext(
        session: RUMSessionScope,
        view: RUMViewScope?
    ) -> RUMCoreContext {
        let context = view?.context ?? session.context
        return RUMCoreContext(
            applicationID: context.rumApplicationID,
            sessionID: context.sessionID.toRUMDataFormat,
            sessionSampler: session.sampler,
            viewID: context.activeViewID?.toRUMDataFormat,
            userActionID: context.activeUserActionID?.toRUMDataFormat,
            viewServerTimeOffset: view?.serverTimeOffset,
            viewPath: context.activeViewPath,
            viewName: context.activeViewName
        )
    }

    // TODO: RUMM-896
    // transform() is extracted from process since process() cannot be tested currently
    // once we can mock ApplicationScope, we can test process()
    // then we can remove transform()
    //
    // NOTE: transform() calls self.rumAttributes outside of queue
    // therefore it should be removed once process() is testable
    func transform(command: RUMCommand) -> RUMCommand {
        var mutableCommand = command

        if let customTimestampInMilliseconds: Int64 = mutableCommand.attributes.removeValue(forKey: CrossPlatformAttributes.timestampInMilliseconds)?.dd.decode() {
            let customTimeInterval = TimeInterval.ddFromMilliseconds( customTimestampInMilliseconds)
            mutableCommand.time = Date(timeIntervalSince1970: customTimeInterval)
        }

        return mutableCommand
    }

    private func didUpdateAttributes() {
        fatalErrorContext.globalAttributes = attributes
    }
}

extension Monitor: RUMActiveContextReader {
    var globalAttributes: [AttributeKey: AttributeValue] { attributes }
    var activeView: (id: String?, path: String?, name: String?) { activeViewSnapshot }
    var hasReplay: Bool? { hasReplaySnapshot }

    func isSessionExpired(sessionID: String, at date: Date) -> Bool {
        let activity = sessionActivitySnapshot
        guard activity.sessionID == sessionID,
              let sessionStartTime = activity.sessionStartTime,
              let lastInteractionTime = activity.lastInteractionTime else {
            return false
        }
        return RUMSessionScope.hasExpired(sessionStartTime: sessionStartTime, currentTime: date)
            || RUMSessionScope.hasTimedOut(lastInteractionTime: lastInteractionTime, currentTime: date)
    }
}

extension Monitor: RUMContextSnapshotProviding {
    func rumContextSnapshot(for target: RUMCommandTarget) -> RUMCoreContext? {
        switch target {
        case .none:
            return nil
        case .scene(let sceneIdentifier):
            return rumContextSnapshotsByScene[sceneIdentifier]
        case .view(let viewID):
            return rumContextSnapshotsByScene.values.first {
                $0.viewID == viewID.toRUMDataFormat
            }
        case .processRepresentative, .allActiveViews:
            return representativeRUMContextSnapshot
        }
    }

    func rumContextSnapshot(for target: RUMCommandTarget, at date: Date?) -> RUMCoreContext? {
        let date = date ?? dateProvider.now
        guard let snapshot = rumContextSnapshot(for: target) else {
            return nil
        }
        let activity = sessionActivitySnapshot
        // Snapshot dictionaries and session activity use independent locks.
        // If a boundary is being published between these reads, fail closed
        // instead of returning a context from the previous session.
        guard activity.sessionID == snapshot.sessionID,
              let sessionStartTime = activity.sessionStartTime,
              let lastInteractionTime = activity.lastInteractionTime,
              !RUMSessionScope.hasExpired(sessionStartTime: sessionStartTime, currentTime: date),
              !RUMSessionScope.hasTimedOut(lastInteractionTime: lastInteractionTime, currentTime: date) else {
            return nil
        }
        return snapshot
    }
}

/// Declares `Monitor` conformance to public `RUMMonitorProtocol`.
extension Monitor: RUMMonitorProtocol {
    // MARK: - attributes

    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        attributes[key] = value
        self.didUpdateAttributes()
    }

    func addAttributes(_ attributes: [AttributeKey: AttributeValue]) {
        self.attributes.merge(attributes) { $1 }
        self.didUpdateAttributes()
    }

    func removeAttribute(forKey key: AttributeKey) {
        attributes[key] = nil
        self.didUpdateAttributes()
    }

    func removeAttributes(forKeys keys: [AttributeKey]) {
        _attributes.mutate { attributes in
            keys.forEach { key in attributes.removeValue(forKey: key) }
        }
        self.didUpdateAttributes()
    }

    // MARK: - session

    func currentSessionID(completion: @escaping (String?) -> Void) {
        // Synchronise it through the context thread to make sure we return the correct
        // sessionID after all other events have been processed (also on the context thread):
        featureScope.context { [weak self] _ in
            guard let activeSession = self?.applicationScope.activeSession else {
                completion(nil)
                return
            }

            var sessionIdValue: String? = nil
            if activeSession.sampler.isSampled, activeSession.sessionUUID != .nullUUID {
                sessionIdValue = activeSession.sessionUUID.toRUMDataFormat
            }

            completion(sessionIdValue)
        }
    }

    func stopSession() {
        process(command: RUMStopSessionCommand(time: dateProvider.now))
    }

    func reportAppFullyDisplayed() {
        process(command: RUMTimeToFullDisplayCommand(time: dateProvider.now))
    }

    // MARK: - errors

    func addError(message: String, type: String?, stack: String?, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue], file: StaticString?, line: UInt?) {
        addError(message: message, type: type, stack: stack, source: source, attributes: attributes, file: file, line: line, explicitTarget: nil)
    }

    func addError(
        message: String,
        type: String?,
        stack: String?,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        file: StaticString?,
        line: UInt?,
        explicitTarget: RUMCommandTarget?
    ) {
        let stack: String? = stack ?? {
            if let file = file,
               let fileName = "\(file)".split(separator: "/").last,
               let line = line {
                return "\(fileName):\(line)"
            }
            return nil
        }()
        processCurrentViewError(
            RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                message: message,
                type: type,
                stack: stack,
                source: RUMInternalErrorSource(source),
                globalAttributes: self.attributes,
                attributes: attributes,
                completionHandler: NOPCompletionHandler
            ),
            explicitTarget: explicitTarget
        )
    }

    func addError(error: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]) {
        addError(error: error, source: source, attributes: attributes, explicitTarget: nil)
    }

    func addError(error: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue], explicitTarget: RUMCommandTarget?) {
        processCurrentViewError(
            RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                error: error,
                source: RUMInternalErrorSource(source),
                globalAttributes: self.attributes,
                attributes: attributes,
                completionHandler: NOPCompletionHandler
            ),
            explicitTarget: explicitTarget
        )
    }

    // MARK: - resources

    func startResource(resourceKey: String, request: URLRequest, attributes: [AttributeKey: AttributeValue]) {
        startResource(resourceKey: resourceKey, request: request, attributes: attributes, explicitTarget: nil)
    }

    func startResource(
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    ) {
        var command = RUMStartResourceCommand(
            resourceKey: resourceKey,
            time: dateProvider.now,
            globalAttributes: self.attributes,
            attributes: attributes,
            url: request.url?.absoluteString ?? "unknown_url",
            httpMethod: RUMMethod(httpMethod: request.httpMethod),
            kind: RUMResourceType(request: request),
            spanContext: nil
        )
        command.target = currentExecutionTarget
        command.explicitTarget = explicitTarget
        process(
            command: command
        )
    }

    func startResource(resourceKey: String, url: URL, attributes: [AttributeKey: AttributeValue]) {
        startResource(resourceKey: resourceKey, url: url, attributes: attributes, explicitTarget: nil)
    }

    func startResource(
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    ) {
        var command = RUMStartResourceCommand(
            resourceKey: resourceKey,
            time: dateProvider.now,
            globalAttributes: self.attributes,
            attributes: attributes,
            url: url.absoluteString,
            httpMethod: .get,
            kind: nil,
            spanContext: nil
        )
        command.target = currentExecutionTarget
        command.explicitTarget = explicitTarget
        process(
            command: command
        )
    }

    func startResource(resourceKey: String, httpMethod: RUMMethod, urlString: String, attributes: [AttributeKey: AttributeValue]) {
        startResource(resourceKey: resourceKey, httpMethod: httpMethod, urlString: urlString, attributes: attributes, explicitTarget: nil)
    }

    func startResource(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    ) {
        var command = RUMStartResourceCommand(
            resourceKey: resourceKey,
            time: dateProvider.now,
            globalAttributes: self.attributes,
            attributes: attributes,
            url: urlString,
            httpMethod: httpMethod,
            kind: nil,
            spanContext: nil
        )
        command.target = currentExecutionTarget
        command.explicitTarget = explicitTarget
        process(
            command: command
        )
    }

    func addResourceMetrics(resourceKey: String, metrics: URLSessionTaskMetrics, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddResourceMetricsCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                globalAttributes: self.attributes,
                attributes: attributes,
                metrics: ResourceMetrics(taskMetrics: metrics)
            )
        )
    }

    func stopResource(resourceKey: String, response: URLResponse, size: Int64?, attributes: [AttributeKey: AttributeValue]) {
        let resourceKind: RUMResourceType
        var statusCode: Int?

        if let response = response as? HTTPURLResponse {
            resourceKind = RUMResourceType(response: response)
            statusCode = response.statusCode
        } else {
            resourceKind = .xhr
        }

        process(
            command: RUMStopResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                globalAttributes: self.attributes,
                attributes: attributes,
                kind: resourceKind,
                httpStatusCode: statusCode,
                size: size
            )
        )
    }

    func stopResource(resourceKey: String, statusCode: Int?, kind: RUMResourceType, size: Int64?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                globalAttributes: self.attributes,
                attributes: attributes,
                kind: kind,
                httpStatusCode: statusCode,
                size: size
            )
        )
    }

    func stopResourceWithError(resourceKey: String, error: Error, response: URLResponse?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                error: error,
                source: .network,
                httpStatusCode: (response as? HTTPURLResponse)?.statusCode,
                globalAttributes: self.attributes,
                attributes: attributes
            )
        )
    }

    func stopResourceWithError(resourceKey: String, message: String, type: String?, response: URLResponse?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                message: message,
                type: type,
                source: .network,
                httpStatusCode: (response as? HTTPURLResponse)?.statusCode,
                globalAttributes: self.attributes,
                attributes: attributes
            )
        )
    }

    // MARK: - actions

    func addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue]) {
        addAction(
            type: type,
            name: name,
            attributes: attributes,
            explicitTarget: nil
        )
    }

    func addAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    ) {
        var command = RUMAddUserActionCommand(
            time: dateProvider.now,
            globalAttributes: self.attributes,
            attributes: attributes,
            instrumentation: .manual,
            actionType: type,
            name: name
        )
        command.target = currentExecutionTarget
        command.explicitTarget = explicitTarget
        process(
            command: command
        )
    }

    func startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue]) {
        startAction(type: type, name: name, attributes: attributes, explicitTarget: nil)
    }

    func startAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    ) {
        var command = RUMStartUserActionCommand(
            time: dateProvider.now,
            globalAttributes: self.attributes,
            attributes: attributes,
            instrumentation: .manual,
            actionType: type,
            name: name
        )
        command.target = currentExecutionTarget
        command.explicitTarget = explicitTarget
        process(
            command: command
        )
    }

    func stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue]) {
        stopAction(type: type, name: name, attributes: attributes, explicitTarget: nil)
    }

    func stopAction(
        type: RUMActionType,
        name: String?,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    ) {
        var command = RUMStopUserActionCommand(
            time: dateProvider.now,
            globalAttributes: self.attributes,
            attributes: attributes,
            actionType: type,
            name: name
        )
        command.target = currentExecutionTarget
        command.explicitTarget = explicitTarget
        process(
            command: command
        )
    }

    // MARK: - feature flags

    func addFeatureFlagEvaluation(name: String, value: Encodable) {
        var command = RUMAddFeatureFlagEvaluationCommand(
            time: dateProvider.now,
            name: name,
            value: value
        )
        command.target = currentExecutionTarget
        process(
            command: command
        )
    }

    // MARK: - Feature Operations

    func startOperation(name: String, operationKey: String?, attributes: [AttributeKey: AttributeValue], options: OperationOptions?) {
        startOperation(
            name: name,
            operationKey: operationKey,
            attributes: attributes,
            options: options,
            explicitTarget: nil
        )
    }

    func startOperation(
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue],
        options: OperationOptions?,
        explicitTarget: RUMCommandTarget?
    ) {
        DD.logger.debug("Feature Operation `\(name)`\(instanceSuffix(operationKey)) started")

        telemetry.usage(event: .addOperationStepVital(.init(actionType: .start)))

        processOperationStep(
            RUMOperationStepVitalCommand(
                vitalId: rumUUIDGenerator.generateUnique().toRUMDataFormat,
                name: name,
                operationKey: operationKey,
                stepType: .start,
                failureReason: nil,
                options: options,
                time: dateProvider.now,
                attributes: attributes
            ),
            explicitTarget: explicitTarget
        )
    }

    func startFeatureOperation(name: String, operationKey: String?, attributes: [AttributeKey: AttributeValue]) {
        startOperation(name: name, operationKey: operationKey, attributes: attributes, options: nil)
    }

    func succeedOperation(name: String, operationKey: String?, attributes: [AttributeKey: AttributeValue]) {
        succeedOperation(
            name: name,
            operationKey: operationKey,
            attributes: attributes,
            explicitTarget: nil
        )
    }

    func succeedOperation(
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    ) {
        DD.logger.debug("Feature Operation `\(name)`\(instanceSuffix(operationKey)) successfully ended")

        telemetry.usage(event: .addOperationStepVital(.init(actionType: .succeed)))

        processOperationStep(
            RUMOperationStepVitalCommand(
                vitalId: rumUUIDGenerator.generateUnique().toRUMDataFormat,
                name: name,
                operationKey: operationKey,
                stepType: .end,
                failureReason: nil,
                time: dateProvider.now,
                attributes: attributes
            ),
            explicitTarget: explicitTarget
        )
    }

    func succeedFeatureOperation(name: String, operationKey: String?, attributes: [AttributeKey: AttributeValue]) {
        succeedOperation(name: name, operationKey: operationKey, attributes: attributes)
    }

    func failOperation(name: String, operationKey: String?, reason: RUMFeatureOperationFailureReason, attributes: [AttributeKey: AttributeValue]) {
        failOperation(
            name: name,
            operationKey: operationKey,
            reason: reason,
            attributes: attributes,
            explicitTarget: nil
        )
    }

    func failOperation(
        name: String,
        operationKey: String?,
        reason: RUMFeatureOperationFailureReason,
        attributes: [AttributeKey: AttributeValue],
        explicitTarget: RUMCommandTarget?
    ) {
        DD.logger.debug("Feature Operation `\(name)`\(instanceSuffix(operationKey)) unsuccessfully ended with the following failure reason: \(reason.rawValue)")

        telemetry.usage(event: .addOperationStepVital(.init(actionType: .fail)))

        processOperationStep(
            RUMOperationStepVitalCommand(
                vitalId: rumUUIDGenerator.generateUnique().toRUMDataFormat,
                name: name,
                operationKey: operationKey,
                stepType: .end,
                failureReason: reason,
                time: dateProvider.now,
                attributes: attributes
            ),
            explicitTarget: explicitTarget
        )
    }

    func failFeatureOperation(name: String, operationKey: String?, reason: RUMFeatureOperationFailureReason, attributes: [AttributeKey: AttributeValue]) {
        failOperation(name: name, operationKey: operationKey, reason: reason, attributes: attributes)
    }

    private func processOperationStep(
        _ operationStep: RUMOperationStepVitalCommand,
        explicitTarget: RUMCommandTarget?
    ) {
        var operationStep = operationStep
        operationStep.explicitTarget = explicitTarget
        operationStep.target = currentExecutionTarget
        process(command: operationStep)
    }

    private func processCurrentViewError(_ error: RUMAddCurrentViewErrorCommand, explicitTarget: RUMCommandTarget? = nil) {
        var error = error
        error.explicitTarget = explicitTarget
        error.target = currentExecutionTarget
        process(command: error)
    }

    private var currentExecutionSceneTarget: RUMCommandTarget {
        guard let handoff = RUMContextHandoff.current(for: rumContextHandoffOwner) else {
            return .processRepresentative
        }
        if let viewID = handoff.rumContext?.viewID,
           let sceneIdentifier = rumContextSnapshotsByScene.first(where: {
               $0.value.viewID == viewID
           })?.key {
            return .scene(sceneIdentifier)
        }
        if let sceneIdentifier = handoff.sceneIdentifier {
            return .scene(RUMSceneIdentifier(rawValue: sceneIdentifier))
        }
        return .processRepresentative
    }

    private func instanceSuffix(_ operationKey: String?) -> String {
        guard let operationKey = operationKey else {
            return ""
        }
        return " (instance `\(operationKey)`)"
    }

    // MARK: - debugging

    var debug: Bool {
        set {
            debugging = newValue ? RUMDebugging() : nil

            // Synchronise `debug(applicationScope:)` through the context thread to make sure it can safely
            // read `scopes` after all events have been processed (also on the context thread):
            featureScope.context { [weak self] _ in
                guard let self = self else {
                    return
                }
                self.debugging?.debug(applicationScope: self.applicationScope)
            }
        }
        get {
            debugging != nil
        }
    }

    // MARK: - Internal

    func addError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        completionHandler: @escaping CompletionHandler
    ) {
        addError(error: error, source: source, attributes: attributes, completionHandler: completionHandler, explicitTarget: nil)
    }

    func addError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        completionHandler: @escaping CompletionHandler,
        explicitTarget: RUMCommandTarget?
    ) {
        processCurrentViewError(
            RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                error: error,
                source: RUMInternalErrorSource(source),
                globalAttributes: self.attributes,
                attributes: attributes,
                completionHandler: completionHandler
            ),
            explicitTarget: explicitTarget
        )
    }
}

// MARK: - View

/// Declares `Monitor` conformance to public `RUMMonitorViewProtocol`.
extension Monitor: RUMMonitorViewProtocol {
    func addViewAttribute(forKey key: AttributeKey, value: AttributeValue) {
        var command = RUMAddViewAttributesCommand(
            time: dateProvider.now,
            attributes: [key: value]
        )
        command.target = currentExecutionTarget
        process(
            command: command
        )
    }

    func addViewAttributes(_ attributes: [AttributeKey: AttributeValue]) {
        var command = RUMAddViewAttributesCommand(
            time: dateProvider.now,
            attributes: attributes
        )
        command.target = currentExecutionTarget
        process(
            command: command
        )
    }

    func removeViewAttribute(forKey key: AttributeKey) {
        var command = RUMRemoveViewAttributesCommand(
            time: dateProvider.now,
            keysToRemove: [key]
        )
        command.target = currentExecutionTarget
        process(
            command: command
        )
    }

    func removeViewAttributes(forKeys keys: [AttributeKey]) {
        var command = RUMRemoveViewAttributesCommand(
            time: dateProvider.now,
            keysToRemove: keys
        )
        command.target = currentExecutionTarget
        process(
            command: command
        )
    }

    #if !os(watchOS)
    func startView(viewController: UIViewController, name: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier(viewController),
                name: name ?? viewController.canonicalClassName,
                path: viewController.canonicalClassName,
                globalAttributes: self.attributes,
                attributes: attributes,
                instrumentationType: .manual,
                target: sceneTarget(for: viewController)
            )
        )
    }

    func stopView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue]) {
        var command = RUMStopViewCommand(
                time: dateProvider.now,
                globalAttributes: self.attributes,
                attributes: attributes,
                identity: ViewIdentifier(viewController)
        )
        command.target = sceneTarget(for: viewController)
        process(command: command)
    }

    private func sceneTarget(for viewController: UIViewController) -> RUMCommandTarget {
        // Existing controller APIs accept calls from any thread. Keep background
        // callers on inferred routing without reading UIKit or waiting for main.
        guard Thread.isMainThread else {
            return currentExecutionSceneTarget
        }
        guard let identifier = viewController.viewIfLoaded?
            .window?
            .windowScene?
            .session
            .persistentIdentifier else {
            return currentExecutionSceneTarget
        }
        return .scene(RUMSceneIdentifier(rawValue: identifier))
    }
    #endif

    func startView(key: String, name: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier(key),
                name: name ?? key,
                path: key,
                globalAttributes: self.attributes,
                attributes: attributes,
                instrumentationType: .manual,
                target: currentExecutionSceneTarget
            )
        )
    }

    func stopView(key: String, attributes: [AttributeKey: AttributeValue]) {
        var command = RUMStopViewCommand(
            time: dateProvider.now,
            globalAttributes: self.attributes,
            attributes: attributes,
            identity: ViewIdentifier(key)
        )
        command.target = currentExecutionSceneTarget
        process(command: command)
    }

    func addTiming(name: String) {
        var command = RUMAddViewTimingCommand(
            time: dateProvider.now,
            globalAttributes: self.attributes,
            attributes: [:],
            timingName: name
        )
        command.target = currentExecutionTarget
        process(
            command: command
        )
    }

    func addViewLoadingTime(overwrite: Bool) {
        var command = RUMAddViewLoadingTime(
            time: dateProvider.now,
            globalAttributes: self.attributes,
            attributes: [:],
            overwrite: overwrite
        )
        command.target = currentExecutionTarget
        process(
            command: command
        )
    }
}

#if os(iOS)
extension Monitor: RUMErrorViewTargetHandling {}

extension Monitor: RUMResourceViewTargetHandling {}

extension Monitor: RUMActionViewTargetHandling {}

extension Monitor: RUMOperationViewTargetHandling {}

extension Monitor: RUMSceneTargetedManualViewHandling {
    func startView(
        key: String,
        name: String?,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier
    ) {
        sceneTargetedManualViewHandler?.startView(
            key: key,
            name: name,
            attributes: attributes,
            sceneIdentifier: sceneIdentifier
        )
    }

    func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue],
        sceneIdentifier: RUMSceneIdentifier
    ) {
        sceneTargetedManualViewHandler?.stopView(
            key: key,
            attributes: attributes,
            sceneIdentifier: sceneIdentifier
        )
    }
}
#endif

/// An internal interface of RUM monitor.
extension Monitor {
    /// Performs initial work in RUM monitor.
    func notifySDKInit() {
        process(
            command: RUMSDKInitCommand(time: dateProvider.now)
        )
    }

    func addError(
        message: String,
        type: String?,
        stack: String?,
        source: RUMInternalErrorSource,
        attributes: [AttributeKey: AttributeValue]
    ) {
        processCurrentViewError(
            RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                message: message,
                type: type,
                stack: stack,
                source: source,
                globalAttributes: self.attributes,
                attributes: attributes,
                completionHandler: NOPCompletionHandler
            )
        )
    }
}
