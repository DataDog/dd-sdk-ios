/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Constraint on RUM event types that require sanitization before encoding.
internal protocol RUMSanitizableEvent {
    /// Mutable user property.
    var usr: RUMUser? { get set }

    /// Mutable event context.
    var context: RUMEventAttributes? { get set }
}

/// Sanitizes `RUMEvent` representation received from the user, so it can match Datadog RUM Events constraints.
internal struct RUMEventSanitizer {
    private let attributesSanitizer = AttributesSanitizer(featureName: "RUM Event")

    func sanitize<Event>(event: Event) -> Event where Event: RUMSanitizableEvent {
        var event = event

        // Limit to max number of attributes.
        // If any attributes need to be removed, we first reduce number of
        // event attributes, then user info extra attributes.
        var limit = AttributesSanitizer.Constraints.maxNumberOfAttributes
        event.usr = sanitize(usr: event.usr, limit: &limit)
        event.context = sanitize(context: event.context, limit: &limit)

        return event
    }

    private func sanitize(usr: RUMUser?, limit: inout Int) -> RUMUser? {
        guard var usr = usr else {
            return nil
        }

        // Sanitize attribute names
        let attributes = attributesSanitizer.sanitizeKeys(for: usr.usrInfo, prefixLevels: 1)

        // Limit to max number of attributes.
        usr.usrInfo = attributesSanitizer.limitNumberOf(attributes: attributes, to: limit)

        limit -= usr.usrInfo.count
        return usr
    }

    private func sanitize(context: RUMEventAttributes?, limit: inout Int) -> RUMEventAttributes? {
        guard var context = context else {
            return nil
        }

        // Sanitize attribute names
        let attributes = attributesSanitizer.sanitizeKeys(for: context.contextInfo, prefixLevels: 1)

        // Limit to max number of attributes.
        context.contextInfo = attributesSanitizer.limitNumberOf(attributes: attributes, to: limit)

        limit -= context.contextInfo.count
        return context
    }
}

extension RUMViewEvent: RUMSanitizableEvent {}

extension RUMActionEvent: RUMSanitizableEvent {}

extension RUMResourceEvent: RUMSanitizableEvent {}

extension RUMErrorEvent: RUMSanitizableEvent {}

extension RUMLongTaskEvent: RUMSanitizableEvent {}
