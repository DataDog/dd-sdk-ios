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
    /// Calls the `completion` by passing it the server time offset when the synchronization succeeds or`nil` if it fails.
    func synchronize(with pool: String, completion: @escaping (TimeInterval?) -> Void)
    /// Returns the server time offset or `nil` if not yet determined.
    /// This offset gets more precise while synchronization is pending.
    var offset: TimeInterval? { get }
}

internal class NTPServerDateProvider: ServerDateProvider {
    /// Server offset publisher.
    private let publisher: ValuePublisher<TimeInterval?> = ValuePublisher(initialValue: nil)

    /// Returns the server time offset or `nil` if not yet determined.
    /// This offset gets more precise while synchronization is pending.
    var offset: TimeInterval? {
        return publisher.currentValue
    }

    func synchronize(with pool: String, completion: @escaping (TimeInterval?) -> Void) {
        Clock.sync(
            from: pool,
            first: { [weak self] _, offset in
                self?.publisher.publishAsync(offset)
            },
            completion: { [weak self] now, offset in
                // Kronos only notifies for the first and last samples.
                // In case, the last sample does not return an offset, we calculate the offset
                // from the returned `now` parameter. The `now` parameter in this callback
                // is `Clock.now`, so it is possible to have `now` but not `offset`.
                if let offset = offset {
                    self?.publisher.publishAsync(offset)
                } else if let now = now {
                    self?.publisher.publishAsync(now.timeIntervalSinceNow)
                }

                completion(self?.publisher.currentValue)
            }
        )

        // `Kronos.sync` first loads the previous state from the `UserDefaults` if any.
        // We can invoke `Clock.now` to retrieve the stored offset.
        publisher.publishAsync(Clock.now?.timeIntervalSinceNow)
    }
}
