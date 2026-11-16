/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CryptoKit
import Foundation
import Security

/// Encodes a public `SecKey` as a DER `SubjectPublicKeyInfo` (RFC 5280, section 4.1).
///
/// `SecKeyCopyExternalRepresentation` returns only the key bytes: a PKCS #1 `RSAPublicKey` for RSA keys, or an
/// uncompressed ANSI X9.63 point for EC keys. Pins hash the full `SubjectPublicKeyInfo`, as `openssl` and other
/// platforms compute it, so the algorithm identifier and the bit string wrapper are added here.
internal enum SubjectPublicKeyInfo {
    /// DER `AlgorithmIdentifier` for `rsaEncryption` with `NULL` parameters.
    static let rsaAlgorithmIdentifier: [UInt8] = [
        0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00
    ]
    /// DER `AlgorithmIdentifier` for `id-ecPublicKey` with the `prime256v1` (P-256) curve.
    static let p256AlgorithmIdentifier: [UInt8] = [
        0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07
    ]
    /// DER `AlgorithmIdentifier` for `id-ecPublicKey` with the `secp384r1` (P-384) curve.
    static let p384AlgorithmIdentifier: [UInt8] = [
        0x30, 0x10, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x22
    ]
    /// DER `AlgorithmIdentifier` for `id-ecPublicKey` with the `secp521r1` (P-521) curve.
    static let p521AlgorithmIdentifier: [UInt8] = [
        0x30, 0x10, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x23
    ]

    /// Returns the DER `SubjectPublicKeyInfo` of a public RSA or EC key, or `nil` for another key type.
    static func der(of key: SecKey) -> Data? {
        // Normalize the key class and type, which some OS versions report as numbers.
        guard let attributes = SecKeyCopyAttributes(key) as? [String: Any],
              attributes[kSecAttrKeyClass as String].map({ "\($0)" }) == kSecAttrKeyClassPublic as String,
              let keyType = attributes[kSecAttrKeyType as String].map({ "\($0)" }),
              let keySize = attributes[kSecAttrKeySizeInBits as String] as? Int,
              let keyBytes = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return nil
        }
        guard let algorithmIdentifier = algorithmIdentifier(keyType: keyType, keySizeInBits: keySize, keyBytes: keyBytes) else {
            return nil
        }
        return der(algorithmIdentifier: algorithmIdentifier, keyBytes: keyBytes)
    }

    /// Returns the base64-encoded SHA-256 hash of the DER `SubjectPublicKeyInfo`, the format of a pin.
    static func sha256Base64(of key: SecKey) -> String? {
        der(of: key).map { Data(SHA256.hash(data: $0)).base64EncodedString() }
    }

    static func algorithmIdentifier(keyType: String, keySizeInBits: Int, keyBytes: Data) -> [UInt8]? {
        if keyType == kSecAttrKeyTypeRSA as String {
            return rsaAlgorithmIdentifier
        }
        guard keyType == kSecAttrKeyTypeECSECPrimeRandom as String else {
            return nil
        }
        // An uncompressed point: 0x04, then the X and Y coordinates.
        let coordinateLength = (keySizeInBits + 7) / 8
        guard keyBytes.count == 1 + 2 * coordinateLength, keyBytes.first == 0x04 else {
            return nil
        }
        switch keySizeInBits {
        case 256: return p256AlgorithmIdentifier
        case 384: return p384AlgorithmIdentifier
        case 521: return p521AlgorithmIdentifier
        default: return nil
        }
    }

    /// `SEQUENCE { algorithm AlgorithmIdentifier, subjectPublicKey BIT STRING }`
    static func der(algorithmIdentifier: [UInt8], keyBytes: Data) -> Data {
        // The bit string starts with the number of unused bits, which is always 0 for a key.
        let bitString = [0x03] + derLength(keyBytes.count + 1) + [0x00] + [UInt8](keyBytes)
        let content = algorithmIdentifier + bitString
        return Data([0x30] + derLength(content.count) + content)
    }

    private static func derLength(_ length: Int) -> [UInt8] {
        if length < 0x80 {
            return [UInt8(length)]
        }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xFF), at: 0)
            remaining >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}
