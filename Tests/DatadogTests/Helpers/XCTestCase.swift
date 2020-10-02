/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest

extension XCTestCase {
    /// Calls given closures concurrently from multiple threads.
    /// Each closure is called only once.
    func callConcurrently(
        _ closure1: @escaping () -> Void,
        _ closure2: @escaping () -> Void,
        _ closure3: (() -> Void)? = nil,
        _ closure4: (() -> Void)? = nil,
        _ closure5: (() -> Void)? = nil,
        _ closure6: (() -> Void)? = nil
    ) {
        callConcurrently(
            closures: [closure1, closure2, closure3, closure4, closure5, closure6].compactMap { $0 },
            iterations: 1
        )
    }

    /// Calls given closures concurrently from multiple threads.
    /// Each closure will be called the number of times given by `iterations` count.
    func callConcurrently(closures: [() -> Void], iterations: Int) {
        var moreClosures: [() -> Void] = []
        (0..<iterations).forEach { _ in moreClosures.append(contentsOf: closures) }
        let randomizedClosures = moreClosures.shuffled()

        DispatchQueue.concurrentPerform(iterations: randomizedClosures.count) { iteration in
            randomizedClosures[iteration]()
        }
    }
}
