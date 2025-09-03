/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import SwiftUI
import CommonCrypto

@available(iOS 13.0, *)
internal final class ShapeResource: NSObject {
    let svgString: String

    private lazy var identifier = makeIdentifier()
    private lazy var data = makeData()

    init(svgString: String) {
        self.svgString = svgString
    }

    private func makeIdentifier() -> String {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        self.data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &digest)
        }
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }

    private func makeData() -> Data {
        Data(svgString.utf8)
    }
}

@available(iOS 13.0, *)
extension ShapeResource: Resource {
    var mimeType: String {
        "image/svg+xml"
    }

    func calculateIdentifier() -> String {
        self.identifier
    }

    func calculateData() -> Data {
        self.data
    }
}

#endif
