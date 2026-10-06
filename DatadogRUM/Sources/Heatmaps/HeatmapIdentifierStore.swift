/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)
import Foundation
import DatadogInternal

internal final class HeatmapIdentifierStore: @unchecked Sendable, HeatmapIdentifierRegistry {
    private struct State {
        var identifiers: [ObjectIdentifier: HeatmapIdentifier] = [:]
        var requiresDescendantLookup = false
    }

    @ReadWriteLock
    private var state = State()

    var requiresDescendantLookup: Bool {
        state.requiresDescendantLookup
    }

    func setHeatmapIdentifiers(
        _ heatmapIdentifiers: [ObjectIdentifier: HeatmapIdentifier],
        requiresDescendantLookup: Bool
    ) {
        state = State(
            identifiers: heatmapIdentifiers,
            requiresDescendantLookup: requiresDescendantLookup
        )
    }

    func heatmapIdentifier(for objectIdentifier: ObjectIdentifier) -> HeatmapIdentifier? {
        state.identifiers[objectIdentifier]
    }
}
#endif
