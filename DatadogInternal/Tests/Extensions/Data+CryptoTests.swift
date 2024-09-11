/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

final class DataCryptoTests: XCTestCase {
    func testSha1() throws {
        let str1 = "The quick brown fox jumps over the lazy dog"
        let data1 = str1.data(using: .utf8)!
        let sha1 = data1.sha1()
        XCTAssertEqual(sha1, "2fd4e1c67a2d28fced849ee1bb76e7391b93eb12")

        let str2 = "The quick brown fox jumps over the lazy cog"
        let data2 = str2.data(using: .utf8)!
        let sha2 = data2.sha1()
        XCTAssertEqual(sha2, "de9f2c7fd25e1b3afad3e85a0bd17d9b100db4b3")
    }

    func testSha1_emptyString() throws {
        let str = ""
        let data = str.data(using: .utf8)!
        let sha = data.sha1()
        XCTAssertEqual(sha, "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    }
}
