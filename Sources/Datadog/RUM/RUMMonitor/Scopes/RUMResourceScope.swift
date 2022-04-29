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
    let resourceUUID: RUMUUID
    /// The name used to identify this Resource.
    private let resourceKey: String
    /// Resource attributes.
    private var attributes: [AttributeKey: AttributeValue]

    /// The Resource url.
    private var resourceURL: String
    /// The start time of this Resource loading.
    private var resourceLoadingStartTime: Date
    /// Date correction to server time.
    private let dateCorrection: DateCorrection
    /// The HTTP method used to load this Resource.
    private var resourceHTTPMethod: RUMMethod
    /// Whether or not the Resource is provided by a first party host, if that information is available.
    private let isFirstPartyResource: Bool?
    /// The Resource kind captured when starting the `URLRequest`.
    /// It may be `nil` if it's not possible to predict the kind from resource and the response MIME type is needed.
    private var resourceKindBasedOnRequest: RUMResourceType?

    /// The Resource metrics, if received. When sending RUM Resource event, `resourceMetrics` values
    /// take precedence over other values collected for this Resource.
    private var resourceMetrics: ResourceMetrics?

    /// Span context passed to the RUM backend in order to generate the APM span for underlying resource.
    private let spanContext: RUMSpanContext?

    /// Callback called when a `RUMResourceEvent` is submitted for storage.
    private let onResourceEventSent: () -> Void
    /// Callback called when a `RUMErrorEvent` is submitted for storage.
    private let onErrorEventSent: () -> Void

    init(
        context: RUMContext,
        dependencies: RUMScopeDependencies,
        resourceKey: String,
        attributes: [AttributeKey: AttributeValue],
        startTime: Date,
        dateCorrection: DateCorrection,
        url: String,
        httpMethod: RUMMethod,
        isFirstPartyResource: Bool?,
        resourceKindBasedOnRequest: RUMResourceType?,
        spanContext: RUMSpanContext?,
        onResourceEventSent: @escaping () -> Void,
        onErrorEventSent: @escaping () -> Void
    ) {
        self.context = context
        self.dependencies = dependencies
        self.resourceUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.resourceKey = resourceKey
        self.attributes = attributes
        self.resourceURL = url
        self.resourceLoadingStartTime = startTime
        self.dateCorrection = dateCorrection
        self.resourceHTTPMethod = httpMethod
        self.isFirstPartyResource = isFirstPartyResource
        self.resourceKindBasedOnRequest = resourceKindBasedOnRequest
        self.spanContext = spanContext
        self.onResourceEventSent = onResourceEventSent
        self.onErrorEventSent = onErrorEventSent
    }

    // MARK: - RUMScope

    func process(command: RUMCommand) -> Bool {
        switch command {
        case let command as RUMStopResourceCommand where command.resourceKey == resourceKey:
            if sendResourceEvent(on: command) {
                onResourceEventSent()
            }
            return false
        case let command as RUMStopResourceWithErrorCommand where command.resourceKey == resourceKey:
            if sendErrorEvent(on: command) {
                onErrorEventSent()
            }
            return false
        case let command as RUMAddResourceMetricsCommand where command.resourceKey == resourceKey:
            addMetrics(from: command)
        default:
            break
        }
        return true
    }

    private func addMetrics(from command: RUMAddResourceMetricsCommand) {
        attributes.merge(rumCommandAttributes: command.attributes)
        resourceMetrics = command.metrics
    }

    // MARK: - Sending RUM Events

    private func sendResourceEvent(on command: RUMStopResourceCommand) -> Bool {
        attributes.merge(rumCommandAttributes: command.attributes)

        let resourceStartTime: Date
        let resourceDuration: TimeInterval
        let size: Int64?

        // Check trace attributes
        let traceId = (attributes.removeValue(forKey: CrossPlatformAttributes.traceID) as? String) ?? spanContext?.traceID
        let spanId = (attributes.removeValue(forKey: CrossPlatformAttributes.spanID) as? String) ?? spanContext?.spanID

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
        let resourceType: RUMResourceType = resourceKindBasedOnRequest ?? command.kind

        let eventData = RUMResourceEvent(
            dd: .init(
                browserSdkVersion: nil,
                session: .init(plan: .plan1),
                spanId: spanId,
                traceId: traceId
            ),
            action: context.activeUserActionID.flatMap { rumUUID in
                .init(id: rumUUID.toRUMDataFormat)
            },
            application: .init(id: context.rumApplicationID),
            ciTest: dependencies.ciTest,
            connectivity: dependencies.connectivityInfoProvider.current,
            context: .init(contextInfo: attributes),
            date: dateCorrection.applying(to: resourceStartTime).timeIntervalSince1970.toInt64Milliseconds,
            resource: .init(
                connect: resourceMetrics?.connect.flatMap { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                dns: resourceMetrics?.dns.flatMap { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                download: resourceMetrics?.download.flatMap { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                duration: resolveResourceDuration(resourceDuration),
                firstByte: resourceMetrics?.firstByte.flatMap { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                id: resourceUUID.toRUMDataFormat,
                method: resourceHTTPMethod,
                provider: resourceEventProvider,
                redirect: resourceMetrics?.redirection.flatMap { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                size: size,
                ssl: resourceMetrics?.ssl.flatMap { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                statusCode: command.httpStatusCode?.toInt64,
                type: resourceType,
                url: resourceURL
            ),
            service: dependencies.serviceName,
            session: .init(
                hasReplay: nil,
                id: context.sessionID.toRUMDataFormat,
                type: dependencies.ciTest != nil ? .ciTest : .user
            ),
            source: RUMResourceEvent.Source(rawValue: dependencies.source) ?? .ios,
            synthetics: nil,
            usr: dependencies.userInfoProvider.current,
            version: dependencies.applicationVersion,
            view: .init(
                id: context.activeViewID.orNull.toRUMDataFormat,
                name: context.activeViewName,
                referrer: nil,
                url: context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: eventData) {
            dependencies.eventOutput.write(event: event)
            return true
        }
        return false
    }

    private func sendErrorEvent(on command: RUMStopResourceWithErrorCommand) -> Bool {
        attributes.merge(rumCommandAttributes: command.attributes)

        let eventData = RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                session: .init(plan: .plan1)
            ),
            action: context.activeUserActionID.flatMap { rumUUID in
                .init(id: rumUUID.toRUMDataFormat)
            },
            application: .init(id: context.rumApplicationID),
            ciTest: dependencies.ciTest,
            connectivity: dependencies.connectivityInfoProvider.current,
            context: .init(contextInfo: attributes),
            date: dateCorrection.applying(to: command.time).timeIntervalSince1970.toInt64Milliseconds,
            error: .init(
                handling: nil,
                handlingStack: nil,
                id: nil,
                isCrash: false,
                message: command.errorMessage,
                resource: .init(
                    method: resourceHTTPMethod,
                    provider: errorEventProvider,
                    statusCode: command.httpStatusCode?.toInt64 ?? 0,
                    url: resourceURL
                ),
                source: command.errorSource.toRUMDataFormat,
                sourceType: command.errorSourceType,
                stack: command.stack,
                type: command.errorType
            ),
            service: dependencies.serviceName,
            session: .init(
                hasReplay: nil,
                id: context.sessionID.toRUMDataFormat,
                type: dependencies.ciTest != nil ? .ciTest : .user
            ),
            source: RUMErrorEvent.Source(rawValue: dependencies.source) ?? .ios,
            synthetics: nil,
            usr: dependencies.userInfoProvider.current,
            version: dependencies.applicationVersion,
            view: .init(
                id: context.activeViewID.orNull.toRUMDataFormat,
                inForeground: nil,
                name: context.activeViewName,
                referrer: nil,
                url: context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: eventData) {
            dependencies.eventOutput.write(event: event)
            return true
        }
        return false
    }

    // MARK: - Resource provider helpers

    private var resourceEventProvider: RUMResourceEvent.Resource.Provider? {
        if isFirstPartyResource == true {
            return RUMResourceEvent.Resource.Provider(
                domain: providerDomain(from: resourceURL),
                name: nil,
                type: .firstParty
            )
        } else {
            return nil
        }
    }

    private var errorEventProvider: RUMErrorEvent.Error.Resource.Provider? {
        if isFirstPartyResource == true {
            return RUMErrorEvent.Error.Resource.Provider(
                domain: providerDomain(from: resourceURL),
                name: nil,
                type: .firstParty
            )
        } else {
            return nil
        }
    }

    private func providerDomain(from url: String) -> String? {
        return URL(string: url)?.host ?? url
    }

    private func resolveResourceDuration(_ duration: TimeInterval) -> Int64 {
        if duration <= 0.0 {
            let negativeDurationWarningMessage =
            """
            The computed duration for your resource: \(resourceURL) was 0 or negative. In order to keep the resource event we forced it to 1ns.
            """
            userLogger.warn(negativeDurationWarningMessage)
            return 1 // 1ns
        }
        return duration.toInt64Nanoseconds
    }
}
