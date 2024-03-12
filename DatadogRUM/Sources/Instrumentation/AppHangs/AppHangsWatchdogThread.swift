/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct AppHang {
    /// The date of hang end.
    let date: Date
    /// The duration of the hang.
    let duration: TimeInterval
    /// The snapshot of all running threads during the hang.
    /// Might be unavailable if `BacktraceReportingFeature` is not available in core.
    let backtrace: BacktraceReport?
}

internal final class AppHangsWatchdogThread: Thread {
    enum Constants {
        /// The "idle" interval for sleeping the watchdog thread before scheduling the next task on the main queue, represented as a percentage of the `appHangThreshold`.
        ///
        /// Introducing even a small sleep significantly reduces CPU consumption by the watchdog thread (nearly 0%). No sleep would result in close to 100% CPU usage.
        ///
        /// `tolerance` defines the margin of error in hang monitoring. The "measured hang duration" may differ from `0` to `tolerance` % when compared to the "actual hang duration".
        /// This means some actual hangs very close to `appHangThreshold` might be considered false negatives and not reported.
        ///
        /// **Example:**
        /// If `appHangThreshold` is 2 seconds and tolerance is 2.5%, the watchdog thread will idle for 50 milliseconds before taking each sample of the main thread.
        /// Because the sleep might start right at the moment of hang beginning on the main thread, the watchdog thread will miss the first 50 milliseconds of hang duration.
        /// If the actual hang lasts exactly 2 seconds, the watchdog will measure it as 1950 milliseconds. As a result, the SDK will not report it as it falls under `appHangThreshold`.
        static let tolerance: Double = 0.025 // 2.5%
    }

    /// The minimal duration of the main thread hang to consider it an App Hang.
    private let appHangThreshold: TimeInterval
    /// The "idle" interval for watchdog thread operations. Reduces the pressure on CPU.
    private let idleInterval: TimeInterval
    /// Semaphore used to block this thread until main thread responds.
    private let mainThreadTask = DispatchSemaphore(value: 0)
    /// The queue to observe by this thread (main queue).
    private let mainQueue: DispatchQueue
    /// SDK date provider.
    private let dateProvider: DateProvider
    /// Backtrace reporter for hang's stack trace generation.
    private let backtraceReporter: BacktraceReporting
    /// An identifier of the main thread required for backtrace generation.
    /// Because backtrace is generated from the watchdog thread, we must identify the main thread to be promoted in `BacktraceReport`. This value is
    /// obtained at runtime, only once and it is cached for later use.
    @ReadWriteLock
    private var mainThreadID: ThreadID? = nil
    /// Telemetry interface.
    private let telemetry: Telemetry
    /// Closure to be notified when App Hang ends. It will be executed on the watchdog thread.
    @ReadWriteLock
    internal var onHangEnded: ((AppHang) -> Void)?
    /// A block called after this thread finished its pass and will become idle.
    @ReadWriteLock
    internal var onBeforeSleep: (() -> Void)?

    /// Creates an instance of an App Hang watchdog thread.
    ///
    /// This thread is not started by default and requires manual invocation of `.start()`.
    ///
    /// - Parameters:
    ///   - appHangThreshold: Minimum duration of the `queue` hang to consider it an App Hang.
    ///   - queue: The queue to observe for hangs. (main queue)
    ///   - dateProvider: Date provider.
    ///   - backtraceReporter: Backtrace reporter for hang's stack trace generation.
    ///   - telemetry: The handler to report issues through RUM Telemetry.
    init(
        appHangThreshold: TimeInterval,
        queue: DispatchQueue,
        dateProvider: DateProvider,
        backtraceReporter: BacktraceReporting,
        telemetry: Telemetry
    ) {
        self.appHangThreshold = appHangThreshold
        self.idleInterval = appHangThreshold * Constants.tolerance
        self.mainQueue = queue
        self.dateProvider = dateProvider
        self.backtraceReporter = backtraceReporter
        self.telemetry = telemetry

        super.init()
        self.name = "com.datadoghq.app-hang-watchdog"

        if Thread.isMainThread {
            // When initialization happens on the main thread, we can get its `ThreadID` right away, so startup hangs are covered
            self.mainThreadID = Thread.currentThreadID
        } else {
            // Otherwise, schedule async task to capture the main `ThreadID`. This task will execute before any other `mainThreadTask`
            // scheduled by watchdog thread (in `main()`), making sure the thread ID is available as soon as possible.
            self.mainQueue.async { [weak self] in
                self?.mainThreadID = Thread.currentThreadID
            }
        }
    }

    override func main() {
        let mainThreadTask = self.mainThreadTask

        while !isCancelled {
            defer {
                // Notify that thread finished its next pass and will be put to IDLE
                onBeforeSleep?()
                // Sleep (become idle) to reduce the CPU consumption by watchdog thread:
                Thread.sleep(forTimeInterval: idleInterval)
            }

            let waitStart: DispatchTime = .now()

            // Schedule task on the main thread to measure how fast it responds
            mainQueue.async {
                mainThreadTask.signal()
            }

            // Await task completion
            let result = mainThreadTask.wait(timeout: waitStart + appHangThreshold)

            if result == .success {
                // This is predominant case of "no hang" situation. The main thread executed the task way below hang threshold.
                continue
            } // Otherwise, `result == .timeOut`, meaning that the main thread task is delayed to more than hang threshold.

            // We expect to be here roughtly `~appHangThreshold` after `wait()`. If this code is executed well after (50% margin),
            // assume that the thread was suspended and app just woke up. In such case, ignore the hang as likely false-positive.
            if interval(from: waitStart, to: .now()) > appHangThreshold * 1.5 {
                DD.logger.debug("Ignoring likely false-positive App Hang")
                continue // ignore likely false-positive
            }

            // Capture the stack trace of all running threads with promoting the main thread stack.
            guard let mainThreadID = mainThreadID else {
                telemetry.error("Failed to determine main thread ID for backtrace generation")
                continue // unexpected
            }
            let backtrace = backtraceReporter.generateBacktrace(threadID: mainThreadID)

            // Previous wait timed out, so wait again for the task completion, this time infinitely until the hang ends.
            mainThreadTask.wait()

            // The hang has finished.
            let hangDuration = interval(from: waitStart, to: .now())

            if hangDuration > 30 { // sanity-check
                // If the hang duration is irrealistically long (way more than assumed iOS watchdog termination limit: ~10s), send telemetry.
                // This could be another false-positive caused by thread suspension between the two `wait()` calls.
                telemetry.debug("Detected an App Hang with an unusually long duration", attributes: ["hang_duration": hangDuration])
                continue
            }

            let appHang = AppHang(
                date: dateProvider.now,
                duration: hangDuration,
                backtrace: backtrace
            )
            onHangEnded?(appHang)
        }
    }

    private func interval(from t1: DispatchTime, to t2: DispatchTime) -> TimeInterval {
        TimeInterval(t2.uptimeNanoseconds - t1.uptimeNanoseconds) / 1_000_000_000
    }
}
