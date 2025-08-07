/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
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

    return UIColor(cgColor: color).dd.hexString
}
#endif
