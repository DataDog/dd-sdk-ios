/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// MARK: - Overview
//
// Defines the time abstraction used by screen change monitoring and its live
// implementation. `LiveTimeProvider` reads now from CACurrentMediaTime (monotonic)
// and schedules using Dispatch timers to avoid clock-change skew.

#if os(iOS)
import QuartzCore

internal protocol TimeProviderTask {
    func cancel()
}

internal protocol TimeProvider {
    associatedtype Task: TimeProviderTask

    var now: TimeInterval { get }

    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> Task
}

internal struct LiveTimeProvider: TimeProvider {
    final class Task: TimeProviderTask {
        private var timer: DispatchSourceTimer?

        init(timer: DispatchSourceTimer) {
            self.timer = timer
        }

        func cancel() {
            timer?.cancel()
            timer = nil
        }

        deinit {
            cancel()
        }
    }

    var now: TimeInterval {
        CACurrentMediaTime()
    }

    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> Task {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler(handler: action)
        timer.resume()

        return Task(timer: timer)
    }
}

extension TimeProvider where Self == LiveTimeProvider {
    static func live(queue: DispatchQueue = .main) -> Self {
        .init(queue: queue)
    }
}
#endif
