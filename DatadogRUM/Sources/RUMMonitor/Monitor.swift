/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
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
        }
    }
}

/// A mobile-specific category of the error. It provides a high-level grouping for different types of errors.
internal typealias RUMErrorCategory = RUMErrorEvent.Error.Category

internal final class Monitor: RUMCommandSubscriber, @unchecked Sendable {
    let featureScope: FeatureScope
    let dateProvider: DateProvider

    /// The scope tree. Mutated exclusively from the `for await` command loop.
    /// Read from `currentSessionID` outside the loop (acknowledged benign race
    /// for a callback that is already eventually-consistent).
    let scopes: RUMApplicationScope

    let fatalErrorContext: FatalErrorContextNotifying
    let rumUUIDGenerator: RUMUUIDGenerator
    let telemetry: Telemetry

    /// Global attributes — only mutated inside the processing loop via
    /// `RUMGlobalAttributeCommand`. No lock needed.
    private var attributes: [AttributeKey: AttributeValue] = [:]

    /// Debugging overlay — only mutated inside the processing loop via
    /// `RUMSetDebugCommand`. No lock needed.
    private var debugging: RUMDebugging?

    /// Continuation for the command stream. Commands are yielded from any
    /// thread and processed sequentially by the `for await` loop.
    private let commandContinuation: AsyncStream<RUMCommand>.Continuation

    init(
        dependencies: RUMScopeDependencies,
        dateProvider: DateProvider
    ) {
        self.featureScope = dependencies.featureScope
        self.scopes = RUMApplicationScope(dependencies: dependencies)
        self.dateProvider = dateProvider
        self.fatalErrorContext = dependencies.fatalErrorContext
        self.rumUUIDGenerator = dependencies.rumUUIDGenerator
        self.telemetry = dependencies.telemetry

        let (stream, continuation) = AsyncStream<RUMCommand>.makeStream()
        self.commandContinuation = continuation

        Task { [weak self] in
            for await command in stream {
                guard let self else { break }
                await self.processFromStream(command: command)
            }
        }
    }

    deinit {
        commandContinuation.finish()
    }

    /// Awaits processing of all commands currently in the stream.
    /// Used by tests to ensure deterministic ordering.
    func flush() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            commandContinuation.yield(
                RUMFlushCommand(time: Date(), continuation: continuation)
            )
        }
    }

    // MARK: - RUMCommandSubscriber

    /// Yields the command to the async stream for FIFO processing.
    func process(command: RUMCommand) {
        commandContinuation.yield(command)
    }

    // MARK: - Stream Processing

    /// Processes a single command from the stream. Called sequentially by the
    /// `for await` loop — no lock needed because only one command is in-flight
    /// at a time.
    private func processFromStream(command: RUMCommand) async {
        // Flush sentinel — resume the continuation and return.
        if let flush = command as? RUMFlushCommand {
            flush.continuation.resume()
            return
        }

        // Global attribute mutation — apply and sync to fatal-error context.
        if let attrCmd = command as? RUMGlobalAttributeCommand {
            attrCmd.apply(to: &attributes)
            fatalErrorContext.globalAttributes = attributes
            return
        }

        // Debug toggle — create or destroy the debugging overlay.
        if let debugCmd = command as? RUMSetDebugCommand {
            debugging = debugCmd.enabled ? RUMDebugging() : nil
            if let debugging {
                debugging.debug(applicationScope: scopes)
            }
            return
        }

        // Regular command — snapshot global attributes, then process.
        var mutableCommand = transform(command: command)
        mutableCommand.globalAttributes = attributes

        guard let (context, writer) = await featureScope.eventWriteContext() else { return }
        _ = scopes.process(command: mutableCommand, context: context, writer: writer)

        if let debugging {
            debugging.debug(applicationScope: scopes)
        }

        updateCoreContext()
    }

    /// Computes the current RUM context from the scope tree and publishes it
    /// to the core so other features (Logs, Traces, etc.) can read it.
    private func updateCoreContext() {
        let context = scopes.activeSession?.viewScopes.last?.context ??
                        scopes.activeSession?.context ??
                        scopes.context

        guard context.sessionID != .nullUUID else {
            featureScope.set(context: { nil as RUMCoreContext? })
            return
        }

        let rumContext = RUMCoreContext(
            applicationID: context.rumApplicationID,
            sessionID: context.sessionID.rawValue.uuidString.lowercased(),
            viewID: context.activeViewID?.rawValue.uuidString.lowercased(),
            userActionID: context.activeUserActionID?.rawValue.uuidString.lowercased(),
            viewServerTimeOffset: scopes.activeSession?.viewScopes.last?.serverTimeOffset
        )
        featureScope.set(context: { rumContext })
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
}

/// Declares `Monitor` conformance to public `RUMMonitorProtocol`.
extension Monitor: RUMMonitorProtocol {
    // MARK: - attributes

    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        process(command: RUMGlobalAttributeCommand(time: dateProvider.now, mutation: .set(key: key, value: value)))
    }

    func addAttributes(_ attributes: [AttributeKey: AttributeValue]) {
        process(command: RUMGlobalAttributeCommand(time: dateProvider.now, mutation: .setMultiple(attributes)))
    }

    func removeAttribute(forKey key: AttributeKey) {
        process(command: RUMGlobalAttributeCommand(time: dateProvider.now, mutation: .remove(key: key)))
    }

    func removeAttributes(forKeys keys: [AttributeKey]) {
        process(command: RUMGlobalAttributeCommand(time: dateProvider.now, mutation: .removeMultiple(keys: keys)))
    }

    // MARK: - session

    func currentSessionID(completion: @escaping @Sendable (String?) -> Void) {
        Task { [weak self] in
            _ = await self?.featureScope.context()
            guard let sessionId = self?.scopes.activeSession?.sessionUUID else {
                completion(nil)
                return
            }

            var sessionIdValue: String? = nil
            if sessionId != RUMUUID.nullUUID {
                sessionIdValue = sessionId.rawValue.uuidString
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
        let stack: String? = stack ?? {
            if let file = file,
               let fileName = "\(file)".split(separator: "/").last,
               let line = line {
                return "\(fileName):\(line)"
            }
            return nil
        }()
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                message: message,
                type: type,
                stack: stack,
                source: RUMInternalErrorSource(source),
                attributes: attributes,
                completionHandler: NOPCompletionHandler
            )
        )
    }

    func addError(error: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                error: error,
                source: RUMInternalErrorSource(source),
                attributes: attributes,
                completionHandler: NOPCompletionHandler
            )
        )
    }

    // MARK: - resources

    func startResource(resourceKey: String, request: URLRequest, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                url: request.url?.absoluteString ?? "unknown_url",
                httpMethod: RUMMethod(httpMethod: request.httpMethod),
                kind: RUMResourceType(request: request),
                spanContext: nil
            )
        )
    }

    func startResource(resourceKey: String, url: URL, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                url: url.absoluteString,
                httpMethod: .get,
                kind: nil,
                spanContext: nil
            )
        )
    }

    func startResource(resourceKey: String, httpMethod: RUMMethod, urlString: String, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                url: urlString,
                httpMethod: httpMethod,
                kind: nil,
                spanContext: nil
            )
        )
    }

    func addResourceMetrics(resourceKey: String, metrics: URLSessionTaskMetrics, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddResourceMetricsCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
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
                attributes: attributes
            )
        )
    }

    // MARK: - actions

    func addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddUserActionCommand(
                time: dateProvider.now,
                attributes: attributes,
                instrumentation: .manual,
                actionType: type,
                name: name
            )
        )
    }

    func startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartUserActionCommand(
                time: dateProvider.now,
                attributes: attributes,
                instrumentation: .manual,
                actionType: type,
                name: name
            )
        )
    }

    func stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopUserActionCommand(
                time: dateProvider.now,
                attributes: attributes,
                actionType: type,
                name: name
            )
        )
    }

    // MARK: - feature flags

    func addFeatureFlagEvaluation(name: String, value: AttributeValue) {
        process(
            command: RUMAddFeatureFlagEvaluationCommand(
                time: dateProvider.now,
                name: name,
                value: value
            )
        )
    }

    // MARK: - Feature Operations

    func startFeatureOperation(name: String, operationKey: String?, attributes: [AttributeKey: AttributeValue]) {
        DD.logger.debug("Feature Operation `\(name)`\(instanceSuffix(operationKey)) started")

        telemetry.send(telemetry: .usage(.init(event: .addOperationStepVital(.init(actionType: .start)))))

        process(
            command: RUMOperationStepVitalCommand(
                vitalId: rumUUIDGenerator.generateUnique().toRUMDataFormat,
                name: name,
                operationKey: operationKey,
                stepType: .start,
                failureReason: nil,
                time: dateProvider.now,
                attributes: attributes
            )
        )
    }

    func succeedFeatureOperation(name: String, operationKey: String?, attributes: [AttributeKey: AttributeValue]) {
        DD.logger.debug("Feature Operation `\(name)`\(instanceSuffix(operationKey)) successfully ended")

        telemetry.send(telemetry: .usage(.init(event: .addOperationStepVital(.init(actionType: .succeed)))))

        process(
            command: RUMOperationStepVitalCommand(
                vitalId: rumUUIDGenerator.generateUnique().toRUMDataFormat,
                name: name,
                operationKey: operationKey,
                stepType: .end,
                failureReason: nil,
                time: dateProvider.now,
                attributes: attributes
            )
        )
    }

    func failFeatureOperation(name: String, operationKey: String?, reason: RUMFeatureOperationFailureReason, attributes: [AttributeKey: AttributeValue]) {
        DD.logger.debug("Feature Operation `\(name)`\(instanceSuffix(operationKey)) unsuccessfully ended with the following failure reason: \(reason.rawValue)")

        telemetry.send(telemetry: .usage(.init(event: .addOperationStepVital(.init(actionType: .fail)))))

        process(
            command: RUMOperationStepVitalCommand(
                vitalId: rumUUIDGenerator.generateUnique().toRUMDataFormat,
                name: name,
                operationKey: operationKey,
                stepType: .end,
                failureReason: reason,
                time: dateProvider.now,
                attributes: attributes
            )
        )
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
            process(command: RUMSetDebugCommand(time: dateProvider.now, enabled: newValue))
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
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                error: error,
                source: RUMInternalErrorSource(source),
                attributes: attributes,
                completionHandler: completionHandler
            )
        )
    }
}

// MARK: - View

/// Declares `Monitor` conformance to public `RUMMonitorViewProtocol`.
extension Monitor: RUMMonitorViewProtocol {
    func addViewAttribute(forKey key: AttributeKey, value: AttributeValue) {
        process(
            command: RUMAddViewAttributesCommand(
                time: dateProvider.now,
                attributes: [key: value]
            )
        )
    }

    func addViewAttributes(_ attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddViewAttributesCommand(
                time: dateProvider.now,
                attributes: attributes
            )
        )
    }

    func removeViewAttribute(forKey key: AttributeKey) {
        process(
            command: RUMRemoveViewAttributesCommand(
                time: dateProvider.now,
                keysToRemove: [key]
            )
        )
    }

    func removeViewAttributes(forKeys keys: [AttributeKey]) {
        process(
            command: RUMRemoveViewAttributesCommand(
                time: dateProvider.now,
                keysToRemove: keys
            )
        )
    }

    func startView(viewController: UIViewController, name: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier(viewController),
                name: name ?? viewController.canonicalClassName,
                path: viewController.canonicalClassName,
                attributes: attributes,
                instrumentationType: .manual
            )
        )
    }

    func stopView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: attributes,
                identity: ViewIdentifier(viewController)
            )
        )
    }

    func startView(key: String, name: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: ViewIdentifier(key),
                name: name ?? key,
                path: key,
                attributes: attributes,
                instrumentationType: .manual
            )
        )
    }

    func stopView(key: String, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: attributes,
                identity: ViewIdentifier(key)
            )
        )
    }

    func addTiming(name: String) {
        process(
            command: RUMAddViewTimingCommand(
                time: dateProvider.now,
                attributes: [:],
                timingName: name
            )
        )
    }

    func addViewLoadingTime(overwrite: Bool) {
        process(
            command: RUMAddViewLoadingTime(
                time: dateProvider.now,
                attributes: [:],
                overwrite: overwrite
            )
        )
    }
}

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
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                message: message,
                type: type,
                stack: stack,
                source: source,
                attributes: attributes,
                completionHandler: NOPCompletionHandler
            )
        )
    }
}
