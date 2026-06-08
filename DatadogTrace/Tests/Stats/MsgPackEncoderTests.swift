/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogTrace

/// Verifies the in-house `MsgPackBytes` writers (used by `MsgPackEncoder`) produce byte
/// sequences that conform to the MessagePack specification
/// (https://github.com/msgpack/msgpack/blob/master/spec.md).
///
/// Tests compare writer output against hand-typed reference byte sequences derived from
/// the spec. This is the same cross-check style used by the Android implementation
/// (RUM-16535) and guarantees byte-level parity between platforms.
class MsgPackEncoderTests: XCTestCase {
    private var buffer = Data()

    override func setUp() {
        super.setUp()
        buffer = Data()
    }

    // MARK: - Null and Boolean

    func testWriteNull() {
        buffer.append(MsgPackBytes.nullByte)
        XCTAssertEqual(buffer, Data([0xC0]))
    }

    func testWriteBooleanTrue() {
        MsgPackBytes.appendBool(into: &buffer, value: true)
        XCTAssertEqual(buffer, Data([0xC3]))
    }

    func testWriteBooleanFalse() {
        MsgPackBytes.appendBool(into: &buffer, value: false)
        XCTAssertEqual(buffer, Data([0xC2]))
    }

    // MARK: - String

    func testWriteStringEmpty() {
        MsgPackBytes.appendString(into: &buffer, value: "")
        XCTAssertEqual(buffer, Data([0xA0]))
    }

    func testWriteStringFixStrShort() {
        MsgPackBytes.appendString(into: &buffer, value: "a")
        XCTAssertEqual(buffer, Data([0xA1, 0x61]))
    }

    func testWriteStringFixStrUpperBoundary() {
        MsgPackBytes.appendString(into: &buffer, value: String(repeating: "a", count: 31))
        var expected = Data([0xBF])
        expected.append(Data(repeating: 0x61, count: 31))
        XCTAssertEqual(buffer, expected)
    }

    func testWriteStringStr8LowerBoundary() {
        MsgPackBytes.appendString(into: &buffer, value: String(repeating: "a", count: 32))
        var expected = Data([0xD9, 0x20])
        expected.append(Data(repeating: 0x61, count: 32))
        XCTAssertEqual(buffer, expected)
    }

    func testWriteStringStr8UpperBoundary() {
        MsgPackBytes.appendString(into: &buffer, value: String(repeating: "a", count: 255))
        var expected = Data([0xD9, 0xFF])
        expected.append(Data(repeating: 0x61, count: 255))
        XCTAssertEqual(buffer, expected)
    }

    func testWriteStringStr16LowerBoundary() {
        MsgPackBytes.appendString(into: &buffer, value: String(repeating: "a", count: 256))
        var expected = Data([0xDA, 0x01, 0x00])
        expected.append(Data(repeating: 0x61, count: 256))
        XCTAssertEqual(buffer, expected)
    }

    func testWriteStringStr16UpperBoundary() {
        MsgPackBytes.appendString(into: &buffer, value: String(repeating: "a", count: 65_535))
        var expected = Data([0xDA, 0xFF, 0xFF])
        expected.append(Data(repeating: 0x61, count: 65_535))
        XCTAssertEqual(buffer, expected)
    }

    func testWriteStringStr32LowerBoundary() {
        MsgPackBytes.appendString(into: &buffer, value: String(repeating: "a", count: 65_536))
        var expected = Data([0xDB, 0x00, 0x01, 0x00, 0x00])
        expected.append(Data(repeating: 0x61, count: 65_536))
        XCTAssertEqual(buffer, expected)
    }

    func testWriteStringUTF8() {
        // "héllo" = 0x68 0xC3 0xA9 0x6C 0x6C 0x6F (6 bytes)
        MsgPackBytes.appendString(into: &buffer, value: "héllo")
        XCTAssertEqual(buffer, Data([0xA6, 0x68, 0xC3, 0xA9, 0x6C, 0x6C, 0x6F]))
    }

    // MARK: - Binary

    func testWriteBinaryEmpty() {
        MsgPackBytes.appendBinary(into: &buffer, value: Data())
        XCTAssertEqual(buffer, Data([0xC4, 0x00]))
    }

    func testWriteBinaryBin8UpperBoundary() {
        let data = Data(repeating: 0xAB, count: 255)
        MsgPackBytes.appendBinary(into: &buffer, value: data)
        var expected = Data([0xC4, 0xFF])
        expected.append(data)
        XCTAssertEqual(buffer, expected)
    }

    func testWriteBinaryBin16LowerBoundary() {
        let data = Data(repeating: 0xAB, count: 256)
        MsgPackBytes.appendBinary(into: &buffer, value: data)
        var expected = Data([0xC5, 0x01, 0x00])
        expected.append(data)
        XCTAssertEqual(buffer, expected)
    }

    func testWriteBinaryBin32LowerBoundary() {
        let data = Data(repeating: 0xAB, count: 65_536)
        MsgPackBytes.appendBinary(into: &buffer, value: data)
        var expected = Data([0xC6, 0x00, 0x01, 0x00, 0x00])
        expected.append(data)
        XCTAssertEqual(buffer, expected)
    }

    // MARK: - Int32 (appendInt)

    func testWriteIntPositiveFixNumZero() {
        MsgPackBytes.appendInt(into: &buffer, value: 0)
        XCTAssertEqual(buffer, Data([0x00]))
    }

    func testWriteIntPositiveFixNumUpperBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: 127)
        XCTAssertEqual(buffer, Data([0x7F]))
    }

    func testWriteIntUInt8LowerBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: 128)
        XCTAssertEqual(buffer, Data([0xCC, 0x80]))
    }

    func testWriteIntUInt8UpperBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: 255)
        XCTAssertEqual(buffer, Data([0xCC, 0xFF]))
    }

    func testWriteIntUInt16LowerBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: 256)
        XCTAssertEqual(buffer, Data([0xCD, 0x01, 0x00]))
    }

    func testWriteIntUInt16UpperBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: 65_535)
        XCTAssertEqual(buffer, Data([0xCD, 0xFF, 0xFF]))
    }

    func testWriteIntUInt32LowerBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: 65_536)
        XCTAssertEqual(buffer, Data([0xCE, 0x00, 0x01, 0x00, 0x00]))
    }

    func testWriteIntUInt32MaxInt32() {
        MsgPackBytes.appendInt(into: &buffer, value: Int32.max)
        XCTAssertEqual(buffer, Data([0xCE, 0x7F, 0xFF, 0xFF, 0xFF]))
    }

    func testWriteIntNegativeFixNumMinusOne() {
        MsgPackBytes.appendInt(into: &buffer, value: -1)
        XCTAssertEqual(buffer, Data([0xFF]))
    }

    func testWriteIntNegativeFixNumLowerBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: -32)
        XCTAssertEqual(buffer, Data([0xE0]))
    }

    func testWriteIntInt8UpperBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: -33)
        XCTAssertEqual(buffer, Data([0xD0, 0xDF]))
    }

    func testWriteIntInt8LowerBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: -128)
        XCTAssertEqual(buffer, Data([0xD0, 0x80]))
    }

    func testWriteIntInt16UpperBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: -129)
        XCTAssertEqual(buffer, Data([0xD1, 0xFF, 0x7F]))
    }

    func testWriteIntInt16LowerBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: -32_768)
        XCTAssertEqual(buffer, Data([0xD1, 0x80, 0x00]))
    }

    func testWriteIntInt32UpperBoundary() {
        MsgPackBytes.appendInt(into: &buffer, value: -32_769)
        XCTAssertEqual(buffer, Data([0xD2, 0xFF, 0xFF, 0x7F, 0xFF]))
    }

    func testWriteIntInt32MinInt32() {
        MsgPackBytes.appendInt(into: &buffer, value: Int32.min)
        XCTAssertEqual(buffer, Data([0xD2, 0x80, 0x00, 0x00, 0x00]))
    }

    // MARK: - Int64 (appendLong)

    func testWriteLongPositiveFixNum() {
        MsgPackBytes.appendLong(into: &buffer, value: 42)
        XCTAssertEqual(buffer, Data([0x2A]))
    }

    func testWriteLongUInt8() {
        MsgPackBytes.appendLong(into: &buffer, value: 200)
        XCTAssertEqual(buffer, Data([0xCC, 0xC8]))
    }

    func testWriteLongUInt16() {
        MsgPackBytes.appendLong(into: &buffer, value: 1_000)
        XCTAssertEqual(buffer, Data([0xCD, 0x03, 0xE8]))
    }

    func testWriteLongUInt32() {
        MsgPackBytes.appendLong(into: &buffer, value: 1_000_000)
        XCTAssertEqual(buffer, Data([0xCE, 0x00, 0x0F, 0x42, 0x40]))
    }

    func testWriteLongUInt64LowerBoundary() {
        MsgPackBytes.appendLong(into: &buffer, value: Int64(UInt32.max) + 1)
        XCTAssertEqual(buffer, Data([0xCF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]))
    }

    func testWriteLongUInt64MaxInt64() {
        MsgPackBytes.appendLong(into: &buffer, value: Int64.max)
        XCTAssertEqual(buffer, Data([0xCF, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    func testWriteLongNegativeFixNum() {
        MsgPackBytes.appendLong(into: &buffer, value: -5)
        XCTAssertEqual(buffer, Data([0xFB]))
    }

    func testWriteLongInt8() {
        MsgPackBytes.appendLong(into: &buffer, value: -100)
        XCTAssertEqual(buffer, Data([0xD0, 0x9C]))
    }

    func testWriteLongInt16() {
        MsgPackBytes.appendLong(into: &buffer, value: -1_000)
        XCTAssertEqual(buffer, Data([0xD1, 0xFC, 0x18]))
    }

    func testWriteLongInt32() {
        MsgPackBytes.appendLong(into: &buffer, value: -1_000_000)
        XCTAssertEqual(buffer, Data([0xD2, 0xFF, 0xF0, 0xBD, 0xC0]))
    }

    func testWriteLongInt64LowerBoundary() {
        MsgPackBytes.appendLong(into: &buffer, value: Int64(Int32.min) - 1)
        XCTAssertEqual(buffer, Data([0xD3, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0xFF, 0xFF, 0xFF]))
    }

    func testWriteLongInt64MinInt64() {
        MsgPackBytes.appendLong(into: &buffer, value: Int64.min)
        XCTAssertEqual(buffer, Data([0xD3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    }

    // MARK: - UInt32 (appendUInt)

    func testWriteUIntPositiveFixNumZero() {
        MsgPackBytes.appendUInt(into: &buffer, value: 0)
        XCTAssertEqual(buffer, Data([0x00]))
    }

    func testWriteUIntPositiveFixNumUpperBoundary() {
        MsgPackBytes.appendUInt(into: &buffer, value: 127)
        XCTAssertEqual(buffer, Data([0x7F]))
    }

    func testWriteUIntUInt8LowerBoundary() {
        MsgPackBytes.appendUInt(into: &buffer, value: 128)
        XCTAssertEqual(buffer, Data([0xCC, 0x80]))
    }

    func testWriteUIntUInt8UpperBoundary() {
        MsgPackBytes.appendUInt(into: &buffer, value: 255)
        XCTAssertEqual(buffer, Data([0xCC, 0xFF]))
    }

    func testWriteUIntUInt16LowerBoundary() {
        MsgPackBytes.appendUInt(into: &buffer, value: 256)
        XCTAssertEqual(buffer, Data([0xCD, 0x01, 0x00]))
    }

    func testWriteUIntUInt16UpperBoundary() {
        MsgPackBytes.appendUInt(into: &buffer, value: 65_535)
        XCTAssertEqual(buffer, Data([0xCD, 0xFF, 0xFF]))
    }

    func testWriteUIntUInt32LowerBoundary() {
        MsgPackBytes.appendUInt(into: &buffer, value: 65_536)
        XCTAssertEqual(buffer, Data([0xCE, 0x00, 0x01, 0x00, 0x00]))
    }

    func testWriteUIntAtInt32Max() {
        MsgPackBytes.appendUInt(into: &buffer, value: UInt32(Int32.max))
        XCTAssertEqual(buffer, Data([0xCE, 0x7F, 0xFF, 0xFF, 0xFF]))
    }

    /// Above `Int32.max`, `appendInt(_:)` would route to a negative int32 format due to the
    /// sign-bit ambiguity. `appendUInt(_:)` must emit `uint32`.
    func testWriteUIntAboveInt32MaxUsesUInt32Marker() {
        MsgPackBytes.appendUInt(into: &buffer, value: UInt32(Int32.max) + 1)
        XCTAssertEqual(buffer, Data([0xCE, 0x80, 0x00, 0x00, 0x00]))
    }

    func testWriteUIntMaxUInt32() {
        MsgPackBytes.appendUInt(into: &buffer, value: UInt32.max)
        XCTAssertEqual(buffer, Data([0xCE, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    // MARK: - UInt64 (appendULong)

    func testWriteULongPositiveFixNumZero() {
        MsgPackBytes.appendULong(into: &buffer, value: 0)
        XCTAssertEqual(buffer, Data([0x00]))
    }

    func testWriteULongPositiveFixNumUpperBoundary() {
        MsgPackBytes.appendULong(into: &buffer, value: 127)
        XCTAssertEqual(buffer, Data([0x7F]))
    }

    func testWriteULongUInt8LowerBoundary() {
        MsgPackBytes.appendULong(into: &buffer, value: 128)
        XCTAssertEqual(buffer, Data([0xCC, 0x80]))
    }

    func testWriteULongUInt8UpperBoundary() {
        MsgPackBytes.appendULong(into: &buffer, value: 255)
        XCTAssertEqual(buffer, Data([0xCC, 0xFF]))
    }

    func testWriteULongUInt16LowerBoundary() {
        MsgPackBytes.appendULong(into: &buffer, value: 256)
        XCTAssertEqual(buffer, Data([0xCD, 0x01, 0x00]))
    }

    func testWriteULongUInt16UpperBoundary() {
        MsgPackBytes.appendULong(into: &buffer, value: 65_535)
        XCTAssertEqual(buffer, Data([0xCD, 0xFF, 0xFF]))
    }

    func testWriteULongUInt32LowerBoundary() {
        MsgPackBytes.appendULong(into: &buffer, value: 65_536)
        XCTAssertEqual(buffer, Data([0xCE, 0x00, 0x01, 0x00, 0x00]))
    }

    func testWriteULongUInt32UpperBoundary() {
        MsgPackBytes.appendULong(into: &buffer, value: UInt64(UInt32.max))
        XCTAssertEqual(buffer, Data([0xCE, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    func testWriteULongUInt64LowerBoundary() {
        MsgPackBytes.appendULong(into: &buffer, value: UInt64(UInt32.max) + 1)
        XCTAssertEqual(buffer, Data([0xCF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]))
    }

    func testWriteULongAtInt64Max() {
        MsgPackBytes.appendULong(into: &buffer, value: UInt64(Int64.max))
        XCTAssertEqual(buffer, Data([0xCF, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    /// Above `Int64.max`, `appendLong(_:)` would route to a negative int64 format. `appendULong(_:)`
    /// must emit `uint64` with the high bit set.
    func testWriteULongAboveInt64MaxUsesUInt64Marker() {
        MsgPackBytes.appendULong(into: &buffer, value: UInt64(Int64.max) + 1)
        XCTAssertEqual(buffer, Data([0xCF, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    }

    func testWriteULongMaxUInt64() {
        MsgPackBytes.appendULong(into: &buffer, value: UInt64.max)
        XCTAssertEqual(buffer, Data([0xCF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    // MARK: - Map

    func testStartMapEmpty() {
        MsgPackBytes.appendMapHeader(into: &buffer, elementCount: 0)
        XCTAssertEqual(buffer, Data([0x80]))
    }

    func testStartMapFixMapUpperBoundary() {
        MsgPackBytes.appendMapHeader(into: &buffer, elementCount: 15)
        XCTAssertEqual(buffer, Data([0x8F]))
    }

    func testStartMapMap16LowerBoundary() {
        MsgPackBytes.appendMapHeader(into: &buffer, elementCount: 16)
        XCTAssertEqual(buffer, Data([0xDE, 0x00, 0x10]))
    }

    func testStartMapMap16UpperBoundary() {
        MsgPackBytes.appendMapHeader(into: &buffer, elementCount: 65_535)
        XCTAssertEqual(buffer, Data([0xDE, 0xFF, 0xFF]))
    }

    func testStartMapMap32LowerBoundary() {
        MsgPackBytes.appendMapHeader(into: &buffer, elementCount: 65_536)
        XCTAssertEqual(buffer, Data([0xDF, 0x00, 0x01, 0x00, 0x00]))
    }

    // MARK: - Array

    func testStartArrayEmpty() {
        MsgPackBytes.appendArrayHeader(into: &buffer, elementCount: 0)
        XCTAssertEqual(buffer, Data([0x90]))
    }

    func testStartArrayFixArrayUpperBoundary() {
        MsgPackBytes.appendArrayHeader(into: &buffer, elementCount: 15)
        XCTAssertEqual(buffer, Data([0x9F]))
    }

    func testStartArrayArray16LowerBoundary() {
        MsgPackBytes.appendArrayHeader(into: &buffer, elementCount: 16)
        XCTAssertEqual(buffer, Data([0xDC, 0x00, 0x10]))
    }

    func testStartArrayArray16UpperBoundary() {
        MsgPackBytes.appendArrayHeader(into: &buffer, elementCount: 65_535)
        XCTAssertEqual(buffer, Data([0xDC, 0xFF, 0xFF]))
    }

    func testStartArrayArray32LowerBoundary() {
        MsgPackBytes.appendArrayHeader(into: &buffer, elementCount: 65_536)
        XCTAssertEqual(buffer, Data([0xDD, 0x00, 0x01, 0x00, 0x00]))
    }

    // MARK: - Spec sanity (first-byte type markers)

    func testFirstByteMarkersMatchSpec() {
        // A spot-check that the first byte of each emitted value matches the
        // MessagePack spec marker. Catches accidental regressions in format constants.
        let cases: [(action: (inout Data) -> Void, marker: UInt8)] = [
            ({ $0.append(MsgPackBytes.nullByte) }, 0xC0),
            ({ MsgPackBytes.appendBool(into: &$0, value: true) }, 0xC3),
            ({ MsgPackBytes.appendBool(into: &$0, value: false) }, 0xC2),
            ({ MsgPackBytes.appendInt(into: &$0, value: 127) }, 0x7F),
            ({ MsgPackBytes.appendInt(into: &$0, value: 128) }, 0xCC),
            ({ MsgPackBytes.appendInt(into: &$0, value: 256) }, 0xCD),
            ({ MsgPackBytes.appendInt(into: &$0, value: 65_536) }, 0xCE),
            ({ MsgPackBytes.appendInt(into: &$0, value: -1) }, 0xFF),
            ({ MsgPackBytes.appendInt(into: &$0, value: -33) }, 0xD0),
            ({ MsgPackBytes.appendInt(into: &$0, value: -129) }, 0xD1),
            ({ MsgPackBytes.appendInt(into: &$0, value: -32_769) }, 0xD2),
            ({ MsgPackBytes.appendLong(into: &$0, value: Int64(UInt32.max) + 1) }, 0xCF),
            ({ MsgPackBytes.appendLong(into: &$0, value: Int64(Int32.min) - 1) }, 0xD3),
            ({ MsgPackBytes.appendBinary(into: &$0, value: Data()) }, 0xC4),
            ({ MsgPackBytes.appendBinary(into: &$0, value: Data(repeating: 0, count: 256)) }, 0xC5),
            ({ MsgPackBytes.appendBinary(into: &$0, value: Data(repeating: 0, count: 65_536)) }, 0xC6),
            ({ MsgPackBytes.appendArrayHeader(into: &$0, elementCount: 16) }, 0xDC),
            ({ MsgPackBytes.appendArrayHeader(into: &$0, elementCount: 65_536) }, 0xDD),
            ({ MsgPackBytes.appendMapHeader(into: &$0, elementCount: 16) }, 0xDE),
            ({ MsgPackBytes.appendMapHeader(into: &$0, elementCount: 65_536) }, 0xDF)
        ]
        for (index, testCase) in cases.enumerated() {
            var buffer = Data()
            testCase.action(&buffer)
            XCTAssertEqual(buffer.first, testCase.marker, "case \(index): expected first byte 0x\(String(testCase.marker, radix: 16, uppercase: true))")
        }
    }
}
