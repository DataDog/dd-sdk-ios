/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
import Foundation
import DatadogInternal

public protocol RUMMonitorProtocol {
    // MARK: - attributes

    func addAttribute(forKey key: AttributeKey,value: AttributeValue)
    func removeAttribute(forKey key: AttributeKey)

    // MARK: - session

    func stopSession()

    // MARK: - views

    func startView(
        viewController: UIViewController,
        name: String?,
        attributes: [AttributeKey: AttributeValue]
    )

    func stopView(
        viewController: UIViewController,
        attributes: [AttributeKey: AttributeValue]
    )

    func startView(
        key: String,
        name: String?,
        attributes: [AttributeKey: AttributeValue]
    )

    func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue]
    )

    // MARK: - custom timings

    func addTiming(name: String)

    // MARK: - errors

    func addError(
        message: String,
        type: String?,
        stack: String?,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue],
        file: StaticString?,
        line: UInt?
    )

    func addError(
        error: Error,
        source: RUMErrorSource,
        attributes: [AttributeKey: AttributeValue]
    )

    // MARK: - resources

    func startResourceLoading(
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue]
    )

    func startResourceLoading(
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue]
    )

    func startResourceLoading(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        attributes: [AttributeKey: AttributeValue]
    )

    func addResourceMetrics(
        resourceKey: String,
        metrics: URLSessionTaskMetrics,
        attributes: [AttributeKey: AttributeValue]
    )

    func addResourceMetrics(
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
    )

    func stopResourceLoading(
        resourceKey: String,
        response: URLResponse,
        size: Int64?,
        attributes: [AttributeKey: AttributeValue]
    )

    func stopResourceLoading(
        resourceKey: String,
        statusCode: Int?,
        kind: RUMResourceType,
        size: Int64?,
        attributes: [AttributeKey: AttributeValue]
    )

    func stopResourceLoadingWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse?,
        attributes: [AttributeKey: AttributeValue]
    )

    func stopResourceLoadingWithError(
        resourceKey: String,
        errorMessage: String,
        type: String?,
        response: URLResponse?,
        attributes: [AttributeKey: AttributeValue]
    )

    // MARK: - actions

    func addUserAction(
        type: RUMUserActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue]
    )

    func startUserAction(
        type: RUMUserActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue]
    )

    func stopUserAction(
        type: RUMUserActionType,
        name: String?,
        attributes: [AttributeKey: AttributeValue]
    )

    // MARK: - feature flags

    func addFeatureFlagEvaluation(
        name: String,
        value: Encodable
    )
}

// MARK: - NOP moniotor

struct NOPRUMMonitor: RUMMonitorProtocol {
    func addAttribute(forKey key: AttributeKey, value: AttributeValue) {}
    func removeAttribute(forKey key: AttributeKey) {}
    func stopSession() {}
    func startView(viewController: UIViewController, name: String?, attributes: [AttributeKey : AttributeValue]) {}
    func stopView(viewController: UIViewController, attributes: [AttributeKey : AttributeValue]) {}
    func startView(key: String, name: String?, attributes: [AttributeKey : AttributeValue]) {}
    func stopView(key: String, attributes: [AttributeKey : AttributeValue]) {}
    func addTiming(name: String) {}
    func addError(message: String, type: String?, stack: String?, source: DatadogRUM.RUMErrorSource, attributes: [AttributeKey : AttributeValue], file: StaticString?, line: UInt?) {}
    func addError(error: Error, source: DatadogRUM.RUMErrorSource, attributes: [AttributeKey : AttributeValue]) {}
    func startResourceLoading(resourceKey: String, request: URLRequest, attributes: [AttributeKey : AttributeValue]) {}
    func startResourceLoading(resourceKey: String, url: URL, attributes: [AttributeKey : AttributeValue]) {}
    func startResourceLoading(resourceKey: String, httpMethod: DatadogRUM.RUMMethod, urlString: String, attributes: [AttributeKey : AttributeValue]) {}
    func addResourceMetrics(resourceKey: String, metrics: URLSessionTaskMetrics, attributes: [AttributeKey : AttributeValue]) {}
    func addResourceMetrics(resourceKey: String, fetch: (start: Date, end: Date), redirection: (start: Date, end: Date)?, dns: (start: Date, end: Date)?, connect: (start: Date, end: Date)?, ssl: (start: Date, end: Date)?, firstByte: (start: Date, end: Date)?, download: (start: Date, end: Date)?, responseSize: Int64?, attributes: [AttributeKey : AttributeValue]) {}
    func stopResourceLoading(resourceKey: String, response: URLResponse, size: Int64?, attributes: [AttributeKey : AttributeValue]) {}
    func stopResourceLoading(resourceKey: String, statusCode: Int?, kind: DatadogRUM.RUMResourceType, size: Int64?, attributes: [AttributeKey : AttributeValue]) {}
    func stopResourceLoadingWithError(resourceKey: String, error: Error, response: URLResponse?, attributes: [AttributeKey : AttributeValue]) {}
    func stopResourceLoadingWithError(resourceKey: String, errorMessage: String, type: String?, response: URLResponse?, attributes: [AttributeKey : AttributeValue]) {}
    func addUserAction(type: DatadogRUM.RUMUserActionType, name: String, attributes: [AttributeKey : AttributeValue]) {}
    func startUserAction(type: DatadogRUM.RUMUserActionType, name: String, attributes: [AttributeKey : AttributeValue]) {}
    func stopUserAction(type: DatadogRUM.RUMUserActionType, name: String?, attributes: [AttributeKey : AttributeValue]) {}
    func addFeatureFlagEvaluation(name: String, value: Encodable) {}
}
