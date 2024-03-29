/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CommonCrypto

internal protocol Hashing {
    func hash(from data: Data) -> String
}

internal struct SHA1Hashing: Hashing {
    func hash(from data: Data) -> String {
        var digest: [UInt8] = Array(repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA1($0.baseAddress, UInt32(data.count), &digest) }
        return digest
            .map { String(format: "%02hhx", $0) }
            .joined(separator: "")
    }
}
