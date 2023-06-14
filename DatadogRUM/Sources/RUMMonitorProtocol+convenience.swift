/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Foundation
import DatadogInternal

/// Convenience extension. It defines method variants that provide default values for optional parameters.
///
/// ⚠️ Be super caucious when extending it with new methods. Defining a method here will shadow its
/// requirement for the type conforming to `RUMMonitorProtocol`. If that method is not defined
/// in original type (by mistake), it will cause an infinite recursive call and crash.
public extension RUMMonitorProtocol {
    // MARK: - views

    func startView(
        viewController: UIViewController,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startView(viewController: viewController, name: name, attributes: attributes)
    }

    func stopView(
        viewController: UIViewController,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopView(viewController: viewController, attributes: attributes)
    }

    func startView(
        key: String,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startView(key: key, name: name, attributes: attributes)
    }

    func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopView(key: key, attributes: attributes)
    }

    // MARK: - errors

    func addError(
        message: String,
        type: String? = nil,
        stack: String? = nil,
        source: RUMErrorSource = .custom,
        attributes: [AttributeKey: AttributeValue] = [:],
        file: StaticString? = #file,
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

    func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addError(error: error, source: source, attributes: attributes)
    }

    // MARK: - resources

    func startResourceLoading(
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startResourceLoading(resourceKey: resourceKey, request: request, attributes: attributes)
    }

    func startResourceLoading(
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startResourceLoading(resourceKey: resourceKey, url: url, attributes: attributes)
    }

    func startResourceLoading(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startResourceLoading(resourceKey: resourceKey, httpMethod: httpMethod, urlString: urlString, attributes: attributes)
    }

    func addResourceMetrics(
        resourceKey: String,
        metrics: URLSessionTaskMetrics,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addResourceMetrics(resourceKey: resourceKey, metrics: metrics, attributes: attributes)
    }

    func addResourceMetrics(
        resourceKey: String,
        fetch: (start: Date, end: Date),
        redirection: (start: Date, end: Date)? = nil,
        dns: (start: Date, end: Date)? = nil,
        connect: (start: Date, end: Date)? = nil,
        ssl: (start: Date, end: Date)? = nil,
        firstByte: (start: Date, end: Date)? = nil,
        download: (start: Date, end: Date)? = nil,
        responseSize: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addResourceMetrics(
            resourceKey: resourceKey,
            fetch: fetch,
            redirection: redirection,
            dns: dns,
            connect: connect,
            ssl: ssl,
            firstByte: firstByte,
            download: download,
            responseSize: responseSize,
            attributes: attributes
        )
    }

    func stopResourceLoading(
        resourceKey: String,
        response: URLResponse,
        size: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResourceLoading(
            resourceKey: resourceKey,
            response: response,
            size: size,
            attributes: attributes
        )
    }

    func stopResourceLoading(
        resourceKey: String,
        statusCode: Int? = nil,
        kind: RUMResourceType,
        size: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResourceLoading(
            resourceKey: resourceKey,
            statusCode: statusCode,
            kind: kind,
            size: size,
            attributes: attributes
        )
    }

    func stopResourceLoadingWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResourceLoadingWithError(
            resourceKey: resourceKey,
            error: error,
            response: response,
            attributes: attributes
        )
    }

    func stopResourceLoadingWithError(
        resourceKey: String,
        errorMessage: String,
        type: String? = nil,
        response: URLResponse? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopResourceLoadingWithError(
            resourceKey: resourceKey,
            errorMessage: errorMessage,
            type: type,
            response: response,
            attributes: attributes
        )
    }

    // MARK: - actions

    func addUserAction(
        type: RUMUserActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        addUserAction(type: type, name: name, attributes: attributes)
    }

    func startUserAction(
        type: RUMUserActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        startUserAction(type: type, name: name, attributes: attributes)
    }

    func stopUserAction(
        type: RUMUserActionType,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        stopUserAction(type: type, name: name, attributes: attributes)
    }
}
