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

@available(iOS 13.0, tvOS 13.0, *)
internal struct ShapeResource {
    let svgString: String

    init(path: SwiftUI.Path, color: ResolvedPaint, fillStyle: SwiftUI.FillStyle, size: CGSize) {
        let pathData = path.cgPath.dd.svgString
        let fillColor = color.paint.map(\.uiColor.dd.hexString) ?? "#000000FF"
        let fillRule = fillStyle.isEOFilled ? "evenodd" : "nonzero"

        self.svgString = """
          <svg width="\(String(format: "%.3f", size.width))" height="\(String(format: "%.3f", size.height))" xmlns="http://www.w3.org/2000/svg">
            <path d="\(pathData)" fill="\(fillColor)" fill-rule="\(fillRule)"/>
          </svg>
          """
    }
}

@available(iOS 13.0, tvOS 13.0, *)
extension ShapeResource: Resource {
    var mimeType: String {
        "image/svg+xml"
    }

    func calculateIdentifier() -> String {
        #if canImport(CryptoKit)
            let data = Data(svgString.utf8)
            let hash = Insecure.MD5.hash(data: data)
            return hash.map { String(format: "%02hhx", $0) }.joined()
        #else
            // Should never execute since CryptoKit is available iOS 13
            fatalError("CryptoKit not available")
        #endif
    }

    func calculateData() -> Data {
        Data(svgString.utf8)
    }
}

#endif
