/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CommonCrypto

/// A globally unique, stable identifier for a UI element.
public struct HeatmapIdentifier: Sendable, RawRepresentable, Hashable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(
        elementPath: [String],
        screenName: String,
        bundleIdentifier: String
    ) {
        let canonicalPath = [
            bundleIdentifier,
            "view:\(screenName)"
        ] + elementPath

        let data = Data(canonicalPath.joined(separator: "/").utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))

        data.withUnsafeBytes {
            _ = CC_MD5($0.baseAddress, CC_LONG(data.count), &digest)
        }

        let identifier = digest.map { String(format: "%02x", $0) }.joined()
        self.init(rawValue: identifier)
    }
}
