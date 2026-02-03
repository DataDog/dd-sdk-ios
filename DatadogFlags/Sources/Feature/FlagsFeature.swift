/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FlagsFeature: DatadogRemoteFeature {
    static let name = "flags"

    let flagAssignmentsFetcher: any FlagAssignmentsFetching
    let requestBuilder: any FeatureRequestBuilder
    let messageReceiver: any FeatureMessageReceiver
    let clientRegistry: FlagsClientRegistry
    let makeExposureLogger: (any FeatureScope) -> any ExposureLogging
    let makeRUMFlagEvaluationReporter: (any FeatureScope) -> any RUMFlagEvaluationReporting
    let performanceOverride: PerformancePresetOverride
    let issueReporter: IssueReporter

    init(
        configuration: Flags.Configuration,
        featureScope: FeatureScope
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
