/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class URLSessionRUMResourcesHandler: URLSessionInterceptionHandler {
    private let dateProvider: DateProvider

    // MARK: - Initialization

    init(dateProvider: DateProvider) {
        self.dateProvider = dateProvider
    }

    // MARK: - Internal

    weak var subscriber: RUMCommandSubscriber?

    func subscribe(commandsSubscriber: RUMCommandSubscriber) {
        self.subscriber = commandsSubscriber
    }

    // MARK: - URLSessionInterceptionHandler

    func notify_taskInterceptionStarted(interception: TaskInterception) {
        let url = interception.request.url?.absoluteString ?? "unknown_url"

        subscriber?.process(
            command: RUMStartResourceCommand(
                resourceKey: interception.identifier.uuidString,
                time: dateProvider.currentDate(),
                attributes: [:],
                url: url,
                httpMethod: RUMHTTPMethod(request: interception.request),
                kind: RUMResourceKind(request: interception.request),
                spanContext: interception.spanContext.flatMap { spanContext in
                    .init(
                        traceID: String(spanContext.traceID.rawValue),
                        spanID: String(spanContext.spanID.rawValue)
                    )
                }
            )
        )
    }

    func notify_taskInterceptionCompleted(interception: TaskInterception) {
        if subscriber == nil {
            userLogger.warn(
                """
                RUM Resource was completed, but no `RUMMonitor` is registered on `Global.rum`. RUM auto instrumentation will not work.
                Make sure `Global.rum = RUMMonitor.initialize()` is called before any network request is send.
                """
            )
        }

        if let resourceMetrics = interception.metrics {
            subscriber?.process(
                command: RUMAddResourceMetricsCommand(
                    resourceKey: interception.identifier.uuidString,
                    time: dateProvider.currentDate(),
                    attributes: [:],
                    metrics: resourceMetrics
                )
            )
        }

        if let httpResponse = interception.completion?.httpResponse {
            subscriber?.process(
                command: RUMStopResourceCommand(
                    resourceKey: interception.identifier.uuidString,
                    time: dateProvider.currentDate(),
                    attributes: [:],
                    kind: RUMResourceKind(response: httpResponse),
                    httpStatusCode: httpResponse.statusCode,
                    size: interception.metrics?.responseSize
                )
            )
        }

        if let error = interception.completion?.error {
            subscriber?.process(
                command: RUMStopResourceWithErrorCommand(
                    resourceKey: interception.identifier.uuidString,
                    time: dateProvider.currentDate(),
                    error: error,
                    source: .network,
                    httpStatusCode: interception.completion?.httpResponse?.statusCode,
                    attributes: [:]
                )
            )
        }
    }
}
