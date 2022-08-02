/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal class DatadogNTPDateProvider: ServerDateProvider {
    let kronos: KronosClockProtocol

    init(kronos: KronosClockProtocol = KronosClock()) {
        self.kronos = kronos
    }

    func synchronize(update: @escaping (TimeInterval) -> Void) {
        kronos.sync(
            from: DatadogNTPServers.randomElement()!, // swiftlint:disable:this force_unwrapping
            first: { _, offset in
                update(offset)
            },
            completion: { now, offset in
                // Kronos only notifies for the first and last samples.
                // In case, the last sample does not return an offset, we calculate the offset
                // from the returned `now` parameter. The `now` parameter in this callback
                // is `Clock.now` and it can be either offset computed from prior samples or persisted
                // in user defaults from previous app session.
                if let offset = offset ?? now?.timeIntervalSinceNow {
                    update(offset)

                    let difference = (offset * 1_000).rounded() / 1_000
                    DD.logger.debug(
                        """
                        NTP time synchronization completed.
                        Server time will be used for signing events (\(difference)s difference with device time).
                        """
                    )
                } else {
                    update(0)

                    DD.logger.error(
                        """
                        NTP time synchronization failed.
                        Device time will be used for signing events.
                        """
                    )
                }
            }
        )

        // `Kronos.sync` first loads the previous state from the `UserDefaults` if any.
        // We can invoke `Clock.now` to retrieve the stored offset.
        if let offset = kronos.now?.timeIntervalSinceNow {
            update(offset)
        }
    }
}
