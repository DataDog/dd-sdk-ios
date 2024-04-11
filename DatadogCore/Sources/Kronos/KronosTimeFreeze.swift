/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software developed by MobileNativeFoundation, https://mobilenativefoundation.org and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/MobileNativeFoundation/Kronos/blob/main/LICENSE
 */

import Foundation

private let kUptimeKey = "Uptime"
private let kTimestampKey = "Timestamp"
private let kOffsetKey = "Offset"

internal struct KronosTimeFreeze {
    private let uptime: TimeInterval
    private let timestamp: TimeInterval
    private let offset: TimeInterval

    /// The stable timestamp adjusted by the most accurate offset known so far.
    var adjustedTimestamp: TimeInterval {
        return self.offset + self.stableTimestamp
    }

    /// The stable timestamp (calculated based on the uptime); note that this doesn't have sub-seconds
    /// precision. See `getSystemUptime()` for more information.
    var stableTimestamp: TimeInterval {
        return (KronosTimeFreeze.getSystemUptime() - self.uptime) + self.timestamp
    }

    /// Time interval between now and the time the NTP response represented by this TimeFreeze was received.
    var timeSinceLastNtpSync: TimeInterval {
        return KronosTimeFreeze.getSystemUptime() - uptime
    }

    init(offset: TimeInterval) {
        self.offset = offset
        self.timestamp = kronosCurrentTime()
        self.uptime = KronosTimeFreeze.getSystemUptime()
    }

    init?(from dictionary: [String: TimeInterval]) {
        guard let uptime = dictionary[kUptimeKey],
              let timestamp = dictionary[kTimestampKey],
              let offset = dictionary[kOffsetKey] else {
            return nil
        }

        let currentUptime = KronosTimeFreeze.getSystemUptime()
        let currentTimestamp = kronosCurrentTime()
        let currentBoot = currentUptime - currentTimestamp
        let previousBoot = uptime - timestamp
        if rint(currentBoot) - rint(previousBoot) != 0 {
            return nil
        }

        self.uptime = uptime
        self.timestamp = timestamp
        self.offset = offset
    }

    /// Convert this TimeFreeze to a dictionary representation.
    ///
    /// - returns: A dictionary representation.
    func toDictionary() -> [String: TimeInterval] {
        return [
            kUptimeKey: self.uptime,
            kTimestampKey: self.timestamp,
            kOffsetKey: self.offset,
        ]
    }

    /// Returns a high-resolution measurement of system uptime, that continues ticking through device sleep
    /// *and* user- or system-generated clock adjustments. This allows for stable differences to be calculated
    /// between timestamps.
    ///
    /// Note: Due to an issue in BSD/darwin, sub-second precision will be lost;
    /// see: https://github.com/darwin-on-arm/xnu/blob/master/osfmk/kern/clock.c#L522.
    ///
    /// - returns: An Int measurement of system uptime in microseconds.
    private static func getSystemUptime() -> TimeInterval {
        var mib = [CTL_KERN, KERN_BOOTTIME]
        var size = MemoryLayout<timeval>.stride
        var bootTime = timeval()

        let bootTimeError = sysctl(&mib, u_int(mib.count), &bootTime, &size, nil, 0) != 0
        assert(!bootTimeError, "system clock error: kernel boot time unavailable")

        let now = kronosCurrentTime()
        let uptime = Double(bootTime.tv_sec) + Double(bootTime.tv_usec) / 1_000_000
        assert(now >= uptime, "inconsistent clock state: system time precedes boot time")

        return now - uptime
    }
}
