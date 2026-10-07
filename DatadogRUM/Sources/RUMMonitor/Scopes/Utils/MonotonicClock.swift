/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Measures elapsed time for deciding when a session times out through inactivity or reaches its maximum duration.
///
/// Session lifetime is a *duration*, so measuring it with `Date`s is unsafe: the wall clock moves when the device
/// time changes, and `RUMCommand.time` may carry a timestamp produced by a cross-platform SDK's own clock
/// (see `Monitor.transform(command:)`). Comparing either against a previously stored `Date` can report minutes or
/// hours of inactivity that never elapsed, ending a session that is still in use.
internal protocol MonotonicClock {
    /// A monotonically increasing number of seconds from an arbitrary origin.
    ///
    /// Only the difference between two readings is meaningful. It cannot be moved by device time changes, and it
    /// keeps advancing while the device is asleep, so a backgrounded session still times out.
    var elapsedTime: TimeInterval { get }
}

internal struct SystemMonotonicClock: MonotonicClock {
    var elapsedTime: TimeInterval {
        // On Darwin, `CLOCK_MONOTONIC` cannot be set and keeps advancing while the device sleeps,
        // unlike `CLOCK_UPTIME_RAW`, which pauses.
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC)) / 1_000_000_000
    }
}
