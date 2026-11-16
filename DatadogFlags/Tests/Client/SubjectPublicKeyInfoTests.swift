/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CryptoKit
import XCTest
import Security
@testable import DatadogFlags

final class SubjectPublicKeyInfoTests: XCTestCase {
    func testPinsMatchOpenSSLVectors() throws {
        // The expected pins and DER headers were computed by OpenSSL from each certificate.
        let vectors: [(name: String, certificate: SecCertificate, header: String, pin: String)] = [
            ("EC P-256", TLSPinningFixtures.leafP256, "3059301306072a8648ce3d020106082a8648ce3d030107034200", TLSPinningFixtures.pinP256),
            ("EC P-384", TLSPinningFixtures.leafP384, "3076301006072a8648ce3d020106052b8104002203620004", TLSPinningFixtures.pinP384),
            ("RSA 2048", TLSPinningFixtures.leafRSA2048, "30820122300d06092a864886f70d01010105000382010f00", TLSPinningFixtures.pinRSA2048),
            ("RSA 4096", TLSPinningFixtures.leafRSA4096, "30820222300d06092a864886f70d01010105000382020f00", TLSPinningFixtures.pinRSA4096),
            ("EC P-256 root", TLSPinningFixtures.root, "3059301306072a8648ce3d020106082a8648ce3d030107034200", TLSPinningFixtures.pinRoot),
        ]

        for vector in vectors {
            // Given
            let key = try XCTUnwrap(SecCertificateCopyKey(vector.certificate), vector.name)

            // When
            let der = try XCTUnwrap(SubjectPublicKeyInfo.der(of: key), vector.name)
            let pin = SubjectPublicKeyInfo.sha256Base64(of: key)

            // Then
            XCTAssertTrue(hex(der).hasPrefix(vector.header), "\(vector.name): \(hex(der).prefix(60))")
            XCTAssertEqual(pin, vector.pin, vector.name)
        }
    }

    func testDERIsTheAlgorithmIdentifierAndTheKeyBitString() throws {
        // Given
        let key = try XCTUnwrap(SecCertificateCopyKey(TLSPinningFixtures.leafP256))
        let keyBytes = try XCTUnwrap(SecKeyCopyExternalRepresentation(key, nil) as Data?)

        // When
        let der = try XCTUnwrap(SubjectPublicKeyInfo.der(of: key))

        // Then
        // Raw key bytes alone are not a SubjectPublicKeyInfo and must not match the pin.
        XCTAssertEqual(keyBytes.count, 65)
        XCTAssertEqual(der.count, 91)
        XCTAssertEqual(der.suffix(65), keyBytes)
        XCTAssertNotEqual(Data(SHA256.hash(data: keyBytes)).base64EncodedString(), TLSPinningFixtures.pinP256)
    }

    func testDERUsesLongFormLengths() {
        // Given
        let keyBytes = Data(repeating: 0xAB, count: 270)

        // When
        let der = SubjectPublicKeyInfo.der(algorithmIdentifier: SubjectPublicKeyInfo.rsaAlgorithmIdentifier, keyBytes: keyBytes)

        // Then
        XCTAssertEqual(hex(der.prefix(24)), "30820122300d06092a864886f70d01010105000382010f00")
        XCTAssertEqual(der.count, 294)
    }

    func testUnsupportedKeysHaveNoSubjectPublicKeyInfo() throws {
        // Given
        let privateKey = try XCTUnwrap(
            SecKeyCreateRandomKey(
                [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeySizeInBits: 256] as CFDictionary,
                nil
            )
        )

        // Then
        // A private key must never be hashed as a pin.
        XCTAssertNil(SubjectPublicKeyInfo.der(of: privateKey))
        XCTAssertNotNil(SecKeyCopyPublicKey(privateKey).flatMap(SubjectPublicKeyInfo.der(of:)))
        XCTAssertNil(SubjectPublicKeyInfo.algorithmIdentifier(keyType: "unknown", keySizeInBits: 256, keyBytes: Data(count: 65)))
        XCTAssertNil(
            SubjectPublicKeyInfo.algorithmIdentifier(
                keyType: kSecAttrKeyTypeECSECPrimeRandom as String,
                keySizeInBits: 256,
                keyBytes: Data(count: 33) // compressed point
            )
        )
        XCTAssertNil(
            SubjectPublicKeyInfo.algorithmIdentifier(
                keyType: kSecAttrKeyTypeECSECPrimeRandom as String,
                keySizeInBits: 224,
                keyBytes: Data([0x04]) + Data(count: 56)
            )
        )
    }

    private func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
