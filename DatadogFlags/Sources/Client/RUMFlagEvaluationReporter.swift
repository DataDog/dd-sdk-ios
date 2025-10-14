/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol RUMFlagEvaluationReporting {
    func sendFlagEvaluation<T: FlagValue>(flagKey: String, value: T)
}

internal final class RUMFlagEvaluationReporter: RUMFlagEvaluationReporting {
    private let featureScope: any FeatureScope

    init(featureScope: any FeatureScope) {
        self.featureScope = featureScope
    }

    func sendFlagEvaluation<T>(flagKey: String, value: T) where T: FlagValue {
        featureScope.send(
            message: .payload(
                RUMFlagEvaluationMessage(
                    flagKey: flagKey,
                    value: value
                )
            )
        )
    }
}

// MARK: NOPRUMFlagEvaluationReporter

internal final class NOPRUMFlagEvaluationReporter: RUMFlagEvaluationReporting {
    func sendFlagEvaluation<T>(flagKey: String, value: T) where T: FlagValue {
        // Do nothing
    }
}
