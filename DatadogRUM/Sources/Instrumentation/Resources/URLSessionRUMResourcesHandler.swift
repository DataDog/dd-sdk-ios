/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
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

internal final class URLSessionRUMResourcesHandler: DatadogURLSessionHandlerSupportingDistributedTracing, DatadogURLSessionHandlerCapturingRUMContext, RUMCommandPublisher {
    /// Captured state for RUM URL session handler
    struct RUMURLSessionHandlerCapturedState: URLSessionHandlerCapturedState {
        /// Whether GraphQL headers were detected in the request
        let hasGraphQLHeaders: Bool
        /// Exact RUM view that was representative when the task was created.
        let rumViewID: RUMUUID?
        /// Source scene of a request created synchronously by a tracked UI event.
        let sceneIdentifier: RUMSceneIdentifier?
        /// Internal resource key when start was enqueued synchronously from `modify`.
        let prestartedResourceKey: String?

        init(
            hasGraphQLHeaders: Bool,
            rumViewID: RUMUUID? = nil,
            sceneIdentifier: RUMSceneIdentifier? = nil,
            prestartedResourceKey: String? = nil
        ) {
            self.hasGraphQLHeaders = hasGraphQLHeaders
            self.rumViewID = rumViewID
            self.sceneIdentifier = sceneIdentifier
            self.prestartedResourceKey = prestartedResourceKey
        }
    }

    private struct ResourceOwner {
        let resourceKey: String
        let target: RUMCommandTarget
    }

    /// The date provider
    let dateProvider: DateProvider
    /// Distributed Tracing
    let distributedTracing: DistributedTracing?
    /// Attributes-providing callback.
    /// It is configured by the user and should be used to associate additional RUM attributes with intercepted RUM Resource.
    let rumAttributesProvider: RUM.ResourceAttributesProvider?
    /// Telemetry interface for tracking SDK usage
    let telemetry: Telemetry
    /// Header processor for capturing HTTP headers.
    let headerProcessor: HeaderProcessor?
    /// The disallow-list of URLs excluded from RUM resource tracking.
    let disallowList: DisallowList?

    /// Retains the captured owner until the intercepted task completes. URLSession
    /// callbacks may arrive on different threads, so access must be synchronized.
    @ReadWriteLock
    private var resourceOwners: [UUID: ResourceOwner] = [:]

    /// First party hosts defined by the user.
    var firstPartyHosts: FirstPartyHosts {
        distributedTracing?.firstPartyHosts ?? .init()
    }

    // MARK: - Initialization

    init(
        dateProvider: DateProvider,
        rumAttributesProvider: RUM.ResourceAttributesProvider?,
        distributedTracing: DistributedTracing?,
        headerProcessor: HeaderProcessor?,
        disallowList: DisallowList?,
        telemetry: Telemetry
    ) {
        self.dateProvider = dateProvider
        self.rumAttributesProvider = rumAttributesProvider
        self.distributedTracing = distributedTracing
        self.headerProcessor = headerProcessor
        self.disallowList = disallowList
        self.telemetry = telemetry
    }

    // MARK: - Internal

    weak var subscriber: RUMCommandSubscriber?

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    // MARK: - DatadogURLSessionHandler

    func modify(request: URLRequest, headerTypes: Set<DatadogInternal.TracingHeaderType>, networkContext: NetworkContext?) -> (URLRequest, TraceContext?, URLSessionHandlerCapturedState?) {
        guard !isDisallowed(url: request.url) else {
            return (request, nil, nil)
        }

        let (modifiedRequest, traceContext, _) = distributedTracing?.modify(
            request: request,
            headerTypes: headerTypes,
            networkContext: networkContext
        ) ?? (request, nil, nil)

        // Note: DistributedTracing.modify() currently returns nil for captured state.
        // If this changes, we'll need to merge captured states instead of replacing.
        let rumViewID = networkContext?.rumContext?.viewID
            .flatMap(UUID.init(uuidString:))
            .map(RUMUUID.init(rawValue:))
        let sceneIdentifier = RUMUIEventNetworkContext.currentSceneIdentifier(for: subscriber?.rumContextHandoffOwner)
        let target = rumViewID.map(RUMCommandTarget.view)
            ?? sceneIdentifier.map(RUMCommandTarget.scene)
            ?? .processRepresentative
        var prestartedResourceKey: String?
        if rumViewID != nil || sceneIdentifier != nil {
            let resourceKey = UUID().uuidString
            // Network instrumentation selects the winning trace context only after
            // all handlers run. Correlation is therefore attached on completion.
            if startResource(
                key: resourceKey,
                request: modifiedRequest,
                target: target,
                spanContext: nil
            ) {
                prestartedResourceKey = resourceKey
            }
        }

        let hasGraphQLHeaders = modifiedRequest.hasGraphQLHeaders
        let capturedState: URLSessionHandlerCapturedState? = hasGraphQLHeaders
            || rumViewID != nil
            || sceneIdentifier != nil
            ? RUMURLSessionHandlerCapturedState(
                hasGraphQLHeaders: hasGraphQLHeaders,
                rumViewID: rumViewID,
                sceneIdentifier: sceneIdentifier,
                prestartedResourceKey: prestartedResourceKey
            )
            : nil

        return (modifiedRequest, traceContext, capturedState)
    }

    func interceptionDidStart(interception: DatadogInternal.URLSessionTaskInterception, capturedStates: [any URLSessionHandlerCapturedState]) {
        guard !isDisallowed(url: interception.request.url) else {
            return
        }

        interception.register(origin: "rum")

        let capturedState = capturedStates.compactMap { $0 as? RUMURLSessionHandlerCapturedState }.first
        if capturedState?.hasGraphQLHeaders == true {
            telemetry.usage(event: .addGraphQLRequest)
        }

        let target = capturedState?.rumViewID.map(RUMCommandTarget.view)
            ?? capturedState?.sceneIdentifier.map(RUMCommandTarget.scene)
            ?? .processRepresentative
        let resourceKey = capturedState?.prestartedResourceKey ?? interception.identifier.uuidString
        _resourceOwners.mutate {
            $0[interception.identifier] = ResourceOwner(resourceKey: resourceKey, target: target)
        }

        if capturedState?.prestartedResourceKey == nil {
            startResource(
                key: resourceKey,
                request: interception.request.unsafeOriginal,
                target: target,
                spanContext: distributedTracing?.trace(from: interception)
            )
        }
    }

    private func startResource(
        key: String,
        request: URLRequest,
        target: RUMCommandTarget,
        spanContext: RUMSpanContext?
    ) -> Bool {
        guard let subscriber else {
            return false
        }
        var command = RUMStartResourceCommand(
            resourceKey: key,
            time: dateProvider.now,
            attributes: [:],
            url: request.url?.absoluteString ?? "unknown_url",
            httpMethod: RUMMethod(httpMethod: request.httpMethod),
            kind: RUMResourceType(request: request),
            spanContext: spanContext
        )
        command.target = target
        subscriber.process(command: command)
        return true
    }

    func interceptionDidComplete(interception: DatadogInternal.URLSessionTaskInterception) {
        var owner = ResourceOwner(
            resourceKey: interception.identifier.uuidString,
            target: .processRepresentative
        )
        _resourceOwners.mutate {
            owner = $0.removeValue(forKey: interception.identifier) ?? owner
        }
        let resourceKey = owner.resourceKey
        let target = owner.target

        guard !isDisallowed(url: interception.request.url) else {
            return
        }

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
        if let traceContext = interception.trace {
            // Cross-platform trace attributes take precedence over the
            // start-time span context in `RUMResourceScope`. Supplying the
            // interception's winning context here keeps an eagerly-started
            // resource aligned with the headers selected across all handlers.
            if combinedAttributes[CrossPlatformAttributes.traceID] == nil {
                combinedAttributes[CrossPlatformAttributes.traceID] = traceContext.traceID.toString(representation: .hexadecimal)
            }
            if combinedAttributes[CrossPlatformAttributes.spanID] == nil {
                combinedAttributes[CrossPlatformAttributes.spanID] = traceContext.spanID.toString(representation: .decimal)
            }
            if combinedAttributes[CrossPlatformAttributes.parentSpanID] == nil, let parentSpanID = traceContext.parentSpanID {
                combinedAttributes[CrossPlatformAttributes.parentSpanID] = parentSpanID.toString(representation: .decimal)
            }
            if combinedAttributes[CrossPlatformAttributes.rulePSR] == nil {
                combinedAttributes[CrossPlatformAttributes.rulePSR] = Double(traceContext.sampleRate.percentageProportion)
            }
        }
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
        if let errorsString = extractGraphQLErrorsIfPresent(from: interception) {
            combinedAttributes[CrossPlatformAttributes.graphqlErrors] = errorsString
        }

        // Capture HTTP headers if configured
        if let headerProcessor {
            // RUM-14563: Accessing allHTTPHeaderFields is safe here because the interception
            // is complete and the request is no longer being mutated.
            // swiftlint:disable:next unsafe_all_http_header_fields
            let requestHeaders = interception.request.unsafeOriginal.allHTTPHeaderFields
            let headers = headerProcessor.process(
                requestHeaders: requestHeaders,
                responseHeaders: interception.completion?.httpResponse?.allHeaderFields
            )
            if !headers.request.isEmpty {
                combinedAttributes[CrossPlatformAttributes.requestHeaders] = headers.request
            }
            if !headers.response.isEmpty {
                combinedAttributes[CrossPlatformAttributes.responseHeaders] = headers.response
            }
        }

        if interception.metrics?.isLocalCacheHit == true {
            combinedAttributes[CrossPlatformAttributes.localCacheHit] = true
        }

        if let resourceMetrics = interception.metrics {
            var command = RUMAddResourceMetricsCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: [:],
                metrics: resourceMetrics
            )
            command.target = target
            subscriber.process(command: command)
        }

        // A task may fail after receiving response headers. End it once as an
        // error; a success first would remove the Resource before error routing.
        if let httpResponse = interception.completion?.httpResponse,
           interception.completion?.error == nil {
            var command = RUMStopResourceCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                attributes: combinedAttributes,
                kind: RUMResourceType(response: httpResponse),
                httpStatusCode: httpResponse.statusCode,
                size: interception.mostAccurateResponseSize
            )
            command.target = target
            subscriber.process(command: command)
        }

        if let error = interception.completion?.error {
            var errorAttributes = combinedAttributes
            errorAttributes.removeValue(forKey: CrossPlatformAttributes.localCacheHit)
            var command = RUMStopResourceWithErrorCommand(
                resourceKey: resourceKey,
                time: dateProvider.now,
                error: error,
                source: .network,
                httpStatusCode: interception.completion?.httpResponse?.statusCode,
                globalAttributes: [:],
                attributes: errorAttributes
            )
            command.target = target
            subscriber.process(command: command)
        }
    }

    private func isDisallowed(url: URL?) -> Bool {
        disallowList?.isDisallowed(url: url) == true
    }

    /// Extracts GraphQL errors from JSON response if present and returns them as a JSON string.
    /// Only the errors array is extracted to avoid storing potentially large response data fields.
    private func extractGraphQLErrorsIfPresent(from interception: URLSessionTaskInterception) -> String? {
        guard let data = interception.data,
              let httpResponse = interception.completion?.httpResponse,
              let mimeType = httpResponse.mimeType,
              mimeType.lowercased().contains("json") else {
            return nil
        }

        guard let response = try? JSONDecoder().decode(GraphQLResponse.self, from: data),
              let errors = response.errors,
              !errors.isEmpty else {
            return nil
        }

        do {
            let errorsData = try JSONEncoder().encode(errors)
            return String(data: errorsData, encoding: .utf8)
        } catch {
            DD.logger.debug("Failed to encode GraphQL errors array: \(error)")
            return nil
        }
    }

    var distributedTracingSampleRate: SampleRate? {
        distributedTracing?.samplingRate
    }
}

extension DistributedTracing {
    fileprivate static func rumSpanContext(from traceContext: TraceContext) -> RUMSpanContext {
        .init(
            traceID: traceContext.traceID,
            spanID: traceContext.spanID,
            parentSpanID: traceContext.parentSpanID,
            samplingRate: Double(traceContext.sampleRate.percentageProportion)
        )
    }

    func modify(request: URLRequest, headerTypes: Set<DatadogInternal.TracingHeaderType>, networkContext: NetworkContext?) -> (URLRequest, TraceContext?, URLSessionHandlerCapturedState?) {
        // Per RUM-15310: If there is an active span, and that span is sampled, we use it as the parent span,
        // and set everything in the RUM resource span to be consistent with it.
        // If we don't have an active span, or if we do have one, but it's not sampled, we ignore it. The
        // latter case is important, as it provides RUM the opportunity to sample this request even if the
        // trace that would be related to it is not. In that case, the RUM Resource span will be the root.
        let activeSpanContext: ActiveSpanContext?
        if let possibleActiveSpanContext = networkContext?.activeSpanProvider?.activeSpanContext(),
           possibleActiveSpanContext.samplingPriority.isKept {
            activeSpanContext = possibleActiveSpanContext
        } else {
            activeSpanContext = nil
        }

        // When a RUM context is available, its `sessionSampler` is a `DeterministicSampler`
        // seeded from the session ID. Calling `combined(with:)` composes the session rate
        // with the tracing `samplingRate` while preserving the seed, so every resource in
        // the same session receives a consistent sampling decision.
        // When no RUM context exists, fall back to a random `Sampler`.
        let sampler: () -> Sampling = {
            networkContext?.rumContext?.sessionSampler.combined(with: samplingRate)
            ?? Sampler(samplingRate: samplingRate)
        }
        // In case there is, we use the same traceID so the backend can link the span generated from the RUM resource
        // with the trace.
        let traceID = activeSpanContext?.traceID ?? traceIDGenerator.generate()
        let spanID = spanIDGenerator.generate()
        let samplingPriority = activeSpanContext?.samplingPriority ?? (sampler().sample() ? .autoKeep : .autoDrop)
        let samplingDecisionMaker = activeSpanContext?.samplingMechanismType ?? .agentRate

        // Extract GraphQL attributes from request before they are removed
        let graphql = GraphQLRequestAttributes(
            operationName: request.value(forHTTPHeaderField: GraphQLHeaders.operationName),
            operationType: request.value(forHTTPHeaderField: GraphQLHeaders.operationType),
            variables: request.value(forHTTPHeaderField: GraphQLHeaders.variables),
            payload: request.value(forHTTPHeaderField: GraphQLHeaders.payload)
        )

        let injectedSpanContext = TraceContext(
            traceID: traceID,
            spanID: spanID,
            // If there is an active span, use it as parent span for the span
            // the backend creates out of the RUM resource:
            parentSpanID: activeSpanContext?.activeSpanID,
            sampleRate: activeSpanContext?.samplingRate ?? samplingRate,
            samplingPriority: samplingPriority,
            samplingDecisionMaker: samplingDecisionMaker,
            rumSessionId: networkContext?.rumContext?.sessionID,
            userId: networkContext?.userConfigurationContext?.id,
            accountId: networkContext?.accountConfigurationContext?.id,
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

        return (request, (hasSetAnyHeader && injectedSpanContext.samplingPriority.isKept) ? injectedSpanContext : nil, nil)
    }

    fileprivate func trace(from interception: DatadogInternal.URLSessionTaskInterception) -> RUMSpanContext? {
        interception.trace.map(Self.rumSpanContext)
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
