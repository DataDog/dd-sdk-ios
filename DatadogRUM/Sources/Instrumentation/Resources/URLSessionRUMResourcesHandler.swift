/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct DistributedTracing {
    /// The sampling rate for tracing. Value between `0.0` and `100.0`, where `0.0` means NO trace will be sent and `100.0` means ALL traces will be sent.
    let samplingRate: SampleRate
    /// The distributed tracing ID generator.
    let traceIDGenerator: TraceIDGenerator
    let spanIDGenerator: SpanIDGenerator
    /// First party hosts defined by the user.
    let firstPartyHosts: FirstPartyHosts
    /// Trace context injection configuration to determine whether the trace context should be injected or not.
    let traceContextInjection: TraceContextInjection

    init(
        samplingRate: SampleRate,
        firstPartyHosts: FirstPartyHosts,
        traceIDGenerator: TraceIDGenerator,
        spanIDGenerator: SpanIDGenerator,
        traceContextInjection: TraceContextInjection
    ) {
        self.samplingRate = samplingRate
        self.traceIDGenerator = traceIDGenerator
        self.spanIDGenerator = spanIDGenerator
        self.firstPartyHosts = firstPartyHosts
        self.traceContextInjection = traceContextInjection
    }
}

internal final class URLSessionRUMResourcesHandler: DatadogURLSessionHandler, RUMCommandPublisher {
    /// The date provider
    let dateProvider: DateProvider
    /// Distributed Tracing
    let distributedTracing: DistributedTracing?
    /// Attributes-providing callback.
    /// It is configured by the user and should be used to associate additional RUM attributes with intercepted RUM Resource.
    let rumAttributesProvider: RUM.ResourceAttributesProvider?

    /// First party hosts defined by the user.
    var firstPartyHosts: FirstPartyHosts {
        distributedTracing?.firstPartyHosts ?? .init()
    }

    // MARK: - Initialization

    init(
        dateProvider: DateProvider,
        rumAttributesProvider: RUM.ResourceAttributesProvider?,
        distributedTracing: DistributedTracing?
    ) {
        self.dateProvider = dateProvider
        self.rumAttributesProvider = rumAttributesProvider
        self.distributedTracing = distributedTracing
    }

    // MARK: - Internal

    weak var subscriber: RUMCommandSubscriber?

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    // MARK: - DatadogURLSessionHandler

    func modify(request: URLRequest, headerTypes: Set<DatadogInternal.TracingHeaderType>, networkContext: NetworkContext?) -> (URLRequest, TraceContext?) {
        distributedTracing?.modify(
            request: request,
            headerTypes: headerTypes,
            rumSessionId: networkContext?.rumContext?.sessionID,
            userId: networkContext?.userConfigurationContext?.id,
            accountId: networkContext?.accountConfigurationContext?.id
        ) ?? (request, nil)
    }

    func interceptionDidStart(interception: DatadogInternal.URLSessionTaskInterception) {
        let url = interception.request.url?.absoluteString ?? "unknown_url"
        interception.register(origin: "rum")

        subscriber?.process(
            command: RUMStartResourceCommand(
                resourceKey: interception.identifier.uuidString,
                time: dateProvider.now,
                attributes: [:],
                url: url,
                httpMethod: RUMMethod(httpMethod: interception.request.httpMethod),
                kind: RUMResourceType(request: interception.request.unsafeOriginal),
                spanContext: distributedTracing?.trace(from: interception)
            )
        )
    }

    func interceptionDidComplete(interception: DatadogInternal.URLSessionTaskInterception) {
        guard let subscriber = subscriber else {
            return DD.logger.warn(
                """
                RUM Resource was completed, but no `RUMMonitor` is initialized in the core. RUM auto instrumentation will not work.
                Make sure `RUMMonitor.initialize()` is called before any network request is send.
                """
            )
        }

        // Get RUM Resource attributes from the user.
        let userAttributes = rumAttributesProvider?(
            interception.request.unsafeOriginal,
            interception.completion?.httpResponse,
            interception.data,
            interception.completion?.error
        ) ?? [:]

        // Extract GraphQL attributes from trace context
        var combinedAttributes = userAttributes
        if let graphqlAttributes = interception.trace?.graphql {
            if let operationName = graphqlAttributes.operationName {
                combinedAttributes[CrossPlatformAttributes.graphqlOperationName] = operationName
            }
            if let operationType = graphqlAttributes.operationType {
                combinedAttributes[CrossPlatformAttributes.graphqlOperationType] = operationType
            }
            if let variables = graphqlAttributes.variables {
                combinedAttributes[CrossPlatformAttributes.graphqlVariables] = variables
            }
            if let payload = graphqlAttributes.payload {
                combinedAttributes[CrossPlatformAttributes.graphqlPayload] = payload
            }
        }

        // Extract GraphQL errors from response if present
        if let errorsData = extractGraphQLErrorsIfPresent(from: interception) {
            combinedAttributes[CrossPlatformAttributes.graphqlErrors] = errorsData
        }

        if let resourceMetrics = interception.metrics {
            subscriber.process(
                command: RUMAddResourceMetricsCommand(
                    resourceKey: interception.identifier.uuidString,
                    time: dateProvider.now,
                    attributes: [:],
                    metrics: resourceMetrics
                )
            )
        }

        if let httpResponse = interception.completion?.httpResponse {
            subscriber.process(
                command: RUMStopResourceCommand(
                    resourceKey: interception.identifier.uuidString,
                    time: dateProvider.now,
                    attributes: combinedAttributes,
                    kind: RUMResourceType(response: httpResponse),
                    httpStatusCode: httpResponse.statusCode,
                    size: interception.metrics?.responseSize ?? interception.responseSize
                )
            )
        }

        if let error = interception.completion?.error {
            subscriber.process(
                command: RUMStopResourceWithErrorCommand(
                    resourceKey: interception.identifier.uuidString,
                    time: dateProvider.now,
                    error: error,
                    source: .network,
                    httpStatusCode: interception.completion?.httpResponse?.statusCode,
                    globalAttributes: [:],
                    attributes: combinedAttributes
                )
            )
        }
    }

    /// Extracts GraphQL errors from JSON response if present.
    /// Only the errors array is extracted to avoid storing potentially large response data fields.
    private func extractGraphQLErrorsIfPresent(from interception: URLSessionTaskInterception) -> Data? {
        guard let data = interception.data,
              let httpResponse = interception.completion?.httpResponse,
              let mimeType = httpResponse.mimeType,
              mimeType.lowercased().contains("json") else {
            return nil
        }

        // Fast check: does the response contain an "errors" key?
        guard let result = try? JSONDecoder().decode(GraphQLResponseHasErrors.self, from: data),
              result.hasErrors else {
            return nil
        }

        return data
    }
}

extension DistributedTracing {
    func modify(request: URLRequest, headerTypes: Set<DatadogInternal.TracingHeaderType>, rumSessionId: String?, userId: String?, accountId: String?) -> (URLRequest, TraceContext?) {
        let traceID = traceIDGenerator.generate()
        let spanID = spanIDGenerator.generate()

        // Extract GraphQL attributes from request before they are removed
        let graphql = GraphQLRequestAttributes(
            operationName: request.value(forHTTPHeaderField: GraphQLHeaders.operationName),
            operationType: request.value(forHTTPHeaderField: GraphQLHeaders.operationType),
            variables: request.value(forHTTPHeaderField: GraphQLHeaders.variables),
            payload: request.value(forHTTPHeaderField: GraphQLHeaders.payload)
        )

        let sampler = sampler(sessionID: rumSessionId)
        let injectedSpanContext = TraceContext(
            traceID: traceID,
            spanID: spanID,
            parentSpanID: nil,
            sampleRate: samplingRate,
            samplingPriority: sampler.sample() ? .autoKeep : .autoDrop,
            samplingDecisionMaker: .agentRate,
            rumSessionId: rumSessionId,
            userId: userId,
            accountId: accountId,
            graphql: graphql
        )

        var request = request
        var hasSetAnyHeader = false
        headerTypes.forEach {
            let writer: TracePropagationHeadersWriter
            switch $0 {
            case .datadog:
                writer = HTTPHeadersWriter(traceContextInjection: traceContextInjection)
                // To make sure the generated traces from RUM don’t affect APM Index Spans counts.
                request.setValue("rum", forHTTPHeaderField: TracingHTTPHeaders.originField)
            case .b3:
                writer = B3HTTPHeadersWriter(
                    injectEncoding: .single,
                    traceContextInjection: traceContextInjection
                )
            case .b3multi:
                writer = B3HTTPHeadersWriter(
                    injectEncoding: .multiple,
                    traceContextInjection: traceContextInjection
                )
            case .tracecontext:
                writer = W3CHTTPHeadersWriter(
                    tracestate: [
                        W3CHTTPHeaders.Constants.origin: W3CHTTPHeaders.Constants.originRUM
                    ],
                    traceContextInjection: traceContextInjection
                )
            }

            writer.write(traceContext: injectedSpanContext)

            writer.traceHeaderFields.forEach { field, value in
                if field.lowercased() == W3CHTTPHeaders.baggage.lowercased() {
                    // Handle baggage header merging
                    if let existingValue = request.value(forHTTPHeaderField: field) {
                        let mergedValue = BaggageHeaderMerger.merge(previousHeader: existingValue, with: value)
                        request.setValue(mergedValue, forHTTPHeaderField: field)
                    } else {
                        request.setValue(value, forHTTPHeaderField: field)
                    }
                    hasSetAnyHeader = true
                } else {
                    // do not overwrite existing header
                    if request.value(forHTTPHeaderField: field) == nil {
                        hasSetAnyHeader = true
                        request.setValue(value, forHTTPHeaderField: field)
                    }
                }
            }
        }

        return (request, (hasSetAnyHeader && injectedSpanContext.samplingPriority.isKept) ? injectedSpanContext : nil)
    }

    func trace(from interception: DatadogInternal.URLSessionTaskInterception) -> RUMSpanContext? {
        return interception.trace.map {
            .init(
                traceID: $0.traceID,
                spanID: $0.spanID,
                samplingRate: Double(samplingRate.percentageProportion)
            )
        }
    }

    /// Creates a sampler that makes consistent sampling decisions per session.
    ///
    /// This method implements deterministic sampling based on the RUM session ID.
    /// When a session ID is available, it uses the last 48 bits of the session UUID as a `seed`
    /// to create a `DeterministicSampler`, ensuring all resources within the same session
    /// have the same sampling decision.
    ///
    /// Fallback chain:
    /// 1. Session ID (preferred) → session-consistent sampling
    /// 2. Trace ID → trace-consistent sampling
    /// 3. Random sampler → fallback if neither is available
    ///
    /// - Parameters:
    ///   - sessionID: The RUM session ID
    /// - Returns: A `Sampling` instance that will consistently sample based on the provided seed
    private func sampler(sessionID: String?) -> Sampling {
        if let sessionID,
           // For a UUID with value aaaaaaaa-bbbb-Mccc-Nddd-1234567890ab
           // we use as the base id the last part: 0x1234567890ab
            let seed = sessionID
            .split(separator: "-")
            .last
            .flatMap({ UInt64($0, radix: 16) }) {
            return DeterministicSampler(seed: seed, samplingRate: samplingRate)
        }

        return Sampler(samplingRate: samplingRate)
    }
}

private extension HTTPURLResponse {
    func asClientError() -> Error? {
        // 4xx Client Errors
        guard statusCode >= 400 && statusCode < 500 else {
            return nil
        }
        let message = "\(statusCode) " + HTTPURLResponse.localizedString(forStatusCode: statusCode)
        return NSError(domain: "HTTPURLResponse", code: statusCode, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
