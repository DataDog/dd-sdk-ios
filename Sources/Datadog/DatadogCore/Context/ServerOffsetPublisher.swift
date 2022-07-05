/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal let DatadogNTPServers = [
    "0.datadog.pool.ntp.org",
    "1.datadog.pool.ntp.org",
    "2.datadog.pool.ntp.org",
    "3.datadog.pool.ntp.org"
]

internal final class ServerOffsetPublisher: ContextValuePublisher {
    let initialValue: TimeInterval = .zero

    private var kronos: KronosClockProtocol?

    init(kronos: KronosClockProtocol = KronosClock()) {
        self.kronos = kronos
    }

    func publish(to receiver: @escaping (TimeInterval) -> Void) {
        kronos?.sync(
            from: DatadogNTPServers.randomElement()!, // swiftlint:disable:this force_unwrapping
            first: { _, offset in
                receiver(offset)
            },
            completion: { now, offset in
                // Kronos only notifies for the first and last samples.
                // In case, the last sample does not return an offset, we calculate the offset
                // from the returned `now` parameter. The `now` parameter in this callback
                // is `Clock.now` and it can be either offset computed from prior samples or persisted
                // in user defaults from previous app session.
                if let offset = offset ?? now?.timeIntervalSinceNow {
                    receiver(offset)

                    let difference = (offset * 1_000).rounded() / 1_000
                    DD.logger.debug(
                        """
                        NTP time synchronization completed.
                        Server time will be used for signing events (\(difference)s difference with device time).
                        """
                    )
                } else {
                    receiver(0)

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

    func cancel() {
        kronos = nil
    }
}
