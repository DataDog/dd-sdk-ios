/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

class ColorsTests: XCTestCase {
    func testWhenConvertingKnownOpaqueColorsToHexString() {
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1).cgColor
        XCTAssertEqual(hexString(from: red), "#FF0000FF")

        let green = UIColor(red: 0, green: 1, blue: 0, alpha: 1).cgColor
        XCTAssertEqual(hexString(from: green), "#00FF00FF")

        let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1).cgColor
        XCTAssertEqual(hexString(from: blue), "#0000FFFF")

        let black = UIColor(red: 0, green: 0, blue: 0, alpha: 1).cgColor
        XCTAssertEqual(hexString(from: black), "#000000FF")

        let white = UIColor(red: 1, green: 1, blue: 1, alpha: 1).cgColor
        XCTAssertEqual(hexString(from: white), "#FFFFFFFF")
    }

    func testWhenConvertingKnownSemiTransparentColorsToHexString() {
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 0.5).cgColor
        XCTAssertEqual(hexString(from: red), "#FF000080")

        let green = UIColor(red: 0, green: 1, blue: 0, alpha: 0.5).cgColor
        XCTAssertEqual(hexString(from: green), "#00FF0080")

        let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 0.5).cgColor
        XCTAssertEqual(hexString(from: blue), "#0000FF80")

        let black = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5).cgColor
        XCTAssertEqual(hexString(from: black), "#00000080")

        let white = UIColor(red: 1, green: 1, blue: 1, alpha: 0.5).cgColor
        XCTAssertEqual(hexString(from: white), "#FFFFFF80")
    }

    func testWhenConvertingAnyColorToHexString() throws {
        /// Returns `CGColor` constructed from provided `#RRGGBBAA` string.
        func cgColor(from rrggbbaaHex: String) -> CGColor {
            let hex8 = UInt64(rrggbbaaHex.dropFirst(), radix: 16)!
            return UIColor(
                red: CGFloat((hex8 & 0xFF000000) >> 24) / CGFloat(255),
                green: CGFloat((hex8 & 0x00FF0000) >> 16) / CGFloat(255),
                blue: CGFloat((hex8 & 0x0000FF00) >> 8) / CGFloat(255),
                alpha: CGFloat(hex8 & 0x000000FF) / CGFloat(255)
            ).cgColor
        }

        /// Returns random hexadecimal character (0-F).
        func randomHexCharacter() -> String {
            return String(Int.mockRandom(min: 0, max: 15), radix: 16, uppercase: true)
        }

        try (0..<100).forEach { _ in
            // Given
            let expectedHex = "#" + (0..<8).map({ _ in randomHexCharacter() }).joined(separator: "")
            let actualColor = cgColor(from: expectedHex)

            // When
            let actualHex = try XCTUnwrap(hexString(from: actualColor))

            // Then
            XCTAssertEqual(expectedHex, actualHex)
        }
    }
}
