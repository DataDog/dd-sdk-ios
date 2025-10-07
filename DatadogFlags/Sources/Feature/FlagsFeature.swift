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
    let rumIntegrationEnabled: Bool
    let trackExposures: Bool

    let performanceOverride: PerformancePresetOverride

    init(
        configuration: Flags.Configuration,
        featureScope: FeatureScope
    ) {
        self.rumIntegrationEnabled = configuration.rumIntegrationEnabled
        self.trackExposures = configuration.trackExposures
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
        performanceOverride = PerformancePresetOverride(maxObjectsInFile: 50)
    }
}
