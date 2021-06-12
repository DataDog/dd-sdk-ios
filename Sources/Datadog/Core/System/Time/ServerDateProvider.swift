/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Kronos

/// Abstract the monotonic clock synchronized with the server using NTP.
internal protocol ServerDateProvider {
    /// Start the clock synchronisation with NTP server.
    /// Calls the `completion` by passing it the server time when the synchronization succeeds or`nil` if it fails.
    func synchronize(with ntpPool: String, completion: @escaping (Date?) -> Void)
    /// Returns the server time or `nil` if not yet determined.
    /// This time gets more precise while synchronization is pending.
    func currentDate() -> Date?
}

internal class NTPServerDateProvider: ServerDateProvider {
    func synchronize(with ntpPool: String, completion: @escaping (Date?) -> Void) {
        Clock.sync(from: ntpPool, completion: { serverTime, _ in
            completion(serverTime)
        })
    }

    func currentDate() -> Date? {
        return Clock.now
    }
}
