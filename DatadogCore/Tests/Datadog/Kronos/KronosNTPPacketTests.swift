/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 *
 * This file includes software developed by MobileNativeFoundation, https://mobilenativefoundation.org and altered by Datadog.
 * Use of this source code is governed by Apache License 2.0 license: https://github.com/MobileNativeFoundation/Kronos/blob/main/LICENSE
 */

import XCTest
@testable import DatadogCore

final class KronosNTPPacketTests: XCTestCase {
    func testToData() {
        var packet = KronosNTPPacket()
        let data = packet.prepareToSend(transmitTime: 1_463_303_662.776552)
        XCTAssertEqual(data!, Data(hex: "1b0004fa0001000000010000000000000000000000000000" +
                                        "00000000000000000000000000000000dae2bc6ec6cc1c00")!)
    }

    func testParseInvalidData() {
        let network = Data(hex: "0badface")!
        let PDU = try? KronosNTPPacket(data: network, destinationTime: 0)
        XCTAssertNil(PDU)
    }

    func testParseData() {
        let network = Data(hex: "1c0203e90000065700000a68ada2c09cdae2d084a5a76d5fdae2d3354a529000dae2d32b" +
                                "b38bab46dae2d32bb38d9e00")!
        let PDU = try? KronosNTPPacket(data: network, destinationTime: 0)
        XCTAssertEqual(PDU?.version, 3)
        XCTAssertEqual(PDU?.leap, KronosLeapIndicator.noWarning)
        XCTAssertEqual(PDU?.mode, KronosMode.server)
        XCTAssertEqual(PDU?.stratum, KronosStratum.secondary)
        XCTAssertEqual(PDU?.poll, 3)
        XCTAssertEqual(PDU?.precision, -23)
    }

    // MARK: - Overflow Protection Tests (Issue #2568)

    func testPrepareToSendWithFarFutureTime_returnsNil() {
        // time + kEpochDelta > UInt32.max → packet cannot be represented in NTP format.
        // Returns nil instead of crashing or sending corrupted data.
        var packet = KronosNTPPacket()
        let farFutureTime: TimeInterval = 2_200_000_000.0 // ~year 2039
        XCTAssertNil(
            packet.prepareToSend(transmitTime: farFutureTime),
            "Should return nil when timestamp overflows NTP format"
        )
    }

    func testPrepareToSendWithNegativeTime_returnsNil() {
        // time + kEpochDelta < 0 → outside representable NTP range
        var packet = KronosNTPPacket()
        let negativeTime: TimeInterval = -3_000_000_000.0
        XCTAssertNil(
            packet.prepareToSend(transmitTime: negativeTime),
            "Should return nil when timestamp is negative in NTP format"
        )
    }

    func testPrepareToSendWithExtremelyLargeTime_returnsNil() {
        var packet = KronosNTPPacket()
        let extremeTime: TimeInterval = Double(UInt32.max) * 2
        XCTAssertNil(
            packet.prepareToSend(transmitTime: extremeTime),
            "Should return nil for extremely large timestamps"
        )
    }

    func testPrepareToSendWithMaxDateBoundary_producesValidPacket() {
        // Just below the overflow boundary should produce a valid packet
        var packet = KronosNTPPacket()
        let epochDelta = 2_208_988_800.0
        let justBelowOverflow: TimeInterval = Double(UInt32.max) - epochDelta - 1.0
        let data = packet.prepareToSend(transmitTime: justBelowOverflow)
        XCTAssertNotNil(data, "Should produce a valid packet near the boundary")
        XCTAssertEqual(data?.count, 48)
    }

    // MARK: - Integration: NTP round-trip with valid timestamps

    func testNTPPacketRoundTrip_validTime_canBeParsedBack() {
        var clientPacket = KronosNTPPacket()
        let validTime: TimeInterval = 1_463_303_662.776552
        let encoded = clientPacket.prepareToSend(transmitTime: validTime)
        XCTAssertNotNil(encoded)
        XCTAssertNoThrow(try KronosNTPPacket(data: encoded!, destinationTime: validTime))
    }

    func testParseTimeData() {
        let network = Data(hex: "1c0203e90000065700000a68ada2c09cdae2d084a5a76d5fdae2d3354a529000dae2d32b" +
                                "b38bab46dae2d32bb38d9e00")!
        let PDU = try? KronosNTPPacket(data: network, destinationTime: 0)
        XCTAssertEqual(PDU?.rootDelay, 0.0247650146484375)
        XCTAssertEqual(PDU?.rootDispersion, 0.0406494140625)
        XCTAssertEqual(PDU?.clockSource.ID, 2_913_124_508)
        XCTAssertEqual(PDU?.referenceTime, 1_463_308_804.6470859051)
        XCTAssertEqual(PDU?.originTime, 1_463_309_493.2903223038)
        XCTAssertEqual(PDU?.receiveTime, 1_463_309_483.7013499737)
    }
}
