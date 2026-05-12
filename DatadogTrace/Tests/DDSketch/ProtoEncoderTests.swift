/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import DatadogTrace
import XCTest

final class ProtoEncoderTests: XCTestCase {
    // MARK: - Varint

    func testEncodeVarint_singleByte() {
        var enc = ProtoEncoder()
        enc.encodeVarint(1)
        XCTAssertEqual(enc.data, Data([0x01]))
    }

    func testEncodeVarint_zero() {
        var enc = ProtoEncoder()
        enc.encodeVarint(0)
        XCTAssertEqual(enc.data, Data([0x00]))
    }

    func testEncodeVarint_multiByte() {
        var enc = ProtoEncoder()
        // 300 = 0b100101100 -> varint: [0xAC, 0x02]
        enc.encodeVarint(300)
        XCTAssertEqual(enc.data, Data([0xAC, 0x02]))
    }

    func testEncodeVarint_maxUInt64() {
        var enc = ProtoEncoder()
        enc.encodeVarint(UInt64.max)
        // UInt64.max = 10 bytes of varint (9 full bytes + 1 byte)
        XCTAssertEqual(enc.data.count, 10)
        // First 9 bytes should all have continuation bit set
        for i in 0..<9 {
            XCTAssertEqual(enc.data[i] & 0x80, 0x80)
        }
        // Last byte should not have continuation bit
        XCTAssertEqual(enc.data[9] & 0x80, 0x00)
    }

    // MARK: - ZigZag

    func testZigZagEncode_positive() {
        XCTAssertEqual(ProtoEncoder.zigZagEncode(0), 0)
        XCTAssertEqual(ProtoEncoder.zigZagEncode(1), 2)
        XCTAssertEqual(ProtoEncoder.zigZagEncode(2), 4)
    }

    func testZigZagEncode_negative() {
        XCTAssertEqual(ProtoEncoder.zigZagEncode(-1), 1)
        XCTAssertEqual(ProtoEncoder.zigZagEncode(-2), 3)
    }

    func testZigZagEncode_extremes() {
        XCTAssertEqual(ProtoEncoder.zigZagEncode(Int32.max), UInt64(UInt32.max - 1))
        XCTAssertEqual(ProtoEncoder.zigZagEncode(Int32.min), UInt64(UInt32.max))
    }

    // MARK: - Double Field

    func testEncodeDoubleField_nonZero() {
        var enc = ProtoEncoder()
        enc.encodeDoubleField(fieldNumber: 1, value: 1.0)
        // Tag: (1 << 3) | 1 = 0x09
        // Value: 1.0 as IEEE-754 little-endian = 0x000000000000F03F
        XCTAssertEqual(enc.data.count, 9) // 1 byte tag + 8 bytes double
        XCTAssertEqual(enc.data[0], 0x09)
    }

    func testEncodeDoubleField_zero_skipped() {
        var enc = ProtoEncoder()
        enc.encodeDoubleField(fieldNumber: 1, value: 0.0)
        XCTAssertTrue(enc.data.isEmpty)
    }

    func testEncodeDoubleField_negativeZero_notSkipped() {
        var enc = ProtoEncoder()
        enc.encodeDoubleField(fieldNumber: 1, value: -0.0)
        XCTAssertEqual(enc.data.count, 9)
    }

    // MARK: - Varint Field

    func testEncodeVarintField_nonZero() {
        var enc = ProtoEncoder()
        enc.encodeVarintField(fieldNumber: 2, value: 150)
        // Tag: (2 << 3) | 0 = 0x10
        // Value: 150 = [0x96, 0x01]
        XCTAssertEqual(enc.data, Data([0x10, 0x96, 0x01]))
    }

    func testEncodeVarintField_zero_skipped() {
        var enc = ProtoEncoder()
        enc.encodeVarintField(fieldNumber: 1, value: 0)
        XCTAssertTrue(enc.data.isEmpty)
    }

    // MARK: - SInt32 Field

    func testEncodeSInt32Field_positive() {
        var enc = ProtoEncoder()
        enc.encodeSInt32Field(fieldNumber: 3, value: 1)
        // Tag: (3 << 3) | 0 = 0x18
        // zigzag(1) = 2
        XCTAssertEqual(enc.data, Data([0x18, 0x02]))
    }

    func testEncodeSInt32Field_negative() {
        var enc = ProtoEncoder()
        enc.encodeSInt32Field(fieldNumber: 3, value: -1)
        // zigzag(-1) = 1
        XCTAssertEqual(enc.data, Data([0x18, 0x01]))
    }

    func testEncodeSInt32Field_zero_skipped() {
        var enc = ProtoEncoder()
        enc.encodeSInt32Field(fieldNumber: 3, value: 0)
        XCTAssertTrue(enc.data.isEmpty)
    }

    // MARK: - Nested Message

    func testEncodeNestedMessage() {
        var inner = ProtoEncoder()
        inner.encodeVarintField(fieldNumber: 1, value: 42)

        var outer = ProtoEncoder()
        outer.encodeNestedMessage(fieldNumber: 1, payload: inner.data)

        // Tag: (1 << 3) | 2 = 0x0A
        // Length: 2 bytes (tag 0x08 + varint 42 = 0x2A)
        XCTAssertEqual(outer.data[0], 0x0A)
        XCTAssertEqual(outer.data[1], 0x02)
        XCTAssertEqual(outer.data[2], 0x08)
        XCTAssertEqual(outer.data[3], 0x2A)
    }

    func testEncodeNestedMessage_emptyPayload_skipped() {
        var enc = ProtoEncoder()
        enc.encodeNestedMessage(fieldNumber: 1, payload: Data())
        XCTAssertTrue(enc.data.isEmpty)
    }

    // MARK: - Packed Doubles

    func testEncodePackedDoubles() {
        var enc = ProtoEncoder()
        enc.encodePackedDoubles(fieldNumber: 2, values: [1.0, 2.0])
        // Tag: (2 << 3) | 2 = 0x12
        // Length: 16 bytes (2 doubles)
        XCTAssertEqual(enc.data[0], 0x12)
        XCTAssertEqual(enc.data[1], 16) // length varint

        // Verify the doubles can be read back
        let double1 = enc.data.subdata(in: 2..<10).withUnsafeBytes { $0.load(as: Double.self) }
        let double2 = enc.data.subdata(in: 10..<18).withUnsafeBytes { $0.load(as: Double.self) }
        XCTAssertEqual(double1, 1.0)
        XCTAssertEqual(double2, 2.0)
    }

    func testEncodePackedDoubles_empty_skipped() {
        var enc = ProtoEncoder()
        enc.encodePackedDoubles(fieldNumber: 2, values: [])
        XCTAssertTrue(enc.data.isEmpty)
    }

    // MARK: - Round-Trip Field Numbers

    func testFieldNumbers_upTo15_singleByteTag() {
        var enc = ProtoEncoder()
        enc.encodeVarintField(fieldNumber: 15, value: 1)
        // Tag should be single byte: (15 << 3) | 0 = 120 = 0x78
        XCTAssertEqual(enc.data[0], 0x78)
    }

    func testFieldNumbers_above15_multiByteTag() {
        var enc = ProtoEncoder()
        enc.encodeVarintField(fieldNumber: 16, value: 1)
        // Tag: (16 << 3) | 0 = 128 = varint [0x80, 0x01]
        XCTAssertEqual(enc.data[0], 0x80)
        XCTAssertEqual(enc.data[1], 0x01)
    }
}
