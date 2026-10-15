/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@_spi(Internal)
import DatadogInternal

/// Receives flag evaluation messages and adds them to RUM.
internal struct FlagEvaluationReceiver: FeatureMessageReceiver {
    /// The RUM monitor instance.
    let monitor: Monitor

    /// Adds feature flag evaluation to the current RUM view.
    func receive(message: FeatureMessage, from core: any DatadogCoreProtocol) -> Bool {
        if case let .payload(captured as RUMFlagEvaluationContextMessage) = message {
            guard let context = captured.context(for: monitor.rumContextHandoffOwner) else {
                return true
            }
            let target: RUMCommandTarget
            if let viewID = context.rumContext?.viewID.flatMap(UUID.init(uuidString:)) {
                target = .view(RUMUUID(rawValue: viewID))
            } else if let scene = context.sceneIdentifier, !scene.isEmpty {
                target = .scene(RUMSceneIdentifier(rawValue: scene))
            } else {
                target = .none
            }
            monitor.addFeatureFlagEvaluation(
                name: captured.evaluation.flagKey,
                value: captured.evaluation.value,
                target: target
            )
            return true
        }

        guard case let .payload(flagEvaluation as RUMFlagEvaluationMessage) = message else {
            return false
        }

        monitor.addFeatureFlagEvaluation(
            name: flagEvaluation.flagKey,
            value: flagEvaluation.value
        )

        return true
    }
}
