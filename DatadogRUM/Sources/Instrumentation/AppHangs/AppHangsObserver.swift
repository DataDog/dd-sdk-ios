/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class AppHangsObserver: RUMCommandPublisher {
    enum Constants {
        /// The standardized `error.message` for RUM errors describing an app hang.
        static let appHangErrorMessage = "App Hang"

        /// The standardized `error.type` for RUM errors describing an app hang.
        static let appHangErrorType = "AppHang"

        /// The standardized `error.stack` when a backtrace couldn't be generated.
        static let appHangNoStackErrorMessage = "Stack trace was not generated because `DatadogCrashReporting` had not been enabled."
    }

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
        let command = RUMAddCurrentViewErrorCommand(
            time: appHang.date,
            message: Constants.appHangErrorMessage,
            type: Constants.appHangErrorType,
            stack: appHang.backtrace?.stack ?? Constants.appHangNoStackErrorMessage,
            source: .source,
            isCrash: false,
            threads: appHang.backtrace?.threads,
            binaryImages: appHang.backtrace?.binaryImages,
            isStackTraceTruncated: appHang.backtrace?.wasTruncated,
            attributes: [
                "hang_duration": appHang.duration
            ]
        )

        subscriber?.process(command: command)
    }
}

extension AppHangsObserver {
    /// Awaits the processing of pending app hang.
    ///
    /// Note: This method is synchronous and will block the caller thread, in worst case up for `appHangThreshold`.
    func flush() {
        let semaphore = DispatchSemaphore(value: 0)
        watchdogThread.onBeforeSleep = { semaphore.signal() }
        semaphore.wait()
    }
}
