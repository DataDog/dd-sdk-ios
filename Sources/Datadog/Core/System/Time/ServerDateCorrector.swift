/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class ServerDateCorrector: DateCorrector {
    /// Server offset publisher.
    private let publisher: ValuePublisher<TimeInterval?> = ValuePublisher(initialValue: nil)

    init(serverDateProvider: ServerDateProvider) {
        serverDateProvider.synchronize(
            update: publisher.publishAsync,
            completion: { [weak self] offset in
                self?.publisher.publishAsync(offset)

                if let offset = offset {
                    let difference = (offset * 1_000).rounded() / 1_000
                    DD.logger.debug(
                        """
                        NTP time synchronization completed.
                        Server time will be used for signing events (\(difference)s difference with device time).
                        """
                    )
                } else {
                    DD.logger.error(
                        """
                        NTP time synchronization failed.
                        Device time will be used for signing events.
                        """
                    )
                }
            }
        )
    }

    var offset: TimeInterval {
        return publisher.currentValue ?? 0
    }
}
