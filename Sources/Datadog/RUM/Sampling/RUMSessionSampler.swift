/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Decides if RUM session should be "sampled", i.e. if it will be sent to Datadog.
internal struct RUMSessionSampler {
    /// Value between `0.0` and `100.0`, where `0.0` means NO events will be sent and `100.0` means ALL will be send.
    let samplingRate: Float

    init(samplingRate: Float) {
        self.samplingRate = max(0, min(100, samplingRate))
    }

    /// Based on the sampling rate, it returns random value deciding if a session should be "sampled" or not.
    /// - Returns: `true` if session should be sent to Datadog and `false` otherwise.
    func isSampled() -> Bool {
        return Float.random(in: 0.0..<100.0) < samplingRate
    }
}
