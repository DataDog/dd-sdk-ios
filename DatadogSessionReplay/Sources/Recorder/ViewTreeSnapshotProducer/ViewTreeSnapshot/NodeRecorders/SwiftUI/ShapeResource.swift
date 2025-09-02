/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import SwiftUI

#if canImport(CryptoKit)
import CryptoKit
#endif

@available(iOS 13.0, *)
internal final class ShapeResource: NSObject {
    let svgString: String

    private lazy var identifier = makeIdentifier()
    private lazy var data = makeData()

    init(svgString: String) {
        self.svgString = svgString
    }

    private func makeIdentifier() -> String {
#if canImport(CryptoKit)
        let hash = Insecure.MD5.hash(data: self.data)
        return hash.map { String(format: "%02hhx", $0) }.joined()
#else
        // Should never execute since CryptoKit is available iOS 13
        fatalError("CryptoKit not available")
#endif
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
