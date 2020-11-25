/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Adjusts device time to server time using the time difference calculated with NTP.
internal protocol DateCorrectionType {
    /// Corrects given device time to server time using the last known time difference between the two.
    func toServerDate(deviceDate: Date) -> Date
}

internal class DateCorrection: DateCorrectionType {
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
        // swiftlint:disable trailing_closure
        serverDateProvider.synchronize(
            with: DateCorrection.datadogNTPServers.randomElement()!, // swiftlint:disable:this force_unwrapping
            completion: { serverTime in
                let deviceTime = deviceDateProvider.currentDate()
                if let serverTime = serverTime {
                    let difference = (serverTime.timeIntervalSince(deviceTime) * 1_000).rounded() / 1_000
                    userLogger.info(
                        """
                        NTP time synchronization completed.
                        Server time will be used for signing events (current server time is \(serverTime); \(difference)s difference with device time).
                        """
                    )
                } else {
                    userLogger.warn(
                        """
                        NTP time synchronization failed.
                        Device time will be used for signing events (current device time is \(deviceTime)).
                        """
                    )
                }
            }
        )
        // swiftlint:enable trailing_closure
    }

    func toServerDate(deviceDate: Date) -> Date {
        if let serverTime = serverDateProvider.currentDate() {
            let deviceTime = deviceDateProvider.currentDate()
            let timeDifference = serverTime.timeIntervalSince(deviceTime)
            return deviceDate.addingTimeInterval(timeDifference)
        } else {
            return deviceDate
        }
    }
}
