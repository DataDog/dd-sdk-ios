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
        var sanitizedUserExtraInfo = attributesSanitizer.sanitizeKeys(for: event.userInfoAttributes, prefixLevels: 1)
        var sanitizedAttributes = attributesSanitizer.sanitizeKeys(for: event.attributes, prefixLevels: 1)

        // Limit to max number of attributes.
        // If any attributes need to be removed, we first reduce number of
        // event attributes, then user info extra attributes.
        sanitizedUserExtraInfo = attributesSanitizer.limitNumberOf(
            attributes: sanitizedUserExtraInfo,
            to: AttributesSanitizer.Constraints.maxNumberOfAttributes
        )
        sanitizedAttributes = attributesSanitizer.limitNumberOf(
            attributes: sanitizedAttributes,
            to: AttributesSanitizer.Constraints.maxNumberOfAttributes - sanitizedUserExtraInfo.count
        )

        var sanitizedEvent = event
        sanitizedEvent.attributes = sanitizedAttributes
        sanitizedEvent.userInfoAttributes = sanitizedUserExtraInfo
        return sanitizedEvent
    }
}
