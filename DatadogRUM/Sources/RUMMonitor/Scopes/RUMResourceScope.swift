/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class RUMResourceScope: RUMScope {
    // MARK: - Initialization

    let parent: RUMContextProvider

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
        parent: RUMContextProvider,
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
        self.parent = parent
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
            networkSettledMetric.updateResource(with: command.metrics, resourceID: resourceUUID, resourceURL: resourceURL)
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
        let graphqlErrorsString: String? = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlErrors)?.dd.decode()

        // Parse GraphQL errors if present
        let graphqlErrors = parseGraphQLErrors(from: graphqlErrorsString)

        if
            let rawGraphqlOperationType: String = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlOperationType)?.dd.decode(),
            let graphqlOperationType = RUMResourceEvent.Resource.Graphql.OperationType(rawValue: rawGraphqlOperationType) {
            graphql = .init(
                errorCount: graphqlErrors?.count.toInt64,
                errors: graphqlErrors,
                operationName: graphqlOperationName,
                operationType: graphqlOperationType,
                payload: graphqlPayload,
                variables: graphqlVariables
            )
        }

        // Extract captured HTTP headers
        let requestHeaders: [String: String]? = attributes.removeValue(forKey: CrossPlatformAttributes.resourceRequestHeaders)?.dd.decode()
        let responseHeaders: [String: String]? = attributes.removeValue(forKey: CrossPlatformAttributes.resourceResponseHeaders)?.dd.decode()

        // Metrics values take precedence over other values.
        if let metrics = resourceMetrics {
            resourceStartTime = metrics.fetch.start
            resourceDuration = metrics.fetch.end.timeIntervalSince(metrics.fetch.start)
            let metricsSize = metrics.responseBodySize?.decoded ?? 0
            size = metricsSize > 0 ? metricsSize : command.size
        } else {
            resourceStartTime = resourceLoadingStartTime
            resourceDuration = command.time.timeIntervalSince(resourceLoadingStartTime)
            size = command.size
        }

        let encodedBodySize = resourceMetrics?.responseBodySize?.encoded
        let decodedBodySize = resourceMetrics?.responseBodySize?.decoded

        let requestHeadersObj = requestHeaders.flatMap { $0.isEmpty ? nil : RUMResourceEvent.Resource.Request.Headers(headersInfo: $0) }
        var request: RUMResourceEvent.Resource.Request? = resourceMetrics?.requestBodySize.map { size in
            .init(
                decodedBodySize: size.decoded,
                encodedBodySize: size.encoded,
                headers: requestHeadersObj
            )
        }
        if request == nil, let requestHeadersObj {
            request = .init(headers: requestHeadersObj)
        }

        let response: RUMResourceEvent.Resource.Response? = responseHeaders.flatMap { headers in
            headers.isEmpty ? nil : .init(headers: .init(headersInfo: headers))
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
                    sessionPrecondition: parent.context.sessionPrecondition
                ),
                spanId: spanId?.toString(representation: .decimal),
                traceId: traceId?.toString(representation: .hexadecimal)
            ),
            account: .init(context: context),
            action: parent.context.activeUserActionID.map { rumUUID in
                .init(id: .string(value: rumUUID.toRUMDataFormat))
            },
            application: .init(id: parent.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: command.globalAttributes.merging(parent.attributes) { $1 }.merging(attributes) { $1 }),
            date: resourceStartTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
            ddtags: context.ddTags,
            device: context.normalizedDevice(),
            display: nil,
            os: context.os,
            resource: .init(
                connect: resourceMetrics?.connect.map { metric in
                    .init(
                        duration: metric.duration.dd.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).dd.toInt64Nanoseconds
                    )
                },
                decodedBodySize: decodedBodySize,
                deliveryType: nil,
                dns: resourceMetrics?.dns.map { metric in
                    .init(
                        duration: metric.duration.dd.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).dd.toInt64Nanoseconds
                    )
                },
                download: resourceMetrics?.download.map { metric in
                    .init(
                        duration: metric.duration.dd.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).dd.toInt64Nanoseconds
                    )
                },
                duration: resolveResourceDuration(resourceDuration),
                encodedBodySize: encodedBodySize,
                firstByte: resourceMetrics?.firstByte.map { metric in
                    .init(
                        duration: metric.duration.dd.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).dd.toInt64Nanoseconds
                    )
                },
                graphql: graphql,
                id: resourceUUID.toRUMDataFormat,
                method: resourceHTTPMethod,
                protocol: nil,
                provider: resourceEventProvider,
                redirect: resourceMetrics?.redirection.map { metric in
                    .init(
                        duration: metric.duration.dd.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).dd.toInt64Nanoseconds
                    )
                },
                renderBlockingStatus: nil,
                request: request,
                response: response,
                size: size ?? 0,
                ssl: resourceMetrics?.ssl.map { metric in
                    .init(
                        duration: metric.duration.dd.toInt64Nanoseconds,
                        start: metric.start.timeIntervalSince(resourceStartTime).dd.toInt64Nanoseconds
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
                id: parent.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                id: parent.context.activeViewID.orNull.toRUMDataFormat,
                name: parent.context.activeViewName,
                referrer: nil,
                url: parent.context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: resourceEvent) {
            writer.write(value: event)
            onResourceEvent(true)
            networkSettledMetric.trackResourceEnd(
                at: resourceMetrics?.fetch.end ?? command.time,
                resourceID: resourceUUID,
                resourceDuration: resourceDuration
            )
        } else {
            onResourceEvent(false)
            networkSettledMetric.trackResourceDropped(resourceID: resourceUUID)
        }
    }

    private func sendErrorEvent(on command: RUMStopResourceWithErrorCommand, context: DatadogContext, writer: Writer) {
        let errorFingerprint: String? = attributes.removeValue(forKey: RUM.Attributes.errorFingerprint)?.dd.decode()
        let timeSinceAppStart = command.time.timeIntervalSince(context.launchInfo.processLaunchDate).dd.toInt64Milliseconds

        // Write error event
        let errorEvent = RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: parent.context.sessionPrecondition
                )
            ),
            account: .init(context: context),
            action: parent.context.activeUserActionID.map { rumUUID in
                .init(id: .string(value: rumUUID.toRUMDataFormat))
            },
            application: .init(id: parent.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: command.globalAttributes.merging(parent.attributes) { $1 }.merging(attributes) { $1 }),
            date: command.time.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.dd.toInt64Milliseconds,
            ddtags: context.ddTags,
            device: context.normalizedDevice(),
            display: nil,
            error: .init(
                binaryImages: nil,
                category: command.isNetworkError ? .network : .exception,
                csp: nil,
                fingerprint: errorFingerprint,
                handling: nil,
                handlingStack: nil,
                id: dependencies.rumUUIDGenerator.generateUnique().toRUMDataFormat,
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
            os: context.os,
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: parent.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                id: parent.context.activeViewID.orNull.toRUMDataFormat,
                inForeground: nil,
                name: parent.context.activeViewName,
                referrer: nil,
                url: parent.context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: errorEvent) {
            writer.write(value: event)
            onErrorEvent(true)
            networkSettledMetric.trackResourceEnd(
                at: resourceMetrics?.fetch.end ?? command.time,
                resourceID: resourceUUID,
                resourceDuration: nil
            )
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

        return duration.dd.toInt64Nanoseconds
    }

    /// Decodes GraphQL errors from JSON string and returns them as RUM event errors
    private func parseGraphQLErrors(from jsonString: String?) -> [RUMResourceEvent.Resource.Graphql.Errors]? {
        guard let jsonString, !jsonString.isEmpty else {
            return nil
        }

        guard let data = jsonString.data(using: .utf8) else {
            DD.logger.debug("Failed to convert GraphQL errors string to UTF-8 data")
            return nil
        }

        do {
            let responseErrors = try JSONDecoder().decode([GraphQLResponseError].self, from: data)

            guard !responseErrors.isEmpty else {
                return nil
            }

            let parsedErrors = responseErrors.map { error in
                RUMResourceEvent.Resource.Graphql.Errors(
                    code: error.code,
                    locations: error.locations?.map { location in
                        RUMResourceEvent.Resource.Graphql.Errors.Locations(
                            column: Int64(location.column),
                            line: Int64(location.line)
                        )
                    },
                    message: error.message,
                    path: error.path?.map { pathElement in
                        switch pathElement {
                        case .string(let value):
                            return .string(value: value)
                        case .int(let value):
                            return .integer(value: Int64(value))
                        }
                    }
                )
            }

            return parsedErrors
        } catch {
            DD.logger.debug("Failed to decode GraphQL errors: \(error)")
            return nil
        }
    }
}
