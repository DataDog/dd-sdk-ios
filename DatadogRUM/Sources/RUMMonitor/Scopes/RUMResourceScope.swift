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

        // Trace context from cross-platform attributes or spanContext fallback
        let traceContext = extractTraceAttributes()

        // GraphQL attributes from cross-platform attributes
        let graphql = extractGraphQL()

        // Extract captured HTTP headers
        let requestHeaders: [String: String]? = attributes.removeValue(forKey: CrossPlatformAttributes.requestHeaders)?.dd.decode()
        let responseHeaders: [String: String]? = attributes.removeValue(forKey: CrossPlatformAttributes.responseHeaders)?.dd.decode()

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
        let request: RUMResourceEvent.Resource.Request? = {
            let hasBodySize = resourceMetrics?.requestBodySize != nil
            let hasHeaders = requestHeadersObj != nil

            guard hasBodySize || hasHeaders else {
                return nil
            }

            return .init(
                decodedBodySize: resourceMetrics?.requestBodySize?.decoded,
                encodedBodySize: resourceMetrics?.requestBodySize?.encoded,
                headers: requestHeadersObj
            )
        }()

        let response: RUMResourceEvent.Resource.Response? = responseHeaders.flatMap { headers in
            headers.isEmpty ? nil : .init(headers: .init(headersInfo: headers))
        }

        // Write resource event
        let resourceEvent = RUMResourceEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(
                    sessionReplaySampleRate: nil,
                    sessionSampleRate: Double(dependencies.samplingRate)
                ),
                discarded: nil,
                parentSpanId: traceContext.parentSpanID?.toString(representation: .decimal),
                rulePsr: traceContext.samplingRate,
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: parent.context.sessionPrecondition
                ),
                spanId: traceContext.spanID?.toString(representation: .decimal),
                traceId: traceContext.traceID?.toString(representation: .hexadecimal)
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

        // Trace context from cross-platform attributes or spanContext fallback
        let traceContext = extractTraceAttributes()

        // GraphQL attributes from cross-platform attributes
        let graphql = extractGraphQL()

        // Write error event
        let errorEvent = RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.samplingRate)),
                parentSpanId: traceContext.parentSpanID?.toString(representation: .decimal),
                rulePsr: traceContext.samplingRate,
                session: .init(plan: .plan1, sessionPrecondition: parent.context.sessionPrecondition),
                spanId: traceContext.spanID?.toString(representation: .decimal),
                traceId: traceContext.traceID?.toString(representation: .hexadecimal)
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
                    graphql: graphql,
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

    /// Decodes GraphQL errors JSON string into intermediate response error models.
    ///
    /// Note: The cross-platform attribute `_dd.graphql.errors` contains a JSON array of error objects
    /// (e.g. `[{"message": "...", "locations": [...]}]`), not a full GraphQL response body.
    /// This is why we decode `[GraphQLResponseError]` directly rather than using the `GraphQLResponse`
    /// wrapper struct, which is used elsewhere for full response body parsing.
    private func decodeGraphQLResponseErrors(from jsonString: String?) -> [GraphQLResponseError]? {
        guard let jsonString, !jsonString.isEmpty else {
            return nil
        }
        guard let data = jsonString.data(using: .utf8) else {
            DD.logger.debug("Failed to convert GraphQL errors string to UTF-8 data")
            return nil
        }
        do {
            let errors = try JSONDecoder().decode([GraphQLResponseError].self, from: data)
            return errors.isEmpty ? nil : errors
        } catch {
            DD.logger.debug("Failed to decode GraphQL errors: \(error)")
            return nil
        }
    }

    // MARK: - Attribute extraction helpers

    /// Extracts trace attributes from `self.attributes`, consuming them via `removeValue`.
    /// Must be called at most once per event send — repeated calls return nil for consumed keys.
    private func extractTraceAttributes() -> (traceID: TraceID?, spanID: SpanID?, parentSpanID: SpanID?, samplingRate: Double?) {
        let traceID: TraceID? = attributes.removeValue(forKey: CrossPlatformAttributes.traceID)?
            .dd.decode()
            .map { .init($0, representation: .hexadecimal) }
            ?? spanContext?.traceID
        let spanID: SpanID? = attributes.removeValue(forKey: CrossPlatformAttributes.spanID)?
            .dd.decode()
            .map { .init($0, representation: .decimal) }
            ?? spanContext?.spanID
        let parentSpanID: SpanID? = attributes.removeValue(forKey: CrossPlatformAttributes.parentSpanID)?
            .dd.decode()
            .map { .init($0, representation: .decimal) }
            ?? spanContext?.parentSpanID
        let samplingRate = attributes.removeValue(forKey: CrossPlatformAttributes.rulePSR)?.dd.decode() ?? spanContext?.samplingRate

        return (traceID, spanID, parentSpanID, samplingRate)
    }

    /// Extracts GraphQL attributes from `self.attributes` and builds a `RUMGraphql` value.
    /// Consumes attributes via `removeValue` — must be called at most once per event send.
    /// Returns `nil` if no valid operation type is found.
    private func extractGraphQL() -> RUMGraphql? {
        let operationType: String? = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlOperationType)?.dd.decode()
        let operationName: String? = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlOperationName)?.dd.decode()
        let payload: String? = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlPayload)?.dd.decode()
        let variables: String? = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlVariables)?.dd.decode()
        let errorsJSON: String? = attributes.removeValue(forKey: CrossPlatformAttributes.graphqlErrors)?.dd.decode()

        guard
            let rawOperationType = operationType,
            let opType = RUMGraphql.OperationType(rawValue: rawOperationType)
        else {
            return nil
        }
        let errors = decodeGraphQLResponseErrors(from: errorsJSON)?.map { error in
            RUMGraphql.Errors(
                code: error.code,
                locations: error.locations?.map { .init(column: Int64($0.column), line: Int64($0.line)) },
                message: error.message,
                path: error.path?.map { pathElement in
                    switch pathElement {
                    case .string(let value): return .string(value: value)
                    case .int(let value): return .integer(value: Int64(value))
                    }
                }
            )
        }
        return .init(
            errorCount: errors?.count.toInt64,
            errors: errors,
            operationName: operationName,
            operationType: opType,
            payload: payload,
            variables: variables
        )
    }
}
