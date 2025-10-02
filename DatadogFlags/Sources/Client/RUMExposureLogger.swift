/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol RUMExposureLogging {
    func logExposure<T: FlagValue>(
        flagKey: String,
        value: T,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext
    )
}

internal final class RUMExposureLogger: RUMExposureLogging {
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope

    init(dateProvider: any DateProvider, featureScope: any FeatureScope) {
        self.dateProvider = dateProvider
        self.featureScope = featureScope
    }

    func logExposure<T: FlagValue>(
        flagKey: String,
        value: T,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext
    ) {
        featureScope.send(
            message: .payload(
                RUMFlagEvaluationMessage(
                    flagKey: flagKey,
                    value: value
                )
            )
        )

        featureScope.context { [weak self] context in
            guard let self else {
                return
            }

            let timestamp = self.dateProvider.now
                .addingTimeInterval(context.serverTimeOffset)
                .timeIntervalSince1970

            self.featureScope.send(
                message: .payload(
                    RUMFlagExposureMessage(
                        timestamp: timestamp,
                        flagKey: flagKey,
                        allocationKey: assignment.allocationKey,
                        exposureKey: "\(flagKey)-\(assignment.allocationKey)",
                        subjectKey: evaluationContext.targetingKey,
                        variantKey: assignment.variationKey,
                        subjectAttributes: evaluationContext.attributes
                    )
                )
            )
        }
    }
}
