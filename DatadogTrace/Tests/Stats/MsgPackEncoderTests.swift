/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogTrace

/// Verifies the in-house `MsgPackEncoder` produces byte sequences that conform to the
/// MessagePack specification (https://github.com/msgpack/msgpack/blob/master/spec.md).
///
/// Tests compare encoder output against hand-typed reference byte sequences derived from
/// the spec. This is the same cross-check style used by the Android implementation
/// (RUM-16535) and guarantees byte-level parity between platforms.
class MsgPackEncoderTests: XCTestCase {
    private var encoder: MsgPackEncoder! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        encoder = MsgPackEncoder()
    }

    override func tearDown() {
        encoder = nil
        super.tearDown()
    }

    // MARK: - Null and Boolean

    func testWriteNull() {
        encoder.writeNull()
        XCTAssertEqual(encoder.getBytes(), Data([0xC0]))
    }

    func testWriteBooleanTrue() {
        encoder.writeBoolean(true)
        XCTAssertEqual(encoder.getBytes(), Data([0xC3]))
    }

    func testWriteBooleanFalse() {
        encoder.writeBoolean(false)
        XCTAssertEqual(encoder.getBytes(), Data([0xC2]))
    }

    // MARK: - String

    func testWriteStringNilEncodesAsNull() {
        encoder.writeString(nil)
        XCTAssertEqual(encoder.getBytes(), Data([0xC0]))
    }

    func testWriteStringEmpty() {
        encoder.writeString("")
        XCTAssertEqual(encoder.getBytes(), Data([0xA0]))
    }

    func testWriteStringFixStrShort() {
        encoder.writeString("a")
        XCTAssertEqual(encoder.getBytes(), Data([0xA1, 0x61]))
    }

    func testWriteStringFixStrUpperBoundary() {
        let str = String(repeating: "a", count: 31)
        encoder.writeString(str)
        var expected = Data([0xBF])
        expected.append(Data(repeating: 0x61, count: 31))
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    func testWriteStringStr8LowerBoundary() {
        let str = String(repeating: "a", count: 32)
        encoder.writeString(str)
        var expected = Data([0xD9, 0x20])
        expected.append(Data(repeating: 0x61, count: 32))
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    func testWriteStringStr8UpperBoundary() {
        let str = String(repeating: "a", count: 255)
        encoder.writeString(str)
        var expected = Data([0xD9, 0xFF])
        expected.append(Data(repeating: 0x61, count: 255))
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    func testWriteStringStr16LowerBoundary() {
        let str = String(repeating: "a", count: 256)
        encoder.writeString(str)
        var expected = Data([0xDA, 0x01, 0x00])
        expected.append(Data(repeating: 0x61, count: 256))
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    func testWriteStringStr16UpperBoundary() {
        let str = String(repeating: "a", count: 65_535)
        encoder.writeString(str)
        var expected = Data([0xDA, 0xFF, 0xFF])
        expected.append(Data(repeating: 0x61, count: 65_535))
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    func testWriteStringStr32LowerBoundary() {
        let str = String(repeating: "a", count: 65_536)
        encoder.writeString(str)
        var expected = Data([0xDB, 0x00, 0x01, 0x00, 0x00])
        expected.append(Data(repeating: 0x61, count: 65_536))
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    func testWriteStringUTF8() {
        // "héllo" = 0x68 0xC3 0xA9 0x6C 0x6C 0x6F (6 bytes)
        encoder.writeString("héllo")
        XCTAssertEqual(encoder.getBytes(), Data([0xA6, 0x68, 0xC3, 0xA9, 0x6C, 0x6C, 0x6F]))
    }

    func testWriteRawString() {
        encoder.writeRawString(Data([0x66, 0x6F, 0x6F]))
        XCTAssertEqual(encoder.getBytes(), Data([0xA3, 0x66, 0x6F, 0x6F]))
    }

    // MARK: - Binary

    func testWriteBinaryEmpty() {
        encoder.writeBinary(Data())
        XCTAssertEqual(encoder.getBytes(), Data([0xC4, 0x00]))
    }

    func testWriteBinaryBin8UpperBoundary() {
        let data = Data(repeating: 0xAB, count: 255)
        encoder.writeBinary(data)
        var expected = Data([0xC4, 0xFF])
        expected.append(data)
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    func testWriteBinaryBin16LowerBoundary() {
        let data = Data(repeating: 0xAB, count: 256)
        encoder.writeBinary(data)
        var expected = Data([0xC5, 0x01, 0x00])
        expected.append(data)
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    func testWriteBinaryBin32LowerBoundary() {
        let data = Data(repeating: 0xAB, count: 65_536)
        encoder.writeBinary(data)
        var expected = Data([0xC6, 0x00, 0x01, 0x00, 0x00])
        expected.append(data)
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    // MARK: - Int32 (writeInt)

    func testWriteIntPositiveFixNumZero() {
        encoder.writeInt(0)
        XCTAssertEqual(encoder.getBytes(), Data([0x00]))
    }

    func testWriteIntPositiveFixNumUpperBoundary() {
        encoder.writeInt(127)
        XCTAssertEqual(encoder.getBytes(), Data([0x7F]))
    }

    func testWriteIntUInt8LowerBoundary() {
        encoder.writeInt(128)
        XCTAssertEqual(encoder.getBytes(), Data([0xCC, 0x80]))
    }

    func testWriteIntUInt8UpperBoundary() {
        encoder.writeInt(255)
        XCTAssertEqual(encoder.getBytes(), Data([0xCC, 0xFF]))
    }

    func testWriteIntUInt16LowerBoundary() {
        encoder.writeInt(256)
        XCTAssertEqual(encoder.getBytes(), Data([0xCD, 0x01, 0x00]))
    }

    func testWriteIntUInt16UpperBoundary() {
        encoder.writeInt(65_535)
        XCTAssertEqual(encoder.getBytes(), Data([0xCD, 0xFF, 0xFF]))
    }

    func testWriteIntUInt32LowerBoundary() {
        encoder.writeInt(65_536)
        XCTAssertEqual(encoder.getBytes(), Data([0xCE, 0x00, 0x01, 0x00, 0x00]))
    }

    func testWriteIntUInt32MaxInt32() {
        encoder.writeInt(Int32.max)
        XCTAssertEqual(encoder.getBytes(), Data([0xCE, 0x7F, 0xFF, 0xFF, 0xFF]))
    }

    func testWriteIntNegativeFixNumMinusOne() {
        encoder.writeInt(-1)
        XCTAssertEqual(encoder.getBytes(), Data([0xFF]))
    }

    func testWriteIntNegativeFixNumLowerBoundary() {
        encoder.writeInt(-32)
        XCTAssertEqual(encoder.getBytes(), Data([0xE0]))
    }

    func testWriteIntInt8UpperBoundary() {
        encoder.writeInt(-33)
        XCTAssertEqual(encoder.getBytes(), Data([0xD0, 0xDF]))
    }

    func testWriteIntInt8LowerBoundary() {
        encoder.writeInt(-128)
        XCTAssertEqual(encoder.getBytes(), Data([0xD0, 0x80]))
    }

    func testWriteIntInt16UpperBoundary() {
        encoder.writeInt(-129)
        XCTAssertEqual(encoder.getBytes(), Data([0xD1, 0xFF, 0x7F]))
    }

    func testWriteIntInt16LowerBoundary() {
        encoder.writeInt(-32_768)
        XCTAssertEqual(encoder.getBytes(), Data([0xD1, 0x80, 0x00]))
    }

    func testWriteIntInt32UpperBoundary() {
        encoder.writeInt(-32_769)
        XCTAssertEqual(encoder.getBytes(), Data([0xD2, 0xFF, 0xFF, 0x7F, 0xFF]))
    }

    func testWriteIntInt32MinInt32() {
        encoder.writeInt(Int32.min)
        XCTAssertEqual(encoder.getBytes(), Data([0xD2, 0x80, 0x00, 0x00, 0x00]))
    }

    // MARK: - Int64 (writeLong)

    func testWriteLongPositiveFixNum() {
        encoder.writeLong(42)
        XCTAssertEqual(encoder.getBytes(), Data([0x2A]))
    }

    func testWriteLongUInt8() {
        encoder.writeLong(200)
        XCTAssertEqual(encoder.getBytes(), Data([0xCC, 0xC8]))
    }

    func testWriteLongUInt16() {
        encoder.writeLong(1_000)
        XCTAssertEqual(encoder.getBytes(), Data([0xCD, 0x03, 0xE8]))
    }

    func testWriteLongUInt32() {
        encoder.writeLong(1_000_000)
        XCTAssertEqual(encoder.getBytes(), Data([0xCE, 0x00, 0x0F, 0x42, 0x40]))
    }

    func testWriteLongUInt64LowerBoundary() {
        encoder.writeLong(Int64(UInt32.max) + 1)
        XCTAssertEqual(encoder.getBytes(), Data([0xCF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]))
    }

    func testWriteLongUInt64MaxInt64() {
        encoder.writeLong(Int64.max)
        XCTAssertEqual(encoder.getBytes(), Data([0xCF, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    func testWriteLongNegativeFixNum() {
        encoder.writeLong(-5)
        XCTAssertEqual(encoder.getBytes(), Data([0xFB]))
    }

    func testWriteLongInt8() {
        encoder.writeLong(-100)
        XCTAssertEqual(encoder.getBytes(), Data([0xD0, 0x9C]))
    }

    func testWriteLongInt16() {
        encoder.writeLong(-1_000)
        XCTAssertEqual(encoder.getBytes(), Data([0xD1, 0xFC, 0x18]))
    }

    func testWriteLongInt32() {
        encoder.writeLong(-1_000_000)
        XCTAssertEqual(encoder.getBytes(), Data([0xD2, 0xFF, 0xF0, 0xBD, 0xC0]))
    }

    func testWriteLongInt64LowerBoundary() {
        encoder.writeLong(Int64(Int32.min) - 1)
        XCTAssertEqual(encoder.getBytes(), Data([0xD3, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 0xFF, 0xFF, 0xFF]))
    }

    func testWriteLongInt64MinInt64() {
        encoder.writeLong(Int64.min)
        XCTAssertEqual(encoder.getBytes(), Data([0xD3, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    }

    // MARK: - UInt32 (writeUInt)

    func testWriteUIntPositiveFixNumZero() {
        encoder.writeUInt(0)
        XCTAssertEqual(encoder.getBytes(), Data([0x00]))
    }

    func testWriteUIntPositiveFixNumUpperBoundary() {
        encoder.writeUInt(127)
        XCTAssertEqual(encoder.getBytes(), Data([0x7F]))
    }

    func testWriteUIntUInt8LowerBoundary() {
        encoder.writeUInt(128)
        XCTAssertEqual(encoder.getBytes(), Data([0xCC, 0x80]))
    }

    func testWriteUIntUInt8UpperBoundary() {
        encoder.writeUInt(255)
        XCTAssertEqual(encoder.getBytes(), Data([0xCC, 0xFF]))
    }

    func testWriteUIntUInt16LowerBoundary() {
        encoder.writeUInt(256)
        XCTAssertEqual(encoder.getBytes(), Data([0xCD, 0x01, 0x00]))
    }

    func testWriteUIntUInt16UpperBoundary() {
        encoder.writeUInt(65_535)
        XCTAssertEqual(encoder.getBytes(), Data([0xCD, 0xFF, 0xFF]))
    }

    func testWriteUIntUInt32LowerBoundary() {
        encoder.writeUInt(65_536)
        XCTAssertEqual(encoder.getBytes(), Data([0xCE, 0x00, 0x01, 0x00, 0x00]))
    }

    func testWriteUIntAtInt32Max() {
        encoder.writeUInt(UInt32(Int32.max))
        XCTAssertEqual(encoder.getBytes(), Data([0xCE, 0x7F, 0xFF, 0xFF, 0xFF]))
    }

    /// Above `Int32.max`, `writeInt(_:)` would route to a negative int32 format due to the
    /// sign-bit ambiguity. `writeUInt(_:)` must emit `uint32`.
    func testWriteUIntAboveInt32MaxUsesUInt32Marker() {
        encoder.writeUInt(UInt32(Int32.max) + 1)
        XCTAssertEqual(encoder.getBytes(), Data([0xCE, 0x80, 0x00, 0x00, 0x00]))
    }

    func testWriteUIntMaxUInt32() {
        encoder.writeUInt(UInt32.max)
        XCTAssertEqual(encoder.getBytes(), Data([0xCE, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    // MARK: - UInt64 (writeULong)

    func testWriteULongPositiveFixNumZero() {
        encoder.writeULong(0)
        XCTAssertEqual(encoder.getBytes(), Data([0x00]))
    }

    func testWriteULongPositiveFixNumUpperBoundary() {
        encoder.writeULong(127)
        XCTAssertEqual(encoder.getBytes(), Data([0x7F]))
    }

    func testWriteULongUInt8LowerBoundary() {
        encoder.writeULong(128)
        XCTAssertEqual(encoder.getBytes(), Data([0xCC, 0x80]))
    }

    func testWriteULongUInt8UpperBoundary() {
        encoder.writeULong(255)
        XCTAssertEqual(encoder.getBytes(), Data([0xCC, 0xFF]))
    }

    func testWriteULongUInt16LowerBoundary() {
        encoder.writeULong(256)
        XCTAssertEqual(encoder.getBytes(), Data([0xCD, 0x01, 0x00]))
    }

    func testWriteULongUInt16UpperBoundary() {
        encoder.writeULong(65_535)
        XCTAssertEqual(encoder.getBytes(), Data([0xCD, 0xFF, 0xFF]))
    }

    func testWriteULongUInt32LowerBoundary() {
        encoder.writeULong(65_536)
        XCTAssertEqual(encoder.getBytes(), Data([0xCE, 0x00, 0x01, 0x00, 0x00]))
    }

    func testWriteULongUInt32UpperBoundary() {
        encoder.writeULong(UInt64(UInt32.max))
        XCTAssertEqual(encoder.getBytes(), Data([0xCE, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    func testWriteULongUInt64LowerBoundary() {
        encoder.writeULong(UInt64(UInt32.max) + 1)
        XCTAssertEqual(encoder.getBytes(), Data([0xCF, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]))
    }

    func testWriteULongAtInt64Max() {
        encoder.writeULong(UInt64(Int64.max))
        XCTAssertEqual(encoder.getBytes(), Data([0xCF, 0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    /// Above `Int64.max`, `writeLong(_:)` would route to a negative int64 format. `writeULong(_:)`
    /// must emit `uint64` with the high bit set.
    func testWriteULongAboveInt64MaxUsesUInt64Marker() {
        encoder.writeULong(UInt64(Int64.max) + 1)
        XCTAssertEqual(encoder.getBytes(), Data([0xCF, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
    }

    func testWriteULongMaxUInt64() {
        encoder.writeULong(UInt64.max)
        XCTAssertEqual(encoder.getBytes(), Data([0xCF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]))
    }

    // MARK: - Map

    func testStartMapEmpty() {
        encoder.startMap(elementCount: 0)
        XCTAssertEqual(encoder.getBytes(), Data([0x80]))
    }

    func testStartMapFixMapUpperBoundary() {
        encoder.startMap(elementCount: 15)
        XCTAssertEqual(encoder.getBytes(), Data([0x8F]))
    }

    func testStartMapMap16LowerBoundary() {
        encoder.startMap(elementCount: 16)
        XCTAssertEqual(encoder.getBytes(), Data([0xDE, 0x00, 0x10]))
    }

    func testStartMapMap16UpperBoundary() {
        encoder.startMap(elementCount: 65_535)
        XCTAssertEqual(encoder.getBytes(), Data([0xDE, 0xFF, 0xFF]))
    }

    func testStartMapMap32LowerBoundary() {
        encoder.startMap(elementCount: 65_536)
        XCTAssertEqual(encoder.getBytes(), Data([0xDF, 0x00, 0x01, 0x00, 0x00]))
    }

    // MARK: - Array

    func testStartArrayEmpty() {
        encoder.startArray(elementCount: 0)
        XCTAssertEqual(encoder.getBytes(), Data([0x90]))
    }

    func testStartArrayFixArrayUpperBoundary() {
        encoder.startArray(elementCount: 15)
        XCTAssertEqual(encoder.getBytes(), Data([0x9F]))
    }

    func testStartArrayArray16LowerBoundary() {
        encoder.startArray(elementCount: 16)
        XCTAssertEqual(encoder.getBytes(), Data([0xDC, 0x00, 0x10]))
    }

    func testStartArrayArray16UpperBoundary() {
        encoder.startArray(elementCount: 65_535)
        XCTAssertEqual(encoder.getBytes(), Data([0xDC, 0xFF, 0xFF]))
    }

    func testStartArrayArray32LowerBoundary() {
        encoder.startArray(elementCount: 65_536)
        XCTAssertEqual(encoder.getBytes(), Data([0xDD, 0x00, 0x01, 0x00, 0x00]))
    }

    // MARK: - Append raw bytes

    func testAppendRawBytes() {
        encoder.appendRawBytes(Data([0xC0, 0xC3, 0xC2]))
        XCTAssertEqual(encoder.getBytes(), Data([0xC0, 0xC3, 0xC2]))
    }

    // MARK: - Composite

    func testFixMapWithTwoStringEntries() {
        encoder.startMap(elementCount: 2)
        encoder.writeString("a")
        encoder.writeString("1")
        encoder.writeString("b")
        encoder.writeString("2")
        let expected = Data([
            0x82,
            0xA1, 0x61,
            0xA1, 0x31,
            0xA1, 0x62,
            0xA1, 0x32
        ])
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    func testFixArrayWithMixedEntries() {
        encoder.startArray(elementCount: 3)
        encoder.writeBoolean(true)
        encoder.writeNull()
        encoder.writeLong(42)
        let expected = Data([
            0x93,
            0xC3,
            0xC0,
            0x2A
        ])
        XCTAssertEqual(encoder.getBytes(), expected)
    }

    // MARK: - Spec sanity (first-byte type markers)

    func testFirstByteMarkersMatchSpec() {
        // A spot-check that the first byte of each emitted value matches the
        // MessagePack spec marker. Catches accidental regressions in format constants.
        let cases: [(action: (MsgPackEncoder) -> Void, marker: UInt8)] = [
            ({ $0.writeNull() }, 0xC0),
            ({ $0.writeBoolean(true) }, 0xC3),
            ({ $0.writeBoolean(false) }, 0xC2),
            ({ $0.writeInt(127) }, 0x7F),
            ({ $0.writeInt(128) }, 0xCC),
            ({ $0.writeInt(256) }, 0xCD),
            ({ $0.writeInt(65_536) }, 0xCE),
            ({ $0.writeInt(-1) }, 0xFF),
            ({ $0.writeInt(-33) }, 0xD0),
            ({ $0.writeInt(-129) }, 0xD1),
            ({ $0.writeInt(-32_769) }, 0xD2),
            ({ $0.writeLong(Int64(UInt32.max) + 1) }, 0xCF),
            ({ $0.writeLong(Int64(Int32.min) - 1) }, 0xD3),
            ({ $0.writeBinary(Data()) }, 0xC4),
            ({ $0.writeBinary(Data(repeating: 0, count: 256)) }, 0xC5),
            ({ $0.writeBinary(Data(repeating: 0, count: 65_536)) }, 0xC6),
            ({ $0.startArray(elementCount: 16) }, 0xDC),
            ({ $0.startArray(elementCount: 65_536) }, 0xDD),
            ({ $0.startMap(elementCount: 16) }, 0xDE),
            ({ $0.startMap(elementCount: 65_536) }, 0xDF)
        ]
        for (index, testCase) in cases.enumerated() {
            let encoder = MsgPackEncoder()
            testCase.action(encoder)
            let bytes = encoder.getBytes()
            XCTAssertEqual(bytes.first, testCase.marker, "case \(index): expected first byte 0x\(String(testCase.marker, radix: 16, uppercase: true))")
        }
    }
}
