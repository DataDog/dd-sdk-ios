/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// `PerformancePresetOverride` is a public structure that allows you to customize
/// performance presets by setting optional limits. If the limits are not provided, the default values from
/// the `PerformancePreset` object will be used.
public struct PerformancePresetOverride {
    /// An optional value representing the maximum allowed file size in bytes.
    /// If not provided, the default value from the `PerformancePreset` object is used.
    let maxFileSize: UInt64?

    /// An optional value representing the maximum allowed object size in bytes.
    /// If not provided, the default value from the `PerformancePreset` object is used.
    let maxObjectSize: UInt64?

    /// Initializes a new `PerformancePresetOverride` instance with the provided
    /// maximum file size and maximum object size limits.
    ///
    /// - Parameters:
    ///   - maxFileSize: The maximum allowed file size in bytes, or `nil` to use the default value from `PerformancePreset`.
    ///   - maxObjectSize: The maximum allowed object size in bytes, or `nil` to use the default value from `PerformancePreset`.
    public init(maxFileSize: UInt64?, maxObjectSize: UInt64?) {
        self.maxFileSize = maxFileSize
        self.maxObjectSize = maxObjectSize
    }
}
