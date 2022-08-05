/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import DatadogSessionReplay

/// Convenient `Scheduler` for tests.
/// It executes operations synchronously on caller thread right after it's started.
/// Allows for configuring the number of times each operation should be repeated.
internal class TestScheduler: Scheduler {
    /// The number of times to repeat each scheduled operation after starting this scheduler.
    private let numberOfRepeats: Int
    /// Scheduled operations.
    private var operations: [() -> Void] = []

    init(numberOfRepeats: Int = 1) {
        self.numberOfRepeats = numberOfRepeats
    }

    func schedule(operation: @escaping () -> Void) {
        operations.append(operation)
    }

    func start() {
        (0..<numberOfRepeats).forEach { _ in
            operations.forEach { operation in operation() }
        }
    }

    func stop() {
        /* no-op */
    }
}
