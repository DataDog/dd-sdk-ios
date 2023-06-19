/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class LongTaskObserver: RUMCommandPublisher {
    private let longTaskDurationThreshold: TimeInterval
    private let dateProvider: DateProvider

    private(set) var observer_begin: CFRunLoopObserver?
    private(set) var observer_end: CFRunLoopObserver?
    private var lastActivity: (kind: CFRunLoopActivity, date: Date)?

    weak var subscriber: RUMCommandSubscriber?

    func publish(to subscriber: RUMCommandSubscriber) {
        self.subscriber = subscriber
    }

    init(threshold: TimeInterval, dateProvider: DateProvider) {
        self.longTaskDurationThreshold = threshold
        self.dateProvider = dateProvider

        let activites_begin: [CFRunLoopActivity] = [
            .entry,
            .afterWaiting,
            .beforeSources,
            .beforeTimers
        ]
        observer_begin = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity(activites_begin).rawValue,
            true,
            CFIndex.min
        ) { [weak self] block_obs, block_act in
            guard let strongSelf = self else {
                return
            }
            let now = strongSelf.dateProvider.now
            strongSelf.processActivity(block_act, at: now)
            strongSelf.lastActivity = (kind: block_act, date: now)
        }

        let activites_end: [CFRunLoopActivity] = [.beforeWaiting, .exit]
        observer_end = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault,
            CFRunLoopActivity(activites_end).rawValue,
            true,
            CFIndex.max
        ) { [weak self] block_obs, block_act in
            guard let strongSelf = self else {
                return
            }
            strongSelf.processActivity(block_act, at: strongSelf.dateProvider.now)
            strongSelf.lastActivity = nil
        }
    }

    func start() {
        CFRunLoopAddObserver(RunLoop.main.getCFRunLoop(), observer_begin, .commonModes)
        CFRunLoopAddObserver(RunLoop.main.getCFRunLoop(), observer_end, .commonModes)
    }

    func stop() {
        CFRunLoopRemoveObserver(RunLoop.main.getCFRunLoop(), observer_begin, .commonModes)
        CFRunLoopRemoveObserver(RunLoop.main.getCFRunLoop(), observer_end, .commonModes)
    }

    private func processActivity(_ activity: CFRunLoopActivity, at date: Date) {
        if let last = self.lastActivity,
           date.timeIntervalSince(last.date) > self.longTaskDurationThreshold {
            let duration = date.timeIntervalSince(last.date)
            let longTaskCommand = RUMAddLongTaskCommand(
                time: date,
                attributes: [:],
                duration: duration
            )
            subscriber?.process(command: longTaskCommand)
        }
    }
}
