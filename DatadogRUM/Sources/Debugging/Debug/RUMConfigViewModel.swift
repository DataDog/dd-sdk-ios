/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

@available(iOS 15.0, *)
public final class RUMConfigViewModel: ObservableObject {
    @Published var customEndpointUrl: String
    @Published var featureFlags: [RUM.Configuration.FeatureFlag: Bool]

    private let rumFeature: RUMFeature?
//    let metricsManager: DatadogMetricSubscriber

    public init(
        core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        rumFeature = core.get(feature: RUMFeature.self)
//        self.metricsManager = metricsManager
        customEndpointUrl = rumFeature?.configuration.customEndpoint?.absoluteString ?? "Unknown"
        featureFlags = rumFeature?.configuration.featureFlags ?? [:]
    }

    func toggleFeatureFlag(_ flag: RUM.Configuration.FeatureFlag) {
        featureFlags[flag]?.toggle()
        // TODO: Apply the changes to RUM configuration (it's constant)
    }
}
