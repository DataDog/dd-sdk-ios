/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Observes `DatadogContext.hasReplay` through the core's context message bus so `Monitor` stays current
/// even when Session Replay starts/stops with no `RUMCommand` processed around the same time.
internal struct HasReplayMessageReceiver: FeatureMessageReceiver {
    let monitor: Monitor

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message else {
            return false
        }

        monitor.update(hasReplay: context.hasReplay)

        return false
    }
}
