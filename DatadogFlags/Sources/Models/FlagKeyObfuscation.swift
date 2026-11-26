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
    private static let dependencyKeyEncryptionScheme = "dependency-key-hkdf-sha256-aes-256-gcm-v1"

    struct DependencyKeyEncryption: Equatable, Codable {
        let scheme: String
    }

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
    let dependencyKeyEncryption: DependencyKeyEncryption?

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

    func validateKeys(_ keys: [String], codingPath: [CodingKey]) throws {
        guard keys.allSatisfy({ [UInt8](lowercaseHex: $0, byteCount: SHA256.byteCount) != nil }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Flag keys are not SHA-256 digests"))
        }
    }

    func validateErrorKeys(_ keys: Dictionary<String, FlagEvaluationFailure>.Keys, codingPath: [CodingKey]) throws {
        guard keys.allSatisfy({ [UInt8](lowercaseHex: $0, byteCount: SHA256.byteCount) != nil }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "Flag keys are not SHA-256 digests"))
        }
    }

    func validateDependencyEvaluations(
        in assignments: Dictionary<String, FlagAssignment>.Values,
        and failures: Dictionary<String, FlagEvaluationFailure>.Values
    ) throws {
        let evaluations = assignments.flatMap(\.dependencyEvaluations) + failures.flatMap(\.dependencyEvaluations)
        guard evaluations.isEmpty || dependencyKeyEncryption?.scheme == Self.dependencyKeyEncryptionScheme else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Dependency evaluations require supported encryption metadata"))
        }
        guard evaluations.allSatisfy({ Self.isEncryptedDependencyKey($0.flagKey) }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid encrypted dependency flag key"))
        }
    }

    func dependencyFlagKey(_ encryptedKey: String, rootFlagKey: String) -> String? {
        guard dependencyKeyEncryption?.scheme == Self.dependencyKeyEncryptionScheme,
              let envelope = Self.decodeBase64URL(encryptedKey),
              envelope.count >= 28 else {
            return nil
        }
        let nonceData = envelope.prefix(12)
        let ciphertext = envelope.dropFirst(12).dropLast(16)
        let tag = envelope.suffix(16)
        let pseudoRandomKey = HMAC<SHA256>.authenticationCode(
            for: Data(rootFlagKey.utf8),
            using: SymmetricKey(data: Data(salt.bytes))
        )
        let info = Data("datadog.feature-flags.dependency-key.v1\0enc".utf8)
        var expandInput = info
        expandInput.append(1)
        let encryptionKey = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(
            for: expandInput,
            using: SymmetricKey(data: Data(pseudoRandomKey))
        )))
        do {
            let nonce = try AES.GCM.Nonce(data: nonceData)
            let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
            let plaintext = try AES.GCM.open(
                sealed,
                using: encryptionKey,
                authenticating: Data("datadog.feature-flags.dependency-key.v1\0".utf8)
            )
            return String(data: plaintext, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// Only native Apple consumers are supported. Bridges must first support encoding metadata.
    static func isSupported(source: String) -> Bool {
        source == "ios"
    }

    private static func isEncryptedDependencyKey(_ value: String) -> Bool {
        value.utf8.count >= 38 && value.utf8.count % 4 != 1 && value.utf8.allSatisfy {
            ($0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z"))
                || ($0 >= UInt8(ascii: "a") && $0 <= UInt8(ascii: "z"))
                || ($0 >= UInt8(ascii: "0") && $0 <= UInt8(ascii: "9"))
                || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "_")
        }
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        guard isEncryptedDependencyKey(value) else { return nil }
        var encoded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded.append(String(repeating: "=", count: (4 - encoded.count % 4) % 4))
        guard let decoded = Data(base64Encoded: encoded) else { return nil }
        let canonical = decoded.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return canonical == value ? decoded : nil
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
