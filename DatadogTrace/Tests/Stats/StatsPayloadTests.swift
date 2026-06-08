/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogTrace

class StatsPayloadTests: XCTestCase {
    private let encoder = MsgPackEncoder()

    private func decode(_ payload: StatsPayload) throws -> [(key: String, value: Any?)] {
        var decoder = MsgPackTestDecoder(data: try encoder.encode(payload))
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

    func testStatsFieldEncodesNestedClientStatsPayloads() throws {
        let payload = StatsPayload(
            clientStats: [
                ClientStatsPayload(
                    hostname: "a", env: "prod", version: "1", service: "s1",
                    tracerVersion: "1", runtimeID: "r", sequenceNumber: 1, stats: []
                ),
                ClientStatsPayload(
                    hostname: "b", env: "prod", version: "1", service: "s2",
                    tracerVersion: "1", runtimeID: "r", sequenceNumber: 2, stats: []
                )
            ],
            splitPayload: false
        )

        let fields = Dictionary(uniqueKeysWithValues: try decode(payload))
        let statsArray = try XCTUnwrap(fields["Stats"] as? [Any?])
        XCTAssertEqual(statsArray.count, 2)

        let firstEntries = try XCTUnwrap(statsArray[0] as? [(String, Any?)])
        let firstFields = Dictionary(uniqueKeysWithValues: firstEntries.map { ($0.0, $0.1) })
        XCTAssertEqual(firstFields["Hostname"] as? String, "a")
        XCTAssertEqual(firstFields["Service"] as? String, "s1")

        let secondEntries = try XCTUnwrap(statsArray[1] as? [(String, Any?)])
        let secondFields = Dictionary(uniqueKeysWithValues: secondEntries.map { ($0.0, $0.1) })
        XCTAssertEqual(secondFields["Hostname"] as? String, "b")
        XCTAssertEqual(secondFields["Service"] as? String, "s2")
    }
}
