/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Set of constatns for Synthetics configuration.
internal enum Synthetics {
    /// The duration of benchmark in Synthetics.
    /// This is the duration since starting a benchmark to asserting that end result screen is presented.
    static let testDuration: TimeInterval = 30 * 60
}
