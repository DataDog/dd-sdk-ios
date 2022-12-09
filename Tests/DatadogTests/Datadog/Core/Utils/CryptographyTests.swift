/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class CryptographyTests: XCTestCase {
    func testItComputesSHA256ForArbitraryString() {
        (0..<20).forEach { _ in
            // Given
            let string: String = .mockRandom(among: .allUnicodes, length: .mockRandom(min: 1, max: 500))

            // When
            let sha = sha256(string)

            // Then
            XCTAssertEqual(sha.count, 64, "It must use 64 characters")
            XCTAssertFalse(sha.contains(where: { !$0.isASCII }), "It must contain only ASCII characters")
        }
    }

    func testWhenComputingSHA256_itGivesStableResults() {
        XCTAssertEqual(sha256(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(sha256("foo"), "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae")
        XCTAssertEqual(sha256("Bar Bizz"), "ad81f738a40902ef4bb3e4d5f5b83d3e2b3b7edfcd1669ddd4004d4815d03a75")
        XCTAssertEqual(sha256(".//,"), "822236197264817e14fdd2939d9dc68c7d0151a6265798dd29511315cb428c66")
    }
}
