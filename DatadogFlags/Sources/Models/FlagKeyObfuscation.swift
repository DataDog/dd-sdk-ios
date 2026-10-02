/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CryptoKit
import Foundation

/// Describes the lookup keys in one assignment set. The salt is public.
internal struct FlagKeyObfuscation: Equatable, Codable {
    static let supportedScheme = "flag-key-sha256-v1"

    let scheme: String
    let salt: String
    private let saltBytes: [UInt8]

    private enum CodingKeys: String, CodingKey {
        case scheme, salt
    }

    private enum MetadataKeys: String, CodingKey {
        case obfuscated, obfuscation
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scheme = try container.decode(String.self, forKey: .scheme)
        salt = try container.decode(String.self, forKey: .salt)
        guard scheme == Self.supportedScheme, Self.isLowercaseHex(salt, bytes: 16) else {
            throw FlagsError.invalidResponse
        }
        let characters = Array(salt.utf8)
        saltBytes = stride(from: 0, to: characters.count, by: 2).map { index in
            Self.hexDigit(characters[index]) * 16 + Self.hexDigit(characters[index + 1])
        }
    }

    /// Distinguishes absent metadata from explicit null or an inconsistent descriptor.
    static func read(from decoder: any Decoder) throws -> FlagKeyObfuscation? {
        let container = try decoder.container(keyedBy: MetadataKeys.self)
        let obfuscated = container.contains(.obfuscated)
            ? try container.decode(Bool.self, forKey: .obfuscated) : false
        guard obfuscated else {
            guard !container.contains(.obfuscation) else { throw FlagsError.invalidResponse }
            return nil
        }
        return try container.decode(Self.self, forKey: .obfuscation)
    }

    func encodeMetadata(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: MetadataKeys.self)
        try container.encode(true, forKey: .obfuscated)
        try container.encode(self, forKey: .obfuscation)
    }

    func lookupKey(for key: String) -> String {
        var input = Data("datadog.feature-flags.flag-key.v1\0".utf8)
        input.append(contentsOf: saltBytes)
        input.append(contentsOf: key.utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    func validateKeys(_ keys: Dictionary<String, FlagAssignment>.Keys) throws {
        guard keys.allSatisfy({ Self.isLowercaseHex($0, bytes: 32) }) else {
            throw FlagsError.invalidResponse
        }
    }

    /// Only native Apple consumers are supported. Bridges must first support encoding metadata.
    static func isSupported(source: String) -> Bool {
        source == "ios"
    }

    private static func isLowercaseHex(_ value: String, bytes: Int) -> Bool {
        value.utf8.count == bytes * 2 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func hexDigit(_ character: UInt8) -> UInt8 {
        character <= 57 ? character - 48 : character - 87
    }
}
