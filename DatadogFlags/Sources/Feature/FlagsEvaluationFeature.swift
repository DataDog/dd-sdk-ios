/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FlagsEvaluationFeature: DatadogRemoteFeature {
    static let name = "flags-evaluation"

    let requestBuilder: any FeatureRequestBuilder
    let messageReceiver: any FeatureMessageReceiver
    let performanceOverride: PerformancePresetOverride

    init(
        customIntakeURL: URL?,
        telemetry: Telemetry
    ) {
        requestBuilder = EvaluationRequestBuilder(
            customIntakeURL: customIntakeURL,
            telemetry: telemetry
        )
        messageReceiver = NOPFeatureMessageReceiver()
        performanceOverride = PerformancePresetOverride(maxObjectsInFile: 50)
    }
}
