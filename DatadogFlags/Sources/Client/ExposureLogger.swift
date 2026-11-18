/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// The one exposure verdict of an evaluation, shared by the Datadog send and the customer hook.
internal struct ExposureDecision: Equatable {
    /// A successful evaluation of an allocation that logs exposures, repeats included.
    let isExposure: Bool
    /// For an exposure (`isExposure`), the exposure cache holds the same allocation, variant and serial ID for the subject and flag.
    let isCacheHit: Bool

    /// A new exposure. The Datadog write depends on exposure tracking and the tracking consent.
    var shouldSend: Bool { isExposure && !isCacheHit }

    static let notAnExposure = ExposureDecision(isExposure: false, isCacheHit: false)
}

internal protocol ExposureLogging {
    /// Records the exposure in the cache and returns the verdict. Call it for successful evaluations.
    @discardableResult
    func logExposure(
        for flagKey: String,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext
    ) -> ExposureDecision
}

internal final class ExposureLogger: ExposureLogging {
    private let dateProvider: any DateProvider
    private let featureScope: any FeatureScope
    private let sendsExposures: Bool
    private let loggedExposures = ExposureTracker()

    /// - Parameter sendsExposures: `true` writes new exposures to Datadog. The cache records in both modes, which keeps verdicts correct.
    init(dateProvider: any DateProvider, featureScope: any FeatureScope, sendsExposures: Bool = true) {
        self.dateProvider = dateProvider
        self.featureScope = featureScope
        self.sendsExposures = sendsExposures
    }

    @discardableResult
    func logExposure(
        for flagKey: String,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext
    ) -> ExposureDecision {
        guard assignment.doLog else {
            return .notAnExposure
        }

        let exposure = ExposureTracker.Exposure(
            targetingKey: evaluationContext.targetingKey,
            flagKey: flagKey,
            allocationKey: assignment.allocationKey,
            variationKey: assignment.variationKey,
            serialID: assignment.serialID
        )

        guard loggedExposures.track(exposure) else {
            return ExposureDecision(isExposure: true, isCacheHit: true)
        }

        let decision = ExposureDecision(isExposure: true, isCacheHit: false)
        guard sendsExposures else {
            return decision
        }

        let features = assignment.features.values(for: .exposure)
        featureScope.eventWriteContext { [dateProvider] context, writer in
            let date = dateProvider.now.addingTimeInterval(context.serverTimeOffset)
            let exposureEvent = ExposureEvent(
                timestamp: date.timeIntervalSince1970.dd.toInt64Milliseconds,
                allocation: .init(key: assignment.allocationKey),
                flag: .init(key: flagKey),
                variant: .init(key: assignment.variationKey),
                serialID: assignment.serialID,
                subject: .init(
                    id: evaluationContext.targetingKey,
                    attributes: evaluationContext.attributes
                ),
                features: features.isEmpty ? nil : features
            )

            writer.write(value: exposureEvent)
        }
        return decision
    }
}

/// Used when exposure tracking is disabled and no ``ExposureHook`` reads the verdict.
internal final class NOPExposureLogger: ExposureLogging {
    func logExposure(
        for flagKey: String,
        assignment: FlagAssignment,
        evaluationContext: FlagsEvaluationContext
    ) -> ExposureDecision {
        .notAnExposure
    }
}
