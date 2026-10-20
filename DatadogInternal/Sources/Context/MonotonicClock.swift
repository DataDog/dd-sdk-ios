/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Measures elapsed time, including device sleep, independently of changes to the device date.
///
/// Use this clock for timeouts and durations that must include sleep, such as RUM session lifetime.
/// `CACurrentMediaTimeProvider` supplies media uptime, which pauses during sleep and matches Core Animation
/// frame timestamps. Readings from these two clocks are not interchangeable.
public protocol MonotonicClock {
    /// A monotonically increasing number of seconds from an arbitrary origin.
    ///
    /// Only differences between readings from the same clock are meaningful. This clock continues
    /// advancing while the device is asleep, so timeouts still account for that elapsed time.
    var elapsedTime: TimeInterval { get }
}

/// Provides elapsed time that includes device sleep.
public struct SystemMonotonicClock: MonotonicClock {
    public init() { }

    public var elapsedTime: TimeInterval {
        // On Darwin, CLOCK_MONOTONIC includes device sleep; CLOCK_UPTIME_RAW does not.
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}
