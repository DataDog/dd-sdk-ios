/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Calculates the date correction for adjusting device time to server time.
internal protocol DateCorrectorType {
    /// Returns recent date correction for adjusting device time to server time.
    var currentCorrection: DateCorrection { get }
}

/// Date correction for adjusting device time to server time.
internal struct DateCorrection {
    /// The difference between server time and device time known at the time of creating this `DateCorrection`.
    let serverTimeOffset: TimeInterval

    /// Applies this correction to given `deviceDate` to represent it in server time.
    func applying(to deviceDate: Date) -> Date {
        return deviceDate.addingTimeInterval(serverTimeOffset)
    }
}

internal class DateCorrector: DateCorrectorType {
    static let datadogNTPServers = [
        "0.datadog.pool.ntp.org",
        "1.datadog.pool.ntp.org",
        "2.datadog.pool.ntp.org",
        "3.datadog.pool.ntp.org"
    ]
    private let deviceDateProvider: DateProvider
    private let serverDateProvider: ServerDateProvider

    init(deviceDateProvider: DateProvider, serverDateProvider: ServerDateProvider) {
        self.deviceDateProvider = deviceDateProvider
        self.serverDateProvider = serverDateProvider
        serverDateProvider.synchronize(
            with: DateCorrector.datadogNTPServers.randomElement()!, // swiftlint:disable:this force_unwrapping
            completion: { offset in
                if let offset = offset {
                    let difference = (offset * 1_000).rounded() / 1_000
                    userLogger.info(
                        """
                        NTP time synchronization completed.
                        Server time will be used for signing events (\(difference)s difference with device time).
                        """
                    )
                } else {
                    let deviceTime = deviceDateProvider.currentDate()
                    userLogger.warn(
                        """
                        NTP time synchronization failed.
                        Device time will be used for signing events (current device time is \(deviceTime)).
                        """
                    )
                }
            }
        )
    }

    var currentCorrection: DateCorrection {
        guard let offset = serverDateProvider.offset else {
            return DateCorrection(serverTimeOffset: 0)
        }

        return DateCorrection(serverTimeOffset: offset)
    }
}
