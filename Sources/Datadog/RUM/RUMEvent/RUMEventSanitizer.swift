/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Sanitizes `RUMEvent` representation received from the user, so it can match Datadog RUM Events constraints.
internal struct RUMEventSanitizer {
    private let attributesSanitizer = AttributesSanitizer(featureName: "RUM Event")

    func sanitize<DM: RUMDataModel>(event: RUMEvent<DM>) -> RUMEvent<DM> {
        // Sanitize attribute names
        var sanitizedTimings = event.customViewTimings.flatMap { attributesSanitizer.sanitizeKeys(for: $0) }
        var sanitizedUserExtraInfo = attributesSanitizer.sanitizeKeys(for: event.userInfoAttributes)
        var sanitizedAttributes = attributesSanitizer.sanitizeKeys(for: event.attributes)

        // Limit to max number of attributes.
        // If any attributes need to be removed, we first reduce number of
        // event attributes, then user info extra attributes, then custom timings.
        sanitizedTimings = sanitizedTimings.flatMap { timings in
            attributesSanitizer.limitNumberOf(
                attributes: timings,
                to: AttributesSanitizer.Constraints.maxNumberOfAttributes
            )
        }
        sanitizedUserExtraInfo = attributesSanitizer.limitNumberOf(
            attributes: sanitizedUserExtraInfo,
            to: AttributesSanitizer.Constraints.maxNumberOfAttributes - (sanitizedTimings?.count ?? 0)
        )
        sanitizedAttributes = attributesSanitizer.limitNumberOf(
            attributes: sanitizedAttributes,
            to: AttributesSanitizer.Constraints.maxNumberOfAttributes - (sanitizedTimings?.count ?? 0) - sanitizedUserExtraInfo.count
        )

        var sanitizedEvent = event
        sanitizedEvent.attributes = sanitizedAttributes
        sanitizedEvent.userInfoAttributes = sanitizedUserExtraInfo
        sanitizedEvent.customViewTimings = sanitizedTimings
        return sanitizedEvent
    }
}
