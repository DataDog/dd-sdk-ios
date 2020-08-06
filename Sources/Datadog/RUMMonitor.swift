/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit
import Foundation

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

public class RUMMonitor: RUMMonitorInternal {
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
        start(view: viewController, attributes: attributes)
    }

    /// Notifies that the View stops being presented to the user.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this View.
    ///   - attributes: custom attributes to attach to the View.
    public func stopView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue]? = nil) {
        stop(view: viewController, attributes: attributes)
    }

    /// Notifies that an Error occurred in currently presented View.
    /// - Parameters:
    ///   - message: a message explaining the Error.
    ///   - source: the origin of the Error.
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
        add(
            viewErrorMessage: message,
            source: source,
            attributes: attributes,
            stack: (file: file, line: line)
        )
    }

    /// Notifies that an Error occurred in currently presented View.
    /// - Parameters:
    ///   - error: the `Error` object. It will be used to build the Error description.
    ///   - source: the origin of the Error.
    ///   - attributes: custom attributes to attach to the Error
    public func addViewError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue]? = nil
    ) {
        add(viewError: error, source: source, attributes: attributes)
    }

    /// Notifies that the Resource starts being loaded.
    /// - Parameters:
    ///   - resourceName: the name representing this Resource - must be unique among all Resources currently being loaded.
    ///   - request: the `URLRequest` issued for this Resource
    ///   - attributes: custom attributes to attach to the Resource.
    public func startResourceLoading(resourceName: String, request: URLRequest, attributes: [AttributeKey: AttributeValue]? = nil) {
        start(
            resource: resourceName,
            url: request.url?.absoluteString ?? "",
            httpMethod: request.httpMethod ?? "",
            attributes: attributes
        )
    }

    /// Notifies that the Resource stops being loaded.
    /// - Parameters:
    ///   - resourceName: the name representing this Resource - must match the one used in `startResourceLoading(...)`.
    ///   - response: the `HTTPURLResponse` issued for this Resource
    ///   - size: size of loaded Resource (in bytes). If not specified, it will be inferred from the `Content-Length` HTTP header if available.
    ///   - attributes: custom attributes to attach to the Resource.
    public func stopResourceLoading(resourceName: String, response: HTTPURLResponse, size: UInt64? = nil, attributes: [AttributeKey: AttributeValue]? = nil) {
        stop(
            resource: resourceName,
            type: resourceType(from: response.mimeType),
            httpStatusCode: response.statusCode,
            size: size ?? resourceSize(from: response),
            attributes: attributes
        )
    }

    /// Notifies that the User Action has started.
    /// This is used to track long running user actions (e.g. "scroll").
    /// Such an User Action must be stopped with `stopUserAction(type:)`, and will be stopped automatically if it lasts more than 10 seconds.
    /// - Parameters:
    ///   - type: the User Action type
    ///   - attributes: custom attributes to attach to the User Action.
    public func startUserAction(type: RUMUserActionType, attributes: [AttributeKey: AttributeValue]? = nil) {
        start(userAction: type, attributes: attributes)
    }

    /// Notifies that the User Action has stopped.
    /// This is used to stop tracking long running user actions (e.g. "scroll"), started with `startUserAction(type:)`.
    /// - Parameters:
    ///   - type: the User Action type
    ///   - attributes: custom attributes to attach to the User Action.
    public func stopUserAction(type: RUMUserActionType, attributes: [AttributeKey: AttributeValue]? = nil) {
        stop(userAction: type, attributes: attributes)
    }

    /// Registers the occurence of an User Action.
    /// This is used to track discrete User Actions (e.g. "tap").
    /// - Parameters:
    ///   - type: the User Action type
    ///   - attributes: custom attributes to attach to the User Action.
    public func registerUserAction(type: RUMUserActionType, attributes: [AttributeKey: AttributeValue]? = nil) {
        add(userAction: type, attributes: attributes)
    }

    // MARK: - RUMMonitorInternal

    func start(view id: AnyObject, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStartViewCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                identity: id
            )
        )
    }

    func stop(view id: AnyObject, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStopViewCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                identity: id
            )
        )
    }

    func add(viewErrorMessage: String, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]?, stack: (file: StaticString, line: UInt)?) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.currentDate(),
                message: viewErrorMessage,
                source: source,
                stack: stack,
                attributes: attributes ?? [:]
            )
        )
    }

    func add(viewError: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMAddCurrentViewErrorCommand(
                time: dateProvider.currentDate(),
                error: viewError,
                source: source,
                attributes: attributes ?? [:]
            )
        )
    }

    func start(resource resourceName: String, url: String, httpMethod: String, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStartResourceCommand(
                resourceName: resourceName,
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                url: url,
                httpMethod: httpMethod
            )
        )
    }

    func stop(resource resourceName: String, type: String, httpStatusCode: Int?, size: UInt64?, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStopResourceCommand(
                resourceName: resourceName,
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                type: type,
                httpStatusCode: httpStatusCode,
                size: size
            )
        )
    }

    func stop(resource resourceName: String, withError errorMessage: String, errorSource: RUMErrorSource, httpStatusCode: Int?, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStopResourceWithErrorCommand(
                resourceName: resourceName,
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                errorMessage: errorMessage,
                errorSource: errorSource,
                httpStatusCode: httpStatusCode
            )
        )
    }

    func start(userAction: RUMUserActionType, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStartUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                actionType: userAction
            )
        )
    }

    func stop(userAction: RUMUserActionType, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMStopUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                actionType: userAction
            )
        )
    }

    func add(userAction: RUMUserActionType, attributes: [AttributeKey: AttributeValue]?) {
        process(
            command: RUMAddUserActionCommand(
                time: dateProvider.currentDate(),
                attributes: attributes ?? [:],
                actionType: userAction
            )
        )
    }

    // MARK: - Private

    private func process(command: RUMCommand) {
        queue.async {
            _ = self.applicationScope.process(command: command)
        }
    }

    private func resourceType(from mimeType: String?) -> String {
        return "other" // TODO: RUMM-633 Add Resource type and size
    }

    private func resourceSize(from response: HTTPURLResponse) -> UInt64? {
        return nil // TODO: RUMM-633 Add Resource type and size
    }
}
