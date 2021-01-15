/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Sanitizes `Span` representation received from the user, so it can match Datadog APM constraints.
internal struct SpanSanitizer {
    private let attributesSanitizer = AttributesSanitizer()

    func sanitize(span: Span) -> Span {
        // Sanitize attribute names
        var sanitizedUserExtraInfo = attributesSanitizer.sanitizeKeys(for: span.userInfo.extraInfo)
        var sanitizedTags = attributesSanitizer.sanitizeKeys(for: span.tags)

        // Limit to max number of attributes
        // If any attributes need to be removed, we first reduce number of
        // span tags, then user info extra attributes.
        sanitizedUserExtraInfo = attributesSanitizer.limitNumberOf(
            attributes: sanitizedUserExtraInfo,
            to: AttributesSanitizer.Constraints.maxNumberOfAttributes
        )
        sanitizedTags = attributesSanitizer.limitNumberOf(
            attributes: sanitizedTags,
            to: AttributesSanitizer.Constraints.maxNumberOfAttributes - sanitizedUserExtraInfo.count
        )

        return Span(
            traceID: span.traceID,
            spanID: span.spanID,
            parentID: span.parentID,
            operationName: span.operationName,
            serviceName: span.serviceName,
            resource: span.resource,
            startTime: span.startTime,
            duration: span.duration,
            isError: span.isError,
            tracerVersion: span.tracerVersion,
            applicationVersion: span.applicationVersion,
            networkConnectionInfo: span.networkConnectionInfo,
            mobileCarrierInfo: span.mobileCarrierInfo,
            userInfo: .init(
                id: span.userInfo.id,
                name: span.userInfo.name,
                email: span.userInfo.email,
                extraInfo: sanitizedUserExtraInfo
            ),
            tags: sanitizedTags
        )
    }
}
