/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CommonCrypto

extension Data {
    public func sha1() -> String {
        let hash = withUnsafeBytes { bytes -> [UInt8] in
            var hash: [UInt8] = Array(repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
            CC_SHA1(bytes.baseAddress, CC_LONG(count), &hash)
            return hash
        }

        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
