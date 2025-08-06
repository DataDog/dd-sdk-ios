/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Foundation
import DatadogInternal

// swiftlint:disable function_default_parameter_at_end

/// Convenience extension for defining `RUMMonitorProtocol` methods with default parameter values.
///
/// ⚠️ Be extra cautious when adding new methods here. Each method overloads (shadows) its original
/// definition in extended protocol, which makes the Swift compiler no longer require it on the type conforming
/// to `RUMMonitorProtocol`. If that conformance is not provided, it will cause an infinite recursive call and crash.
///
/// TODO: RUMM-3347 Use code generation for supplying default parameter values in public protocols
public extension RUMMonitorProtocol {
    // MARK: - views

    /// Starts RUM view.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this view.
    ///   - name: the name of the view. If not provided, the `viewController` class name will be used.
    ///   - attributes: custom attributes to attach to this view.
    func startView(
        viewController: UIViewController,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startView(viewController: viewController, name: name, attributes: attributes)
    }

    /// Stops RUM view.
    /// - Parameters:
    ///   - viewController: the instance of `UIViewController` representing this view.
    ///   - attributes: custom attributes to attach to this view.
    func stopView(
        viewController: UIViewController,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopView(viewController: viewController, attributes: attributes)
    }

    /// Starts RUM view.
    /// - Parameters:
    ///   - key: a `String` value identifying this view. It must match the `key` passed later to `stopView(key:attributes:)`.
    ///   - name: the name of the view. If not provided, the `key` name will be used.
    ///   - attributes: custom attributes to attach to this view.
    func startView(
        key: String,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startView(key: key, name: name, attributes: attributes)
    }

    /// Stops RUM view.
    /// - Parameters:
    ///   - key: a `String` value identifying this view. It must match the `key` passed earlier to `startView(key:name:attributes:)`.
    ///   - attributes: custom attributes to attach to this view.
    func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopView(key: key, attributes: attributes)
    }

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
        type: String? = nil,
        stack: String? = nil,
        source: RUMErrorSource = .custom,
        attributes: [AttributeKey: AttributeValue] = [:],
        file: StaticString? = #fileID,
        line: UInt? = #line
    ) {
        addError(
            message: message,
            type: type,
            stack: stack,
            source: source,
            attributes: attributes,
            file: file,
            line: line
        )
    }

    /// Adds RUM error to current RUM view.
    /// - Parameters:
    ///   - error: the `Error` object. It will be used to infer error details.
    ///   - source: the origin of the error.
    ///   - attributes: custom attributes to attach to this error.
    func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addError(error: error, source: source, attributes: attributes)
    }

    // MARK: - resources

    /// Starts RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must be unique among all resources being currently tracked.
    ///   - request: the `URLRequest` of this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func startResource(
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startResource(resourceKey: resourceKey, request: request, attributes: attributes)
    }

    /// Starts RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must be unique among all resources being currently tracked.
    ///   - url: the `URL` of this resource.
    ///   - attributes: custom attributes to attach to this resource.
    func startResource(
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startResource(resourceKey: resourceKey, url: url, attributes: attributes)
    }

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
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startResource(resourceKey: resourceKey, httpMethod: httpMethod, urlString: urlString, attributes: attributes)
    }

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
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addResourceMetrics(resourceKey: resourceKey, metrics: metrics, attributes: attributes)
    }

    /// Stops RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - response: the `URLResepone` received for the resource.
    ///   - size: an optional size of the data received for the resource (in bytes). If not provided, it will be inferred from the "Content-Length" header of the `response`.
    ///   - attributes: custom attributes to attach to this resource.
    func stopResource(
        resourceKey: String,
        response: URLResponse,
        size: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResource(
            resourceKey: resourceKey,
            response: response,
            size: size,
            attributes: attributes
        )
    }

    /// Stops RUM resource.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - statusCode: HTTP code of the response.
    ///   - kind: type of the resource.
    ///   - size: an optional size of the data received for the resource (in bytes).
    ///   - attributes: custom attributes to attach to this resource.
    func stopResource(
        resourceKey: String,
        statusCode: Int? = nil,
        kind: RUMResourceType,
        size: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResource(
            resourceKey: resourceKey,
            statusCode: statusCode,
            kind: kind,
            size: size,
            attributes: attributes
        )
    }

    /// Stops RUM resource with reporting an error.
    /// - Parameters:
    ///   - resourceKey: the key representing the resource. It must match the one used to start the resource.
    ///   - error: the `Error` object received when loading the resource.
    ///   - response: an optional `URLResponse` received for the resource.
    ///   - attributes: custom attributes to attach to this resource.
    func stopResourceWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResourceWithError(
            resourceKey: resourceKey,
            error: error,
            response: response,
            attributes: attributes
        )
    }

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
        type: String? = nil,
        response: URLResponse? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResourceWithError(
            resourceKey: resourceKey,
            message: message,
            type: type,
            response: response,
            attributes: attributes
        )
    }

    // MARK: - actions

    /// Adds RUM action.
    /// - Parameters:
    ///   - type: the type of the action.
    ///   - name: the name of the action.
    ///   - attributes: custom attributes to attach to this action.
    func addAction(
        type: RUMActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addAction(type: type, name: name, attributes: attributes)
    }

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
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startAction(type: type, name: name, attributes: attributes)
    }

    /// Stops RUM action.
    /// 
    /// The action must be first started with `startAction(type:)`.
    /// - Parameters:
    ///   - type: the type of the action. It should match type passed when starting this action.
    ///   - name: the name of the action. If not provided it will use the name the action was started with.
    ///   - attributes: custom attributes to attach to this action.
    func stopAction(
        type: RUMActionType,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopAction(type: type, name: name, attributes: attributes)
    }
}

// swiftlint:enable function_default_parameter_at_end
