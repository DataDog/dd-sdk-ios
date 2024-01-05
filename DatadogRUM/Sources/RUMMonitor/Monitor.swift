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
    static func extract(from attributes: inout [AttributeKey: AttributeValue]) -> Self {
        return (attributes.removeValue(forKey: CrossPlatformAttributes.errorSourceType))
            .flatMap({
                $0.decoded()
            })
            .flatMap {
                return RUMErrorEvent.Error.SourceType(rawValue: $0)
            } ?? .ios
    }
}

internal extension AttributeValue {
    func decoded<T>() -> T? {
        switch self {
        case let codable as AnyCodable:
            return codable.value as? T
        case let val as T:
            return val
        default:
            return nil
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

internal class Monitor: RUMCommandSubscriber {
    let scopes: RUMApplicationScope
    let dateProvider: DateProvider
    let queue = DispatchQueue(
        label: "com.datadoghq.rum-monitor",
        target: .global(qos: .userInteractive)
    )

    private(set) weak var core: DatadogCoreProtocol?
    private(set) var debugging: RUMDebugging? = nil

    private var attributes: [AttributeKey: AttributeValue] = [:]

    init(
        core: DatadogCoreProtocol,
        dependencies: RUMScopeDependencies,
        dateProvider: DateProvider
    ) {
        self.core = core
        self.scopes = RUMApplicationScope(dependencies: dependencies)
        self.dateProvider = dateProvider
    }

    func process(command: RUMCommand) {
        // process command in event context
        core?.scope(for: RUMFeature.name)?.eventWriteContext { context, writer in
            self.queue.sync {
                let transformedCommand = self.transform(command: command)

                _ = self.scopes.process(command: transformedCommand, context: context, writer: writer)

                if let debugging = self.debugging {
                    debugging.debug(applicationScope: self.scopes)
                }
            }
        }

        // update the core context with rum context
        core?.set(
            baggage: {
                self.queue.sync { () -> RUMCoreContext? in
                    let context = self.scopes.activeSession?.viewScopes.last?.context ??
                                    self.scopes.activeSession?.context ??
                                    self.scopes.context

                    guard context.sessionID != .nullUUID else {
                        // if Session was sampled or not yet started
                        return nil
                    }

                    return RUMCoreContext(
                        applicationID: context.rumApplicationID,
                        sessionID: context.sessionID.rawValue.uuidString.lowercased(),
                        viewID: context.activeViewID?.rawValue.uuidString.lowercased(),
                        userActionID: context.activeUserActionID?.rawValue.uuidString.lowercased(),
                        viewServerTimeOffset: self.scopes.activeSession?.viewScopes.last?.serverTimeOffset
                    )
                }
            },
            forKey: RUMFeature.name
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

        var combinedUserAttributes = attributes
        combinedUserAttributes.merge(rumCommandAttributes: command.attributes)

        if let customTimestampInMiliseconds = combinedUserAttributes.removeValue(forKey: CrossPlatformAttributes.timestampInMilliseconds) as? Int64 {
            let customTimeInterval = TimeInterval(fromMilliseconds: customTimestampInMiliseconds)
            mutableCommand.time = Date(timeIntervalSince1970: customTimeInterval)
        }

        mutableCommand.attributes = combinedUserAttributes

        return mutableCommand
    }
}

/// Declares `Monitor` conformance to public `RUMMonitorProtocol`.
extension Monitor: RUMMonitorProtocol {
    // MARK: - properties
    var currentSessionID: String? {
        get {
            guard let activeSession = self.scopes.activeSession else {
                return nil
            }

            return activeSession.sessionUUID.rawValue.uuidString
        }
    }

    // MARK: - attributes

    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        queue.async {
            self.attributes[key] = value
        }
    }

    func removeAttribute(forKey key: AttributeKey) {
        queue.async {
            self.attributes[key] = nil
        }
    }

    // MARK: - session

    func stopSession() {
        process(command: RUMStopSessionCommand(time: dateProvider.now))
    }

    // MARK: - views

    func startView(viewController: UIViewController, name: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: viewController.asRUMViewIdentity(),
                name: name,
                path: nil,
                attributes: attributes
            )
        )
    }

    func stopView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: attributes,
                identity: viewController.asRUMViewIdentity()
            )
        )
    }

    func startView(key: String, name: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: key.asRUMViewIdentity(),
                name: name ?? key,
                path: key,
                attributes: attributes
            )
        )
    }

    func stopView(key: String, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: attributes,
                identity: key.asRUMViewIdentity()
            )
        )
    }

    // MARK: - custom timings

    func addTiming(name: String) {
        process(
            command: RUMAddViewTimingCommand(
                time: dateProvider.now,
                attributes: [:],
                timingName: name
            )
        )
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
                attributes: attributes
            )
        )
    }

    func addError(error: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                error: error,
                source: RUMInternalErrorSource(source),
                attributes: attributes
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

    func addFeatureFlagEvaluation(name: String, value: Encodable) {
        process(
            command: RUMAddFeatureFlagEvaluationCommand(
                time: dateProvider.now,
                name: name,
                value: value
            )
        )
    }

    // MARK: - debugging

    var debug: Bool {
        set {
            queue.async {
                self.debugging = newValue ? RUMDebugging() : nil
                self.debugging?.debug(applicationScope: self.scopes)
            }
        }
        get {
            queue.sync {
                self.debugging != nil
            }
        }
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
                attributes: attributes
            )
        )
    }

    /// Completes all asynchronous operations with blocking the caller thread.
    func flush() {
        queue.sync { }
    }
}
