/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Encodes any `Encodable` value to a MessagePack byte sequence (subset of the spec).
///
/// See https://github.com/msgpack/msgpack/blob/master/spec.md
///
/// Layered like Foundation's `JSONEncoder`: this public struct is a thin facade over
/// the private reference-typed `_MsgPackEncoder` that does the actual work via Swift's
/// `Encoder` protocol. Containers write to a shared buffer through `MsgPackBytes`.
/// Cross-SDK parity with the Android implementation is verified by `MsgPackEncoderTests`.
internal struct MsgPackEncoder {
    /// Encodes a single `Encodable` value to a MessagePack byte sequence.
    func encode<T: Encodable>(_ value: T) throws -> Data {
        let inner = _MsgPackEncoder()
        try value.encode(to: inner)
        return inner.finalize()
    }
}

// MARK: - Encoder

private final class _MsgPackEncoder: Encoder {
    var codingPath: [CodingKey] = []
    let userInfo: [CodingUserInfoKey: Any] = [:]

    /// Holds the single container returned to the caller. The standard `Encoder` contract
    /// guarantees at most one container per encoder, so we don't need to merge buffers.
    private var topLevel: _Container?

    func finalize() -> Data {
        return topLevel?.finalize() ?? Data()
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = _KeyedContainer<Key>(codingPath: codingPath)
        topLevel = container
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let container = _UnkeyedContainer(codingPath: codingPath)
        topLevel = container
        return container
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        let container = _SingleValueContainer(codingPath: codingPath)
        topLevel = container
        return container
    }

    /// Encodes a value via a fresh inner encoder, returning the resulting bytes. Used by
    /// containers to encode nested `Encodable` values (e.g. each `ClientStatsBucket` inside
    /// a `[ClientStatsBucket]`). `Data` is intercepted and emitted as a MsgPack `bin` family
    /// value rather than the default `[UInt8]` array shape that Foundation's `Data: Codable`
    /// conformance would produce.
    static func encodeChild(_ value: Encodable, codingPath: [CodingKey]) throws -> Data {
        if let data = value as? Data {
            var out = Data()
            MsgPackBytes.appendBinary(into: &out, value: data)
            return out
        }
        let encoder = _MsgPackEncoder()
        encoder.codingPath = codingPath
        try value.encode(to: encoder)
        return encoder.finalize()
    }
}

// MARK: - Container

private protocol _Container: AnyObject {
    func finalize() -> Data
}

// MARK: - Keyed Container

private final class _KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol, _Container {
    var codingPath: [CodingKey]
    private var buffer = Data()
    private var elementCount = 0

    init(codingPath: [CodingKey]) {
        self.codingPath = codingPath
    }

    func finalize() -> Data {
        var out = Data()
        MsgPackBytes.appendMapHeader(into: &out, elementCount: elementCount)
        out.append(buffer)
        return out
    }

    private func writeKey(_ key: Key) {
        MsgPackBytes.appendString(into: &buffer, value: key.stringValue)
        elementCount += 1
    }

    func encodeNil(forKey key: Key) throws {
        writeKey(key)
        buffer.append(MsgPackBytes.nullByte)
    }

    func encode(_ value: Bool, forKey key: Key) throws {
        writeKey(key)
        MsgPackBytes.appendBool(into: &buffer, value: value)
    }

    func encode(_ value: String, forKey key: Key) throws {
        writeKey(key)
        MsgPackBytes.appendString(into: &buffer, value: value)
    }

    func encode(_ value: Int32, forKey key: Key) throws {
        writeKey(key)
        MsgPackBytes.appendInt(into: &buffer, value: value)
    }

    func encode(_ value: Int64, forKey key: Key) throws {
        writeKey(key)
        MsgPackBytes.appendLong(into: &buffer, value: value)
    }

    func encode(_ value: UInt32, forKey key: Key) throws {
        writeKey(key)
        MsgPackBytes.appendUInt(into: &buffer, value: value)
    }

    func encode(_ value: UInt64, forKey key: Key) throws {
        writeKey(key)
        MsgPackBytes.appendULong(into: &buffer, value: value)
    }

    func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        writeKey(key)
        try buffer.append(contentsOf: _MsgPackEncoder.encodeChild(value, codingPath: codingPath + [key]))
    }

    // Foundation primitives outside the MsgPack subset routed through size-equivalent writers.
    // `Float`/`Double` are unsupported because the v1 stats payload uses no float fields.
    func encode(_ value: Int, forKey key: Key) throws { try encode(Int64(value), forKey: key) }
    func encode(_ value: Int8, forKey key: Key) throws { try encode(Int32(value), forKey: key) }
    func encode(_ value: Int16, forKey key: Key) throws { try encode(Int32(value), forKey: key) }
    func encode(_ value: UInt, forKey key: Key) throws { try encode(UInt64(value), forKey: key) }
    func encode(_ value: UInt8, forKey key: Key) throws { try encode(UInt32(value), forKey: key) }
    func encode(_ value: UInt16, forKey key: Key) throws { try encode(UInt32(value), forKey: key) }
    func encode(_ value: Float, forKey key: Key) throws { throw MsgPackEncoderError.floatNotSupported(codingPath + [key]) }
    func encode(_ value: Double, forKey key: Key) throws { throw MsgPackEncoderError.floatNotSupported(codingPath + [key]) }

    // Nesting and super-encoding are unimplemented because MsgPackEncoder handles nested
    // values transparently via `_MsgPackEncoder.encodeChild`. None of our models use these.
    func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        fatalError("MsgPackEncoder does not support explicit nested containers; encode nested values directly")
    }
    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        fatalError("MsgPackEncoder does not support explicit nested containers; encode nested values directly")
    }
    func superEncoder() -> Encoder {
        fatalError("MsgPackEncoder does not support superEncoder()")
    }
    func superEncoder(forKey key: Key) -> Encoder {
        fatalError("MsgPackEncoder does not support superEncoder(forKey:)")
    }
}

// MARK: - Unkeyed Container

private final class _UnkeyedContainer: UnkeyedEncodingContainer, _Container {
    var codingPath: [CodingKey]
    var count: Int = 0
    private var buffer = Data()

    init(codingPath: [CodingKey]) {
        self.codingPath = codingPath
    }

    func finalize() -> Data {
        var out = Data()
        MsgPackBytes.appendArrayHeader(into: &out, elementCount: count)
        out.append(buffer)
        return out
    }

    func encodeNil() throws {
        buffer.append(MsgPackBytes.nullByte)
        count += 1
    }

    func encode(_ value: Bool) throws {
        MsgPackBytes.appendBool(into: &buffer, value: value)
        count += 1
    }

    func encode(_ value: String) throws {
        MsgPackBytes.appendString(into: &buffer, value: value)
        count += 1
    }

    func encode(_ value: Int32) throws {
        MsgPackBytes.appendInt(into: &buffer, value: value)
        count += 1
    }

    func encode(_ value: Int64) throws {
        MsgPackBytes.appendLong(into: &buffer, value: value)
        count += 1
    }

    func encode(_ value: UInt32) throws {
        MsgPackBytes.appendUInt(into: &buffer, value: value)
        count += 1
    }

    func encode(_ value: UInt64) throws {
        MsgPackBytes.appendULong(into: &buffer, value: value)
        count += 1
    }

    func encode<T: Encodable>(_ value: T) throws {
        try buffer.append(contentsOf: _MsgPackEncoder.encodeChild(value, codingPath: codingPath))
        count += 1
    }

    func encode(_ value: Int) throws { try encode(Int64(value)) }
    func encode(_ value: Int8) throws { try encode(Int32(value)) }
    func encode(_ value: Int16) throws { try encode(Int32(value)) }
    func encode(_ value: UInt) throws { try encode(UInt64(value)) }
    func encode(_ value: UInt8) throws { try encode(UInt32(value)) }
    func encode(_ value: UInt16) throws { try encode(UInt32(value)) }
    func encode(_ value: Float) throws { throw MsgPackEncoderError.floatNotSupported(codingPath) }
    func encode(_ value: Double) throws { throw MsgPackEncoderError.floatNotSupported(codingPath) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        fatalError("MsgPackEncoder does not support explicit nested containers; encode nested values directly")
    }
    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        fatalError("MsgPackEncoder does not support explicit nested containers; encode nested values directly")
    }
    func superEncoder() -> Encoder {
        fatalError("MsgPackEncoder does not support superEncoder()")
    }
}

// MARK: - Single-Value Container

private final class _SingleValueContainer: SingleValueEncodingContainer, _Container {
    var codingPath: [CodingKey]
    private var buffer = Data()

    init(codingPath: [CodingKey]) {
        self.codingPath = codingPath
    }

    func finalize() -> Data { buffer }

    func encodeNil() throws { buffer.append(MsgPackBytes.nullByte) }
    func encode(_ value: Bool) throws { MsgPackBytes.appendBool(into: &buffer, value: value) }
    func encode(_ value: String) throws { MsgPackBytes.appendString(into: &buffer, value: value) }
    func encode(_ value: Int32) throws { MsgPackBytes.appendInt(into: &buffer, value: value) }
    func encode(_ value: Int64) throws { MsgPackBytes.appendLong(into: &buffer, value: value) }
    func encode(_ value: UInt32) throws { MsgPackBytes.appendUInt(into: &buffer, value: value) }
    func encode(_ value: UInt64) throws { MsgPackBytes.appendULong(into: &buffer, value: value) }

    func encode<T: Encodable>(_ value: T) throws {
        try buffer.append(contentsOf: _MsgPackEncoder.encodeChild(value, codingPath: codingPath))
    }

    func encode(_ value: Int) throws { try encode(Int64(value)) }
    func encode(_ value: Int8) throws { try encode(Int32(value)) }
    func encode(_ value: Int16) throws { try encode(Int32(value)) }
    func encode(_ value: UInt) throws { try encode(UInt64(value)) }
    func encode(_ value: UInt8) throws { try encode(UInt32(value)) }
    func encode(_ value: UInt16) throws { try encode(UInt32(value)) }
    func encode(_ value: Float) throws { throw MsgPackEncoderError.floatNotSupported(codingPath) }
    func encode(_ value: Double) throws { throw MsgPackEncoderError.floatNotSupported(codingPath) }
}

// MARK: - Errors

internal enum MsgPackEncoderError: Error {
    /// Thrown when an `Encodable` value tries to write a `Float` or `Double`. The v1
    /// stats payload uses no float fields, so we surface this loudly rather than
    /// silently emitting an unsupported MsgPack format.
    case floatNotSupported([CodingKey])
}

// MARK: - Byte-level MsgPack writers

/// Low-level MessagePack byte writers used by `_MsgPackEncoder` and its containers.
/// Exposed `internal` so unit tests can exercise format boundaries directly without
/// constructing throwaway `Encodable` wrappers.
internal enum MsgPackBytes {
    static let nullByte: UInt8 = Format.null

    static func appendBool(into buffer: inout Data, value: Bool) {
        buffer.append(value ? Format.true : Format.false)
    }

    static func appendString(into buffer: inout Data, value: String) {
        let bytes = Data(value.utf8)
        appendStringHeader(into: &buffer, length: bytes.count)
        buffer.append(bytes)
    }

    static func appendBinary(into buffer: inout Data, value: Data) {
        appendBinaryHeader(into: &buffer, length: value.count)
        buffer.append(value)
    }

    static func appendInt(into buffer: inout Data, value: Int32) {
        if value < 0 {
            let leadingOnes = (~value).leadingZeroBitCount
            switch leadingOnes {
            case ...IntThreshold.negInt32:
                buffer.append(Format.int32)
                putInt32(into: &buffer, value: value)
            case ...IntThreshold.negInt16:
                buffer.append(Format.int16)
                putInt16(into: &buffer, value: Int16(truncatingIfNeeded: value))
            case ...IntThreshold.negInt8:
                buffer.append(Format.int8)
                buffer.append(UInt8(truncatingIfNeeded: value))
            default:
                buffer.append(Format.negFixnum | UInt8(truncatingIfNeeded: value))
            }
        } else {
            let leadingZeros = value.leadingZeroBitCount
            switch leadingZeros {
            case ...IntThreshold.posUInt32:
                buffer.append(Format.uint32)
                putInt32(into: &buffer, value: value)
            case ...IntThreshold.posUInt16:
                buffer.append(Format.uint16)
                putInt16(into: &buffer, value: Int16(truncatingIfNeeded: value))
            case ...IntThreshold.posUInt8:
                buffer.append(Format.uint8)
                buffer.append(UInt8(truncatingIfNeeded: value))
            default:
                buffer.append(UInt8(truncatingIfNeeded: value))
            }
        }
    }

    static func appendLong(into buffer: inout Data, value: Int64) {
        if value < 0 {
            let leadingOnes = (~value).leadingZeroBitCount
            switch leadingOnes {
            case ...LongThreshold.negInt64:
                buffer.append(Format.int64)
                putInt64(into: &buffer, value: value)
            case ...LongThreshold.negInt32:
                buffer.append(Format.int32)
                putInt32(into: &buffer, value: Int32(truncatingIfNeeded: value))
            case ...LongThreshold.negInt16:
                buffer.append(Format.int16)
                putInt16(into: &buffer, value: Int16(truncatingIfNeeded: value))
            case ...LongThreshold.negInt8:
                buffer.append(Format.int8)
                buffer.append(UInt8(truncatingIfNeeded: value))
            default:
                buffer.append(Format.negFixnum | UInt8(truncatingIfNeeded: value))
            }
        } else {
            let leadingZeros = value.leadingZeroBitCount
            switch leadingZeros {
            case ...LongThreshold.posUInt64:
                buffer.append(Format.uint64)
                putInt64(into: &buffer, value: value)
            case ...LongThreshold.posUInt32:
                buffer.append(Format.uint32)
                putInt32(into: &buffer, value: Int32(truncatingIfNeeded: value))
            case ...LongThreshold.posUInt16:
                buffer.append(Format.uint16)
                putInt16(into: &buffer, value: Int16(truncatingIfNeeded: value))
            case ...LongThreshold.posUInt8:
                buffer.append(Format.uint8)
                buffer.append(UInt8(truncatingIfNeeded: value))
            default:
                buffer.append(UInt8(truncatingIfNeeded: value))
            }
        }
    }

    /// Encodes an unsigned 32-bit integer using the smallest MsgPack format that fits.
    ///
    /// Compared to `appendInt(_:)`, this never emits negative-int formats: values in
    /// `[Int32.max + 1, UInt32.max]` are encoded as `uint32`, which matches the
    /// protobuf-derived intake schema for fields like `HTTPStatusCode`.
    static func appendUInt(into buffer: inout Data, value: UInt32) {
        switch value {
        case ...UInt32(Size.posFixnumMax):
            buffer.append(UInt8(value))
        case ...UInt32(Size.oneByteMax):
            buffer.append(Format.uint8)
            buffer.append(UInt8(value))
        case ...UInt32(Size.twoByteMax):
            buffer.append(Format.uint16)
            putUInt16(into: &buffer, value: UInt16(value))
        default:
            buffer.append(Format.uint32)
            putUInt32(into: &buffer, value: value)
        }
    }

    /// Encodes an unsigned 64-bit integer using the smallest MsgPack format that fits.
    ///
    /// Compared to `appendLong(_:)`, this never emits negative-int formats: values in
    /// `[Int64.max + 1, UInt64.max]` are encoded as `uint64`, which matches the
    /// protobuf-derived intake schema for fields like `Hits`, `Errors`, and `Duration`.
    static func appendULong(into buffer: inout Data, value: UInt64) {
        switch value {
        case ...UInt64(Size.posFixnumMax):
            buffer.append(UInt8(value))
        case ...UInt64(Size.oneByteMax):
            buffer.append(Format.uint8)
            buffer.append(UInt8(value))
        case ...UInt64(Size.twoByteMax):
            buffer.append(Format.uint16)
            putUInt16(into: &buffer, value: UInt16(value))
        case ...UInt64(UInt32.max):
            buffer.append(Format.uint32)
            putUInt32(into: &buffer, value: UInt32(value))
        default:
            buffer.append(Format.uint64)
            putUInt64(into: &buffer, value: value)
        }
    }

    static func appendMapHeader(into buffer: inout Data, elementCount: Int) {
        switch elementCount {
        case ...Size.fixCollectionMax:
            buffer.append(Format.fixMap | UInt8(elementCount))
        case ...Size.twoByteMax:
            buffer.append(Format.map16)
            putInt16(into: &buffer, value: Int16(truncatingIfNeeded: elementCount))
        default:
            buffer.append(Format.map32)
            putInt32(into: &buffer, value: Int32(truncatingIfNeeded: elementCount))
        }
    }

    static func appendArrayHeader(into buffer: inout Data, elementCount: Int) {
        switch elementCount {
        case ...Size.fixCollectionMax:
            buffer.append(Format.fixArray | UInt8(elementCount))
        case ...Size.twoByteMax:
            buffer.append(Format.array16)
            putInt16(into: &buffer, value: Int16(truncatingIfNeeded: elementCount))
        default:
            buffer.append(Format.array32)
            putInt32(into: &buffer, value: Int32(truncatingIfNeeded: elementCount))
        }
    }

    // MARK: - Headers

    private static func appendStringHeader(into buffer: inout Data, length: Int) {
        switch length {
        case ...Size.fixStrMax:
            buffer.append(Format.fixStr | UInt8(length))
        case ...Size.oneByteMax:
            buffer.append(Format.str8)
            buffer.append(UInt8(length))
        case ...Size.twoByteMax:
            buffer.append(Format.str16)
            putInt16(into: &buffer, value: Int16(truncatingIfNeeded: length))
        default:
            buffer.append(Format.str32)
            putInt32(into: &buffer, value: Int32(truncatingIfNeeded: length))
        }
    }

    private static func appendBinaryHeader(into buffer: inout Data, length: Int) {
        switch length {
        case ...Size.oneByteMax:
            buffer.append(Format.bin8)
            buffer.append(UInt8(length))
        case ...Size.twoByteMax:
            buffer.append(Format.bin16)
            putInt16(into: &buffer, value: Int16(truncatingIfNeeded: length))
        default:
            buffer.append(Format.bin32)
            putInt32(into: &buffer, value: Int32(truncatingIfNeeded: length))
        }
    }

    // MARK: - Big-endian primitive writers

    private static func putUInt16(into buffer: inout Data, value: UInt16) {
        buffer.append(UInt8(truncatingIfNeeded: value >> 8))
        buffer.append(UInt8(truncatingIfNeeded: value))
    }

    private static func putUInt32(into buffer: inout Data, value: UInt32) {
        buffer.append(UInt8(truncatingIfNeeded: value >> 24))
        buffer.append(UInt8(truncatingIfNeeded: value >> 16))
        buffer.append(UInt8(truncatingIfNeeded: value >> 8))
        buffer.append(UInt8(truncatingIfNeeded: value))
    }

    private static func putUInt64(into buffer: inout Data, value: UInt64) {
        buffer.append(UInt8(truncatingIfNeeded: value >> 56))
        buffer.append(UInt8(truncatingIfNeeded: value >> 48))
        buffer.append(UInt8(truncatingIfNeeded: value >> 40))
        buffer.append(UInt8(truncatingIfNeeded: value >> 32))
        buffer.append(UInt8(truncatingIfNeeded: value >> 24))
        buffer.append(UInt8(truncatingIfNeeded: value >> 16))
        buffer.append(UInt8(truncatingIfNeeded: value >> 8))
        buffer.append(UInt8(truncatingIfNeeded: value))
    }

    private static func putInt16(into buffer: inout Data, value: Int16) {
        putUInt16(into: &buffer, value: UInt16(bitPattern: value))
    }

    private static func putInt32(into buffer: inout Data, value: Int32) {
        putUInt32(into: &buffer, value: UInt32(bitPattern: value))
    }

    private static func putInt64(into buffer: inout Data, value: Int64) {
        putUInt64(into: &buffer, value: UInt64(bitPattern: value))
    }

    // MARK: - Constants

    private enum Format {
        static let null: UInt8 = 0xC0
        static let `false`: UInt8 = 0xC2
        static let `true`: UInt8 = 0xC3

        static let bin8: UInt8 = 0xC4
        static let bin16: UInt8 = 0xC5
        static let bin32: UInt8 = 0xC6

        static let uint8: UInt8 = 0xCC
        static let uint16: UInt8 = 0xCD
        static let uint32: UInt8 = 0xCE
        static let uint64: UInt8 = 0xCF

        static let int8: UInt8 = 0xD0
        static let int16: UInt8 = 0xD1
        static let int32: UInt8 = 0xD2
        static let int64: UInt8 = 0xD3

        static let str8: UInt8 = 0xD9
        static let str16: UInt8 = 0xDA
        static let str32: UInt8 = 0xDB

        static let array16: UInt8 = 0xDC
        static let array32: UInt8 = 0xDD

        static let map16: UInt8 = 0xDE
        static let map32: UInt8 = 0xDF

        static let fixMap: UInt8 = 0x80
        static let fixArray: UInt8 = 0x90
        static let fixStr: UInt8 = 0xA0
        static let negFixnum: UInt8 = 0xE0
    }

    /// Number of leading same-sign bits at which a 32-bit signed value widens to the next format.
    private enum IntThreshold {
        static let negInt32 = 16
        static let negInt16 = 24
        static let negInt8 = 26
        static let posUInt32 = 15
        static let posUInt16 = 23
        static let posUInt8 = 24
    }

    /// Number of leading same-sign bits at which a 64-bit signed value widens to the next format.
    private enum LongThreshold {
        static let negInt64 = 32
        static let negInt32 = 48
        static let negInt16 = 56
        static let negInt8 = 58
        static let posUInt64 = 31
        static let posUInt32 = 47
        static let posUInt16 = 55
        static let posUInt8 = 56
    }

    /// Inclusive maximum element or byte counts per format.
    private enum Size {
        static let fixCollectionMax = 15
        static let fixStrMax = 31
        static let posFixnumMax = 127
        static let oneByteMax = 255
        static let twoByteMax = 65_535
    }
}
