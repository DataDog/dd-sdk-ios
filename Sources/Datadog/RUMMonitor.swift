/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Foundation

public enum RUMHTTPMethod {
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

public class RUMMonitor {
    /// The root scope of RUM monitoring.
    internal let applicationScope: RUMScope
    /// Time provider.
    private let dateProvider: DateProvider
    /// Queue for processing RUM events off the main thread..
    private let queue = DispatchQueue(
        label: "com.datadoghq.rum-monitor",
        target: .global(qos: .userInteractive)
    )

    // MARK: - Initialization

    // TODO: RUMM-614 `RUMMonitor` initialization and configuration API
    public static func initialize(rumApplicationID: String) -> RUMMonitor {
        guard let rumFeature = RUMFeature.instance else {
            // TODO: RUMM-614 `RUMMonitor` initialization API
            fatalError("RUMFeature not initialized")
        }

        return RUMMonitor(rumFeature: rumFeature, rumApplicationID: rumApplicationID)
    }

    internal convenience init(rumFeature: RUMFeature, rumApplicationID: String) {
        self.init(
            applicationScope: RUMApplicationScope(
                rumApplicationID: rumApplicationID,
                dependencies: RUMScopeDependencies(
                    eventBuilder: RUMEventBuilder(
                        userInfoProvider: rumFeature.userInfoProvider,
                        networkConnectionInfoProvider: rumFeature.networkConnectionInfoProvider,
                        carrierInfoProvider: rumFeature.carrierInfoProvider
                    ),
                    eventOutput: RUMEventFileOutput(
                        fileWriter: rumFeature.storage.writer
                    ),
                    rumUUIDGenerator: DefaultRUMUUIDGenerator()
                )
            ),
            dateProvider: rumFeature.dateProvider
        )
    }

    internal init(applicationScope: RUMScope, dateProvider: DateProvider) {
        self.applicationScope = applicationScope
        self.dateProvider = dateProvider
    }

    // MARK: - Public API

    /// Notifies that the View starts being presented to the user.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this View.
    ///   - attributes: custom attributes to attach to the View.
    public func startView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue]? = nil) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                identity: viewController
            )
        )
    }

    /// Notifies that the View stops being presented to the user.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this View.
    ///   - attributes: custom attributes to attach to the View.
    public func stopView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue]? = nil) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                identity: viewController
            )
        )
    }

    /// Notifies that an Error occurred in currently presented View.
    /// - Parameters:
    ///   - message: a message explaining the Error.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to the Error
    ///   - file: the file in which the Error occurred (the default is the file name in which this method was called).
    ///   - line: the line number on which the Error occurred (the default is the line number on which this method was called).
    public func addViewError(
        message: String,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue]? = nil,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.currentDate(),
                message: message,
                source: source,
                stack: (file: file, line: line),
                attributes: attributes ?? [:]
            )
        )
    }

    /// Notifies that an Error occurred in currently presented View.
    /// - Parameters:
    ///   - error: the `Error` object. It will be used to build the Error description.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to the Error.
    public func addViewError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue]? = nil
    ) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.currentDate(),
                error: error,
                source: source,
                attributes: attributes ?? [:]
            )
        )
    }

    /// Notifies that the Resource starts being loaded.
    /// - Parameters:
    ///   - resourceName: the name representing the Resource - must be unique among all Resources being currently loaded.
    ///   - url: the `URL` of the Resource.
    ///   - httpMethod: the HTTP method used to load the Resource.
    ///   - attributes: custom attributes to attach to the Resource.
    public func startResourceLoading(resourceName: String, url: URL, httpMethod: RUMHTTPMethod, attributes: [AttributeKey: AttributeValue]? = nil) {
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

    /// Notifies that the Resource stops being loaded succesfully.
    /// - Parameters:
    ///   - resourceName: the name representing the Resource - must match the one used in `startResourceLoading(...)`.
    ///   - kind: the type of the Resource.
    ///   - httpStatusCode: the HTTP response status code for this Resource.
    ///   - size: the size of the Resource (in bytes).
    ///   - attributes: custom attributes to attach to the Resource.
    public func stopResourceLoading(resourceName: String, kind: RUMResourceKind, httpStatusCode: Int?, size: UInt64? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
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

    /// Notifies that the Resource stops being loaded with error.
    /// This should be used when `Error` object is received on Resource failure.
    /// - Parameters:
    ///   - resourceName: the name representing the Resource - must match the one used in `startResourceLoading(...)`.
    ///   - error: the `Error` object received when loading the Resource.
    ///   - source: the origin of the error.
    ///   - httpStatusCode: HTTP status code (optional).
    ///   - attributes: custom attributes to attach to the Resource.
    public func stopResourceLoadingWithError(resourceName: String, error: Error, source: RUMErrorSource, httpStatusCode: Int?, attributes: [AttributeKey: AttributeValue]? = nil) {
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

    /// Notifies that the Resource stops being loaded with error.
    /// If `Error` object available on Resource failure `stopResourceLoadingWithError(..., error:, ...)` should be used instead.
    /// - Parameters:
    ///   - resourceName: the name representing the Resource - must match the one used in `startResourceLoading(...)`.
    ///   - errorMessage: the message explaining Resource failure.
    ///   - source: the origin of the error.
    ///   - httpStatusCode: HTTP status code (optional).
    ///   - attributes: custom attributes to attach to the Resource.
    public func stopResourceLoadingWithError(resourceName: String, errorMessage: String, source: RUMErrorSource, httpStatusCode: Int? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
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

    /// Notifies that the User Action has started.
    /// This is used to track long running user actions (e.g. "scroll").
    /// Such an User Action must be stopped with `stopUserAction(type:)`, and will be stopped automatically if it lasts more than 10 seconds.
    /// - Parameters:
    ///   - type: the User Action type
    ///   - attributes: custom attributes to attach to the User Action.
    public func startUserAction(type: RUMUserActionType, attributes: [AttributeKey: AttributeValue]? = nil) {
        process(
            command: RUMStartUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                actionType: type
            )
        )
    }

    /// Notifies that the User Action has stopped.
    /// This is used to stop tracking long running user actions (e.g. "scroll"), started with `startUserAction(type:)`.
    /// - Parameters:
    ///   - type: the User Action type
    ///   - attributes: custom attributes to attach to the User Action.
    public func stopUserAction(type: RUMUserActionType, attributes: [AttributeKey: AttributeValue]? = nil) {
        process(
            command: RUMStopUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                actionType: type
            )
        )
    }

    /// Registers the occurence of an User Action.
    /// This is used to track discrete User Actions (e.g. "tap").
    /// - Parameters:
    ///   - type: the User Action type
    ///   - attributes: custom attributes to attach to the User Action.
    public func registerUserAction(type: RUMUserActionType, attributes: [AttributeKey: AttributeValue]? = nil) {
        process(
            command: RUMAddUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                actionType: type
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
