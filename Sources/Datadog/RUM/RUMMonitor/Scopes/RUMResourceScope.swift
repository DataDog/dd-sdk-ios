/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class RUMResourceScope: RUMScope {
    // MARK: - Initialization

    let context: RUMContext
    private let dependencies: RUMScopeDependencies

    /// This Resource's UUID.
    private let resourceUUID: RUMUUID
    /// The name used to identify this Resource.
    private let resourceKey: String
    /// Resource attributes.
    private var attributes: [AttributeKey: AttributeValue]

    /// The Resource url.
    private var resourceURL: String
    /// The start time of this Resource loading.
    private var resourceLoadingStartTime: Date
    /// The HTTP method used to load this Resource.
    private var resourceHTTPMethod: RUMHTTPMethod
    /// The Resource kind captured when starting the `URLRequest`.
    /// It may be `nil` if it's not possible to predict the kind from resource and the response MIME type is needed.
    private var resourceKindBasedOnRequest: RUMResourceKind?

    /// The Resource metrics, if received. When sending RUM Resource event, `resourceMetrics` values
    /// take precedence over other values collected for this Resource.
    private var resourceMetrics: ResourceMetrics?

    /// Span context passed to the RUM backend in order to generate the APM span for underlying resource.
    private let spanContext: RUMSpanContext?

    init(
        context: RUMContext,
        dependencies: RUMScopeDependencies,
        resourceKey: String,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date,
        url: String,
        httpMethod: RUMHTTPMethod,
        resourceKindBasedOnRequest: RUMResourceKind?,
        spanContext: RUMSpanContext?
    ) {
        self.context = context
        self.dependencies = dependencies
        self.resourceUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.resourceKey = resourceKey
        self.attributes = attributes
        self.resourceURL = url
        self.resourceLoadingStartTime = startTime
        self.resourceHTTPMethod = httpMethod
        self.resourceKindBasedOnRequest = resourceKindBasedOnRequest
        self.spanContext = spanContext
    }

    // MARK: - RUMScope

    func process(command: RUMCommand) -> Bool {
        switch command {
        case let command as RUMStopResourceCommand where command.resourceKey == resourceKey:
            sendResourceEvent(on: command)
            return false
        case let command as RUMStopResourceWithErrorCommand where command.resourceKey == resourceKey:
            sendErrorEvent(on: command)
            return false
        case let command as RUMAddResourceMetricsCommand where command.resourceKey == resourceKey:
            resourceMetrics = command.metrics
        default:
            break
        }
        return true
    }

    // MARK: - Sending RUM Events

    private func sendResourceEvent(on command: RUMStopResourceCommand) {
        attributes.merge(rumCommandAttributes: command.attributes)

        let resourceStartTime: Date
        let resourceDuration: TimeInterval
        let size: Int64?

        /// Metrics values take precedence over other values.
        if let metrics = resourceMetrics {
            resourceStartTime = metrics.fetch.start
            resourceDuration = metrics.fetch.end.timeIntervalSince(metrics.fetch.start)
            size = metrics.responseSize ?? command.size
        } else {
            resourceStartTime = resourceLoadingStartTime
            resourceDuration = command.time.timeIntervalSince(resourceLoadingStartTime)
            size = command.size
        }

        let eventData = RUMDataResource(
            date: dependencies.dateCorrection.toServerDate(deviceDate: resourceStartTime).timeIntervalSince1970.toInt64Milliseconds,
            application: .init(id: context.rumApplicationID),
            service: nil,
            session: .init(id: context.sessionID.toRUMDataFormat, type: .user),
            view: .init(
                id: context.activeViewID.orNull.toRUMDataFormat,
                referrer: nil,
                url: context.activeViewURI ?? ""
            ),
            usr: dependencies.userInfoProvider.current,
            connectivity: dependencies.connectivityInfoProvider.current,
            dd: .init(
                spanID: spanContext?.spanID,
                traceID: spanContext?.traceID
            ),
            resource: .init(
                id: resourceUUID.toRUMDataFormat,
                type: (resourceKindBasedOnRequest ?? command.kind).toRUMDataFormat,
                method: resourceHTTPMethod.toRUMDataFormat,
                url: resourceURL,
                statusCode: command.httpStatusCode?.toInt64,
                duration: resourceDuration.toInt64Nanoseconds,
                size: size ?? 0,
                redirect: resourceMetrics?.redirection.flatMap { metric in
                    RUMDataRedirect(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                dns: resourceMetrics?.dns.flatMap { metric in
                    RUMDataDNS(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                connect: resourceMetrics?.connect.flatMap { metric in
                    RUMDataConnect(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                ssl: resourceMetrics?.ssl.flatMap { metric in
                    RUMDataSSL(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                firstByte: resourceMetrics?.firstByte.flatMap { metric in
                    RUMDataFirstByte(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                download: resourceMetrics?.download.flatMap { metric in
                    RUMDataDownload(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                }
            ),
            action: context.activeUserActionID.flatMap { rumUUID in
                .init(id: rumUUID.toRUMDataFormat)
            }
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }

    private func sendErrorEvent(on command: RUMStopResourceWithErrorCommand) {
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMDataError(
            date: dependencies.dateCorrection.toServerDate(deviceDate: command.time).timeIntervalSince1970.toInt64Milliseconds,
            application: .init(id: context.rumApplicationID),
            service: nil,
            session: .init(id: context.sessionID.toRUMDataFormat, type: .user),
            view: .init(
                id: context.activeViewID.orNull.toRUMDataFormat,
                referrer: nil,
                url: context.activeViewURI ?? ""
            ),
            usr: dependencies.userInfoProvider.current,
            connectivity: dependencies.connectivityInfoProvider.current,
            dd: .init(),
            error: .init(
                message: command.errorMessage,
                source: command.errorSource.toRUMDataFormat,
                stack: command.stack,
                isCrash: false,
                resource: .init(
                    method: resourceHTTPMethod.toRUMDataFormat,
                    statusCode: command.httpStatusCode?.toInt64 ?? 0,
                    url: resourceURL
                )
            ),
            action: context.activeUserActionID.flatMap { rumUUID in
                .init(id: rumUUID.toRUMDataFormat)
            }
        )

        let event = dependencies.eventBuilder.createRUMEvent(with: eventData, attributes: attributes)
        dependencies.eventOutput.write(rumEvent: event)
    }
}
