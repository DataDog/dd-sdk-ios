/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Minimal MessagePack decoder used by the stats payload tests.
///
/// Decoding is intentionally implemented from scratch (not via the production encoder)
/// so that it provides an independent cross-check of the encoder output, in the spirit
/// of Austin's Android tests that decode encoder output with `msgpack-java`.
///
/// Only the subset of the spec actually produced by `MsgPackEncoder` is supported. The
/// decoder throws on unsupported markers so a buggy encoder cannot silently pass tests.
internal struct MsgPackTestDecoder {
    enum DecoderError: Error {
        case unexpectedEnd
        case unsupportedMarker(UInt8)
        case nonStringMapKey
    }

    private let bytes: [UInt8]
    private var cursor: Int

    init(data: Data) {
        self.bytes = Array(data)
        self.cursor = 0
    }

    /// Reads a map and returns the entries in original order. Keys must be strings.
    mutating func readMap() throws -> [(key: String, value: Any?)] {
        let count = try readMapHeader()
        var entries: [(String, Any?)] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            guard let key = try readValue() as? String else {
                throw DecoderError.nonStringMapKey
            }
            entries.append((key, try readValue()))
        }
        return entries
    }

    mutating func readArray() throws -> [Any?] {
        let count = try readArrayHeader()
        var values: [Any?] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(try readValue())
        }
        return values
    }

    mutating func readValue() throws -> Any? {
        let marker = try readByte()
        switch marker {
        case 0xC0:
            return nil
        case 0xC2:
            return false
        case 0xC3:
            return true
        case 0xC4:
            let length = Int(try readByte())
            return Data(try readBytes(count: length))
        case 0xC5:
            let length = try readUInt16()
            return Data(try readBytes(count: length))
        case 0xC6:
            let length = try readUInt32()
            return Data(try readBytes(count: length))
        case 0xCC:
            return Int64(try readByte())
        case 0xCD:
            return Int64(try readUInt16())
        case 0xCE:
            return Int64(try readUInt32())
        case 0xCF:
            return Int64(bitPattern: try readUInt64())
        case 0xD0:
            return Int64(Int8(bitPattern: try readByte()))
        case 0xD1:
            return Int64(try readInt16())
        case 0xD2:
            return Int64(try readInt32())
        case 0xD3:
            return Int64(bitPattern: try readUInt64())
        case 0xD9:
            let length = Int(try readByte())
            return try readString(length: length)
        case 0xDA:
            let length = try readUInt16()
            return try readString(length: length)
        case 0xDB:
            let length = try readUInt32()
            return try readString(length: length)
        case 0xDC:
            let count = try readUInt16()
            return try readArrayBody(count: count)
        case 0xDD:
            let count = try readUInt32()
            return try readArrayBody(count: count)
        case 0xDE:
            let count = try readUInt16()
            return try readMapBody(count: count)
        case 0xDF:
            let count = try readUInt32()
            return try readMapBody(count: count)
        default:
            if marker & 0x80 == 0 {
                return Int64(marker)
            }
            if marker & 0xE0 == 0xE0 {
                return Int64(Int8(bitPattern: marker))
            }
            if marker & 0xE0 == 0xA0 {
                let length = Int(marker & 0x1F)
                return try readString(length: length)
            }
            if marker & 0xF0 == 0x90 {
                let count = Int(marker & 0x0F)
                return try readArrayBody(count: count)
            }
            if marker & 0xF0 == 0x80 {
                let count = Int(marker & 0x0F)
                return try readMapBody(count: count)
            }
            throw DecoderError.unsupportedMarker(marker)
        }
    }

    // MARK: - Headers

    private mutating func readMapHeader() throws -> Int {
        let marker = try readByte()
        if marker & 0xF0 == 0x80 {
            return Int(marker & 0x0F)
        }
        switch marker {
        case 0xDE: return try readUInt16()
        case 0xDF: return try readUInt32()
        default: throw DecoderError.unsupportedMarker(marker)
        }
    }

    private mutating func readArrayHeader() throws -> Int {
        let marker = try readByte()
        if marker & 0xF0 == 0x90 {
            return Int(marker & 0x0F)
        }
        switch marker {
        case 0xDC: return try readUInt16()
        case 0xDD: return try readUInt32()
        default: throw DecoderError.unsupportedMarker(marker)
        }
    }

    // MARK: - Bodies (helpers used after the marker has already been consumed)

    private mutating func readArrayBody(count: Int) throws -> [Any?] {
        var values: [Any?] = []
        values.reserveCapacity(count)
        for _ in 0..<count {
            values.append(try readValue())
        }
        return values
    }

    private mutating func readMapBody(count: Int) throws -> [(String, Any?)] {
        var entries: [(String, Any?)] = []
        entries.reserveCapacity(count)
        for _ in 0..<count {
            guard let key = try readValue() as? String else {
                throw DecoderError.nonStringMapKey
            }
            entries.append((key, try readValue()))
        }
        return entries
    }

    // MARK: - Primitive readers

    private mutating func readByte() throws -> UInt8 {
        guard cursor < bytes.count else {
            throw DecoderError.unexpectedEnd
        }
        let byte = bytes[cursor]
        cursor += 1
        return byte
    }

    private mutating func readBytes(count: Int) throws -> [UInt8] {
        guard cursor + count <= bytes.count else {
            throw DecoderError.unexpectedEnd
        }
        let slice = Array(bytes[cursor..<(cursor + count)])
        cursor += count
        return slice
    }

    private mutating func readUInt16() throws -> Int {
        let hi = Int(try readByte())
        let lo = Int(try readByte())
        return (hi << 8) | lo
    }

    private mutating func readUInt32() throws -> Int {
        let b3 = Int(try readByte())
        let b2 = Int(try readByte())
        let b1 = Int(try readByte())
        let b0 = Int(try readByte())
        return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
    }

    private mutating func readUInt64() throws -> UInt64 {
        var value: UInt64 = 0
        for _ in 0..<8 {
            value = (value << 8) | UInt64(try readByte())
        }
        return value
    }

    private mutating func readInt16() throws -> Int16 {
        let raw = UInt16(try readUInt16())
        return Int16(bitPattern: raw)
    }

    private mutating func readInt32() throws -> Int32 {
        let raw = UInt32(try readUInt32())
        return Int32(bitPattern: raw)
    }

    private mutating func readString(length: Int) throws -> String {
        let bytes = try readBytes(count: length)
        return String(decoding: bytes, as: UTF8.self)
    }
}
