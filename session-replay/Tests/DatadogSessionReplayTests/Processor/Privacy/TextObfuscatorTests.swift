/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class TestObfuscatorTests: XCTestCase {
    let obfuscator = TextObfuscator()

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
