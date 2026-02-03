/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FlagsFeature: DatadogRemoteFeature {
    static let name = "flags"

    private enum Constants {
        static let minEvaluationFlushInterval: TimeInterval = 1.0
        static let maxEvaluationFlushInterval: TimeInterval = 60.0
    }

    let flagAssignmentsFetcher: any FlagAssignmentsFetching
    let requestBuilder: any FeatureRequestBuilder
    let messageReceiver: any FeatureMessageReceiver
    let clientRegistry: FlagsClientRegistry
    let makeExposureLogger: (any FeatureScope) -> any ExposureLogging
    let makeEvaluationLogger: (any FeatureScope) -> any EvaluationLogging
    let makeRUMFlagEvaluationReporter: (any FeatureScope) -> any RUMFlagEvaluationReporting
    let performanceOverride: PerformancePresetOverride
    let issueReporter: IssueReporter
    private let evaluationAggregator: EvaluationAggregator?

    init(
        configuration: Flags.Configuration,
        featureScope: FeatureScope,
        core: DatadogCoreProtocol
    ) {
        flagAssignmentsFetcher = FlagAssignmentsFetcher(
            customEndpoint: configuration.customFlagsEndpoint,
            customHeaders: configuration.customFlagsHeaders,
            featureScope: featureScope
        )
        requestBuilder = ExposureRequestBuilder(
            customIntakeURL: configuration.customExposureEndpoint,
            telemetry: featureScope.telemetry
        )
        messageReceiver = NOPFeatureMessageReceiver()
        clientRegistry = FlagsClientRegistry()
        makeExposureLogger = { featureScope in
            guard configuration.trackExposures else {
                return NOPExposureLogger()
            }
            return ExposureLogger(
                dateProvider: SystemDateProvider(),
                featureScope: featureScope
            )
        }

        evaluationAggregator = configuration.trackEvaluations ? {
            var flushInterval = configuration.evaluationFlushInterval
            if flushInterval < Constants.minEvaluationFlushInterval {
                DD.logger.warn("`Flags.Configuration.evaluationFlushInterval` cannot be less than \(Constants.minEvaluationFlushInterval)s. A value of \(Constants.minEvaluationFlushInterval)s will be used.")
                flushInterval = Constants.minEvaluationFlushInterval
            } else if flushInterval > Constants.maxEvaluationFlushInterval {
                DD.logger.warn("`Flags.Configuration.evaluationFlushInterval` cannot exceed \(Constants.maxEvaluationFlushInterval)s. A value of \(Constants.maxEvaluationFlushInterval)s will be used.")
                flushInterval = Constants.maxEvaluationFlushInterval
            }

            return EvaluationAggregator(
                dateProvider: SystemDateProvider(),
                featureScope: core.scope(for: FlagsEvaluationFeature.self),
                flushInterval: flushInterval
            )
        }() : nil

        makeEvaluationLogger = { [aggregator = evaluationAggregator] _ in
            guard let aggregator = aggregator else {
                return NOPEvaluationLogger()
            }
            return EvaluationLogger(aggregator: aggregator)
        }

        makeRUMFlagEvaluationReporter = { featureScope in
            guard configuration.rumIntegrationEnabled else {
                return NOPRUMFlagEvaluationReporter()
            }
            return RUMFlagEvaluationReporter(featureScope: featureScope)
        }
        performanceOverride = PerformancePresetOverride(maxObjectsInFile: 50)

        issueReporter = IssueReporter.default(isGracefulModeEnabled: configuration.gracefulModeEnabled)
    }
}

extension FlagsFeature: Flushable {
    func flush() {
        evaluationAggregator?.sendEvaluations()
    }
}
