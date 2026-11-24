/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogFlags

final class UFCReaderTests: XCTestCase {
    private let varintField = UFCField(number: 1, wireType: .varint)
    private let fixed64Field = UFCField(number: 1, wireType: .fixed64)
    private let bytesField = UFCField(number: 1, wireType: .lengthDelimited)
    /// The longest valid varint (10 bytes): `UInt64.max`, or -1 as a signed integer.
    private let maxVarint = [UInt8](repeating: 0xFF, count: 9) + [0x01]

    private func read<T>(_ bytes: [UInt8], _ body: (inout UFCReader) throws -> T) throws -> T {
        try bytes.withUnsafeBytes { buffer in
            var reader = UFCReader(buffer)
            return try body(&reader)
        }
    }

    /// Calls `body` for each field of `bytes`, in order.
    private func readFields(_ bytes: [UInt8], _ body: (inout UFCReader, UFCField) throws -> Void) throws {
        try read(bytes) { reader in
            while let field = try reader.nextField() {
                try body(&reader, field)
            }
        }
    }

    private func assertThrows<T>(_ expected: UFCDecodingError, _ bytes: [UInt8], _ body: (inout UFCReader) throws -> T, line: UInt = #line) {
        XCTAssertThrowsError(try read(bytes, body), line: line) { XCTAssertEqual($0 as? UFCDecodingError, expected, line: line) }
    }

    func testReadsFieldHeadersAndSkipsUnknownFields() throws {
        // One field of each wire type. Field 1000 has a two-byte tag. Each skip must stop at the next field header.
        let bytes: [UInt8] = [0x08, 0x96, 0x01, 0x11, 1, 2, 3, 4, 5, 6, 7, 8, 0x1A, 0x02, 0xAA, 0xBB, 0xC5, 0x3E, 1, 2, 3, 4]
        var fields: [String] = []
        try readFields(bytes) { reader, field in
            fields.append("\(field.number):\(field.wireType)")
            try reader.skip(field)
        }
        XCTAssertEqual(fields, ["1:varint", "2:fixed64", "3:lengthDelimited", "1000:fixed32"])
    }

    func testRejectsInvalidFieldHeaders() {
        assertThrows(.invalidFieldNumber, [0x00, 0x01]) { try $0.nextField() }
        assertThrows(.invalidWireType, [0x0B]) { try $0.nextField() } // wire type 3, start group
        assertThrows(.invalidWireType, [0x0C]) { try $0.nextField() } // wire type 4, end group
    }

    func testReadsVarints() throws {
        XCTAssertEqual(try read([0x00]) { try $0.uint64(varintField) }, 0)
        XCTAssertEqual(try read([0x96, 0x01]) { try $0.uint64(varintField) }, 150)
        XCTAssertEqual(try read(maxVarint) { try $0.uint64(varintField) }, .max)
        XCTAssertEqual(try read(maxVarint) { try $0.int64(varintField) }, -1)
        XCTAssertEqual(try read(maxVarint) { try $0.int32(varintField) }, -1)
        assertThrows(.malformedVarint, [0xFF] + maxVarint) { try $0.uint64(varintField) } // 11 bytes
        assertThrows(.truncated, [0xFF]) { try $0.uint64(varintField) }
    }

    func testReadsDoublesAndStrings() throws {
        XCTAssertEqual(try read([0, 0, 0, 0, 0, 0, 0x04, 0x40]) { try $0.double(fixed64Field) }, 2.5) // little-endian IEEE 754
        assertThrows(.truncated, [0, 0, 0]) { try $0.double(fixed64Field) }
        XCTAssertEqual(try read([0x04, 0x66, 0xC3, 0xA9, 0x65]) { try $0.string(bytesField) }, "fée")
        XCTAssertEqual(try read([0x00]) { try $0.string(bytesField) }, "")
        assertThrows(.invalidUTF8, [0x02, 0xC3, 0x28]) { try $0.string(bytesField) }
        assertThrows(.truncated, [0x05, 0x01]) { try $0.data(bytesField) } // the length goes past the end
    }

    func testReadsPackedAndUnpackedRepeatedUInt32() throws {
        // `0x08 0x03` is one unpacked varint. `0x0A 0x03` is a packed run of 3 bytes with the varints 7 and 150.
        var values: [UInt32] = []
        try readFields([0x08, 0x03, 0x0A, 0x03, 0x07, 0x96, 0x01]) { try $0.appendUInt32($1, to: &values) }
        XCTAssertEqual(values, [3, 7, 150])
    }

    func testSkipsKnownFieldsWithTheWrongWireType() throws {
        // A typed accessor throws before it reads anything.
        assertThrows(.wireTypeMismatch, [0x01]) { try $0.uint32(bytesField) }
        // A message skips it like an unknown field: `seconds` (field 1) comes as a fixed32 and keeps its default value.
        let bytes: [UInt8] = [0x0D, 1, 2, 3, 4, 0x18, 0x05, 0x10, 0x07] // field 1 as a fixed32, unknown field 3, nanos 7
        let timestamp = try bytes.withUnsafeBytes { try UFCTimestamp($0) }
        XCTAssertEqual(timestamp.seconds, 0)
        XCTAssertEqual(timestamp.nanos, 7)
    }
}
