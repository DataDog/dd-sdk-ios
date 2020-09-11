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
            userLogger.warn("RUM feature is enabled, but no `RUMMonitor` is registered. The RUM integration with Tracing will not work.")
            return nil
        }

        return attributes
    }
}

/// Sends given `Span` as RUM Errors.
internal struct TracingWithRUMErrorsIntegration {
    private let rumErrorsIntegration = RUMErrorsIntegration()

    func addError(for ddspan: DDSpan) {
        let rumErrorAttributes = captureRUMErrorAttributes(from: ddspan)

        rumErrorsIntegration.addError(
            with: rumErrorAttributes.message,
            stack: rumErrorAttributes.stack,
            source: .source,
            attributes: [:]
        )
    }

    /// Inspects the `DDSpan` tags set explicitly by the user with `span.setTag(key:value:)`
    /// or passed by `span.log(fields:)` using Open Tracing fields.
    ///
    /// Captures the ones describing the error context and maps them to RUM Error event attributes.
    private func captureRUMErrorAttributes(from ddspan: DDSpan) -> (message: String, stack: String?) {
        let openTracingFieldsReducer = SpanTagsReducer(spanTags: ddspan.tags, logFields: ddspan.logFields)
        let spanTags = openTracingFieldsReducer.reducedSpanTags

        let spanErrorMessage = spanTags[DDTags.errorMessage] as? String
        let spanErrorType = spanTags[DDTags.errorType] as? String
        let spanErrorStack = spanTags[DDTags.errorStack] as? String

        switch (spanErrorMessage, spanErrorType) {
        case (let message?, let type?):
            return (
                message: "Span error (\(ddspan.operationName)): \(type) | \(message)",
                stack: spanErrorStack
            )
        case (let message?, nil):
            return (
                message: "Span error (\(ddspan.operationName)): \(message)",
                stack: spanErrorStack
            )
        case (nil, let type?):
            return (
                message: "Span error (\(ddspan.operationName)): \(type)",
                stack: spanErrorStack
            )
        case (nil, nil):
            return (
                message: "Span error (\(ddspan.operationName))",
                stack: spanErrorStack
            )
        }
    }
}
