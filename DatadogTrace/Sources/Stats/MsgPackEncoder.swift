/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Subset of the MessagePack specification required to encode `StatsPayload`.
///
/// See https://github.com/msgpack/msgpack/blob/master/spec.md
///
/// The encoder is intentionally minimal: only the formats actually used by the
/// client-side stats payload are supported. Cross-SDK parity with the Android
/// implementation is verified by `MsgPackEncoderTests`.
internal final class MsgPackEncoder {
    private var buffer = Data()

    func getBytes() -> Data {
        return buffer
    }

    // MARK: - Primitives

    func writeNull() {
        buffer.append(Format.null)
    }

    func writeBoolean(_ value: Bool) {
        buffer.append(value ? Format.true : Format.false)
    }

    /// Writes a UTF-8 string. A `nil` value is encoded as MsgPack nil.
    func writeString(_ string: String?) {
        guard let string = string else {
            writeNull()
            return
        }
        writeRawString(Data(string.utf8))
    }

    /// Writes the raw bytes of a UTF-8 string. The caller is responsible for ensuring `utf8Bytes` is valid UTF-8.
    func writeRawString(_ utf8Bytes: Data) {
        writeStringHeader(length: utf8Bytes.count)
        buffer.append(utf8Bytes)
    }

    /// Appends already-encoded MessagePack bytes verbatim. Used to splice in pre-encoded sub-payloads.
    func appendRawBytes(_ encoded: Data) {
        buffer.append(encoded)
    }

    func writeBinary(_ binary: Data) {
        writeBinaryHeader(length: binary.count)
        buffer.append(binary)
    }

    func writeInt(_ value: Int32) {
        if value < 0 {
            let leadingOnes = (~value).leadingZeroBitCount
            switch leadingOnes {
            case ...IntThreshold.negInt32:
                buffer.append(Format.int32)
                putInt32(value)
            case ...IntThreshold.negInt16:
                buffer.append(Format.int16)
                putInt16(Int16(truncatingIfNeeded: value))
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
                putInt32(value)
            case ...IntThreshold.posUInt16:
                buffer.append(Format.uint16)
                putInt16(Int16(truncatingIfNeeded: value))
            case ...IntThreshold.posUInt8:
                buffer.append(Format.uint8)
                buffer.append(UInt8(truncatingIfNeeded: value))
            default:
                buffer.append(UInt8(truncatingIfNeeded: value))
            }
        }
    }

    func writeLong(_ value: Int64) {
        if value < 0 {
            let leadingOnes = (~value).leadingZeroBitCount
            switch leadingOnes {
            case ...LongThreshold.negInt64:
                buffer.append(Format.int64)
                putInt64(value)
            case ...LongThreshold.negInt32:
                buffer.append(Format.int32)
                putInt32(Int32(truncatingIfNeeded: value))
            case ...LongThreshold.negInt16:
                buffer.append(Format.int16)
                putInt16(Int16(truncatingIfNeeded: value))
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
                putInt64(value)
            case ...LongThreshold.posUInt32:
                buffer.append(Format.uint32)
                putInt32(Int32(truncatingIfNeeded: value))
            case ...LongThreshold.posUInt16:
                buffer.append(Format.uint16)
                putInt16(Int16(truncatingIfNeeded: value))
            case ...LongThreshold.posUInt8:
                buffer.append(Format.uint8)
                buffer.append(UInt8(truncatingIfNeeded: value))
            default:
                buffer.append(UInt8(truncatingIfNeeded: value))
            }
        }
    }

    /// Writes an unsigned 32-bit integer using the smallest MsgPack format that fits.
    ///
    /// Compared to `writeInt(_:)`, this never emits negative-int formats: values in
    /// `[Int32.max + 1, UInt32.max]` are encoded as `uint32`, which matches the
    /// protobuf-derived intake schema for fields like `HTTPStatusCode`.
    func writeUInt(_ value: UInt32) {
        switch value {
        case ...UInt32(Size.posFixnumMax):
            buffer.append(UInt8(value))
        case ...UInt32(Size.oneByteMax):
            buffer.append(Format.uint8)
            buffer.append(UInt8(value))
        case ...UInt32(Size.twoByteMax):
            buffer.append(Format.uint16)
            putUInt16(UInt16(value))
        default:
            buffer.append(Format.uint32)
            putUInt32(value)
        }
    }

    /// Writes an unsigned 64-bit integer using the smallest MsgPack format that fits.
    ///
    /// Compared to `writeLong(_:)`, this never emits negative-int formats: values in
    /// `[Int64.max + 1, UInt64.max]` are encoded as `uint64`, which matches the
    /// protobuf-derived intake schema for fields like `Hits`, `Errors`, and `Duration`.
    func writeULong(_ value: UInt64) {
        switch value {
        case ...UInt64(Size.posFixnumMax):
            buffer.append(UInt8(value))
        case ...UInt64(Size.oneByteMax):
            buffer.append(Format.uint8)
            buffer.append(UInt8(value))
        case ...UInt64(Size.twoByteMax):
            buffer.append(Format.uint16)
            putUInt16(UInt16(value))
        case ...UInt64(UInt32.max):
            buffer.append(Format.uint32)
            putUInt32(UInt32(value))
        default:
            buffer.append(Format.uint64)
            putUInt64(value)
        }
    }

    // MARK: - Collections

    func startMap(elementCount: Int) {
        switch elementCount {
        case ...Size.fixCollectionMax:
            buffer.append(Format.fixMap | UInt8(elementCount))
        case ...Size.twoByteMax:
            buffer.append(Format.map16)
            putInt16(Int16(truncatingIfNeeded: elementCount))
        default:
            buffer.append(Format.map32)
            putInt32(Int32(truncatingIfNeeded: elementCount))
        }
    }

    func startArray(elementCount: Int) {
        switch elementCount {
        case ...Size.fixCollectionMax:
            buffer.append(Format.fixArray | UInt8(elementCount))
        case ...Size.twoByteMax:
            buffer.append(Format.array16)
            putInt16(Int16(truncatingIfNeeded: elementCount))
        default:
            buffer.append(Format.array32)
            putInt32(Int32(truncatingIfNeeded: elementCount))
        }
    }

    // MARK: - Headers

    private func writeStringHeader(length: Int) {
        switch length {
        case ...Size.fixStrMax:
            buffer.append(Format.fixStr | UInt8(length))
        case ...Size.oneByteMax:
            buffer.append(Format.str8)
            buffer.append(UInt8(length))
        case ...Size.twoByteMax:
            buffer.append(Format.str16)
            putInt16(Int16(truncatingIfNeeded: length))
        default:
            buffer.append(Format.str32)
            putInt32(Int32(truncatingIfNeeded: length))
        }
    }

    private func writeBinaryHeader(length: Int) {
        switch length {
        case ...Size.oneByteMax:
            buffer.append(Format.bin8)
            buffer.append(UInt8(length))
        case ...Size.twoByteMax:
            buffer.append(Format.bin16)
            putInt16(Int16(truncatingIfNeeded: length))
        default:
            buffer.append(Format.bin32)
            putInt32(Int32(truncatingIfNeeded: length))
        }
    }

    // MARK: - Big-endian writers

    private func putUInt16(_ value: UInt16) {
        buffer.append(UInt8(truncatingIfNeeded: value >> 8))
        buffer.append(UInt8(truncatingIfNeeded: value))
    }

    private func putUInt32(_ value: UInt32) {
        buffer.append(UInt8(truncatingIfNeeded: value >> 24))
        buffer.append(UInt8(truncatingIfNeeded: value >> 16))
        buffer.append(UInt8(truncatingIfNeeded: value >> 8))
        buffer.append(UInt8(truncatingIfNeeded: value))
    }

    private func putUInt64(_ value: UInt64) {
        buffer.append(UInt8(truncatingIfNeeded: value >> 56))
        buffer.append(UInt8(truncatingIfNeeded: value >> 48))
        buffer.append(UInt8(truncatingIfNeeded: value >> 40))
        buffer.append(UInt8(truncatingIfNeeded: value >> 32))
        buffer.append(UInt8(truncatingIfNeeded: value >> 24))
        buffer.append(UInt8(truncatingIfNeeded: value >> 16))
        buffer.append(UInt8(truncatingIfNeeded: value >> 8))
        buffer.append(UInt8(truncatingIfNeeded: value))
    }

    private func putInt16(_ value: Int16) {
        putUInt16(UInt16(bitPattern: value))
    }

    private func putInt32(_ value: Int32) {
        putUInt32(UInt32(bitPattern: value))
    }

    private func putInt64(_ value: Int64) {
        putUInt64(UInt64(bitPattern: value))
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
