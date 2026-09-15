/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import UIKit

extension UILabel {
    func isTextWireframeRepresentable() -> Bool {
        guard
            let font,
            font.fontName == UIFont.preferredFont(forTextStyle: .body).fontName,
            font.fontDescriptor.symbolicTraits.isEmpty
        else {
            return false
        }

        return attributedText?.isTextWireframeRepresentable() ?? true
    }
}

extension NSAttributedString {
    fileprivate func isTextWireframeRepresentable() -> Bool {
        guard length > 0 else {
            return false
        }

        // Check for single run supported attributes
        // NOTE: Single run font and foreground color attributes are reflected in UILabel font and textColor properties
        var runCount = 0
        var unsupportedAttributeCount = 0

        enumerateAttributes(in: NSRange(location: 0, length: length), options: []) { attributes, _, stop in
            runCount += 1

            unsupportedAttributeCount += attributes.keys.filter { key in
                // Only check important unsupported attributes, it is ok if we don't render shadows or text effects
                [.strikethroughStyle, .underlineStyle, .link].contains(key)
            }.count

            if runCount > 1 || unsupportedAttributeCount > 0 {
                stop.pointee = true
            }
        }

        return runCount < 2 && unsupportedAttributeCount == 0
    }
}
#endif
