/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCrashReporting

class UInt64Tests: XCTestCase {
    func testSubtractIfNoOverflow() {
        let random1: UInt64 = .mockRandom()
        let random2: UInt64 = .mockRandom(otherThan: random1)

        let big = max(random1, random2)
        let small = min(random1, random2)

        XCTAssertEqual(big.subtractIfNoOverflow(small), big - small)
        XCTAssertNil(small.subtractIfNoOverflow(big), "It should cause the overflow and return `nil`")
    }

    func testAddIfNoOverflow() {
        let random: UInt64 = .mockRandom(otherThan: 0)

        let distanceToMax = UInt64.max - random
        let overflowAddition = distanceToMax + 1
        let safeAddition = distanceToMax - 1

        XCTAssertEqual(random.addIfNoOverflow(safeAddition), random + safeAddition)
        XCTAssertNil(random.addIfNoOverflow(overflowAddition), "It should cause the overflow and return `nil`")
    }
}

class StringTests: XCTestCase {
    func testAddPrefix() {
        let originalString: String = .mockRandom()

        let prefixLength: Int = .mockRandom(min: 1, max: 100)
        let targetLength = prefixLength + originalString.count

        let prefixCharacter: Character = "x"
        let expectedPrefix = String(repeating: prefixCharacter, count: prefixLength)

        let modifiedString = originalString.addPrefix(repeating: prefixCharacter, targetLength: targetLength)

        XCTAssertFalse(originalString.hasPrefix(expectedPrefix))
        XCTAssertTrue(modifiedString.hasPrefix(expectedPrefix))
    }

    func testAddSuffix() {
        let originalString: String = .mockRandom()

        let suffixLength: Int = .mockRandom(min: 1, max: 100)
        let targetLength = suffixLength + originalString.count

        let suffixCharacter: Character = "x"
        let expectedSuffix = String(repeating: suffixCharacter, count: suffixLength)

        let modifiedString = originalString.addSuffix(repeating: suffixCharacter, targetLength: targetLength)

        XCTAssertFalse(originalString.hasSuffix(expectedSuffix))
        XCTAssertTrue(modifiedString.hasSuffix(expectedSuffix))
    }
}
