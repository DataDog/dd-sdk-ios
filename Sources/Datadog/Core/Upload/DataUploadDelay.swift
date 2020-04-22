/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Mutable interval used for periodic data uploads.
internal struct DataUploadDelay {
    private let defaultDelay: TimeInterval
    private let minDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let decreaseFactor: Double

    private var delay: TimeInterval

    init(performance: PerformancePreset) {
        self.defaultDelay = performance.defaultLogsUploadDelay
        self.minDelay = performance.minLogsUploadDelay
        self.maxDelay = performance.maxLogsUploadDelay
        self.decreaseFactor = performance.logsUploadDelayDecreaseFactor
        self.delay = performance.initialLogsUploadDelay
    }

    mutating func nextUploadDelay() -> TimeInterval {
        defer {
            if delay == maxDelay {
                delay = defaultDelay
            }
        }
        return delay
    }

    mutating func decrease() {
        delay = max(minDelay, delay * decreaseFactor)
    }

    mutating func increaseOnce() {
        delay = maxDelay
    }
}
