/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

/// A class enabling Datadog RUM features.
///
/// `DDRUMMonitor` allows you to record User events that can be explored and analyzed in Datadog Dashboards.
/// You can only have one active `RUMMonitor`, and should register/retrieve it from the `Global` object.
public class DDRUMMonitor {
    // MARK: - Public methods

    /// Notifies that the View starts being presented to the user.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this View.
    ///   - path: the View path used for RUM Explorer. If not provided, the `UIViewController` class name will be used.
    ///   - attributes: custom attributes to attach to the View.
    public func startView(viewController: UIViewController, path: String? = nil, attributes: [AttributeKey: AttributeValue] = [:]) {
    }

    /// Notifies that the View stops being presented to the user.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this View.
    ///   - attributes: custom attributes to attach to the View.
    public func stopView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue] = [:]) {
    }

    /// Notifies that an Error occurred in currently presented View.
    /// - Parameters:
    ///   - message: a message explaining the Error.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to the Error
    ///   - file: the file in which the Error occurred (the default is the file name in which this method was called).
    ///   - line: the line number on which the Error occurred (the default is the line number on which this method was called).
    public func addError(
        message: String,
        source: RUMErrorSource = .source,
        attributes: [AttributeKey: AttributeValue] = [:],
        file: StaticString? = #file,
        line: UInt? = #line
    ) {
    }

    /// Notifies that an Error occurred in currently presented View.
    /// - Parameters:
    ///   - error: the `Error` object. It will be used to build the Error description.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to the Error.
    public func addError(
        error: Error,
        source: RUMErrorSource = .source,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
    }

    /// Notifies that the Resource starts being loaded.
    /// - Parameters:
    ///   - resourceKey: the key representing the Resource - must be unique among all Resources being currently loaded.
    ///   - url: the `URL` of the Resource.
    ///   - httpMethod: the HTTP method used to load the Resource.
    ///   - attributes: custom attributes to attach to the Resource.
    public func startResourceLoading(resourceKey: String, url: URL, httpMethod: RUMHTTPMethod, attributes: [AttributeKey: AttributeValue] = [:]) {
    }

    /// Notifies that the Resource stops being loaded succesfully.
    /// - Parameters:
    ///   - resourceKey: the key representing the Resource - must match the one used in `startResourceLoading(...)`.
    ///   - kind: the type of the Resource.
    ///   - httpStatusCode: the HTTP response status code for this Resource.
    ///   - size: the size of the Resource (in bytes).
    ///   - attributes: custom attributes to attach to the Resource.
    public func stopResourceLoading(resourceKey: String, kind: RUMResourceKind, httpStatusCode: Int?, size: Int64? = nil, attributes: [AttributeKey: AttributeValue] = [:]) {
    }

    /// Notifies that the Resource stops being loaded with error.
    /// This should be used when `Error` object is received on Resource failure.
    /// - Parameters:
    ///   - resourceKey: the key representing the Resource - must match the one used in `startResourceLoading(...)`.
    ///   - error: the `Error` object received when loading the Resource.
    ///   - httpStatusCode: HTTP status code (optional).
    ///   - attributes: custom attributes to attach to the Resource.
    public func stopResourceLoadingWithError(resourceKey: String, error: Error, httpStatusCode: Int?, attributes: [AttributeKey: AttributeValue] = [:]) {
    }

    /// Notifies that the Resource stops being loaded with error.
    /// If `Error` object available on Resource failure `stopResourceLoadingWithError(..., error:, ...)` should be used instead.
    /// - Parameters:
    ///   - resourceKey: the key representing the Resource - must match the one used in `startResourceLoading(...)`.
    ///   - errorMessage: the message explaining Resource failure.
    ///   - httpStatusCode: HTTP status code (optional).
    ///   - attributes: custom attributes to attach to the Resource.
    public func stopResourceLoadingWithError(resourceKey: String, errorMessage: String, httpStatusCode: Int? = nil, attributes: [AttributeKey: AttributeValue] = [:]) {
    }

    /// Notifies that the User Action has started.
    /// This is used to track long running user actions (e.g. "scroll").
    /// Such an User Action must be stopped with `stopUserAction(type:)`, and will be stopped automatically if it lasts more than 10 seconds.
    /// - Parameters:
    ///   - type: the User Action type
    ///   - name: the User Action name
    ///   - attributes: custom attributes to attach to the User Action.
    public func startUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey: AttributeValue] = [:]) {
    }

    /// Notifies that the User Action has stopped.
    /// This is used to stop tracking long running user actions (e.g. "scroll"), started with `startUserAction(type:)`.
    /// - Parameters:
    ///   - type: the User Action type
    ///   - name: the User Action name. If `nil`, the `name` used in `startUserAction` will be effective.
    ///   - attributes: custom attributes to attach to the User Action.
    public func stopUserAction(type: RUMUserActionType, name: String? = nil, attributes: [AttributeKey: AttributeValue] = [:]) {
    }

    /// Registers the occurence of an User Action.
    /// This is used to track discrete User Actions (e.g. "tap").
    /// - Parameters:
    ///   - type: the User Action type
    ///   - name: the User Action name
    ///   - attributes: custom attributes to attach to the User Action.
    public func addUserAction(type: RUMUserActionType, name: String, attributes: [AttributeKey: AttributeValue] = [:]) {
    }

    // MARK: - Attributes

    /// Adds a custom attribute to all future commands sent by this monitor.
    /// - Parameters:
    ///   - key: key for this attribute. See `AttributeKey` documentation for information about
    ///   nesting attribute values using dot `.` syntax.
    ///   - value: any value that conforms to `AttributeValue` typealias. See `AttributeValue` documentation
    ///   for information about nested encoding containers limitation.
    public func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
    }

    /// Removes the custom attribute from all future commands sent by this monitor.
    /// Previous commands won't lose this attribute if they were created prior to this call.
    /// - Parameter key: key for the attribute that will be removed.
    public func removeAttribute(forKey key: AttributeKey) {
    }

    // MARK: - Internal

    internal init() {}
}

/// The no-op variant of `DDRUMMonitor`.
internal class DDNoopRUMMonitor: DDRUMMonitor {
}
