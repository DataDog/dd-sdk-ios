/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Heatmap attributes attached to a user action.
public struct HeatmapAttributes: Equatable {
    /// The permanent identifier of the action target.
    public let targetPermanentID: String
    /// The width of the action target, in points.
    public let targetWidth: Int64
    /// The height of the action target, in points.
    public let targetHeight: Int64
    /// The x-coordinate of the tap relative to the target, in points.
    public let positionX: Int64
    /// The y-coordinate of the tap relative to the target, in points.
    public let positionY: Int64

    /// Creates a heatmap attributes value.
    /// - Parameters:
    ///   - identifier: The action target identifier.
    ///   - size: The action target size, in points.
    ///   - location: The tap location relative to the target, in points.
    public init(identifier: HeatmapIdentifier, size: CGSize, location: CGPoint) {
        self.targetPermanentID = identifier.rawValue
        self.targetWidth = Int64.ddWithNoOverflow(size.width)
        self.targetHeight = Int64.ddWithNoOverflow(size.height)
        self.positionX = Int64.ddWithNoOverflow(location.x)
        self.positionY = Int64.ddWithNoOverflow(location.y)
    }
}
