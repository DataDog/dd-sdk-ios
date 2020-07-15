/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Builds `Span` representation (for later serialization) from `DDSpan`.
internal struct SpanBuilder {
    /// Application version to encode in span.
    let applicationVersion: String
    /// Environment to encode in span.
    let environment: String
    /// Service name to encode in span.
    let serviceName: String
    /// Shared user info provider.
    let userInfoProvider: UserInfoProvider
    /// Shared network connection info provider (or `nil` if disabled for given tracer).
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType?
    /// Shared mobile carrier info provider (or `nil` if disabled for given tracer).
    let carrierInfoProvider: CarrierInfoProviderType?

    /// Encodes tag `Span` tag values as JSON string
    private let tagsJSONEncoder: JSONEncoder = .default()

    func createSpan(from ddspan: DDSpan, finishTime: Date) throws -> Span {
        let tagsReducer = SpanTagsReducer(spanTags: ddspan.tags, logFields: ddspan.logFields)

        var jsonStringEncodedTags: [String: JSONStringEncodableValue] = [:]

        // First, add baggage items as tags...
        for (itemKey, itemValue) in ddspan.ddContext.baggageItems.all {
            jsonStringEncodedTags[itemKey] = JSONStringEncodableValue(itemValue, encodedUsing: tagsJSONEncoder)
        }

        // ... then, add regular tags
        for (tagName, tagValue) in tagsReducer.reducedSpanTags {
            jsonStringEncodedTags[tagName] = JSONStringEncodableValue(tagValue, encodedUsing: tagsJSONEncoder)
        }

        return Span(
            traceID: ddspan.ddContext.traceID,
            spanID: ddspan.ddContext.spanID,
            parentID: ddspan.ddContext.parentSpanID,
            operationName: ddspan.operationName,
            serviceName: serviceName,
            resource: tagsReducer.extractedResourceName ?? ddspan.operationName,
            startTime: ddspan.startTime,
            duration: finishTime.timeIntervalSince(ddspan.startTime),
            isError: tagsReducer.extractedIsError ?? false,
            tracerVersion: sdkVersion,
            applicationVersion: applicationVersion,
            networkConnectionInfo: networkConnectionInfoProvider?.current,
            mobileCarrierInfo: carrierInfoProvider?.current,
            userInfo: userInfoProvider.value,
            tags: jsonStringEncodedTags
        )
    }
}
