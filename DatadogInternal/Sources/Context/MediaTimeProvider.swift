/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
#if !os(watchOS)
import QuartzCore
#endif

/// Provides current media uptime.
/// Media uptime is a monotonic clock value, expressed in seconds, that is **not** affected by
/// wall-clock corrections (NTP, DST, manual changes). Only deltas between two readings carry
/// meaning — the absolute value is implementation-defined. Use this provider in combination
/// with a `DateProvider` whenever you need a duration that must be `>= 0` regardless of
/// wall-clock adjustments.
public protocol CACurrentMediaTimeProvider: Sendable {
    /// Current media uptime.
    var current: CFTimeInterval { get }
}

public struct MediaTimeProvider: CACurrentMediaTimeProvider {
    public init() { }
    /// Returns the current CoreAnimation absolute time.
    /// This is the result of calling mach_absolute_time() and converting the units to seconds.
    public var current: CFTimeInterval {
#if !os(watchOS)
        return CACurrentMediaTime()
#else
        ProcessInfo.processInfo.systemUptime
#endif
    }
}
