/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Datadog tag keys used to encode information received from the user through `OpenTracingLogFields`, `OpenTracingTagKeys` or custom fields
/// supported by Datadog platform.
private struct DatadogTagKeys {
    static let errorType     = "error.type"
    static let errorMessage  = "error.msg"
    static let errorStack    = "error.stack"
    static let resourceName  = "resource.name"
}

/// Reduces `DDSpan` tags and log attributes by extracting values that require separate handling.
///
/// The responsibility of `SpanTagsReducer` is to capture Open Tracing [tags](https://github.com/opentracing/specification/blob/master/semantic_conventions.md#span-tags-table)
/// and [log fields](https://github.com/opentracing/specification/blob/master/semantic_conventions.md#log-fields-table) given by the user and
/// transform them into the format used by Datadog. This happens in two ways, by:
/// - extracting information from `spanTags` and `logFields` to `extracted*` variables,
/// - reducing the initial `spanTags` collection by removing extracted information.
///
/// In result, the `spanTags` will contain only the tags that do NOT require special handling by Datadog and can be send as generic `span.meta.*` JSON values.
/// Values extracted from `spanTags` and `logFields` will be passed to the `Span` encoding process in a type-safe manner.
internal struct SpanTagsReducer {
    /// Tags received by the user. This collection may be changed by the `reduce(_:)` function.
    private(set) var spanTags: [String: Codable]
    /// Log fieds send by the user for this `DDSpan`. This collection is never mutated, and is only used to extract extra information about the span.
    private let logFields: [[String: Codable]]

    // MARK: - Extracted Info

    private(set) var extractedIsError: Bool? = nil
    private(set) var extractedResourceName: String? = nil

    // MARK: - Reducers

    internal static func reduce(spanTags: [String: Codable], logFields: [[String: Codable]]) -> SpanTagsReducer {
        var reducer = SpanTagsReducer(spanTags: spanTags, logFields: logFields)
        reducers.forEach { reduce in reduce(&reducer) }
        return reducer
    }

    private static let reducers: [(inout SpanTagsReducer) -> Void] = [
        extractErrorFromLogFields,
        extractErrorFromTags,
        extractResourceNameFromTags
    ]

    private static func extractErrorFromLogFields(_ reducer: inout SpanTagsReducer) {
        for fields in reducer.logFields {
            let isErrorEvent = fields[OpenTracingLogFields.event] as? String == "error"
            let errorKind = fields[OpenTracingLogFields.errorKind] as? String

            if isErrorEvent || errorKind != nil {
                reducer.extractedIsError = true
                reducer.spanTags[DatadogTagKeys.errorMessage] = fields[OpenTracingLogFields.message] as? String
                reducer.spanTags[DatadogTagKeys.errorType] = errorKind
                reducer.spanTags[DatadogTagKeys.errorStack] = fields[OpenTracingLogFields.stack] as? String
                return // ignore further logs
            }
        }
    }

    private static func extractErrorFromTags(_ reducer: inout SpanTagsReducer) {
        if reducer.spanTags[OpenTracingTagKeys.error] as? Bool == true {
            reducer.extractedIsError = true
        }
    }

    private static func extractResourceNameFromTags(_ reducer: inout SpanTagsReducer) {
        if let resourceName = reducer.spanTags.removeValue(forKey: DatadogTagKeys.resourceName) as? String {
            reducer.extractedResourceName = resourceName
        }
    }
}
