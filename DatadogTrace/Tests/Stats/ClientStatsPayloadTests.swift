/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogTrace

class ClientStatsPayloadTests: XCTestCase {
    // MARK: - ClientStatsPayload (outer per-tracer payload)

    func testClientStatsPayloadEncodesAsFixMapWithNineFields() throws {
        let payload = makePayload()
        var decoder = MsgPackTestDecoder(data: payload.toMsgPackPayload())
        XCTAssertEqual(try decoder.readMap().count, 9)
    }

    func testClientStatsPayloadFieldsAppearInExpectedOrder() throws {
        let payload = makePayload()
        var decoder = MsgPackTestDecoder(data: payload.toMsgPackPayload())
        XCTAssertEqual(
            try decoder.readMap().map { $0.key },
            ["Hostname", "Env", "Version", "Stats", "Lang", "TracerVersion", "RuntimeID", "Sequence", "Service"]
        )
    }

    func testClientStatsPayloadEncodesScalarFields() throws {
        let payload = ClientStatsPayload(
            hostname: "host-01",
            env: "prod",
            version: "1.2.3",
            service: "my-service",
            tracerVersion: "2.0.0",
            runtimeID: "run-abc",
            sequenceNumber: 42,
            stats: []
        )
        var decoder = MsgPackTestDecoder(data: payload.toMsgPackPayload())
        let fields = Dictionary(uniqueKeysWithValues: try decoder.readMap())

        XCTAssertEqual(fields["Hostname"] as? String, "host-01")
        XCTAssertEqual(fields["Env"] as? String, "prod")
        XCTAssertEqual(fields["Version"] as? String, "1.2.3")
        XCTAssertEqual(fields["Service"] as? String, "my-service")
        XCTAssertEqual(fields["TracerVersion"] as? String, "2.0.0")
        XCTAssertEqual(fields["RuntimeID"] as? String, "run-abc")
        XCTAssertEqual(fields["Sequence"] as? Int64, 42)
    }

    func testClientStatsPayloadLangIsIos() throws {
        let payload = makePayload()
        var decoder = MsgPackTestDecoder(data: payload.toMsgPackPayload())
        let fields = Dictionary(uniqueKeysWithValues: try decoder.readMap())
        XCTAssertEqual(fields["Lang"] as? String, "ios")
    }

    func testClientStatsPayloadEncodesBuckets() throws {
        let bucket = ClientStatsBucket(start: 100, duration: 60, stats: [])
        let payload = ClientStatsPayload(
            hostname: "",
            env: "",
            version: "",
            service: "",
            tracerVersion: "",
            runtimeID: "",
            sequenceNumber: 0,
            stats: [bucket, bucket]
        )

        var decoder = MsgPackTestDecoder(data: payload.toMsgPackPayload())
        let fields = Dictionary(uniqueKeysWithValues: try decoder.readMap())
        let buckets = try XCTUnwrap(fields["Stats"] as? [Any?])
        XCTAssertEqual(buckets.count, 2)
    }

    // MARK: - ClientStatsBucket

    func testClientStatsBucketEncodesAsFixMapWithThreeFields() throws {
        let bucket = ClientStatsBucket(start: 100, duration: 60, stats: [])
        let encoder = MsgPackEncoder()
        bucket.encode(into: encoder)

        var decoder = MsgPackTestDecoder(data: encoder.getBytes())
        XCTAssertEqual(try decoder.readMap().count, 3)
    }

    func testClientStatsBucketFieldOrder() throws {
        let bucket = ClientStatsBucket(start: 100, duration: 60, stats: [])
        let encoder = MsgPackEncoder()
        bucket.encode(into: encoder)

        var decoder = MsgPackTestDecoder(data: encoder.getBytes())
        XCTAssertEqual(try decoder.readMap().map { $0.key }, ["Start", "Duration", "Stats"])
    }

    func testClientStatsBucketEncodesScalars() throws {
        let bucket = ClientStatsBucket(start: 100, duration: 60, stats: [])
        let encoder = MsgPackEncoder()
        bucket.encode(into: encoder)

        var decoder = MsgPackTestDecoder(data: encoder.getBytes())
        let fields = Dictionary(uniqueKeysWithValues: try decoder.readMap())
        XCTAssertEqual(fields["Start"] as? Int64, 100)
        XCTAssertEqual(fields["Duration"] as? Int64, 60)
    }

    // MARK: - ClientGroupedStats

    func testClientGroupedStatsEncodesAsFixMapWith17Fields() throws {
        let grouped = makeGroupedStats()
        let encoder = MsgPackEncoder()
        grouped.encode(into: encoder)

        var decoder = MsgPackTestDecoder(data: encoder.getBytes())
        XCTAssertEqual(try decoder.readMap().count, 17)
    }

    func testClientGroupedStatsFieldOrder() throws {
        let grouped = makeGroupedStats()
        let encoder = MsgPackEncoder()
        grouped.encode(into: encoder)

        var decoder = MsgPackTestDecoder(data: encoder.getBytes())
        XCTAssertEqual(
            try decoder.readMap().map { $0.key },
            [
                "Service", "Name", "Resource", "HTTPStatusCode", "Type",
                "Hits", "Errors", "Duration", "OkSummary", "ErrorSummary",
                "Synthetics", "TopLevelHits", "SpanKind", "PeerTags", "IsTraceRoot",
                "GRPCStatusCode", "srv_src"
            ]
        )
    }

    func testClientGroupedStatsEncodesValuesFaithfully() throws {
        let grouped = ClientGroupedStats(
            service: "svc",
            name: "op",
            resource: "/users",
            httpStatusCode: 200,
            type: "custom",
            spanKind: "client",
            isTraceRoot: .true,
            hits: 10,
            errors: 1,
            duration: 5_000,
            topLevelHits: 7,
            okSummary: Data([0x01, 0x02, 0x03]),
            errorSummary: Data([0xFF]),
            peerTags: ["k:v"],
            serviceSource: "mobile"
        )
        let encoder = MsgPackEncoder()
        grouped.encode(into: encoder)

        var decoder = MsgPackTestDecoder(data: encoder.getBytes())
        let fields = Dictionary(uniqueKeysWithValues: try decoder.readMap())

        XCTAssertEqual(fields["Service"] as? String, "svc")
        XCTAssertEqual(fields["Name"] as? String, "op")
        XCTAssertEqual(fields["Resource"] as? String, "/users")
        XCTAssertEqual(fields["HTTPStatusCode"] as? Int64, 200)
        XCTAssertEqual(fields["Type"] as? String, "custom")
        XCTAssertEqual(fields["Hits"] as? Int64, 10)
        XCTAssertEqual(fields["Errors"] as? Int64, 1)
        XCTAssertEqual(fields["Duration"] as? Int64, 5_000)
        XCTAssertEqual(fields["OkSummary"] as? Data, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(fields["ErrorSummary"] as? Data, Data([0xFF]))
        XCTAssertEqual(fields["Synthetics"] as? Bool, false)
        XCTAssertEqual(fields["TopLevelHits"] as? Int64, 7)
        XCTAssertEqual(fields["SpanKind"] as? String, "client")
        let peerTags = try XCTUnwrap(fields["PeerTags"] as? [Any?])
        XCTAssertEqual(peerTags.count, 1)
        XCTAssertEqual(peerTags[0] as? String, "k:v")
        XCTAssertEqual(fields["IsTraceRoot"] as? Int64, 1)
        XCTAssertEqual(fields["GRPCStatusCode"] as? String, "")
        XCTAssertEqual(fields["srv_src"] as? String, "mobile")
    }

    func testClientGroupedStatsSyntheticsIsAlwaysFalse() throws {
        let grouped = makeGroupedStats()
        let encoder = MsgPackEncoder()
        grouped.encode(into: encoder)

        var decoder = MsgPackTestDecoder(data: encoder.getBytes())
        let fields = Dictionary(uniqueKeysWithValues: try decoder.readMap())
        XCTAssertEqual(fields["Synthetics"] as? Bool, false)
    }

    func testClientGroupedStatsGRPCStatusCodeIsAlwaysEmpty() throws {
        let grouped = makeGroupedStats()
        let encoder = MsgPackEncoder()
        grouped.encode(into: encoder)

        var decoder = MsgPackTestDecoder(data: encoder.getBytes())
        let fields = Dictionary(uniqueKeysWithValues: try decoder.readMap())
        XCTAssertEqual(fields["GRPCStatusCode"] as? String, "")
    }

    // MARK: - Trilean

    func testClientGroupedStatsEncodesEachTrilean() throws {
        for (trilean, expected) in [(Trilean.notSet, 0), (.true, 1), (.false, 2)] {
            let grouped = ClientGroupedStats(
                service: "",
                name: "",
                resource: "",
                httpStatusCode: 0,
                type: "",
                spanKind: "",
                isTraceRoot: trilean,
                hits: 0,
                errors: 0,
                duration: 0,
                topLevelHits: 0,
                okSummary: Data(),
                errorSummary: Data(),
                peerTags: [],
                serviceSource: ""
            )
            let encoder = MsgPackEncoder()
            grouped.encode(into: encoder)

            var decoder = MsgPackTestDecoder(data: encoder.getBytes())
            let fields = Dictionary(uniqueKeysWithValues: try decoder.readMap())
            XCTAssertEqual(fields["IsTraceRoot"] as? Int64, Int64(expected))
        }
    }

    // MARK: - Helpers

    private func makePayload() -> ClientStatsPayload {
        ClientStatsPayload(
            hostname: "",
            env: "",
            version: "",
            service: "",
            tracerVersion: "",
            runtimeID: "",
            sequenceNumber: 0,
            stats: []
        )
    }

    private func makeGroupedStats() -> ClientGroupedStats {
        ClientGroupedStats(
            service: "",
            name: "",
            resource: "",
            httpStatusCode: 0,
            type: "",
            spanKind: "",
            isTraceRoot: .notSet,
            hits: 0,
            errors: 0,
            duration: 0,
            topLevelHits: 0,
            okSummary: Data(),
            errorSummary: Data(),
            peerTags: [],
            serviceSource: ""
        )
    }
}
