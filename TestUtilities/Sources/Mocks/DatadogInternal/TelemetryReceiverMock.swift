/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// `BusMessageReceiver` that records received telemetry events.
public final class TelemetryReceiverMock: BusMessageReceiver {
    @ReadWriteLock
    public private(set) var messages: [TelemetryMessage] = []

    public init() {}

    public func receive(message: TelemetryMessage, from core: DatadogCoreProtocol) {
        messages.append(message)
    }
}
