/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Defines timer abstractions used by screen change monitoring.

#if os(iOS)
import Foundation
import Dispatch

internal protocol ScheduledTimer {
    func cancel()
}

internal protocol TimerScheduler: TimeSource {
    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> any ScheduledTimer
}

internal struct DispatchSourceTimerScheduler: TimerScheduler {
    private struct Constants {
        // The tolerance applied to dispatch timers for reducing power usage.
        static let timerTolerance: Double = 0.1
    }

    private class Timer: ScheduledTimer {
        private var base: DispatchSourceTimer?

        init(_ base: DispatchSourceTimer) {
            self.base = base
        }

        deinit {
            cancel()
        }

        func cancel() {
            base?.cancel()
            base = nil
        }
    }

    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    var now: TimeInterval {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
    }

    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> any ScheduledTimer {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let leeway = DispatchTimeInterval.milliseconds(Int(interval * Constants.timerTolerance * 1_000))

        timer.schedule(deadline: .now() + interval, leeway: leeway)
        timer.setEventHandler(handler: action)
        timer.resume()

        return Timer(timer)
    }
}

extension TimerScheduler where Self == DispatchSourceTimerScheduler {
    static var dispatchSource: Self {
        .init()
    }
}
#endif
