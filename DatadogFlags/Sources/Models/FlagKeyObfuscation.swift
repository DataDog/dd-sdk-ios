/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CryptoKit
import Foundation

/// Describes the lookup keys in one assignment set. The salt is public.
internal struct FlagKeyObfuscation: Equatable, Codable {
    static let capability = "assignment-encoding-flag-key-256-v1"

    enum Scheme: String, Codable {
        case flagKeySHA256V1 = "flag-key-sha256-v1"
    }

    /// 16 bytes, encoded as lowercase hexadecimal.
    struct Salt: Equatable, Codable {
        let bytes: [UInt8]

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let hex = try container.decode(String.self)
            guard let bytes = [UInt8](lowercaseHex: hex, byteCount: 16) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected 16 bytes of lowercase hex")
            }
            self.bytes = bytes
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(bytes.map { String(format: "%02x", $0) }.joined())
        }
    }

    let scheme: Scheme
    let salt: Salt

    func lookupKey(for key: String) -> String {
        var input = Data("datadog.feature-flags.flag-key.v1\0".utf8)
        input.append(contentsOf: salt.bytes)
        input.append(contentsOf: key.utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    func validateKeys(_ keys: Dictionary<String, FlagAssignment>.Keys, codingPath: [CodingKey]) throws {
        guard keys.allSatisfy({ [UInt8](lowercaseHex: $0, byteCount: SHA256.byteCount) != nil }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Flag keys are not SHA-256 digests"))
        }
    }

    /// Only native Apple consumers are supported. Bridges must first support encoding metadata.
    static func isSupported(source: String) -> Bool {
        source == "ios"
    }
}

private extension Array where Element == UInt8 {
    init?(lowercaseHex hex: String, byteCount: Int) {
        guard hex.utf8.count == byteCount * 2 else {
            return nil
        }
        let digits = Array(hex.utf8)
        func nibble(_ digit: UInt8) -> UInt8? {
            switch digit {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return digit - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return digit - UInt8(ascii: "a") + 10
            default: return nil
            }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(byteCount)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = nibble(digits[index]), let low = nibble(digits[index + 1]) else {
                return nil
            }
            bytes.append(high << 4 | low)
        }
        self = bytes
    }
}
