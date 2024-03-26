/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal final class AppHangsMonitor {
    enum Constants {
        /// The standardized `error.message` for RUM errors describing an app hang.
        static let appHangErrorMessage = "App Hang"
        /// The standardized `error.type` for RUM errors describing an app hang.
        static let appHangErrorType = "AppHang"
        /// The standardized `error.stack` when backtrace generation was not available.
        static let appHangStackNotAvailableErrorMessage = "Stack trace was not generated because `DatadogCrashReporting` had not been enabled."
        /// The standardized `error.stack` when backtrace generation failed due to an internal error.
        static let appHangStackGenerationFailedErrorMessage = "Failed to generate stack trace. This is a known issue and we work on it."
    }

    /// Watchdog thread that monitors the main queue for App Hangs.
    private let watchdogThread: AppHangsObservingThread
    /// Handles non-fatal App Hangs.
    internal let nonFatalHangsHandler: NonFatalAppHangsHandler
    /// Handles non-fatal App Hangs.
    internal let fatalHangsHandler: FatalAppHangsHandler

    convenience init(
        featureScope: FeatureScope,
        appHangThreshold: TimeInterval,
        observedQueue: DispatchQueue,
        backtraceReporter: BacktraceReporting,
        fatalErrorContext: FatalErrorContextNotifier,
        dateProvider: DateProvider,
        processID: UUID
    ) {
        self.init(
            featureScope: featureScope,
            watchdogThread: AppHangsWatchdogThread(
                appHangThreshold: appHangThreshold,
                queue: observedQueue,
                dateProvider: dateProvider,
                backtraceReporter: backtraceReporter,
                telemetry: featureScope.telemetry
            ),
            fatalErrorContext: fatalErrorContext,
            processID: processID
        )
    }

    init(
        featureScope: FeatureScope,
        watchdogThread: AppHangsObservingThread,
        fatalErrorContext: FatalErrorContextNotifier,
        processID: UUID
    ) {
        self.watchdogThread = watchdogThread
        self.nonFatalHangsHandler = NonFatalAppHangsHandler()
        self.fatalHangsHandler = FatalAppHangsHandler(
            featureScope: featureScope,
            fatalErrorContext: fatalErrorContext,
            processID: processID
        )
    }

    func start() {
        fatalHangsHandler.reportFatalAppHangIfFound()
        watchdogThread.onHangStarted = { [weak self] hang in
            self?.fatalHangsHandler.startHang(hang: hang)
        }
        watchdogThread.onHangCancelled = { [weak self] _ in
            self?.fatalHangsHandler.cancelHang()
        }
        watchdogThread.onHangEnded = { [weak self] hang, duration in
            self?.fatalHangsHandler.endHang()
            self?.nonFatalHangsHandler.endHang(appHang: hang, duration: duration)
        }
        watchdogThread.start()
    }

    func stop() {
        watchdogThread.stop()
        watchdogThread.onHangStarted = nil
        watchdogThread.onHangCancelled = nil
        watchdogThread.onHangEnded = nil
    }
}

extension AppHangsMonitor {
    /// Awaits the processing of pending app hang.
    ///
    /// Note: This method is synchronous and will block the caller thread, in worst case up for `appHangThreshold`.
    func flush() {
        let semaphore = DispatchSemaphore(value: 0)
        watchdogThread.onBeforeSleep = { semaphore.signal() }
        semaphore.wait()
    }
}
