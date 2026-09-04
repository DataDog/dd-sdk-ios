/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Builds `SpanEvent` representation (for later serialization) from span information recorded in `DDSpan` and values received from global configuration.
internal struct SpanEventBuilder: Sendable {
    /// Service name to encode in span.
    let service: String?
    /// Enriches traces with network connection info.
    /// This means: reachability status, connection type, mobile carrier name and many more will be added to every span and span logs.
    /// For full list of network info attributes see `NetworkConnectionInfo` and `CarrierInfo`.
    let networkInfoEnabled: Bool
    /// Span events mapper configured by the user, `nil` if not set.
    let eventsMapper: SpanEventMapper?
    /// If spans should be enriched with the current RUM context.
    let bundleWithRUM: Bool
    /// Whether client-side stats computation is enabled. When `true`, spans are stamped with
    /// `meta._dd.compute_stats = "0"` so the backend skips its own (double-counting) computation.
    /// When `false`, the tag is removed so the backend keeps computing stats (backwards-compatible default).
    let statsComputationEnabled: Bool
    /// Telemetry interface.
    let telemetry: Telemetry
    /// Span attributes encoder
    let attributesEncoder: JSONEncoder = .dd.default()

    func createSpanEvent(
        context: DatadogContext,
        traceID: TraceID,
        spanID: SpanID,
        parentSpanID: SpanID?,
        operationName: String,
        startTime: Date,
        finishTime: Date,
        samplingRate: Float,
        samplingPriority: SamplingPriority,
        samplingDecisionMaker: SamplingMechanismType,
        tags: [String: Encodable],
        baggageItems: [String: String],
        logFields: [[String: Encodable]]
    ) -> SpanEvent {
        let tagsReducer = SpanTagsReducer(spanTags: tags, logFields: logFields)

        var tags: [String: String]

        // Add baggage items as tags
        tags = baggageItems

        // Add regular tags (prefer regular tags over baggage items)
        let regularTags = castValuesToString(tagsReducer.reducedSpanTags, context: .custom)
        tags.merge(regularTags) { _, regularTag in regularTag }

        if bundleWithRUM {
            // Enrich with RUM context
            if let rum = context.additionalContext(ofType: RUMCoreContext.self), rum.sessionSampler.isSampled {
                tags[SpanTags.rumApplicationID] = rum.applicationID
                tags[SpanTags.rumSessionID] = rum.sessionID
                tags[SpanTags.rumViewID] = rum.viewID
                tags[SpanTags.rumActionID] = rum.userActionID
            }
        }

        // The SDK owns `_dd.compute_stats`: (over)write it to "0" when client-side stats is enabled,
        // otherwise remove any user-provided value. This guarantees a user tag can never flip the
        // opt-out and silently reintroduce backend double counting (when enabled) or under-counting
        // (when disabled).
        if statsComputationEnabled {
            tags[SpanTags.computeStats] = "0"
        } else {
            tags.removeValue(forKey: SpanTags.computeStats)
        }

        // Transform user info to `SpanEvent.UserInfo` representation
        let spanUserInfo = SpanEvent.UserInfo(
            id: context.userInfo?.id,
            name: context.userInfo?.name,
            email: context.userInfo?.email,
            extraInfo: context.userInfo.map { castValuesToString($0.extraInfo, context: .userInfo) } ?? [:]
        )

        // Transform account info to `SpanEvent.AccountInfo` representation
        let spanEventAccountInfo: SpanEvent.AccountInfo?
        if let accountInfo = context.accountInfo {
            spanEventAccountInfo = SpanEvent.AccountInfo(
                id: accountInfo.id,
                name: accountInfo.name,
                extraInfo: castValuesToString(accountInfo.extraInfo, context: .accountInfo)
            )
        } else {
            spanEventAccountInfo = nil
        }

        let span = SpanEvent(
            traceID: traceID,
            spanID: spanID,
            parentID: parentSpanID,
            operationName: tagsReducer.extractedOperationName ?? operationName,
            serviceName: tagsReducer.extractedServiceName ?? service ?? context.service,
            resource: tagsReducer.extractedResourceName ?? operationName,
            startTime: startTime.addingTimeInterval(context.serverTimeOffset),
            duration: finishTime.timeIntervalSince(startTime),
            isError: tagsReducer.extractedIsError ?? false,
            source: context.source,
            origin: context.ciAppOrigin,
            samplingRate: samplingRate,
            samplingPriority: samplingPriority,
            samplingDecisionMaker: samplingDecisionMaker,
            tracerVersion: context.sdkVersion,
            applicationVersion: context.version,
            networkConnectionInfo: networkInfoEnabled ? context.networkConnectionInfo : nil,
            mobileCarrierInfo: networkInfoEnabled ? context.carrierInfo : nil,
            device: context.normalizedDevice(addLocales: false),
            os: context.os,
            userInfo: spanUserInfo,
            accountInfo: spanEventAccountInfo,
            tags: tags
        )

        guard let eventMapper = eventsMapper else {
            return span
        }

        var mappedSpan = eventMapper(span)

        // Re-assert the SDK-owned `_dd.compute_stats` after the user mapper runs. The mapper receives
        // the tag already stamped above, but a mapper that rewrites or drops `tags` could otherwise
        // strip it, letting the sampled-in span upload without the opt-out while client-side stats are
        // also uploaded, causing the backend to recompute and double-count. `SpanSanitizer` only
        // guards against attribute-count limiting dropping the tag, not against the mapper removing it.
        if statsComputationEnabled {
            mappedSpan.tags[SpanTags.computeStats] = "0"
        } else {
            mappedSpan.tags.removeValue(forKey: SpanTags.computeStats)
        }

        return mappedSpan
    }

    // MARK: - Attributes Conversion

    /// Converts `Encodable` attributes to its lossless JSON string representation, e.g.:
    /// * it will convert `"abc"` string value to `"abc"` JSON string value
    /// * it will convert `1` integer value to `"1"` JSON string value
    /// * it will convert `true` boolean value to `"true"` JSON string value
    /// * it will convert `Person(name: "foo")` encodable struct to `"{\"name\": \"foo\"}"` JSON string value
    private func castValuesToString(_ dictionary: [String: Encodable], context: AttributeEncodingContext = .custom) -> [String: String] {
        var casted: [String: String] = [:]

        dictionary.forEach { key, value in
            if let stringValue = value as? String {
                casted[key] = stringValue
            } else if let urlValue = value as? URL {
                casted[key] = urlValue.absoluteString
            } else {
                do {
                    let encodable = AnyEncodable(value)
                    let jsonData = try attributesEncoder.encode(encodable)

                    if let stringValue = String(data: jsonData, encoding: .utf8) {
                        casted[key] = stringValue
                    } else {
                        let encodingContext = EncodingError.Context(
                            codingPath: [],
                            debugDescription: "Failed to read utf-8 JSON data when encoding span tag '\(key)' to JSON string."
                        )
                        telemetry.error(encodingContext.debugDescription)
                        throw EncodingError.invalidValue(encodable.value, encodingContext)
                    }
                } catch let error {
                    DD.logger.error(
                        "Failed to encode \(context.errorMessagePrefix)attribute '\(key)' to `String`. This attribute will be dropped from the span.",
                        error: error
                    )
                }
            }
        }

        return casted
    }
}
