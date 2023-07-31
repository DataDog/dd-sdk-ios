/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software developed by MobileNativeFoundation, https://mobilenativefoundation.org and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/MobileNativeFoundation/Kronos/blob/main/LICENSE
 */

import Foundation

/// Struct that has time + related metadata
internal typealias KronosAnnotatedTime = (
    /// Time that is being annotated
    date: Date,

    /// Amount of time that has passed since the last NTP sync; in other words, the NTP response age.
    timeSinceLastNtpSync: TimeInterval
)

internal protocol KronosClockProtocol {
    /// The most accurate date that we have so far (nil if no synchronization was done yet)
    var now: Date? { get }

    /// Syncs the clock using NTP. Note that the full synchronization could take a few seconds. The given
    /// closure will be called with the first valid NTP response which accuracy should be good enough for the
    /// initial clock adjustment but it might not be the most accurate representation. After calling the
    /// closure this method will continue syncing with multiple servers and multiple passes.
    ///
    /// - parameter pool:       NTP pool that will be resolved into multiple NTP servers that will be used for
    ///                         the synchronization.
    /// - parameter samples:    The number of samples to be acquired from each server.
    /// - parameter first:      A closure that will be called after the first valid date is calculated.
    /// - parameter completion: A closure that will be called after _all_ the NTP calls are finished.
    func sync(
        from pool: String,
        samples: Int,
        first: ((Date, TimeInterval) -> Void)?,
        completion: ((Date?, TimeInterval?) -> Void)?
    )
}

extension KronosClockProtocol {
    /// Syncs the clock using NTP. Note that the full synchronization could take a few seconds. The given
    /// closure will be called with the first valid NTP response which accuracy should be good enough for the
    /// initial clock adjustment but it might not be the most accurate representation. After calling the
    /// closure this method will continue syncing with multiple servers and multiple passes. 4 samples per
    /// server will be acquired.
    ///
    /// - parameter pool:       NTP pool that will be resolved into multiple NTP servers that will be used for
    ///                         the synchronization.
    /// - parameter first:      A closure that will be called after the first valid date is calculated.
    /// - parameter completion: A closure that will be called after _all_ the NTP calls are finished.
    func sync(
        from pool: String,
        first: ((Date, TimeInterval) -> Void)?,
        completion: ((Date?, TimeInterval?) -> Void)?
    ) {
        sync(from: pool, samples: 4, first: first, completion: completion)
    }
}

/// High level implementation for clock synchronization using NTP. All returned dates use the most accurate
/// synchronization and it's not affected by clock changes. The NTP synchronization implementation has sub-
/// second accuracy but given that Darwin doesn't support microseconds on bootTime, dates don't have sub-
/// second accuracy.
///
/// Example usage:
///
/// ```swift
/// KronosClock.sync { date, offset in
///     print(date)
/// }
/// // (... later on ...)
/// print(KronosClock.now)
/// ```
internal final class KronosClock: KronosClockProtocol {
    private var stableTime: KronosTimeFreeze? {
        didSet {
            self.storage.stableTime = self.stableTime
        }
    }

    /// Determines where the most current stable time is stored. Use TimeStoragePolicy.appGroup to share
    /// between your app and an extension.
    private var storage = KronosTimeStorage(storagePolicy: .standard)

    /// The most accurate timestamp that we have so far (nil if no synchronization was done yet)
    var timestamp: TimeInterval? {
        return self.stableTime?.adjustedTimestamp
    }

    /// The most accurate date that we have so far (nil if no synchronization was done yet)
    var now: Date? {
        return self.annotatedNow?.date
    }

    /// Same as `now` except with analytic metadata about the time
    var annotatedNow: KronosAnnotatedTime? {
        guard let stableTime = self.stableTime else {
            return nil
        }

        return KronosAnnotatedTime(
            date: Date(timeIntervalSince1970: stableTime.adjustedTimestamp),
            timeSinceLastNtpSync: stableTime.timeSinceLastNtpSync
        )
    }

    /// Syncs the clock using NTP. Note that the full synchronization could take a few seconds. The given
    /// closure will be called with the first valid NTP response which accuracy should be good enough for the
    /// initial clock adjustment but it might not be the most accurate representation. After calling the
    /// closure this method will continue syncing with multiple servers and multiple passes.
    ///
    /// - parameter pool:       NTP pool that will be resolved into multiple NTP servers that will be used for
    ///                         the synchronization.
    /// - parameter samples:    The number of samples to be acquired from each server (default 4).
    /// - parameter first:      A closure that will be called after the first valid date is calculated.
    /// - parameter completion: A closure that will be called after _all_ the NTP calls are finished.
    func sync(
        from pool: String = "time.apple.com",
        samples: Int = 4,
        first: ((Date, TimeInterval) -> Void)? = nil,
        completion: ((Date?, TimeInterval?) -> Void)? = nil
    ) {
        self.loadFromDefaults()

        KronosNTPClient().query(pool: pool, numberOfSamples: samples) { [weak self] offset, done, total in
            guard let self = self else {
                return
            }

            if let offset = offset {
                self.stableTime = KronosTimeFreeze(offset: offset)

                if done == 1, let now = self.now {
                    first?(now, offset)
                }
            }

            if done == total {
                completion?(self.now, offset)
            }
        }
    }

    /// Resets all state of the monotonic clock. Note that you won't be able to access `now` until you `sync`
    /// again.
    func reset() {
        self.stableTime = nil
    }

    private func loadFromDefaults() {
        guard let previousStableTime = self.storage.stableTime else {
            self.stableTime = nil
            return
        }
        self.stableTime = previousStableTime
    }
}
