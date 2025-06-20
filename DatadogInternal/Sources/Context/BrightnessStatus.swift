/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Describe the battery state for mobile devices.
public struct BrightnessStatus: Codable, Equatable {
    /// The brightness level
    public let level: Float

    public init(level: Float) {
        self.level = level
    }
}
