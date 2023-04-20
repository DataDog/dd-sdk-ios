/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import Datadog

internal struct DatadogFeatureMock: DatadogFeature {
    static let featureName = "mock"

    var name: String = DatadogFeatureMock.featureName
    var requestBuilder: FeatureRequestBuilder = FeatureRequestBuilderMock()
    var messageReceiver: FeatureMessageReceiver = FeatureMessageReceiverMock()
    var performanceOverride: PerformancePresetOverride? = nil
}
