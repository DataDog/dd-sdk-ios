/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CommonCrypto

internal struct FlagsData: Equatable, Codable {
    var flags: [String: FlagAssignment]
    var context: FlagsEvaluationContext
    var date: Date
    var obfuscationSalt: String? = nil

    func flagAssignment(for clientKey: String) -> FlagAssignment? {
        if let obfuscationSalt {
            let lookupKey = privateFlagLookupKey(salt: obfuscationSalt, clientKey: clientKey)
            if let assignment = flags[lookupKey] {
                return assignment
            }
        }
        return flags[clientKey]
    }
}

internal func privateFlagLookupKey(salt: String, clientKey: String) -> String {
    let input = "dd-ffe-client-key-v1\0\(salt)\0\(clientKey)"
    guard let data = input.data(using: .utf8) else {
        return clientKey
    }

    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
    _ = data.withUnsafeBytes { bytes in
        CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}
