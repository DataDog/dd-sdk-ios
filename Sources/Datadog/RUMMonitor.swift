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
public class RUMMonitor: DDRUMMonitor {
    /// The root scope of RUM monitoring.
    internal let applicationScope: RUMApplicationScope
    /// Current RUM context provider for integrations with Logging and Tracing.
    internal let contextProvider: RUMCurrentContext
    /// Time provider.
    private let dateProvider: DateProvider
    /// Queue for processing RUM commands off the main thread and providing current RUM context.
    private let queue = DispatchQueue(
        label: "com.datadoghq.rum-monitor",
        target: .global(qos: .userInteractive)
    )

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
            return RUMMonitor(rumFeature: rumFeature)
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

    internal init(applicationScope: RUMApplicationScope, dateProvider: DateProvider) {
        self.applicationScope = applicationScope
        self.dateProvider = dateProvider
        self.contextProvider = RUMCurrentContext(
            applicationScope: applicationScope,
            queue: queue
        )
    }

    // MARK: - Public DDRUMMonitor conformance

    override public func startView(viewController: UIViewController, path: String?, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.currentDate(),
                identity: viewController,
                path: path,
                attributes: attributes ?? [:]
            )
        )
    }

    override public func stopView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                identity: viewController
            )
        )
    }

    override public func addViewError(message: String, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]?, file: StaticString?, line: UInt?) {
        var stack: (file: StaticString, line: UInt)? = nil
        if let file = file, let line = line {
            stack = (file: file, line: line)
        }
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.currentDate(),
                message: message,
                source: source,
                stack: stack,
                attributes: attributes ?? [:]
            )
        )
    }

    override public func addViewError(error: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.currentDate(),
                error: error,
                source: source,
                attributes: attributes ?? [:]
            )
        )
    }

    override public func startResourceLoading(resourceName: String, url: URL, httpMethod: RUMHTTPMethod, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStartResourceCommand(
                resourceName: resourceName,
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                url: url.absoluteString,
                httpMethod: httpMethod
            )
        )
    }

    override public func stopResourceLoading(resourceName: String, kind: RUMResourceKind, httpStatusCode: Int?, size: UInt64?, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStopResourceCommand(
                resourceName: resourceName,
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                kind: kind,
                httpStatusCode: httpStatusCode,
                size: size
            )
        )
    }

    override public func stopResourceLoadingWithError(resourceName: String, error: Error, source: RUMErrorSource, httpStatusCode: Int?, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceName: resourceName,
                time: dateProvider.currentDate(),
                error: error,
                source: source,
                httpStatusCode: httpStatusCode,
                attributes: attributes ?? [:]
            )
        )
    }

    override public func stopResourceLoadingWithError(resourceName: String, errorMessage: String, source: RUMErrorSource, httpStatusCode: Int? = nil, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceName: resourceName,
                time: dateProvider.currentDate(),
                message: errorMessage,
                source: source,
                httpStatusCode: httpStatusCode,
                attributes: attributes ?? [:]
            )
        )
    }

    override public func startUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStartUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                actionType: type,
                name: name
            )
        )
    }

    override public func stopUserAction(type: RUMUserActionType, name: String?, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStopUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                actionType: type,
                name: name
            )
        )
    }

    override public func registerUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMAddUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                actionType: type,
                name: name
            )
        )
    }

    // MARK: - Private

    private func process(command: RUMCommand) {
        queue.async {
            _ = self.applicationScope.process(command: command)
        }
    }
}
