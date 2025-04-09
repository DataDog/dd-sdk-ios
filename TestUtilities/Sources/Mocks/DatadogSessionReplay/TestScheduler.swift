/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
@testable import DatadogSessionReplay

/// Convenient `Scheduler` for tests.
/// It executes operations on a given queue right after started.
/// Allows for configuring the number of times each operation should be repeated.
internal class TestScheduler: Scheduler {
    /// The number of times to repeat each scheduled operation after starting this scheduler.
    private let numberOfRepeats: Int
    /// Scheduled operations.
    private var operations: [() -> Void] = []

    /// Queue to execute operations on.
    let queue: Queue

    private var _isRunning = false
    private let isRunningQueue = DispatchQueue(label: "testscheduler.isrunning")
    var isRunning: Bool {
        get { return isRunningQueue.sync { _isRunning } }
        set { isRunningQueue.sync { _isRunning = newValue } }
    }

    init(
        queue: Queue = NoQueue(),
        numberOfRepeats: Int = 1
    ) {
        self.queue = queue
        self.numberOfRepeats = numberOfRepeats
    }

    func schedule(operation: @escaping () -> Void) {
        queue.run {
            self.operations.append(operation)
        }
    }

    func start() {
        isRunning = true
        queue.run {
            (0..<self.numberOfRepeats).forEach { _ in
                self.operations.forEach { operation in operation() }
            }
        }
    }

    func stop() {
        isRunning = false
    }
}
#endif
