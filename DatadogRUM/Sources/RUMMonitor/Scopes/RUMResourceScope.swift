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

    /// Container bundling dependencies for this scope.
    let dependencies: RUMScopeDependencies

    /// This Resource's UUID.
    let resourceUUID: RUMUUID
    /// The name used to identify this Resource.
    private let resourceKey: String
    /// Resource attributes.
    private var attributes: [AttributeKey: AttributeValue] = [:]

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

    /// The Time-to-Network-Settled metric for the view that tracks this resource.
    private let networkSettledMetric: TNSMetricTracking

    /// Callback called when a `RUMResourceEvent` is submitted for storage.
    private let onResourceEvent: (_ sent: Bool) -> Void
    /// Callback called when a `RUMErrorEvent` is submitted for storage.
    private let onErrorEvent: (_ sent: Bool) -> Void

    init(
        context: RUMContext,
        dependencies: RUMScopeDependencies,
        resourceKey: String,
        startTime: Date,
        serverTimeOffset: TimeInterval,
        url: String,
        httpMethod: RUMMethod,
        resourceKindBasedOnRequest: RUMResourceType?,
        spanContext: RUMSpanContext?,
        networkSettledMetric: TNSMetricTracking,
        onResourceEvent: @escaping (Bool) -> Void,
        onErrorEvent: @escaping (Bool) -> Void
    ) {
        self.context = context
        self.dependencies = dependencies
        self.resourceUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.resourceKey = resourceKey
        self.resourceURL = url
        self.resourceLoadingStartTime = startTime
        self.serverTimeOffset = serverTimeOffset
        self.resourceHTTPMethod = httpMethod
        self.isFirstPartyResource = dependencies.firstPartyHosts?.isFirstParty(string: url) ?? false
        self.resourceKindBasedOnRequest = resourceKindBasedOnRequest
        self.spanContext = spanContext
        self.networkSettledMetric = networkSettledMetric
        self.onResourceEvent = onResourceEvent
        self.onErrorEvent = onErrorEvent

        // Track this resource in view's TNS metric:
        networkSettledMetric.trackResourceStart(at: startTime, resourceID: resourceUUID, resourceURL: url)
    }

    // MARK: - RUMScope

    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        self.attributes = self.attributes.merging(command.attributes, uniquingKeysWith: { $1 })

        switch command {
        case let command as RUMStopResourceCommand where command.resourceKey == resourceKey:
            sendResourceEvent(on: command, context: context, writer: writer)
            return false
        case let command as RUMStopResourceWithErrorCommand where command.resourceKey == resourceKey:
            sendErrorEvent(on: command, context: context, writer: writer)
            return false
        case let command as RUMAddResourceMetricsCommand where command.resourceKey == resourceKey:
            resourceMetrics = command.metrics
        default:
            break
        }
        return true
    }

    // MARK: - Sending RUM Events

    private func sendResourceEvent(on command: RUMStopResourceCommand, context: DatadogContext, writer: Writer) {
        let resourceStartTime: Date
        let resourceDuration: TimeInterval
        let size: Int64?

        // Check trace attributes
        let traceId: TraceID? = attributes.removeValue(forKey: CrossPlatformAttributes.traceID)?
            .dd.decode()
            .map { .init($0, representation: .hexadecimal) }
            ?? spanContext?.traceID

        let spanId: SpanID? = attributes.removeValue(forKey: CrossPlatformAttributes.spanID)?
            .dd.decode()
            .map { .init($0, representation: .decimal) }
            ?? spanContext?.spanID

        let traceSamplingRate = attributes.removeValue(forKey: CrossPlatformAttributes.rulePSR)?.dd.decode() ?? spanContext?.samplingRate

        // Check GraphQL attributes
        var graphql: RUMResourceEvent.Resource.Graphql? = nil
        let graphqlOperationName: String? = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlOperationName)?.dd.decode()
        let graphqlPayload: String? = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlPayload)?.dd.decode()
        let graphqlVariables: String? = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlVariables)?.dd.decode()
        if
            let rawGraphqlOperationType: String = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlOperationType)?.dd.decode(),
            let graphqlOperationType = RUMResourceEvent.Resource.Graphql.OperationType(rawValue: rawGraphqlOperationType) {
            graphql = .init(
                operationName: graphqlOperationName,
                operationType: graphqlOperationType,
                payload: graphqlPayload,
                variables: graphqlVariables
            )
        }

        // Metrics values take precedence over other values.
        if let metrics = resourceMetrics {
            resourceStartTime = metrics.fetch.start
            resourceDuration = metrics.fetch.end.timeIntervalSince(metrics.fetch.start)
            size = metrics.responseSize ?? command.size
        } else {
            resourceStartTime = resourceLoadingStartTime
            resourceDuration = command.time.timeIntervalSince(resourceLoadingStartTime)
            size = command.size
        }

        // Write resource event
        let resourceEvent = RUMResourceEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(
                    sessionReplaySampleRate: nil,
                    sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)
                ),
                discarded: nil,
                rulePsr: traceSamplingRate,
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: self.context.sessionPrecondition
                ),
                spanId: spanId?.toString(representation: .decimal),
                traceId: traceId?.toString(representation: .hexadecimal)
            ),
            action: self.context.activeUserActionID.map { rumUUID in
                .init(id: .string(value: rumUUID.toRUMDataFormat))
            },
            application: .init(id: self.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: command.globalAttributes.merging(attributes) { $1 }),
            date: resourceStartTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: .init(context: context, telemetry: dependencies.telemetry),
            display: nil,
            os: .init(device: context.device),
            resource: .init(
                connect: resourceMetrics?.connect.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                decodedBodySize: nil,
                deliveryType: nil,
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
                encodedBodySize: nil,
                firstByte: resourceMetrics?.firstByte.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                graphql: graphql,
                id: resourceUUID.toRUMDataFormat,
                method: resourceHTTPMethod,
                protocol: nil,
                provider: resourceEventProvider,
                redirect: resourceMetrics?.redirection.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                renderBlockingStatus: nil,
                size: size ?? 0,
                ssl: resourceMetrics?.ssl.map { metric in
                    .init(
                        duration: metric.duration.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).toInt64Nanoseconds
                    )
                },
                statusCode: command.httpStatusCode?.toInt64 ?? 0,
                transferSize: nil,
                type: resourceKindBasedOnRequest ?? command.kind,
                url: resourceURL,
                worker: nil
            ),
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
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
            onResourceEvent(true)
            networkSettledMetric.trackResourceEnd(at: command.time, resourceID: resourceUUID, resourceDuration: resourceDuration)
        } else {
            onResourceEvent(false)
            networkSettledMetric.trackResourceDropped(resourceID: resourceUUID)
        }
    }

    private func sendErrorEvent(on command: RUMStopResourceWithErrorCommand, context: DatadogContext, writer: Writer) {
        let errorFingerprint: String? = attributes.removeValue(forKey: RUM.Attributes.errorFingerprint)?.dd.decode()
        let timeSinceAppStart = command.time.timeIntervalSince(context.launchTime.launchDate).toInt64Milliseconds

        // Write error event
        let errorEvent = RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: self.context.sessionPrecondition
                )
            ),
            action: self.context.activeUserActionID.map { rumUUID in
                .init(id: .string(value: rumUUID.toRUMDataFormat))
            },
            application: .init(id: self.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: command.globalAttributes.merging(attributes) { $1 }),
            date: command.time.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: .init(context: context, telemetry: dependencies.telemetry),
            display: nil,
            error: .init(
                binaryImages: nil,
                category: .exception, // resource errors are categorised as "Exception"
                csp: nil,
                fingerprint: errorFingerprint,
                handling: nil,
                handlingStack: nil,
                id: nil,
                isCrash: false,
                message: command.errorMessage,
                meta: nil,
                resource: .init(
                    method: resourceHTTPMethod,
                    provider: errorEventProvider,
                    statusCode: command.httpStatusCode?.toInt64 ?? 0,
                    url: resourceURL
                ),
                source: command.errorSource.toRUMDataFormat,
                sourceType: command.errorSourceType,
                stack: command.stack,
                threads: nil,
                timeSinceAppStart: timeSinceAppStart,
                type: command.errorType,
                wasTruncated: nil
            ),
            freeze: nil,
            os: .init(device: context.device),
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
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
            onErrorEvent(true)
            networkSettledMetric.trackResourceEnd(at: command.time, resourceID: resourceUUID, resourceDuration: nil)
        } else {
            onErrorEvent(false)
            networkSettledMetric.trackResourceDropped(resourceID: resourceUUID)
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
