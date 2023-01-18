/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

/// The no-op variant of `DDRUMMonitor`.
internal class DDNoopRUMMonitor: DDRUMMonitor {
    private func warn() {
        DD.logger.critical(
            """
            The `Global.rum` was called but no `RUMMonitor` is registered. Configure and register the RUM Monitor globally before invoking the feature:
                Global.rum = RUMMonitor.initialize()
            See https://docs.datadoghq.com/real_user_monitoring/ios
            """
        )
    }

    override func startView(
        viewController: UIViewController,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func stopView(
        viewController: UIViewController,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func startView(
        key: String,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func stopView(
        key: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func addTiming(
        name: String
    ) {
        warn()
    }

    override func addError(
        message: String,
        type: String? = nil,
        source: RUMErrorSource = .custom,
        stack: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:],
        file: StaticString? = #file,
        line: UInt? = #line
    ) {
        warn()
    }

    override func addError(
        error: Error,
        source: RUMErrorSource = .custom,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func startResourceLoading(
        resourceKey: String,
        request: URLRequest,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func startResourceLoading(
        resourceKey: String,
        url: URL,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func startResourceLoading(
        resourceKey: String,
        httpMethod: RUMMethod,
        urlString: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func addResourceMetrics(
        resourceKey: String,
        metrics: URLSessionTaskMetrics,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func addResourceMetrics(
        resourceKey: String,
        fetch: (start: Date, end: Date),
        redirection: (start: Date, end: Date)?,
        dns: (start: Date, end: Date)?,
        connect: (start: Date, end: Date)?,
        ssl: (start: Date, end: Date)?,
        firstByte: (start: Date, end: Date)?,
        download: (start: Date, end: Date)?,
        responseSize: Int64?,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func stopResourceLoading(
        resourceKey: String,
        response: URLResponse,
        size: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func stopResourceLoading(
        resourceKey: String,
        statusCode: Int?,
        kind: RUMResourceType,
        size: Int64? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func stopResourceLoadingWithError(
        resourceKey: String,
        error: Error,
        response: URLResponse? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func stopResourceLoadingWithError(
        resourceKey: String,
        errorMessage: String,
        type: String? = nil,
        response: URLResponse? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func startUserAction(
        type: RUMUserActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func stopUserAction(
        type: RUMUserActionType,
        name: String? = nil,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func addUserAction(
        type: RUMUserActionType,
        name: String,
        attributes: [AttributeKey: AttributeValue] = [:]
    ) {
        warn()
    }

    override func addAttribute(forKey key: AttributeKey, value: AttributeValue) {
        warn()
    }

    override func removeAttribute(forKey key: AttributeKey) {
        warn()
    }
}
