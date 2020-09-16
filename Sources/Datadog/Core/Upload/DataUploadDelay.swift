/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal protocol Delay {
    var current: TimeInterval { get }
    mutating func decrease()
    mutating func increase()
}

/// Mutable interval used for periodic data uploads.
internal struct DataUploadDelay: Delay {
    private let defaultDelay: TimeInterval
    private let minDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let changeRate: Double

    private var delay: TimeInterval

    init(performance: UploadPerformancePreset) {
        self.defaultDelay = performance.defaultUploadDelay
        self.minDelay = performance.minUploadDelay
        self.maxDelay = performance.maxUploadDelay
        self.changeRate = performance.uploadDelayChangeRate
        self.delay = performance.initialUploadDelay
    }

    var current: TimeInterval { delay }

    mutating func decrease() {
        delay = max(minDelay, delay * (1.0 - changeRate))
    }

    mutating func increase() {
        delay = min(delay * (1.0 + changeRate), maxDelay)
    }
}
