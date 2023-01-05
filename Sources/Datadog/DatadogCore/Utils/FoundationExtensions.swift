/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

extension DispatchQueue {
    /// Flushes the queue by dispatching a chain of asynchronous operations (one after
    /// another) and awaiting completion of the last one.
    ///
    /// - Parameter numberOfTimes: number of `async {}` operations to chain
    func flush(numberOfTimes: Int) {
        let semaphore = DispatchSemaphore(value: 0)

        func recursiveFlush(countDown: Int) {
            if countDown > 0 {
                self.async { recursiveFlush(countDown: countDown - 1) }
            } else {
                semaphore.signal()
            }
        }

        recursiveFlush(countDown: numberOfTimes)
        _ = semaphore.wait(timeout: .distantFuture)
    }
}
