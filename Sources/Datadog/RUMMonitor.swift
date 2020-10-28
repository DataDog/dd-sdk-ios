/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Foundation

public enum RUMHTTPMethod: String {
    case GET
    case POST
    case PUT
    case DELETE
    case HEAD
    case PATCH

    /// Determines the `RUMHTTPMethod` based on a given `URLRequest`. Defaults to `.GET`.
    /// - Parameter request: the `URLRequest` for the resource.
    public init(request: URLRequest) {
        let requestMethod = request.httpMethod ?? "GET"
        self = RUMHTTPMethod(rawValue: requestMethod.uppercased()) ?? .GET
    }
}

public enum RUMResourceKind {
    case image
    case xhr
    case beacon
    case css
    case document
    case fetch
    case font
    case js
    case media
    case other

    private static let xhrHTTPMethods: Set<String> = ["POST", "PUT", "DELETE"]

    /// Determines the `RUMResourceKind` based on a given `URLRequest` and `HTTPURLResponse`.
    /// Defaults to `.other`.
    ///
    /// - Parameters:
    ///   - request: the `URLRequest` for the resource.
    ///   - response: the `HTTPURLResponse` of the resource.
    public init(request: URLRequest, response: HTTPURLResponse) {
        if let requestMethod = request.httpMethod?.uppercased(), RUMResourceKind.xhrHTTPMethods.contains(requestMethod) {
            self = .xhr
        } else {
            self.init(response: response)
        }
    }

    /// Determines the `RUMResourceKind` based on the MIME type of given `HTTPURLResponse`.
    /// Defaults to `.other`.
    ///
    /// - Parameters:
    ///   - response: the `HTTPURLResponse` of the resource.
    public init(response: HTTPURLResponse) {
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
            default: self = .other
            }
        } else {
            self = .other
        }
    }
}

public enum RUMUserActionType {
    case tap
    case scroll
    case swipe
    case custom
}

public enum RUMErrorSource {
    case source
    case console
    case network
    case agent
    case logger
    case webview
}

/// A class enabling Datadog RUM features.
///
/// `RUMMonitor` allows you to record User events that can be explored and analyzed in Datadog Dashboards.
/// You can only have one active `RUMMonitor`, and should register/retrieve it from the `Global` object.
public class RUMMonitor: DDRUMMonitor, RUMCommandSubscriber {
    /// The root scope of RUM monitoring.
    internal let applicationScope: RUMApplicationScope
    /// Current RUM context provider for integrations with Logging and Tracing.
    internal let contextProvider: RUMCurrentContext
    /// Time provider.
    private let dateProvider: DateProvider
    /// Attributes associated with every command.
    private var rumAttributes: [AttributeKey: AttributeValue] = [:]
    /// Queue for processing RUM commands off the main thread and providing current RUM context.
    internal let queue = DispatchQueue(
        label: "com.datadoghq.rum-monitor",
        target: .global(qos: .userInteractive)
    )
    /// User-targeted, debugging utility which can be toggled with `Datadog.debugRUM`.
    private(set) var debugging: RUMDebugging? = nil

    // MARK: - Initialization

    /// Initializes the Datadog RUM Monitor.
    public static func initialize() -> DDRUMMonitor {
        do {
            if Global.rum is RUMMonitor {
                throw ProgrammerError(
                    description: """
                    The `RUMMonitor` instance was already created. Use existing `Global.rum` instead of initializing the `RUMMonitor` another time.
                    """
                )
            }
            guard let rumFeature = RUMFeature.instance else {
                throw ProgrammerError(
                    description: Datadog.instance == nil
                        ? "`Datadog.initialize()` must be called prior to `RUMMonitor.initialize()`."
                        : "`RUMMonitor.initialize()` produces a non-functional monitor, as the RUM feature is disabled."
                )
            }
            let monitor = RUMMonitor(rumFeature: rumFeature)
            RUMAutoInstrumentation.instance?.subscribe(commandSubscriber: monitor)
            URLSessionAutoInstrumentation.instance?.subscribe(commandSubscriber: monitor)
            return monitor
        } catch {
            consolePrint("\(error)")
            return DDNoopRUMMonitor()
        }
    }

    internal convenience init(rumFeature: RUMFeature) {
        self.init(
            applicationScope: RUMApplicationScope(
                rumApplicationID: rumFeature.configuration.applicationID,
                dependencies: RUMScopeDependencies(
                    userInfoProvider: RUMUserInfoProvider(userInfoProvider: rumFeature.userInfoProvider),
                    connectivityInfoProvider: RUMConnectivityInfoProvider(
                        networkConnectionInfoProvider: rumFeature.networkConnectionInfoProvider,
                        carrierInfoProvider: rumFeature.carrierInfoProvider
                    ),
                    eventBuilder: RUMEventBuilder(),
                    eventOutput: RUMEventFileOutput(
                        fileWriter: rumFeature.storage.writer
                    ),
                    rumUUIDGenerator: DefaultRUMUUIDGenerator()
                ),
                samplingRate: rumFeature.configuration.sessionSamplingRate
            ),
            dateProvider: rumFeature.dateProvider
        )
    }

    internal init(applicationScope: RUMApplicationScope, dateProvider: DateProvider, debugRUMViews: Bool = false) {
        self.applicationScope = applicationScope
        self.dateProvider = dateProvider
        self.contextProvider = RUMCurrentContext(
            applicationScope: applicationScope,
            queue: queue
        )

        super.init()

        if Datadog.debugRUM {
            self.enableRUMDebugging(true)
        }
    }

    // MARK: - Public DDRUMMonitor conformance

    override public func startView(viewController: UIViewController, path: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.currentDate(),
                identity: viewController,
                path: path,
                attributes: attributes
            )
        )
    }

    override public func stopView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.currentDate(),
                attributes: attributes,
                identity: viewController
            )
        )
    }

    override public func addError(message: String, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue], file: StaticString?, line: UInt?) {
        var stack: String? = nil
        if let file = file, let fileName = "\(file)".split(separator: "/").last, let line = line {
            stack = "\(fileName):\(line)"
        }
        addError(message: message, stack: stack, source: source, attributes: attributes)
    }

    internal func addError(message: String, stack: String?, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.currentDate(),
                message: message,
                stack: stack,
                source: source,
                attributes: attributes
            )
        )
    }

    override public func addError(error: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.currentDate(),
                error: error,
                source: source,
                attributes: attributes
            )
        )
    }

    override public func startResourceLoading(resourceKey: String, url: URL, httpMethod: RUMHTTPMethod, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.currentDate(),
                attributes: attributes,
                url: url.absoluteString,
                httpMethod: httpMethod,
                spanContext: nil
            )
        )
    }

    override public func stopResourceLoading(resourceKey: String, kind: RUMResourceKind, httpStatusCode: Int?, size: Int64?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.currentDate(),
                attributes: attributes,
                kind: kind,
                httpStatusCode: httpStatusCode,
                size: size
            )
        )
    }

    override public func stopResourceLoadingWithError(resourceKey: String, error: Error, httpStatusCode: Int?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceKey: resourceKey,
                time: dateProvider.currentDate(),
                error: error,
                source: .network,
                httpStatusCode: httpStatusCode,
                attributes: attributes
            )
        )
    }

    override public func stopResourceLoadingWithError(resourceKey: String, errorMessage: String, httpStatusCode: Int? = nil, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceKey: resourceKey,
                time: dateProvider.currentDate(),
                message: errorMessage,
                source: .network,
                httpStatusCode: httpStatusCode,
                attributes: attributes
            )
        )
    }

    override public func startUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStartUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes,
                actionType: type,
                name: name
            )
        )
    }

    override public func stopUserAction(type: RUMUserActionType, name: String?, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMStopUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes,
                actionType: type,
                name: name
            )
        )
    }

    override public func addUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey: AttributeValue]) {
        process(
            command: RUMAddUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes,
                actionType: type,
                name: name
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
        queue.async {
            var combinedUserAttributes = self.rumAttributes
            combinedUserAttributes.merge(rumCommandAttributes: command.attributes)

            var command = command
            command.attributes = combinedUserAttributes

            _ = self.applicationScope.process(command: command)

            if let debugging = self.debugging {
                debugging.debug(applicationScope: self.applicationScope)
            }
        }
    }
}
