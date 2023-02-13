/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Foundation

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

public typealias RUMResourceType = RUMResourceEvent.Resource.ResourceType

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
        case let codable as DDAnyCodable:
            return codable.value as? T
        case let val as T:
            return val
        default:
            return nil
        }
    }
}

/// Describes the type of a RUM Action.
public enum RUMUserActionType {
    case tap
    case click
    case scroll
    case swipe
    case custom
}

/// Describe the source of a RUM Error.
public enum RUMErrorSource {
    /// Error originated in the source code.
    case source
    /// Error originated in the network layer.
    case network
    /// Error originated in a webview.
    case webview
    /// Error originated in a web console (used by bridges).
    case console
    /// Custom error source.
    case custom
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

/// A class enabling Datadog RUM features.
///
/// `RUMMonitor` allows recording user events that can be explored and analyzed in Datadog Dashboards.
/// There can be only one active `RUMMonitor`, and it should be registered/retrieved through `Global.rum`:
///
///     import Datadog
///
///     // register
///     Global.rum = RUMMonitor.initialize()
///
///     // use
///     Global.rum.startView(...)
///
public class RUMMonitor: DDRUMMonitor, RUMCommandSubscriber {
    internal let core: DatadogCoreProtocol
    /// The root scope of RUM monitoring.
    internal let applicationScope: RUMApplicationScope
    /// Time provider.
    internal let dateProvider: DateProvider
    /// Attributes associated with every command.
    private var rumAttributes: [AttributeKey: AttributeValue] = [:]
    /// Queue for processing RUM commands off the main thread and providing current RUM context.
    private let queue = DispatchQueue(
        label: "com.datadoghq.rum-monitor",
        target: .global(qos: .userInteractive)
    )
    /// User-targeted, debugging utility which can be toggled with `Datadog.debugRUM`.
    private(set) var debugging: RUMDebugging? = nil

    // MARK: - Initialization

    /// Initializes the Datadog RUM Monitor.
    public static func initialize(in core: DatadogCoreProtocol = defaultDatadogCore) -> DDRUMMonitor {
        do {
            if core is NOPDatadogCore {
                throw ProgrammerError(
                    description: "`Datadog.initialize()` must be called prior to `RUMMonitor.initialize()`."
                )
            }
            if Global.rum is RUMMonitor {
                throw ProgrammerError(
                    description: """
                    The `RUMMonitor` instance was already created. Use existing `Global.rum` instead of initializing the `RUMMonitor` another time.
                    """
                )
            }
            guard let rumFeature = core.v1.feature(RUMFeature.self) else {
                throw ProgrammerError(
                    description: "`RUMMonitor.initialize()` produces a non-functional monitor, as the RUM feature is disabled."
                )
            }

            let monitor = RUMMonitor(
                core: core,
                dependencies: RUMScopeDependencies(
                    core: core,
                    rumFeature: rumFeature
                ),
                dateProvider: rumFeature.configuration.dateProvider
            )

            core.v1.feature(RUMInstrumentation.self)?.publish(to: monitor)
            core.v1.feature(URLSessionAutoInstrumentation.self)?.publish(to: monitor)

            return monitor
        } catch {
            consolePrint("\(error)")
            return DDNoopRUMMonitor()
        }
    }

    internal init(core: DatadogCoreProtocol, dependencies: RUMScopeDependencies, dateProvider: DateProvider) {
        self.core = core
        self.applicationScope = RUMApplicationScope(dependencies: dependencies)
        self.dateProvider = dateProvider

        super.init()

        if Datadog.debugRUM {
            self.enableRUMDebugging(true)
        }

        CITestIntegration.active?.startIntegration()
    }

    // MARK: - Public DDRUMMonitor conformance

    override public func startView(
        viewController: UIViewController,
        path: String?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: viewController,
                name: path,
                path: path,
                attributes: attributes
            )
        )
    }

    override public func startView(
        viewController: UIViewController,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: viewController,
                name: name,
                path: nil,
                attributes: attributes
            )
        )
    }

    override public func stopView(
        viewController: UIViewController,
        attributes: [AttributeKey: AttributeValue]
    ) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: attributes,
                identity: viewController
            )
        )
    }

    override public func startView(
        key: String,
        name: String?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.now,
                identity: key,
                name: name ?? key,
                path: key,
                attributes: attributes
            )
        )
    }

    override public func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue]
    ) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.now,
                attributes: attributes,
                identity: key
            )
        )
    }

    override public func addTiming(
        name: String
    ) {
        process(
            command: RUMAddViewTimingCommand(
                time: dateProvider.now,
                attributes: [:],
                timingName: name
            )
        )
    }

    override public func addError(
        message: String,
        type: String? = nil,
        source: RUMErrorSource,
        stack: String?,
        attributes: [AttributeKey: AttributeValue],
        file: StaticString?,
        line: UInt?
    ) {
        let stack: String? = stack ?? {
            if let file = file,
               let fileName = "\(file)".split(separator: "/").last,
               let line = line {
                return "\(fileName):\(line)"
            }
            return nil
        }()
        addError(message: message, type: type, stack: stack, source: RUMInternalErrorSource(source), attributes: attributes)
    }

    internal func addError(
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

    override public func addError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue]
    ) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.now,
                error: error,
                source: RUMInternalErrorSource(source),
                attributes: attributes
            )
        )
    }

    override public func startResourceLoading(
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue]
    ) {
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

    override public func startResourceLoading(
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue]
    ) {
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

    override public func startResourceLoading(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
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

    override public func addResourceMetrics(
        resourceKey: String,
        metrics: URLSessionTaskMetrics,
        attributes: [AttributeKey: AttributeValue]
    ) {
        process(
            command: RUMAddResourceMetricsCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                metrics: ResourceMetrics(taskMetrics: metrics)
            )
        )
    }

    override public func addResourceMetrics(
        resourceKey: String,
        fetch: (start: Date, end: Date),
        redirection: (start: Date, end: Date)?,
        dns: (start: Date, end: Date)?,
        connect: (start: Date, end: Date)?,
        ssl: (start: Date, end: Date)?,
        firstByte: (start: Date, end: Date)?,
        download: (start: Date, end: Date)?,
        responseSize: Int64?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        process(
            command: RUMAddResourceMetricsCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: attributes,
                metrics: ResourceMetrics(
                    fetch: ResourceMetrics.DateInterval(start: fetch.start, end: fetch.end),
                    redirection: ResourceMetrics.DateInterval.create(start: redirection?.start, end: redirection?.end),
                    dns: ResourceMetrics.DateInterval.create(start: dns?.start, end: dns?.end),
                    connect: ResourceMetrics.DateInterval.create(start: connect?.start, end: connect?.end),
                    ssl: ResourceMetrics.DateInterval.create(start: ssl?.start, end: ssl?.end),
                    firstByte: ResourceMetrics.DateInterval.create(start: firstByte?.start, end: firstByte?.end),
                    download: ResourceMetrics.DateInterval.create(start: download?.start, end: download?.end),
                    responseSize: responseSize
                )
            )
        )
    }

    override public func stopResourceLoading(
        resourceKey: String,
        response: URLResponse,
        size: Int64?,
        attributes: [AttributeKey: AttributeValue]
    ) {
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

    override public func stopResourceLoading(
        resourceKey: String,
        statusCode: Int?,
        kind: RUMResourceType,
        size: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
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

    override public func stopResourceLoadingWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse?,
        attributes: [AttributeKey: AttributeValue]
    ) {
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

    override public func stopResourceLoadingWithError(
        resourceKey: String,
        errorMessage: String,
        type: String? = nil,
        response: URLResponse?,
        attributes: [AttributeKey: AttributeValue]
    ) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                message: errorMessage,
                type: type,
                source: .network,
                httpStatusCode: (response as? HTTPURLResponse)?.statusCode,
                attributes: attributes
            )
        )
    }

    override public func startUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartUserActionCommand(
                time: dateProvider.now,
                attributes: attributes,
                actionType: type,
                name: name
            )
        )
    }

    override public func stopUserAction(type: RUMUserActionType, name: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopUserActionCommand(
                time: dateProvider.now,
                attributes: attributes,
                actionType: type,
                name: name
            )
        )
    }

    override public func addUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddUserActionCommand(
                time: dateProvider.now,
                attributes: attributes,
                actionType: type,
                name: name
            )
        )
    }

    override public func addFeatureFlagEvaluation(name: String, value: Encodable) {
        process(
            command: RUMAddFeatureFlagEvaluationCommand(
                time: dateProvider.now,
                name: name,
                value: value
            )
        )
    }

    // MARK: - Attributes

    override public func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        queue.async {
            self.rumAttributes[key] = value
        }
    }

    override public func removeAttribute(forKey key: AttributeKey) {
        queue.async {
            self.rumAttributes[key] = nil
        }
    }

    // MARK: - Internal

    func enableRUMDebugging(_ enabled: Bool) {
        queue.async {
            self.debugging = enabled ? RUMDebugging() : nil
            self.debugging?.debug(applicationScope: self.applicationScope)
        }
    }

    // MARK: - RUMCommandSubscriber

    func process(command: RUMCommand) {
        // process command in event context
        core.v1.scope(for: RUMFeature.self)?.eventWriteContext { context, writer in
            self.queue.sync {
                let transformedCommand = self.transform(command: command)

                _ = self.applicationScope.process(command: transformedCommand, context: context, writer: writer)

                if let debugging = self.debugging {
                    debugging.debug(applicationScope: self.applicationScope)
                }
            }
        }

        // update the core context with rum context
        core.set(feature: "rum", attributes: {
            self.queue.sync {
                let context = self.applicationScope.sessionScope?.viewScopes.last?.context ??
                                self.applicationScope.sessionScope?.context ??
                                self.applicationScope.context

                guard context.sessionID != .nullUUID else {
                    // if Session was sampled or not yet started
                    return [:]
                }

                return [
                    RUMContextAttributes.ids: [
                        RUMContextAttributes.IDs.applicationID: context.rumApplicationID,
                        RUMContextAttributes.IDs.sessionID: context.sessionID.rawValue.uuidString.lowercased(),
                        RUMContextAttributes.IDs.viewID: context.activeViewID?.rawValue.uuidString.lowercased(),
                        RUMContextAttributes.IDs.userActionID: context.activeUserActionID?.rawValue.uuidString.lowercased(),
                    ],
                    RUMContextAttributes.serverTimeOffset: self.applicationScope.sessionScope?.viewScopes.last?.serverTimeOffset
                ]
            }
        })
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

        var combinedUserAttributes = self.rumAttributes
        combinedUserAttributes.merge(rumCommandAttributes: command.attributes)

        if let customTimestampInMiliseconds = combinedUserAttributes.removeValue(forKey: CrossPlatformAttributes.timestampInMilliseconds) as? Int64 {
            let customTimeInterval = TimeInterval(fromMilliseconds: customTimestampInMiliseconds)
            mutableCommand.time = Date(timeIntervalSince1970: customTimeInterval)
        }

        mutableCommand.attributes = combinedUserAttributes

        return mutableCommand
    }

#if DD_SDK_COMPILED_FOR_TESTING
    /// Blocks the caller thread until (asynchronous) command processing in `RUMMonitor` is completed.
    public func flush() {
        queue.sync {}
    }
#endif
}
