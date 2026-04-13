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

internal protocol RepeatingTimer {
    func start(interval: TimeInterval, handler: @escaping () -> Void)
    func stop()
}

internal final class DispatchSourceRepeatingTimer: RepeatingTimer {
    private struct Constants {
        // The tolerance applied to dispatch timers for reducing power usage.
        static let timerTolerance: Double = 0.1
    }

    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    deinit {
        stop()
    }

    func start(interval: TimeInterval, handler: @escaping () -> Void) {
        stop()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        let leeway = DispatchTimeInterval.milliseconds(Int(interval * Constants.timerTolerance * 1_000))

        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: leeway)
        timer.setEventHandler(handler: handler)
        timer.resume()

        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

extension RepeatingTimer where Self == DispatchSourceRepeatingTimer {
    static var dispatchSource: Self { .init() }
}
#endif
