/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import CoreGraphics
import UIKit

/// Computes `#RRGGBBAA` string for given `color`.
/// The implementation is pretty manual for better performance (using String format would be cleaner, but more heavy).
/// - Parameters:
///   - color: the color
/// - Returns: `#RRGGBBAA` string or `nil` if it cannot be constructed for given `color`.
internal func hexString(from color: CGColor) -> String? {
    guard let color = color.safeCast else {
        // Because `CGColor` is dynamic CF type it is possible to get some other CFTypeRef here.
        // To avoid crash on sending message to unexpected type, we sanitize here.
        // For full context, see: https://github.com/DataDog/dd-sdk-ios/pull/1373
        return nil
    }

    let uiColor = UIColor(cgColor: color) // TODO: RUMM-2250 Check if there's a way without converting to `UIColor`

    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 1

    guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
        return nil
    }

    let ri = Int16(withNoOverflow: round(r * 255))
    let gi = Int16(withNoOverflow: round(g * 255))
    let bi = Int16(withNoOverflow: round(b * 255))
    let ai = Int16(withNoOverflow: round(a * 255))

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
