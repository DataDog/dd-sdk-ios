/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CryptoKit
import CommonCrypto

/// Computes SHA256 for given `string`.
///
/// The implementation is portable between iOS versions - it uses `CryptoKit` on iOS13+ and fallbacks
/// to `CommonCrypto` on older devices.
internal func sha256(_ string: String) -> String {
    guard let data = string.data(using: .utf8) else {
        return string
    }

    if #available(iOS 13.0, tvOS 13.0, *) { // Compute SHA256 with `CryptoKit`
        let digest = SHA256.hash(data: data)
        return digest
            .map({ byte in String(format: "%02x", byte) })
            .joined(separator: "")
    } else { // Fallback to SHA256 with `CommonCrypto`
        var digest: [UInt8] = Array(repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, UInt32(data.count), &digest) }
        return digest
            .map({ byte in String(format: "%02x", byte) })
            .joined(separator: "")
    }
}
