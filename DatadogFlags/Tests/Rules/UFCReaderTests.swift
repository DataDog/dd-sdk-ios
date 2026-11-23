/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogFlags

final class UFCReaderTests: XCTestCase {
    private func read<T>(_ bytes: [UInt8], _ body: (inout UFCReader) throws -> T) throws -> T {
        try bytes.withUnsafeBytes { buffer in
            var reader = UFCReader(buffer)
            return try body(&reader)
        }
    }

    private let varintField = UFCField(number: 1, wireType: .varint)
    private let fixed64Field = UFCField(number: 1, wireType: .fixed64)
    private let bytesField = UFCField(number: 1, wireType: .lengthDelimited)

    // MARK: - Field headers

    func testReadsFieldHeaders() throws {
        // Field 1 varint, field 2 length-delimited, field 1000 fixed32 (two-byte tag).
        let fields = try read([0x08, 0x01, 0x12, 0x00, 0xC5, 0x3E, 0, 0, 0, 0]) { reader -> [String] in
            var fields: [String] = []
            while let field = try reader.nextField() {
                fields.append("\(field.number):\(field.wireType)")
                try reader.skip(field)
            }
            return fields
        }

        XCTAssertEqual(fields, ["1:varint", "2:lengthDelimited", "1000:fixed32"])
    }

    func testRejectsFieldNumberZero() {
        XCTAssertThrowsError(try read([0x00, 0x01]) { try $0.nextField() }) { error in
            XCTAssertEqual(error as? UFCDecodingError, .invalidFieldNumber)
        }
    }

    func testRejectsGroupWireTypes() {
        for tag: UInt8 in [0x0B, 0x0C] {
            XCTAssertThrowsError(try read([tag]) { try $0.nextField() }) { error in
                XCTAssertEqual(error as? UFCDecodingError, .invalidWireType)
            }
        }
    }

    // MARK: - Varints

    func testReadsVarints() throws {
        XCTAssertEqual(try read([0x00]) { try $0.uint64(varintField) }, 0)
        XCTAssertEqual(try read([0x96, 0x01]) { try $0.uint64(varintField) }, 150)
        XCTAssertEqual(try read([UInt8](repeating: 0xFF, count: 9) + [0x01]) { try $0.uint64(varintField) }, .max)
    }

    func testReadsNegativeIntegers() throws {
        let minusOne = [UInt8](repeating: 0xFF, count: 9) + [0x01]

        XCTAssertEqual(try read(minusOne) { try $0.int64(varintField) }, -1)
        XCTAssertEqual(try read(minusOne) { try $0.int32(varintField) }, -1)
    }

    func testRejectsVarintsLongerThan10Bytes() {
        XCTAssertThrowsError(try read([UInt8](repeating: 0xFF, count: 10) + [0x01]) { try $0.uint64(varintField) }) { error in
            XCTAssertEqual(error as? UFCDecodingError, .malformedVarint)
        }
    }

    func testRejectsTruncatedVarints() {
        XCTAssertThrowsError(try read([0xFF]) { try $0.uint64(varintField) }) { error in
            XCTAssertEqual(error as? UFCDecodingError, .truncated)
        }
    }

    // MARK: - Fixed-width and length-delimited values

    func testReadsLittleEndianDoubles() throws {
        // 2.5 as a little-endian IEEE 754 double.
        XCTAssertEqual(try read([0, 0, 0, 0, 0, 0, 0x04, 0x40]) { try $0.double(fixed64Field) }, 2.5)
    }

    func testRejectsTruncatedDoubles() {
        XCTAssertThrowsError(try read([0, 0, 0]) { try $0.double(fixed64Field) }) { error in
            XCTAssertEqual(error as? UFCDecodingError, .truncated)
        }
    }

    func testReadsStrings() throws {
        XCTAssertEqual(try read([0x04, 0x66, 0xC3, 0xA9, 0x65]) { try $0.string(bytesField) }, "fée")
        XCTAssertEqual(try read([0x00]) { try $0.string(bytesField) }, "")
    }

    func testRejectsInvalidUTF8() {
        XCTAssertThrowsError(try read([0x02, 0xC3, 0x28]) { try $0.string(bytesField) }) { error in
            XCTAssertEqual(error as? UFCDecodingError, .invalidUTF8)
        }
    }

    func testRejectsLengthsPastTheEnd() {
        XCTAssertThrowsError(try read([0x05, 0x01]) { try $0.data(bytesField) }) { error in
            XCTAssertEqual(error as? UFCDecodingError, .truncated)
        }
    }

    // MARK: - Repeated values and wire type checks

    func testReadsPackedAndUnpackedRepeatedValues() throws {
        // Unpacked: `0x08 0x03` is one varint field. Packed: `0x0A 0x03` is a 3-byte run with the varints 7 and 150.
        let values = try read([0x08, 0x03, 0x0A, 0x03, 0x07, 0x96, 0x01]) { reader -> [UInt32] in
            var values: [UInt32] = []
            while let field = try reader.nextField() {
                try reader.appendUInt32(field, to: &values)
            }
            return values
        }

        XCTAssertEqual(values, [3, 7, 150])
    }

    func testReportsWireTypeMismatches() {
        XCTAssertThrowsError(try read([0x01]) { try $0.uint32(bytesField) }) { error in
            XCTAssertEqual(error as? UFCDecodingError, .wireTypeMismatch)
        }
    }

    func testSkipsUnknownFields() throws {
        // A fixed64 unknown field, then field 2 as a varint.
        let value = try read([0x09] + [UInt8](repeating: 0xAA, count: 8) + [0x10, 0x2A]) { reader -> UInt32? in
            while let field = try reader.nextField() {
                if field.number == 2 {
                    return try reader.uint32(field)
                }
                try reader.skip(field)
            }
            return nil
        }

        XCTAssertEqual(value, 42)
    }
}
