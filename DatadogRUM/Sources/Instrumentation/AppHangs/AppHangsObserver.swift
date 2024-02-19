/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class AppHangsObserver: RUMCommandPublisher {
    /// Watchdog thread that monitors the main queue for App Hangs.
    private let watchdogThread: AppHangsWatchdogThread
    /// Weak reference to RUM monitor for sending App Hang events.
    private(set) weak var subscriber: RUMCommandSubscriber?

    init(
        appHangThreshold: TimeInterval,
        observedQueue: DispatchQueue,
        backtraceReporter: BacktraceReporting,
        dateProvider: DateProvider,
        telemetry: Telemetry
    ) {
        watchdogThread = AppHangsWatchdogThread(
            appHangThreshold: appHangThreshold,
            queue: observedQueue,
            dateProvider: dateProvider,
            backtraceReporter: backtraceReporter,
            telemetry: telemetry
        )
        watchdogThread.onHangEnded = { [weak self] appHang in
            // called on watchdog thread
            self?.report(appHang: appHang)
        }
    }

    func start() {
        watchdogThread.start()
    }

    func stop() {
        watchdogThread.cancel()
    }

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    private func report(appHang: AppHang) {
        let addHangCommand = RUMAddCurrentViewErrorCommand(
            time: appHang.date,
            message: "App Hang",
            type: "AppHang",
            stack: nil, // TODO: RUM-2925 Add hang stack trace
            source: .source,
            attributes: [
                "hang_duration": appHang.duration
            ]
        )
        subscriber?.process(command: addHangCommand)
    }
}
