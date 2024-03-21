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

        /// The standardized `error.stack` when backtrace generation was not available.
        static let appHangStackNotAvailableErrorMessage = "Stack trace was not generated because `DatadogCrashReporting` had not been enabled."

        /// The standardized `error.stack` when backtrace generation failed due to an internal error.
        static let appHangStackGenerationFailedErrorMessage = "Failed to generate stack trace. This is a known issue and we work on it."
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
        watchdogThread.onHangEnded = { [weak self] appHang, duration in
            // called on watchdog thread
            self?.report(nonFatal: appHang, duration: duration)
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

    private func report(nonFatal appHang: AppHang, duration: TimeInterval) {
        let command = RUMAddCurrentViewAppHangCommand(
            time: appHang.startDate,
            attributes: [:],
            message: Constants.appHangErrorMessage,
            type: Constants.appHangErrorType,
            stack: appHang.backtraceResult.stack,
            threads: appHang.backtraceResult.threads,
            binaryImages: appHang.backtraceResult.binaryImages,
            isStackTraceTruncated: appHang.backtraceResult.wasTruncated,
            hangDuration: duration
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

internal extension AppHang.BacktraceGenerationResult {
    var stack: String {
        switch self {
        case .succeeded(let backtrace): return backtrace.stack
        case .failed: return AppHangsObserver.Constants.appHangStackGenerationFailedErrorMessage
        case .notAvailable: return AppHangsObserver.Constants.appHangStackNotAvailableErrorMessage
        }
    }

    var threads: [DDThread]? {
        switch self {
        case .succeeded(let backtrace): return backtrace.threads
        case .failed, .notAvailable: return nil
        }
    }

    var binaryImages: [BinaryImage]? {
        switch self {
        case .succeeded(let backtrace): return backtrace.binaryImages
        case .failed, .notAvailable: return nil
        }
    }

    var wasTruncated: Bool? {
        switch self {
        case .succeeded(let backtrace): return backtrace.wasTruncated
        case .failed, .notAvailable: return nil
        }
    }
}
