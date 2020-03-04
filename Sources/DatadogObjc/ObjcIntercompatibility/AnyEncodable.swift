/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Type erasing `Encodable` wrapper to bridge Objective-C's `Any` to Swift `Encodable`.
///
/// Inspired by `AnyCodable` by Flight-School (MIT):
/// https://github.com/Flight-School/AnyCodable/blob/master/Sources/AnyCodable/AnyEncodable.swift
internal class AnyEncodable: Encodable {
    private let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let number as NSNumber:
            try encodeNSNumber(number, into: &container)
        case is NSNull, is Void:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let int8 as Int8:
            try container.encode(int8)
        case let int16 as Int16:
            try container.encode(int16)
        case let int32 as Int32:
            try container.encode(int32)
        case let int64 as Int64:
            try container.encode(int64)
        case let uint as UInt:
            try container.encode(uint)
        case let uint8 as UInt8:
            try container.encode(uint8)
        case let uint16 as UInt16:
            try container.encode(uint16)
        case let uint32 as UInt32:
            try container.encode(uint32)
        case let uint64 as UInt64:
            try container.encode(uint64)
        case let float as Float:
            try container.encode(float)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let date as Date:
            try container.encode(date)
        case let url as URL:
            try container.encode(url)
        case let array as [Any]:
            try container.encode(array.map { AnyEncodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyEncodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "`AnyEncodable` value cannot be encoded")
            throw EncodingError.invalidValue(value, context)
        }
    }
}

private func encodeNSNumber(_ nsnumber: NSNumber, into container: inout SingleValueEncodingContainer) throws {
    switch CFNumberGetType(nsnumber) {
    case .charType:
        try container.encode(nsnumber.boolValue)
    case .sInt8Type:
        try container.encode(nsnumber.int8Value)
    case .sInt16Type:
        try container.encode(nsnumber.int16Value)
    case .sInt32Type:
        try container.encode(nsnumber.int32Value)
    case .sInt64Type:
        try container.encode(nsnumber.int64Value)
    case .shortType:
        try container.encode(nsnumber.uint16Value)
    case .longType:
        try container.encode(nsnumber.uint32Value)
    case .longLongType:
        try container.encode(nsnumber.uint64Value)
    case .intType, .nsIntegerType, .cfIndexType:
        try container.encode(nsnumber.intValue)
    case .floatType, .float32Type:
        try container.encode(nsnumber.floatValue)
    case .doubleType, .float64Type, .cgFloatType:
        try container.encode(nsnumber.doubleValue)
    @unknown default:
        return
    }
}
