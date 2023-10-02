/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import XCTest

extension XCTestCase {
    /// Calls given closures concurrently from multiple threads.
    /// Each closure is called only once.
    public func callConcurrently(
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
    public func callConcurrently(closures: [() -> Void], iterations: Int = 1) {
        var moreClosures: [() -> Void] = []
        (0..<iterations).forEach { _ in moreClosures.append(contentsOf: closures) }
        let randomizedClosures = moreClosures.shuffled()

        DispatchQueue.concurrentPerform(iterations: randomizedClosures.count) { iteration in
            randomizedClosures[iteration]()
        }
    }

    /// Waits until given `condition` returns `true` and then fulfills the `expectation`.
    /// It executes `condition()` block on the main thread, in every run loop.
    public func wait(until condition: @escaping () -> Bool, andThenFulfill expectation: XCTestExpectation) {
        if condition() {
            expectation.fulfill()
        } else {
            OperationQueue.main.addOperation { [weak self] in
                self?.wait(until: condition, andThenFulfill: expectation)
            }
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    public func dd_fulfillment(
        for expectations: [XCTestExpectation],
        timeout seconds: TimeInterval = .infinity,
        enforceOrder enforceOrderOfFulfillment: Bool = false) async {
#if compiler(>=5.8)
            await fulfillment(of: expectations, timeout: seconds, enforceOrder: enforceOrderOfFulfillment)
#else
        wait(
            for: expectations,
            timeout: seconds,
            enforceOrder: enforceOrderOfFulfillment
        )
#endif
    }
}
