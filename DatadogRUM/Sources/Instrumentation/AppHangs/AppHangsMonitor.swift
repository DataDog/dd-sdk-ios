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
    private var watchdogThread: AppHangsObservingThread
    /// Handles non-fatal App Hangs.
    internal let nonFatalHangsHandler: NonFatalAppHangsHandler
    /// Handles non-fatal App Hangs.
    internal let fatalHangsHandler: FatalAppHangsHandler

    convenience init(
        featureScope: FeatureScope,
        appHangThreshold: TimeInterval,
        observedQueue: DispatchQueue,
        backtraceReporter: BacktraceReporting,
        fatalErrorContext: FatalErrorContextNotifying,
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
            processID: processID,
            dateProvider: dateProvider
        )
    }

    init(
        featureScope: FeatureScope,
        watchdogThread: AppHangsObservingThread,
        fatalErrorContext: FatalErrorContextNotifying,
        processID: UUID,
        dateProvider: DateProvider
    ) {
        self.watchdogThread = watchdogThread
        self.nonFatalHangsHandler = NonFatalAppHangsHandler()
        self.fatalHangsHandler = FatalAppHangsHandler(
            featureScope: featureScope,
            fatalErrorContext: fatalErrorContext,
            processID: processID,
            dateProvider: dateProvider
        )
    }

    func start() {
        fatalHangsHandler.reportFatalAppHangIfFound()
        watchdogThread.start(with: self)
    }

    func stop() {
        watchdogThread.stop()
    }
}

extension AppHangsMonitor: AppHangsObservingThreadDelegate {
    func hangStarted(_ hang: AppHang) {
        fatalHangsHandler.startHang(hang: hang)
    }

    func hangCancelled(_ hang: AppHang) {
        fatalHangsHandler.cancelHang()
    }

    func hangEnded(_ hang: AppHang, duration: TimeInterval) {
        fatalHangsHandler.endHang()
        nonFatalHangsHandler.endHang(appHang: hang, duration: duration)
    }
}

extension AppHangsMonitor {
    /// Awaits the processing of pending app hang.
    ///
    /// Note: This method is synchronous and will block the caller thread, in worst case up to `appHangThreshold`.
    func flush() { watchdogThread.flush() }
}
