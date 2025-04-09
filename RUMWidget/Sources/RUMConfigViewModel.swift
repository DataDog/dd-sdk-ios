/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation
import DatadogRUM

@available(iOS 15.0, *)
public final class RUMConfigViewModel: ObservableObject {
    @Published var customEndpointUrl: String = ""
    @Published var featureFlags: [RUM.Configuration.FeatureFlag: Bool] = [:]

    private let rumFeature: RUMFeature?

    public init(
        core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        rumFeature = core.get(feature: RUMFeature.self)
    }

    func toggleFeatureFlag(_ flag: RUM.Configuration.FeatureFlag) {
        featureFlags[flag]?.toggle()
        // TODO: Apply the changes to RUM configuration (it's constant)
    }
}
