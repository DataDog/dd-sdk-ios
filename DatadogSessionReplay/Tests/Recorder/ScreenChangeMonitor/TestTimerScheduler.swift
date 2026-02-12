/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation

@testable import DatadogSessionReplay

final class TestTimerScheduler: TimerScheduler {
    private class Timer: ScheduledTimer {
        var isCancelled = false

        func cancel() {
            isCancelled = true
        }
    }

    private struct ScheduledItem {
        let id: UUID
        let dueTime: TimeInterval
        let timer: Timer
        let action: () -> Void
    }

    private(set) var now: TimeInterval
    private var queue: [ScheduledItem] = []

    init(now: TimeInterval = 0) {
        self.now = now
    }

    func schedule(after interval: TimeInterval, _ action: @escaping () -> Void) -> any ScheduledTimer {
        precondition(interval >= 0)

        let timer = Timer()
        let item = ScheduledItem(
            id: UUID(),
            dueTime: now + interval,
            timer: timer,
            action: action
        )
        queue.append(item)
        queue.sort { $0.dueTime < $1.dueTime }

        return timer
    }

    func advance(by delta: TimeInterval) {
        advance(to: now + delta)
    }

    func advance(to newTime: TimeInterval) {
        precondition(newTime >= now, "Time cannot move backwards")

        now = newTime
        runDueTasks()
    }

    private func runDueTasks() {
        while let first = queue.first, first.dueTime <= now {
            queue.removeFirst()
            guard !first.timer.isCancelled else { continue }
            first.action()
        }
    }
}
#endif
