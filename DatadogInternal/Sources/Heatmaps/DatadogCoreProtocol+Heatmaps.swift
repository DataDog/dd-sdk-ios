/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension DatadogCoreProtocol {
    /// Registers a heatmap identifier registry in this core.
    public func register(heatmapIdentifierRegistry: HeatmapIdentifierRegistry) throws {
        guard get(feature: HeatmapIdentifierRegistryFeature.self) == nil else {
            return
        }

        let feature = HeatmapIdentifierRegistryFeature(registry: heatmapIdentifierRegistry)
        try register(feature: feature)
    }

    /// Returns the heatmap identifier registry, if registered.
    public var heatmapIdentifierRegistry: HeatmapIdentifierRegistry? {
        self.get(feature: HeatmapIdentifierRegistryFeature.self)?.registry
    }
}
