/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

final class ReadWriteLockTests: XCTestCase {
    @ReadWriteLock
    var value: Int = 0

    func testRandomlyCallingValueConcurrentlyDoesNotCrash() {
        // swiftlint:disable opening_brace
        callConcurrently(
            closures: [
                { _ = self.value },
                { self.value = .mockRandom() },
                { self._value.mutate { $0 = .mockRandom() } }
            ],
            iterations: 1_000
        )
        // swiftlint:enable opening_brace
    }
}
