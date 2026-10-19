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

    var account: RUMAccount? { get set }

    /// Mutable event context.
    var context: RUMEventAttributes? { get set }
}

/// Sanitizes `RUMEvent` representation received from the user, so it can match Datadog RUM Events constraints.
internal struct RUMEventSanitizer {
    private let attributesSanitizer = AttributesSanitizer(featureName: "RUM Event")

    func sanitize<Event>(event: Event) -> Event where Event: RUMSanitizableEvent {
        var event = event

        // Limit to max number of attributes.
        // The limit is applied per field, so `usr`, `account` and `context` do not compete for it.
        event.usr = sanitize(usr: event.usr)
        event.account = sanitize(account: event.account)
        event.context = sanitize(context: event.context)

        return event
    }

    private func sanitize(usr: RUMUser?) -> RUMUser? {
        guard var usr = usr else {
            return nil
        }

        // Sanitize attribute names
        let attributes = attributesSanitizer.sanitizeKeys(for: usr.usrInfo, prefixLevels: 1)

        // Limit to max number of attributes.
        usr.usrInfo = attributesSanitizer.limitNumberOf(
            attributes: attributes,
            to: AttributesSanitizer.Constraints.maxNumberOfAttributes
        )

        return usr
    }

    private func sanitize(account: RUMAccount?) -> RUMAccount? {
        guard var account = account else {
            return nil
        }

        // Sanitize attribute names
        let attributes = attributesSanitizer.sanitizeKeys(for: account.accountInfo, prefixLevels: 1)

        // Limit to max number of attributes.
        account.accountInfo = attributesSanitizer.limitNumberOf(
            attributes: attributes,
            to: AttributesSanitizer.Constraints.maxNumberOfAttributes
        )

        return account
    }

    private func sanitize(context: RUMEventAttributes?) -> RUMEventAttributes? {
        guard var context = context else {
            return nil
        }

        // Sanitize attribute names
        let attributes = attributesSanitizer.sanitizeKeys(for: context.contextInfo, prefixLevels: 1)

        // Limit to max number of attributes.
        context.contextInfo = attributesSanitizer.limitNumberOf(
            attributes: attributes,
            to: AttributesSanitizer.Constraints.maxNumberOfAttributes
        )

        return context
    }
}

extension RUMViewEvent: RUMSanitizableEvent {}

extension RUMActionEvent: RUMSanitizableEvent {}

extension RUMResourceEvent: RUMSanitizableEvent {}

extension RUMErrorEvent: RUMSanitizableEvent {}

extension RUMLongTaskEvent: RUMSanitizableEvent {}

extension RUMVitalAppLaunchEvent: RUMSanitizableEvent {}

extension RUMVitalOperationStepEvent: RUMSanitizableEvent {}

extension RUMTimeseriesMemoryEvent: RUMSanitizableEvent {}

extension RUMTimeseriesCpuEvent: RUMSanitizableEvent {}
