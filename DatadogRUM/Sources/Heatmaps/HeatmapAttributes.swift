/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Heatmap attributes attached to a user action.
internal struct HeatmapAttributes {
    /// The permanent identifier of the action target.
    let targetPermanentID: String
    /// The width of the action target, in points.
    let targetWidth: Int64
    /// The height of the action target, in points.
    let targetHeight: Int64
    /// The x-coordinate of the tap relative to the target, in points.
    let positionX: Int64
    /// The y-coordinate of the tap relative to the target, in points.
    let positionY: Int64
}
