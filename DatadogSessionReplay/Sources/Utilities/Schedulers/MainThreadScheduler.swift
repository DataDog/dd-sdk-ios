/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

/// Schedules operations and repeats them on the main thread.
///
/// It uses the main `RunLoop` as its time source, meaning that all operations are suspended
/// while the app is not in foreground.
internal class MainThreadScheduler: Scheduler {
    private struct Constants {
        /// The `tolerance` applied to `Timer` for reducing the impact on the power usage of the app.
        ///
        /// Ref.: https://developer.apple.com/documentation/foundation/timer
        /// > A general rule, set the tolerance to at least 10% of the interval, for a repeating timer.
        /// > Even a small amount of tolerance has significant positive impact on the power usage of the application.
        static let timerTolerance: Double = 0.1
    }

    /// The time interval between repeating operations.
    private let interval: TimeInterval
    /// The timer driving this scheduler.
    private var timer: Timer? = nil
    /// An array of scheduled operations.
    private var operations: [() -> Void] = []

    /// The queue that operations are executed on.
    let queue: Queue = MainAsyncQueue()

    /// Initializer.
    /// - Parameter interval: the interval between repeating operations
    init(interval: TimeInterval) {
        self.interval = interval
    }

    func schedule(operation: @escaping () -> Void) {
        queue.run {
            self.operations.append(operation)
        }
    }

    func start() {
        queue.run {
            guard self.timer == nil else {
                return // is running
            }

            let newTimer = Timer(timeInterval: self.interval, repeats: true) { [weak self] _ in
                self?.operations.forEach { operation in operation() }
            }
            newTimer.tolerance = self.interval * Constants.timerTolerance
            self.timer = newTimer

            RunLoop.main.add(newTimer, forMode: .common)
        }
    }

    func stop() {
        queue.run {
            guard self.timer != nil else {
                return // is not running
            }

            // Invalidating the `Timer` also removes its reference from the `RunLoop`:
            self.timer?.invalidate()
            self.timer = nil
        }
    }
}
#endif
