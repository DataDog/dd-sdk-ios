/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol ExposureLogging {
    func logExposure(at date: Date, for flagKey: String, flagAssignment: FlagAssignment)
}

internal final class ExposureLogger: ExposureLogging {
    private struct Exposure: Hashable {
        let targetingKey: String
        let flagKey: String
        let allocationKey: String
        let variationKey: String
    }

    private let flagsEvaluationContext: FlagsEvaluationContext
    private let featureScope: FeatureScope

    private var loggedExposures: Set<Exposure> = []

    init(
        flagsEvaluationContext: FlagsEvaluationContext,
        featureScope: FeatureScope
    ) {
        self.featureScope = featureScope
        self.flagsEvaluationContext = flagsEvaluationContext
    }

    func logExposure(at date: Date, for flagKey: String, flagAssignment: FlagAssignment) {
        guard flagAssignment.doLog else {
            return
        }

        featureScope.eventWriteContext { [weak self] _, writer in
            guard let self else {
                return
            }

            let exposure = Exposure(
                targetingKey: flagsEvaluationContext.targetingKey,
                flagKey: flagKey,
                allocationKey: flagAssignment.allocationKey,
                variationKey: flagAssignment.variationKey
            )

            guard !loggedExposures.contains(exposure) else {
                return
            }
            loggedExposures.insert(exposure)

            let exposureEvent = ExposureEvent(
                timestamp: date.timeIntervalSince1970.toInt64Milliseconds,
                allocation: .init(key: flagAssignment.allocationKey),
                flag: .init(key: flagKey),
                variant: .init(key: flagAssignment.variationKey),
                subject: .init(
                    id: flagsEvaluationContext.targetingKey,
                    attributes: flagsEvaluationContext.attributes
                )
            )

            writer.write(value: exposureEvent)
        }
    }
}
