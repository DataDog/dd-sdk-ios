/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class HeatmapIdentifierStore: @unchecked Sendable, HeatmapIdentifierRegistry {
    @ReadWriteLock
    private var identifiers: [ObjectIdentifier: HeatmapIdentifier] = [:]

    func setHeatmapIdentifiers(_ heatmapIdentifiers: [ObjectIdentifier: HeatmapIdentifier]) {
        identifiers = heatmapIdentifiers
    }

    func heatmapIdentifier(for objectIdentifier: ObjectIdentifier) -> HeatmapIdentifier? {
        identifiers[objectIdentifier]
    }
}
