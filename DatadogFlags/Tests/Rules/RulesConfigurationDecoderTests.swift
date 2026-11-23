/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogFlags

final class RulesConfigurationDecoderTests: XCTestCase {
    /// The rules response from the browser SDK fixture `rules-v1-wire.json`, so both SDKs decode the same bytes.
    private let browserFixture = Data(
        base64Encoded: "CgQIABAAEgRwcm9kGm0KCXRlc3QtZmxhZxJgCAAQBBoECAAoASIsCgphbGxvY2F0aW9uEAAaDBIKCgRzYWx0EAEYZCIMCgQIABBkEAAYByABKAEiJgoIZmFsbGJhY2saDBIKCgRzYWx0EAEYZCIMCgQIABBkEAAYByACIgYSBAoCCAMiAgoAKgJvbioDb2ZmKgJVUyoHY291bnRyeTIEXlVTJDoJCgExCgEyCgEzSgYqBAgAEAJQAA=="
    )!

    func testDecodesBrowserFixture() throws {
        let configuration = try RulesConfigurationDecoder.decode(browserFixture)

        XCTAssertEqual(configuration.environmentName, "prod")
        XCTAssertEqual(configuration.strings, ["on", "off", "US", "country"])
        XCTAssertEqual(configuration.regexes, ["^US$"])

        let flag = try XCTUnwrap(configuration.flags["test-flag"])
        XCTAssertEqual(flag.variationType, .boolean)
        XCTAssertEqual(flag.allocations.map(\.key), ["allocation", "fallback"])

        let allocation = flag.allocations[0]
        XCTAssertTrue(allocation.logExposureEvent)
        XCTAssertEqual(allocation.splits.first?.serialID, 7)
        XCTAssertEqual(allocation.splits.first?.reason, .targetingMatch)
        XCTAssertEqual(flag.allocations[1].splits.first?.reason, .split)
    }

    func testDecodesDataWithUnknownFields() throws {
        // Field 1000 with varint value 1: a field this SDK version does not know.
        let unknownField = Data([0xC0, 0x3E, 0x01])

        let configuration = try RulesConfigurationDecoder.decode(browserFixture + unknownField)

        XCTAssertEqual(configuration.flags, try RulesConfigurationDecoder.decode(browserFixture).flags)
    }

    func testDecodesEmptyDataAsEmptyConfiguration() throws {
        let configuration = try RulesConfigurationDecoder.decode(Data())

        XCTAssertTrue(configuration.flags.isEmpty)
    }

    func testThrowsForTruncatedData() {
        // Field 1 declares 5 bytes, but only 1 byte follows.
        let truncated = Data([0x0A, 0x05, 0x01])

        XCTAssertThrowsError(try RulesConfigurationDecoder.decode(truncated)) { error in
            XCTAssertEqual(error as? RulesConfigurationDecodingError, .invalidData)
        }
    }
}
