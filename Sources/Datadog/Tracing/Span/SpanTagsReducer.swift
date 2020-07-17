/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Reduces `DDSpan` tags and log attributes by extracting values that require separate handling.
///
/// The responsibility of `SpanTagsReducer` is to capture Open Tracing [tags](https://github.com/opentracing/specification/blob/master/semantic_conventions.md#span-tags-table)
/// and [log fields](https://github.com/opentracing/specification/blob/master/semantic_conventions.md#log-fields-table) given by the user and
/// transform them into the format used by Datadog. This happens in two ways, by:
/// - extracting information from `spanTags` and `logFields` to `extracted*` variables,
/// - reducing the initial `spanTags` collection to `reducedSpanTags` by removing extracted information.
///
/// In result, the `reducedSpanTags` will contain only the tags that do NOT require special handling by Datadog and can be send as generic `span.meta.*` JSON values.
/// Values extracted from `spanTags` and `logFields` will be passed to the `Span` encoding process in a type-safe manner.
internal struct SpanTagsReducer {
    /// Tags for generic `span.meta.*` encoding in `Span` JSON.
    let reducedSpanTags: [String: Encodable]

    // MARK: - Extracted Info

    /// Error information requiring a special encoding in `Span` JSON.
    let extractedIsError: Bool?
    /// Resource name requiring a special encoding in `Span` JSON.
    let extractedResourceName: String?

    // MARK: - Initialization

    init(spanTags: [String: Encodable], logFields: [[String: Encodable]]) {
        var mutableSpanTags = spanTags

        var extractedIsError: Bool? = nil
        var extractedResourceName: String? = nil

        // extract error from `logFields`
        for fields in logFields {
            let isErrorEvent = fields[OTLogFields.event] as? String == "error"
            let errorKind = fields[OTLogFields.errorKind] as? String

            if isErrorEvent || errorKind != nil {
                extractedIsError = true
                mutableSpanTags[DDTags.errorMessage] = fields[OTLogFields.message] as? String
                mutableSpanTags[DDTags.errorType] = errorKind
                mutableSpanTags[DDTags.errorStack] = fields[OTLogFields.stack] as? String
                break // ignore next logs
            }
        }

        // extract error from `mutableSpanTags`
        if mutableSpanTags[OTTags.error] as? Bool == true {
            extractedIsError = true
        }

        // extract resource name from `mutableSpanTags`
        if let resourceName = mutableSpanTags.removeValue(forKey: DDTags.resource) as? String {
            extractedResourceName = resourceName
        }

        self.reducedSpanTags = mutableSpanTags
        self.extractedIsError = extractedIsError
        self.extractedResourceName = extractedResourceName
    }
}
