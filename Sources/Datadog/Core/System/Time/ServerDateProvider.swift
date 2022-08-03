/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// List of Datadog NTP pools.
public let DatadogNTPServers = [
    "0.datadog.pool.ntp.org",
    "1.datadog.pool.ntp.org",
    "2.datadog.pool.ntp.org",
    "3.datadog.pool.ntp.org"
]

/// Abstract the monotonic clock synchronized with the server using NTP.
public protocol ServerDateProvider {
    /// Start the clock synchronisation with NTP server.
    ///
    /// Calls the `completion` by passing it the server time offset when the synchronization succeeds.
    func synchronize(update: @escaping (TimeInterval) -> Void)
}
