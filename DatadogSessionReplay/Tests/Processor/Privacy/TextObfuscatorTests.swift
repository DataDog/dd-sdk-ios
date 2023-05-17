/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class SpacePreservingMaskObfuscatorTests: XCTestCase {
    let obfuscator = SpacePreservingMaskObfuscator()

    func testWhenMaskingEmptyText() {
        XCTAssertEqual(obfuscator.mask(text: ""), "")
    }

    func testWhenObfuscatingTextWithWhitespacesAndNewlines() {
        func test(separator: String) {
            // Given
            let text: String = (0..<5)
                .map { _ in String.mockRandom(among: .alphanumerics, length: 10) }
                .joined(separator: separator)

            // When
            let actual = obfuscator.mask(text: text)

            // Then
            let expectedText: String = text
                .map { ch in String(ch) == separator ? String(ch) : "x" }
                .joined()

            XCTAssertEqual(expectedText, actual)
        }

        test(separator: " ")
        test(separator: "\n")
        test(separator: "\r")
        test(separator: "\t")
    }

    func testWhenObfuscatingTextWithCustomUnicodeCodePoints() {
        XCTAssertEqual(obfuscator.mask(text: "◌̀"), "xx")
        XCTAssertEqual(obfuscator.mask(text: "🍕"), "x")
        XCTAssertEqual(obfuscator.mask(text: "🍕🇮🇹"), "xxx")
        XCTAssertEqual(obfuscator.mask(text: "🇮🇹"), "xx")
        XCTAssertEqual(obfuscator.mask(text: "foo ◌̀ bar"), "xxx xx xxx")
        XCTAssertEqual(obfuscator.mask(text: "foo 🍕 bar"), "xxx x xxx")
        XCTAssertEqual(obfuscator.mask(text: "foo 🇮🇹 bar"), "xxx xx xxx")
    }
}

class FixLengthMaskObfuscatorTests: XCTestCase {
    let obfuscator = FixLengthMaskObfuscator()

    func testWhenObfuscatingItAlwaysReplacesTextItWithConstantMask() {
        let expectedMask = "***"

        XCTAssertEqual(obfuscator.mask(text: .mockRandom(among: .alphanumericsAndWhitespace)), expectedMask)
        XCTAssertEqual(obfuscator.mask(text: .mockRandom(among: .allUnicodes)), expectedMask)
        XCTAssertEqual(obfuscator.mask(text: .mockRandom(among: .alphanumerics)), expectedMask)
    }
}

class NOPTextObfuscatorTests: XCTestCase {
    let obfuscator = NOPTextObfuscator()

    func testWhenObfuscatingItReturnsOriginalText() {
        let text: String = .mockRandom()
        XCTAssertEqual(obfuscator.mask(text: text), text)
    }
}
