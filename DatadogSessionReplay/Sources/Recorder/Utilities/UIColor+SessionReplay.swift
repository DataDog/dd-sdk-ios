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

        let hash = String(hexString.dropFirst())
        objc_setAssociatedObject(type, &identifierKey, hash, .OBJC_ASSOCIATION_RETAIN)
        return hash
    }

    var hexString: String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1

        type.getRed(&r, green: &g, blue: &b, alpha: &a)

        let ri = Int16(dd_withNoOverflow: round(r * 255))
        let gi = Int16(dd_withNoOverflow: round(g * 255))
        let bi = Int16(dd_withNoOverflow: round(b * 255))
        let ai = Int16(dd_withNoOverflow: round(a * 255))

        var rstr = String(ri, radix: 16, uppercase: true)
        var gstr = String(gi, radix: 16, uppercase: true)
        var bstr = String(bi, radix: 16, uppercase: true)
        var astr = String(ai, radix: 16, uppercase: true)

        rstr = ri < 16 ? "0\(rstr)" : rstr
        gstr = gi < 16 ? "0\(gstr)" : gstr
        bstr = bi < 16 ? "0\(bstr)" : bstr
        astr = ai < 16 ? "0\(astr)" : astr

        return "#\(rstr)\(gstr)\(bstr)\(astr)"
    }
}

#endif
