/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal) import DatadogInternal

/// Keeps the caller's explicit capture separate from the source-less path.
internal struct RUMOwnedOperationStepCommand: RUMCommand {
    var step: RUMOperationStepVitalCommand
    let origin: RUMOperationOrigin
    let capture: RUMContextHandoff.CurrentValue?

    var time: Date { get { step.time } set { step.time = newValue } }
    var target: RUMCommandTarget { get { step.target } set { step.target = newValue } }
    var globalAttributes: [AttributeKey: AttributeValue] {
        get { step.globalAttributes }
        set { step.globalAttributes = newValue }
    }
    var attributes: [AttributeKey: AttributeValue] {
        get { step.attributes }
        set { step.attributes = newValue }
    }
    var canStartBackgroundView: Bool { step.canStartBackgroundView }
    var isUserInteraction: Bool { step.isUserInteraction }
    var missedEventType: SessionEndedMetric.MissedEventType? { step.missedEventType }
    var canStartApplicationLaunchView: Bool { step.canStartApplicationLaunchView }
    var shouldRestartLastViewAfterSessionExpiration: Bool { step.shouldRestartLastViewAfterSessionExpiration }
    var shouldRestartLastViewAfterSessionStop: Bool { step.shouldRestartLastViewAfterSessionStop }
    var canStartBackgroundViewAfterSessionStop: Bool { step.canStartBackgroundViewAfterSessionStop }
}
