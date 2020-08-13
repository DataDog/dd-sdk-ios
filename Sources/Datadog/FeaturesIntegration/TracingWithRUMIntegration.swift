/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides the current RUM context tags for produced `Spans`.
internal struct TracingWithRUMContextIntegration {
    private let rumContextIntegration = RUMContextIntegration()

    /// Produces `Span` tags describing the current RUM context.
    /// Returns `nil` and prints warning if global `RUMMonitor` is not registered.
    var currentRUMContextTags: [String: Encodable]? {
        guard let attributes = rumContextIntegration.currentRUMContextAttributes else {
            userLogger.warn("No `RUMMonitor` is registered, so RUM integration with Tracing will not work.")
            return nil
        }

        return attributes
    }
}

/// Sends given `Span` as RUM Errors.
internal struct TracingWithRUMErrorsIntegration {
    struct Attributes {
        static let spanErrorMessage = "span.error_message"
        static let spanErrorType = "span.error_type"
        static let spanErrorStack = "span.error_stack"
    }

    private let rumErrorsIntegration = RUMErrorsIntegration()

    func addError(for ddspan: DDSpan) {
        let rumErrorMessage = "Span \"\(ddspan.operationName)\" reported an error"
        let rumErrorAttributes = captureRUMErrorAttributesFromOTLogFields(in: ddspan)

        rumErrorsIntegration.addError(with: rumErrorMessage, attributes: rumErrorAttributes)
    }

    /// Inspects the `DDSpan` tags set explicitly by the user with `span.setTag(key:value:)`
    /// or passed by `span.log(fields:)` using Open Tracing fields.
    ///
    /// Captures the ones describing the error context and maps them to RUM Error event attributes.
    private func captureRUMErrorAttributesFromOTLogFields(in ddspan: DDSpan) -> [AttributeKey: AttributeValue] {
        let openTracingFieldsReducer = SpanTagsReducer(spanTags: ddspan.tags, logFields: ddspan.logFields)
        let spanTags = openTracingFieldsReducer.reducedSpanTags

        var rumErrorAttributes: [AttributeKey: AttributeValue] = [:]

        if let spanErrorMessage = spanTags[DDTags.errorMessage] {
            rumErrorAttributes[Attributes.spanErrorMessage] = spanErrorMessage
        }
        if let spanErrorType = spanTags[DDTags.errorType] {
            rumErrorAttributes[Attributes.spanErrorType] = spanErrorType
        }
        if let spanErrorStack = spanTags[DDTags.errorStack] {
            rumErrorAttributes[Attributes.spanErrorStack] = spanErrorStack
        }

        return rumErrorAttributes
    }
}
