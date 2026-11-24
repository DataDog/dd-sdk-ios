/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An error that occurs when data is not a valid rules-based configuration.
/// `wireTypeMismatch` means a known field has an unexpected wire type: `UFCMessage` decoding skips such a field.
internal enum UFCDecodingError: Error, Equatable {
    case truncated, malformedVarint, invalidWireType, invalidFieldNumber, invalidUTF8, wireTypeMismatch
}

/// The protobuf wire types that the rules-based configuration can contain. Groups (3 and 4) are not supported.
internal enum UFCWireType: UInt8 { case varint = 0, fixed64 = 1, lengthDelimited = 2, fixed32 = 5 }

/// One field header: the field number and its wire type.
internal struct UFCField {
    let number: Int
    let wireType: UFCWireType
}

/// A schema message. Each type only maps its field numbers; the shared extension runs the loop.
internal protocol UFCMessage {
    init()
    mutating func decode(_ field: UFCField, from reader: inout UFCReader) throws
}

extension UFCMessage {
    /// Decodes the message from its bytes: loops over fields, skips wire-type mismatches like unknown fields.
    init(_ bytes: UnsafeRawBufferPointer) throws {
        self.init()
        var reader = UFCReader(bytes)
        while let field = try reader.nextField() {
            do {
                try decode(field, from: &reader)
            } catch UFCDecodingError.wireTypeMismatch {
                try reader.skip(field) // Other protobuf decoders also skip a known field with the wrong wire type.
            }
        }
    }
}

/// An open protobuf enum: unknown values are kept.
internal protocol UFCEnum: RawRepresentable, Equatable where RawValue == Int32 { init(rawValue: Int32) }

/// Reads the protobuf wire format from a byte buffer, which must stay valid while the reader is in use.
/// It only decodes; the SDK never encodes this format.
internal struct UFCReader {
    private let bytes: UnsafeRawBufferPointer
    private var index = 0

    init(_ bytes: UnsafeRawBufferPointer) { self.bytes = bytes }

    /// Reads the next field header, or returns `nil` at the end of the buffer.
    mutating func nextField() throws -> UFCField? {
        guard index < bytes.count else {
            return nil
        }
        let tag = try varint()
        guard let wireType = UFCWireType(rawValue: UInt8(tag & 0x7)) else { throw UFCDecodingError.invalidWireType }
        guard (1...0x1FFF_FFFF).contains(tag >> 3) else { throw UFCDecodingError.invalidFieldNumber }
        return UFCField(number: Int(tag >> 3), wireType: wireType)
    }

    /// Skips a field value by its wire type, so a newer schema does not break this decoder.
    mutating func skip(_ field: UFCField) throws {
        switch field.wireType {
        case .varint: _ = try varint()
        case .fixed64: _ = try take(8)
        case .lengthDelimited: _ = try take(varint())
        case .fixed32: _ = try take(4)
        }
    }

    // MARK: - Typed values: each one throws `wireTypeMismatch` before it reads anything.

    mutating func uint32(_ field: UFCField) throws -> UInt32 { UInt32(truncatingIfNeeded: try uint64(field)) }
    mutating func int32(_ field: UFCField) throws -> Int32 { Int32(truncatingIfNeeded: try uint64(field)) }
    mutating func int64(_ field: UFCField) throws -> Int64 { Int64(bitPattern: try uint64(field)) }
    mutating func bool(_ field: UFCField) throws -> Bool { try uint64(field) != 0 }
    mutating func data(_ field: UFCField) throws -> Data { Data(try lengthDelimited(field)) }
    mutating func enumeration<E: UFCEnum>(_ field: UFCField) throws -> E { E(rawValue: try int32(field)) }
    mutating func message<M: UFCMessage>(_ field: UFCField) throws -> M { try M(lengthDelimited(field)) }

    mutating func uint64(_ field: UFCField) throws -> UInt64 {
        try expect(field, .varint)
        return try varint()
    }

    mutating func double(_ field: UFCField) throws -> Double {
        try expect(field, .fixed64)
        return Double(bitPattern: UInt64(littleEndian: try take(8).loadUnaligned(as: UInt64.self)))
    }

    mutating func string(_ field: UFCField) throws -> String {
        let raw = try lengthDelimited(field)
        let string: String?
        if #available(iOS 18.0, tvOS 18.0, watchOS 11.0, macOS 15.0, visionOS 2.0, *) {
            string = String(validating: raw, as: UTF8.self)
        } else {
            string = String(bytes: raw, encoding: .utf8)
        }
        guard let string else { throw UFCDecodingError.invalidUTF8 }
        return string
    }

    /// Appends a `repeated uint32` value. Protobuf allows the packed and the unpacked encoding.
    mutating func appendUInt32(_ field: UFCField, to values: inout [UInt32]) throws {
        if field.wireType == .lengthDelimited {
            var packed = UFCReader(try take(varint()))
            while packed.index < packed.bytes.count {
                values.append(UInt32(truncatingIfNeeded: try packed.varint()))
            }
        } else {
            values.append(try uint32(field))
        }
    }

    // MARK: - Wire format

    private func expect(_ field: UFCField, _ wireType: UFCWireType) throws {
        guard field.wireType == wireType else { throw UFCDecodingError.wireTypeMismatch }
    }

    private mutating func lengthDelimited(_ field: UFCField) throws -> UnsafeRawBufferPointer {
        try expect(field, .lengthDelimited)
        return try take(varint())
    }

    /// Reads a varint of up to 10 bytes. Bits above 64 are dropped.
    private mutating func varint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while shift < 70 {
            guard index < bytes.count else { throw UFCDecodingError.truncated }
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

    /// Returns the next `count` bytes and moves past them.
    private mutating func take(_ count: UInt64) throws -> UnsafeRawBufferPointer {
        guard count <= UInt64(bytes.count - index) else { throw UFCDecodingError.truncated }
        let start = index
        index += Int(count)
        return UnsafeRawBufferPointer(rebasing: bytes[start..<index])
    }
}
