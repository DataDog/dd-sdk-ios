/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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

    /// Server time offset for date correction.
    ///
    /// The offset should be applied to event's timestamp for synchronizing
    /// local time with server time. This time interval value can be added to
    /// any date that needs to be synced. e.g:
    ///
    ///     date.addingTimeInterval(serverTimeOffset)
    private let serverTimeOffset: TimeInterval

    /// The HTTP method used to load this Resource.
    private var resourceHTTPMethod: RUMMethod
    /// Whether or not the Resource is provided by a first party host, if that information is available.
    private let isFirstPartyResource: Bool
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
        serverTimeOffset: TimeInterval,
        url: String,
        httpMethod: RUMMethod,
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
        self.serverTimeOffset = serverTimeOffset
        self.resourceHTTPMethod = httpMethod
        self.isFirstPartyResource = dependencies.firstPartyHosts?.isFirstParty(string: url) ?? false
        self.resourceKindBasedOnRequest = resourceKindBasedOnRequest
        self.spanContext = spanContext
        self.onResourceEventSent = onResourceEventSent
        self.onErrorEventSent = onErrorEventSent
    }

    // MARK: - RUMScope

    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        switch command {
        case let command as RUMStopResourceCommand where command.resourceKey == resourceKey:
            sendResourceEvent(on: command, context: context, writer: writer)
            return false
        case let command as RUMStopResourceWithErrorCommand where command.resourceKey == resourceKey:
            sendErrorEvent(on: command, context: context, writer: writer)
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

    private func sendResourceEvent(on command: RUMStopResourceCommand, context: DatadogContext, writer: Writer) {
        attributes.merge(rumCommandAttributes: command.attributes)

        let resourceStartTime: Date
        let resourceDuration: TimeInterval
        let size: Int64?

        // Check trace attributes
        let traceId = (attributes.removeValue(forKey: CrossPlatformAttributes.traceID) as? String) ?? spanContext?.traceID
        let spanId = (attributes.removeValue(forKey: CrossPlatformAttributes.spanID) as? String) ?? spanContext?.spanID
        let traceSamplingRate = (attributes.removeValue(forKey: CrossPlatformAttributes.rulePSR) as? Double) ?? spanContext?.samplingRate

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

        let resourceEvent = RUMResourceEvent(
            dd: .init(
                browserSdkVersion: nil,
                discarded: nil,
                rulePsr: traceSamplingRate,
                session: .init(plan: .plan1),
                spanId: spanId,
                traceId: traceId
            ),
            action: self.context.activeUserActionID.map { rumUUID in
                .init(id: .string(value: rumUUID.toRUMDataFormat))
            },
            application: .init(id: self.context.rumApplicationID),
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            context: .init(contextInfo: attributes),
            date: resourceStartTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: .init(context: context),
            display: nil,
            os: .init(context: context),
            resource: .init(
                connect: resourceMetrics?.connect.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                dns: resourceMetrics?.dns.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                download: resourceMetrics?.download.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                duration: resolveResourceDuration(resourceDuration),
                firstByte: resourceMetrics?.firstByte.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                id: resourceUUID.toRUMDataFormat,
                method: resourceHTTPMethod,
                provider: resourceEventProvider,
                redirect: resourceMetrics?.redirection.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                size: size ?? 0,
                ssl: resourceMetrics?.ssl.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                statusCode: command.httpStatusCode?.toInt64 ?? 0,
                type: resourceType,
                url: resourceURL
            ),
            service: context.service,
            session: .init(
                hasReplay: context.srBaggage?.isReplayBeingRecorded,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.ciTest != nil ? .ciTest : .user
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: nil,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                id: self.context.activeViewID.orNull.toRUMDataFormat,
                name: self.context.activeViewName,
                referrer: nil,
                url: self.context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: resourceEvent) {
            writer.write(value: event)
            onResourceEventSent()
        }
    }

    private func sendErrorEvent(on command: RUMStopResourceWithErrorCommand, context: DatadogContext, writer: Writer) {
        attributes.merge(rumCommandAttributes: command.attributes)

        let errorEvent = RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                session: .init(plan: .plan1)
            ),
            action: self.context.activeUserActionID.map { rumUUID in
                .init(id: .string(value: rumUUID.toRUMDataFormat))
            },
            application: .init(id: self.context.rumApplicationID),
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            context: .init(contextInfo: attributes),
            date: command.time.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: .init(context: context),
            display: nil,
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
            os: .init(context: context),
            service: context.service,
            session: .init(
                hasReplay: context.srBaggage?.isReplayBeingRecorded,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.ciTest != nil ? .ciTest : .user
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: nil,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                id: self.context.activeViewID.orNull.toRUMDataFormat,
                inForeground: nil,
                name: self.context.activeViewName,
                referrer: nil,
                url: self.context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: errorEvent) {
            writer.write(value: event)
            onErrorEventSent()
        }
    }

    // MARK: - Resource provider helpers

    private var resourceEventProvider: RUMResourceEvent.Resource.Provider? {
        guard isFirstPartyResource == true else {
            return nil
        }

        return RUMResourceEvent.Resource.Provider(
            domain: providerDomain(from: resourceURL),
            name: nil,
            type: .firstParty
        )
    }

    private var errorEventProvider: RUMErrorEvent.Error.Resource.Provider? {
        guard isFirstPartyResource == true else {
            return nil
        }

        return RUMErrorEvent.Error.Resource.Provider(
            domain: providerDomain(from: resourceURL),
            name: nil,
            type: .firstParty
        )
    }

    private func providerDomain(from url: String) -> String? {
        return URL(string: url)?.host ?? url
    }

    private func resolveResourceDuration(_ duration: TimeInterval) -> Int64 {
        guard duration > 0.0 else {
            DD.logger.warn(
                """
                The computed duration for your resource: \(resourceURL) was 0 or negative. In order to keep the resource event we forced it to 1ns.
                """
            )
            return 1 // 1ns
        }

        return duration.toInt64Nanoseconds
    }
}
