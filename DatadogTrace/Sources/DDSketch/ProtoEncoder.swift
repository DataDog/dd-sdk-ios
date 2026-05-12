/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Minimal protobuf encoder for the DDSketch wire format.
///
/// Supports only the subset of proto3 needed by `ddsketch.proto`:
/// varint, fixed64 (double), sint32 (zigzag), length-delimited (nested messages),
/// and packed repeated doubles.
///
/// This encoder is intentionally self-contained with no SDK dependencies
/// so the DDSketch code can be extracted to a standalone repository.
internal struct ProtoEncoder {
    private(set) var data = Data()

    // MARK: - Wire Types

    private enum WireType: UInt8 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
    }

    // MARK: - Tag

    private mutating func encodeTag(fieldNumber: Int, wireType: WireType) {
        encodeVarint(UInt64(fieldNumber) << 3 | UInt64(wireType.rawValue))
    }

    // MARK: - Varint

    mutating func encodeVarint(_ value: UInt64) {
        var v = value
        while v > 0x7F {
            data.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v))
    }

    // MARK: - ZigZag (for sint32)

    static func zigZagEncode(_ value: Int32) -> UInt64 {
        return UInt64(UInt32(bitPattern: (value << 1) ^ (value >> 31)))
    }

    // MARK: - Double (fixed64, little-endian IEEE 754)

    private mutating func encodeDouble(_ value: Double) {
        var bits = value.bitPattern
        withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
    }

    // MARK: - Field Encoders

    /// Encodes a `double` field (wire type: fixed64). Skips if value is 0.0 (proto3 default).
    mutating func encodeDoubleField(fieldNumber: Int, value: Double) {
        guard value.bitPattern != 0 else {
            return
        }
        encodeTag(fieldNumber: fieldNumber, wireType: .fixed64)
        encodeDouble(value)
    }

    /// Encodes a `uint64`/`int32`/`enum` field as varint. Skips if value is 0 (proto3 default).
    mutating func encodeVarintField(fieldNumber: Int, value: UInt64) {
        guard value != 0 else {
            return
        }
        encodeTag(fieldNumber: fieldNumber, wireType: .varint)
        encodeVarint(value)
    }

    /// Encodes a `sint32` field using zigzag encoding. Skips if value is 0 (proto3 default).
    mutating func encodeSInt32Field(fieldNumber: Int, value: Int32) {
        guard value != 0 else {
            return
        }
        encodeTag(fieldNumber: fieldNumber, wireType: .varint)
        encodeVarint(ProtoEncoder.zigZagEncode(value))
    }

    /// Encodes a nested message as a length-delimited field. Skips if payload is empty.
    mutating func encodeNestedMessage(fieldNumber: Int, payload: Data) {
        guard !payload.isEmpty else {
            return
        }
        encodeTag(fieldNumber: fieldNumber, wireType: .lengthDelimited)
        encodeVarint(UInt64(payload.count))
        data.append(payload)
    }

    /// Encodes a packed repeated `double` array. Skips if the array is empty.
    mutating func encodePackedDoubles(fieldNumber: Int, values: [Double]) {
        guard !values.isEmpty else {
            return
        }
        encodeTag(fieldNumber: fieldNumber, wireType: .lengthDelimited)
        let byteCount = values.count * MemoryLayout<Double>.size
        encodeVarint(UInt64(byteCount))
        for value in values {
            encodeDouble(value)
        }
    }
}
