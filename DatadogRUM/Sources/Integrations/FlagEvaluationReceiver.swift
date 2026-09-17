/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Receives flag evaluation messages and adds them to RUM.
internal final class FlagEvaluationReceiver: BusMessageReceiver {
    /// The RUM monitor instance.
    let monitor: Monitor

    init(monitor: Monitor) {
        self.monitor = monitor
    }

    /// Adds feature flag evaluation to the current RUM view.
    func receive(message flagEvaluation: RUMFlagEvaluationMessage, from core: any DatadogCoreProtocol) {
        monitor.addFeatureFlagEvaluation(
            name: flagEvaluation.flagKey,
            value: flagEvaluation.value
        )
    }
}
