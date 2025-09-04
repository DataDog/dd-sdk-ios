/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
@_exported import enum DatadogInternal.RUMMethod
// swiftlint:enable duplicate_imports

/// The type of RUM resource.
public typealias RUMResourceType = RUMResourceEvent.Resource.ResourceType

/// The type of a RUM action.
public enum RUMActionType {
    case tap
    case click
    case scroll
    case swipe
    case custom
}

/// The source of a RUM error.
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

/// Public interface of RUM monitor for manual interaction with RUM feature.
public protocol RUMMonitorProtocol: RUMMonitorViewProtocol, AnyObject {
    // MARK: - attributes

    /// Adds a custom attribute to the next RUM events.
    /// - Parameters:
    ///   - key: key for this attribute. See `AttributeKey` documentation for information about
    ///   nesting attribute values using dot `.` syntax.
    ///   - value: any value that conforms to `Encodable`. See `AttributeValue` documentation
    ///   for information about nested encoding containers limitation.
    func addAttribute(forKey key: AttributeKey, value: AttributeValue)

    /// Adds multiple attributes to the next RUM events.
    /// - Parameter attributes: dictionary with attributes. Each attribute is defined by a key `AttributeKey` and a value that conforms to `Encodable`.
    func addAttributes(_ attributes: [AttributeKey: AttributeValue])

    /// Removes an attribute from the next RUM events.
    /// Events created prior to this call will not lose this attribute.
    /// - Parameter key: key for the attribute that will be removed.
    func removeAttribute(forKey key: AttributeKey)

    /// Removes multiple attributes from the next RUM events.
    /// Events created prior to this call will not lose these attributes.
    /// - Parameter keys: array of attribute keys that will be removed.
    func removeAttributes(forKeys keys: [AttributeKey])

    // MARK: - session

    /// Get the currently active session ID. Returns `nil` if no sessions are currently active or if
    /// the current session is sampled out.
    /// This method uses an asynchronous callback to ensure all pending RUM events have been processed
    /// up to the moment of the call.
    /// - Parameters:
    ///   - completion: the callback that will recieve the current session ID. This will be called from a
    ///   background thread
    func currentSessionID(completion: @escaping (String?) -> Void)

    /// Stops the current RUM session.
    /// A new session will start in response to a call to `startView` or `addAction`.
    /// If the session is started because of a call to `addAction`, the last known view is restarted in the new session.
    func stopSession()

    // MARK: - custom timings

    /// Records a specific timing within the current RUM view.
    /// The duration of the timing is calculated as the number of nanoseconds elapsed between the start of the view and the addition of the timing.
    /// - Parameters:
    ///   - name: The name of the custom timing attribute. It must be unique for each timing.
    func addTiming(name: String)

    // MARK: - errors

    /// Adds RUM error to current RUM view.
    /// - Parameters:
    ///   - message: error message.
    ///   - type: the type of the error.
    ///   - stack: stack trace of the error. No specific format is required. If not specified, it will be inferred from `file` and `line`.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to this error.
    ///   - file: the file in which the error occurred (the default is the `#fileID` of the caller).
    ///   - line: the line number on which the error occurred (the default is the `#line` of the caller).
    func addError(
        message: String,
        type: String?,
        stack: String?,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        file: StaticString?,
        line: UInt?
    )

    /// Adds RUM error to current RUM view.
    /// - Parameters:
    ///   - error: the `Error` object. It will be used to infer error details.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to this error.
    func addError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue]
    )

    // MARK: - resources

    /// Starts RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must be unique among all resources being currently tracked.
    ///   - request: the `URLRequest` of this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func startResource(
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Starts RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must be unique among all resources being currently tracked.
    ///   - url: the `URL` of this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func startResource(
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Starts RUM resource
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must be unique among all resources being currently loaded.
    ///   - httpMethod: HTTP method of this resource
    ///   - urlString: the url string of this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func startResource(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Adds temporal metrics to given RUM resource.
    ///
    /// It must be called before the resource is stopped.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - metrics: the `URLSessionTaskMetrics` for this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func addResourceMetrics(
        resourceKey: String,
        metrics: URLSessionTaskMetrics,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Stops RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - response: the `URLResepone` received for the resource.
    ///   - size: an optional size of the data received for the resource (in bytes). If not provided, it will be inferred from the "Content-Length" header of the `response`.
    ///   - attributes: custom attributes to attach to this resource.
    func stopResource(
        resourceKey: String,
        response: URLResponse,
        size: Int64?,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Stops RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - statusCode: HTTP code of the response.
    ///   - kind: type of the resource.
    ///   - size: an optional size of the data received for the resource (in bytes).
    ///   - attributes: custom attributes to attach to this resource.
    func stopResource(
        resourceKey: String,
        statusCode: Int?,
        kind: RUMResourceType,
        size: Int64?,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Stops RUM resource with reporting an error.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - error: the `Error` object received when loading the resource.
    ///   - response: an optional `URLResponse` received for the resource.
    ///   - attributes: custom attributes to attach to this resource.
    func stopResourceWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse?,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Stops RUM resource with reporting an error.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - message: the message explaining the Resource failure.
    ///   - type: the type of the error.
    ///   - response: an optional `URLResponse` received for the resource.
    ///   - attributes: custom attributes to attach to this resource.
    func stopResourceWithError(
        resourceKey: String,
        message: String,
        type: String?,
        response: URLResponse?,
        attributes: [AttributeKey: AttributeValue]
    )

    // MARK: - actions

    /// Adds RUM action that has no duration.
    /// - Parameters:
    ///   - type: the type of the action.
    ///   - name: the name of the action.
    ///   - attributes: custom attributes to attach to this action.
    func addAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Starts RUM action.
    ///
    /// If the action is not stopped with `stopAction(type:)`, it will be stopped automatically after 10 seconds.
    /// - Parameters:
    ///   - type: the type of the action.
    ///   - name: the name of the action.
    ///   - attributes: custom attributes to attach to this action.
    func startAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Stops RUM action.
    ///
    /// The action must be first started with `startAction(type:)`.
    /// - Parameters:
    ///   - type: the type of the action. It should match type passed when starting this action.
    ///   - name: the name of the action. If not provided it will use the name the action was started with.
    ///   - attributes: custom attributes to attach to this action.
    func stopAction(
        type: RUMActionType,
        name: String?,
        attributes: [AttributeKey: AttributeValue]
    )

    // MARK: - feature flags

    /// Adds the result of evaluating a feature flag to the current RUM view
    ///
    /// Feature flag evaluations are local to the active view and are cleared when the view is stopped.
    /// - Parameters:
    ///   - name: the name of the feature flag
    ///   - value: the result of the evaluation
    func addFeatureFlagEvaluation(
        name: String,
        value: Encodable
    )

    // MARK: - debugging

    /// Debug utility to inspect the active RUM view. Use it only when debugging.
    ///
    /// If enabled, a debugging outline will be displayed on top of the application, indicating the name of the active RUM view.
    /// This can be helpful for debugging RUM instrumentation issues in your app.
    ///
    /// The default value is false.
    var debug: Bool { set get }

    // MARK: - Internal

    /// Adds RUM error to current RUM view.
    /// 
    /// - Parameters:
    ///   - error: the `Error` object. It will be used to infer error details.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to this error.
    ///   - completionHandler: A completion closure called when reporting the error is completed.
    @_spi(Internal)
    func addError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        completionHandler: @escaping CompletionHandler
    )
}

// MARK: - View Interface

/// Public interface of RUM monitor for manual interaction with the active RUM View.
public protocol RUMMonitorViewProtocol: AnyObject {
    /// Adds a custom attribute to the active RUM View. It will be propagated to all future RUM events associated with the active View.
    /// - Parameters:
    ///   - key: key for this view attribute. See `AttributeKey`  documentation for more information.
    ///   - value: any value that conforms to `Encodable`. See `AttributeValue` documentation
    ///   for information about nested encoding containers limitation.
    func addViewAttribute(forKey key: AttributeKey, value: AttributeValue)

    /// Adds multiple attributes to the active RUM View. They will be propagated to all future RUM events associated with the active View.
    /// - Parameter attributes: dictionary with view attributes. Each attribute is defined by a key `AttributeKey` and a value that conforms to `Encodable`.
    func addViewAttributes(_ attributes: [AttributeKey: AttributeValue])

    /// Removes an attribute from the active RUM View.
    /// Future RUM events associated with the active View won't have this attribute.
    /// Events created prior to this call will not lose this attribute.
    /// - Parameter key: key for the view attribute that will be removed.
    func removeViewAttribute(forKey key: AttributeKey)

    /// Removes multiple attributes from the active RUM View.
    /// Future RUM events associated with the active View won't have these attributes.
    /// Events created prior to this call will not lose these attributes.
    /// - Parameter keys: array of attribute keys that will be removed.
    func removeViewAttributes(forKeys keys: [AttributeKey])

    /// Starts RUM view.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this view.
    ///   - name: the name of the view. If not provided, the `viewController` class name will be used.
    ///   - attributes: custom attributes to attach to this view.
    func startView(
        viewController: UIViewController,
        name: String?,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Stops RUM view.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this view.
    ///   - attributes: custom attributes to attach to this view.
    func stopView(
        viewController: UIViewController,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Starts RUM view.
    /// - Parameters:
    ///   - key: a `String` value identifying this view. It must match the `key` passed later to `stopView(key:attributes:)`.
    ///   - name: the name of the view. If not provided, the `key` name will be used.
    ///   - attributes: custom attributes to attach to this  view.
    func startView(
        key: String,
        name: String?,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Stops RUM view.
    /// - Parameters:
    ///   - key: a `String` value identifying this view. It must match the `key` passed earlier to `startView(key:name:attributes:)`.
    ///   - attributes: custom attributes to attach to this view.
    func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue]
    )

    /// Adds view loading time to current RUM view based on the time elapsed since the view was started.
    /// This method should be called only once per view.
    /// If the view is not started, this method does nothing.
    /// If the view is not active, this method does nothing.
    /// - Parameter overwrite: if true, overwrites the previously calculated view loading time.
    @_spi(Experimental)
    func addViewLoadingTime(overwrite: Bool)
}

extension RUMMonitorViewProtocol {
    /// It cannot be declared '@_spi' without a default implementation in a protocol extension
    func addViewLoadingTime(overwrite: Bool) {
        // no-op
    }

    /// It cannot be declared '@_spi' without a default implementation in a protocol extension
    func addError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        completionHandler: @escaping CompletionHandler
    ) {
        completionHandler()
    }
}

// MARK: - NOP monitor

internal class NOPMonitor: RUMMonitorProtocol {
    private func warn(method: StaticString = #function) {
        DD.logger.critical(
            """
            Calling `\(method)` on NOPMonitor.
            Make sure RUM feature is enabled before using `RUMMonitor.shared()`.
            """
        )
    }

    func currentSessionID(completion: (String?) -> Void) { completion(nil) }
    func addAttribute(forKey key: AttributeKey, value: AttributeValue) { warn() }
    func addAttributes(_ attributes: [AttributeKey: AttributeValue]) { warn() }
    func removeAttribute(forKey key: AttributeKey) { warn() }
    func removeAttributes(forKeys keys: [AttributeKey]) {warn() }
    func stopSession() { warn() }
    func addTiming(name: String) { warn() }
    func addError(message: String, type: String?, stack: String?, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue], file: StaticString?, line: UInt?) { warn() }
    func addError(error: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue]) { warn() }
    func startResource(resourceKey: String, request: URLRequest, attributes: [AttributeKey: AttributeValue]) { warn() }
    func startResource(resourceKey: String, url: URL, attributes: [AttributeKey: AttributeValue]) { warn() }
    func startResource(resourceKey: String, httpMethod: RUMMethod, urlString: String, attributes: [AttributeKey: AttributeValue]) { warn() }
    func addResourceMetrics(resourceKey: String, metrics: URLSessionTaskMetrics, attributes: [AttributeKey: AttributeValue]) { warn() }
    func stopResource(resourceKey: String, response: URLResponse, size: Int64?, attributes: [AttributeKey: AttributeValue]) { warn() }
    func stopResource(resourceKey: String, statusCode: Int?, kind: RUMResourceType, size: Int64?, attributes: [AttributeKey: AttributeValue]) { warn() }
    func stopResourceWithError(resourceKey: String, error: Error, response: URLResponse?, attributes: [AttributeKey: AttributeValue]) { warn() }
    func stopResourceWithError(resourceKey: String, message: String, type: String?, response: URLResponse?, attributes: [AttributeKey: AttributeValue]) { warn() }
    func addAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue]) { warn() }
    func startAction(type: RUMActionType, name: String, attributes: [AttributeKey: AttributeValue]) { warn() }
    func stopAction(type: RUMActionType, name: String?, attributes: [AttributeKey: AttributeValue]) { warn() }
    func addFeatureFlagEvaluation(name: String, value: Encodable) { warn() }
    func addError(error: Error, source: RUMErrorSource, attributes: [AttributeKey: AttributeValue], completionHandler: () -> Void) {
        warn()
        completionHandler()
    }

    var debug: Bool {
        set { warn() }
        get {
            warn()
            return false
        }
    }
}

extension NOPMonitor: RUMMonitorViewProtocol {
    func addViewAttribute(forKey key: AttributeKey, value: AttributeValue) { warn() }
    func addViewAttributes(_ attributes: [AttributeKey: AttributeValue]) { warn() }
    func removeViewAttribute(forKey key: AttributeKey) { warn() }
    func removeViewAttributes(forKeys keys: [AttributeKey]) { warn() }

    func startView(viewController: UIViewController, name: String?, attributes: [AttributeKey: AttributeValue]) { warn() }
    func stopView(viewController: UIViewController, attributes: [AttributeKey: AttributeValue]) { warn() }
    func startView(key: String, name: String?, attributes: [AttributeKey: AttributeValue]) { warn() }
    func stopView(key: String, attributes: [AttributeKey: AttributeValue]) { warn() }

    func addViewLoadingTime(overwrite: Bool) { warn() }
}
