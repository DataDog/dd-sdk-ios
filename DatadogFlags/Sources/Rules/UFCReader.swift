/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An error that occurs when data is not a valid rules-based configuration.
internal enum UFCDecodingError: Error, Equatable {
    /// The data ends inside a field.
    case truncated
    /// A varint is longer than 10 bytes.
    case malformedVarint
    /// A field uses a wire type that protobuf does not support (for example, groups).
    case invalidWireType
    /// A known field uses a wire type that does not match the schema. Decoders skip such a field.
    case wireTypeMismatch
    /// A field number is 0.
    case invalidFieldNumber
    /// A `string` field is not valid UTF-8.
    case invalidUTF8
}

/// The protobuf wire types that the rules-based configuration can contain.
internal enum UFCWireType: UInt8 {
    case varint = 0
    case fixed64 = 1
    case lengthDelimited = 2
    case fixed32 = 5
}

/// One field header: the field number and its wire type.
internal struct UFCField {
    let number: Int
    let wireType: UFCWireType
}

/// Reads the protobuf wire format from a byte buffer. It only decodes; the SDK never encodes this format.
///
/// The buffer must stay valid while the reader is in use.
internal struct UFCReader {
    private let bytes: UnsafeRawBufferPointer
    private var index = 0

    init(_ bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
    }

    /// Reads the next field header, or returns `nil` at the end of the buffer.
    mutating func nextField() throws -> UFCField? {
        guard index < bytes.count else {
            return nil
        }
        let tag = try readVarint()
        guard let wireType = UFCWireType(rawValue: UInt8(tag & 0x7)) else {
            throw UFCDecodingError.invalidWireType
        }
        let number = tag >> 3
        guard number > 0, number <= 0x1FFF_FFFF else {
            throw UFCDecodingError.invalidFieldNumber
        }
        return UFCField(number: Int(number), wireType: wireType)
    }

    /// Skips the value of a field that the schema does not define, so a newer schema does not break this decoder.
    mutating func skip(_ field: UFCField) throws {
        switch field.wireType {
        case .varint: _ = try readVarint()
        case .fixed64: try advance(by: 8)
        case .lengthDelimited: _ = try readLengthDelimited()
        case .fixed32: try advance(by: 4)
        }
    }

    // MARK: - Typed values

    mutating func uint32(_ field: UFCField) throws -> UInt32 {
        try expect(field, .varint)
        return UInt32(truncatingIfNeeded: try readVarint())
    }

    mutating func int32(_ field: UFCField) throws -> Int32 {
        try expect(field, .varint)
        return Int32(truncatingIfNeeded: try readVarint())
    }

    mutating func uint64(_ field: UFCField) throws -> UInt64 {
        try expect(field, .varint)
        return try readVarint()
    }

    mutating func int64(_ field: UFCField) throws -> Int64 {
        try expect(field, .varint)
        return Int64(bitPattern: try readVarint())
    }

    mutating func bool(_ field: UFCField) throws -> Bool {
        try expect(field, .varint)
        return try readVarint() != 0
    }

    mutating func enumValue(_ field: UFCField) throws -> Int32 {
        try int32(field)
    }

    mutating func double(_ field: UFCField) throws -> Double {
        try expect(field, .fixed64)
        guard bytes.count - index >= 8 else {
            throw UFCDecodingError.truncated
        }
        let bits = bytes.loadUnaligned(fromByteOffset: index, as: UInt64.self)
        index += 8
        return Double(bitPattern: UInt64(littleEndian: bits))
    }

    mutating func string(_ field: UFCField) throws -> String {
        try expect(field, .lengthDelimited)
        let raw = try readLengthDelimited()
        if #available(iOS 18.0, tvOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *) {
            guard let string = String(validating: raw, as: UTF8.self) else {
                throw UFCDecodingError.invalidUTF8
            }
            return string
        }
        guard let string = String(bytes: raw, encoding: .utf8) else {
            throw UFCDecodingError.invalidUTF8
        }
        return string
    }

    mutating func data(_ field: UFCField) throws -> Data {
        try expect(field, .lengthDelimited)
        return Data(try readLengthDelimited())
    }

    /// Returns the bytes of an embedded message, for the message's own decoder.
    mutating func message(_ field: UFCField) throws -> UnsafeRawBufferPointer {
        try expect(field, .lengthDelimited)
        return try readLengthDelimited()
    }

    /// Appends a `repeated uint32` value. Protobuf allows the packed and the unpacked encoding.
    mutating func appendUInt32(_ field: UFCField, to values: inout [UInt32]) throws {
        switch field.wireType {
        case .varint:
            values.append(UInt32(truncatingIfNeeded: try readVarint()))
        case .lengthDelimited:
            var packed = UFCReader(try readLengthDelimited())
            while packed.index < packed.bytes.count {
                values.append(UInt32(truncatingIfNeeded: try packed.readVarint()))
            }
        default:
            throw UFCDecodingError.wireTypeMismatch
        }
    }

    // MARK: - Wire format

    private func expect(_ field: UFCField, _ wireType: UFCWireType) throws {
        guard field.wireType == wireType else {
            throw UFCDecodingError.wireTypeMismatch
        }
    }

    private mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<10 {
            guard index < bytes.count else {
                throw UFCDecodingError.truncated
            }
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte < 0x80 {
                return result
            }
            shift += 7
        }
        throw UFCDecodingError.malformedVarint
    }

    private mutating func readLengthDelimited() throws -> UnsafeRawBufferPointer {
        let length = try readVarint()
        guard length <= UInt64(bytes.count - index) else {
            throw UFCDecodingError.truncated
        }
        let start = index
        index += Int(length)
        return UnsafeRawBufferPointer(rebasing: bytes[start..<index])
    }

    private mutating func advance(by count: Int) throws {
        guard bytes.count - index >= count else {
            throw UFCDecodingError.truncated
        }
        index += count
    }
}
