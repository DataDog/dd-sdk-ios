/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal protocol ExposureLogging {
    func logExposure(
        at date: Date,
        for flagKey: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext
    )
}

internal final class ExposureLogger: ExposureLogging {
    private struct Exposure: Hashable {
        let targetingKey: String
        let flagKey: String
        let allocationKey: String
        let variationKey: String
    }

    private let featureScope: any FeatureScope
    private var loggedExposures: Set<Exposure> = []

    init(featureScope: any FeatureScope) {
        self.featureScope = featureScope
    }

    func logExposure(
        at date: Date,
        for flagKey: String,
        assignment: FlagAssignment,
        context: FlagsEvaluationContext
    ) {
        guard assignment.doLog else {
            return
        }

        featureScope.eventWriteContext { [weak self] _, writer in
            guard let self else {
                return
            }

            let exposure = Exposure(
                targetingKey: context.targetingKey,
                flagKey: flagKey,
                allocationKey: assignment.allocationKey,
                variationKey: assignment.variationKey
            )

            guard !loggedExposures.contains(exposure) else {
                return
            }
            loggedExposures.insert(exposure)

            let exposureEvent = ExposureEvent(
                timestamp: date.timeIntervalSince1970.toInt64Milliseconds,
                allocation: .init(key: assignment.allocationKey),
                flag: .init(key: flagKey),
                variant: .init(key: assignment.variationKey),
                subject: .init(
                    id: context.targetingKey,
                    attributes: context.attributes
                )
            )

            writer.write(value: exposureEvent)
        }
    }
}
