/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Provides heatmap identifiers for UI elements, enabling correlation between RUM actions and Session Replay wireframes.
public protocol HeatmapIdentifierRegistry: Sendable {
    /// Replaces the current identifiers with a new snapshot.
    func setHeatmapIdentifiers(_ heatmapIdentifiers: [ObjectIdentifier: HeatmapIdentifier])

    /// Returns the heatmap identifier for a UI element, if available.
    func heatmapIdentifier(for objectIdentifier: ObjectIdentifier) -> HeatmapIdentifier?
}
