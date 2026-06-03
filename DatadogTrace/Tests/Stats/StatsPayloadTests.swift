/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogTrace

class StatsPayloadTests: XCTestCase {
    private func decode(_ payload: StatsPayload) throws -> [(key: String, value: Any?)] {
        var decoder = MsgPackTestDecoder(data: payload.toMsgPackPayload())
        return try decoder.readMap()
    }

    func testEncodesAsFixMapWithSixFields() throws {
        let payload = StatsPayload(clientStats: [], splitPayload: false)
        XCTAssertEqual(try decode(payload).count, 6)
    }

    func testFieldsAppearInExpectedOrder() throws {
        let payload = StatsPayload(clientStats: [], splitPayload: false)
        XCTAssertEqual(
            try decode(payload).map { $0.key },
            ["AgentHostname", "AgentEnv", "Stats", "AgentVersion", "ClientComputed", "SplitPayload"]
        )
    }

    func testAgentFieldsAreEmptyStrings() throws {
        let payload = StatsPayload(clientStats: [], splitPayload: false)
        let fields = Dictionary(uniqueKeysWithValues: try decode(payload))
        XCTAssertEqual(fields["AgentHostname"] as? String, "")
        XCTAssertEqual(fields["AgentEnv"] as? String, "")
        XCTAssertEqual(fields["AgentVersion"] as? String, "")
    }

    func testClientComputedIsAlwaysTrue() throws {
        let payload = StatsPayload(clientStats: [], splitPayload: false)
        let fields = Dictionary(uniqueKeysWithValues: try decode(payload))
        XCTAssertEqual(fields["ClientComputed"] as? Bool, true)
    }

    func testSplitPayloadReflectsInput() throws {
        for splitPayload in [true, false] {
            let payload = StatsPayload(clientStats: [], splitPayload: splitPayload)
            let fields = Dictionary(uniqueKeysWithValues: try decode(payload))
            XCTAssertEqual(fields["SplitPayload"] as? Bool, splitPayload)
        }
    }

    func testStatsFieldSplicesPreEncodedBytes() throws {
        let preEncoded1 = Data([0xC0])
        let preEncoded2 = Data([0xC3])
        let payload = StatsPayload(clientStats: [preEncoded1, preEncoded2], splitPayload: false)

        let fields = Dictionary(uniqueKeysWithValues: try decode(payload))
        let statsArray = try XCTUnwrap(fields["Stats"] as? [Any?])
        XCTAssertEqual(statsArray.count, 2)
        XCTAssertNil(statsArray[0])
        XCTAssertEqual(statsArray[1] as? Bool, true)
    }
}
