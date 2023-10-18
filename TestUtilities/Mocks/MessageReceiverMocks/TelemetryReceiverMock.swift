/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// `FeatureMessageReceiver` that records received telemetry events.
public class TelemetryReceiverMock: FeatureMessageReceiver {
    @ReadWriteLock
    public private(set) var messages: [TelemetryMessage] = []

    public init() {}

    public func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .telemetry(message) = message else {
            return false
        }

        messages.append(message)
        return true
    }
}
