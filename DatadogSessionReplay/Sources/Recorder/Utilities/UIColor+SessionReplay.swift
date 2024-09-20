/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import UIKit
import DatadogInternal

extension UIColor: DatadogExtended {}

private var identifierKey: UInt8 = 0

extension DatadogExtension where ExtendedType: UIColor {
    var identifier: String {
        if let hash = objc_getAssociatedObject(type, &identifierKey) as? String {
            return hash
        }

        let hash = computeIdentifier()
        objc_setAssociatedObject(type, &identifierKey, hash, .OBJC_ASSOCIATION_RETAIN)
        return hash
    }

    private func computeIdentifier() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        type.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(
            format: "%02X%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255)),
            Int(round(a * 255))
        )
    }
}

#endif
