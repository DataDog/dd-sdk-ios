/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit
import DatadogInternal
import CryptoKit

private var srIdentifierKey: UInt8 = 11
extension UIImage: DatadogExtended {}
extension DatadogExtension where ExtendedType: UIImage {
    var srIdentifier: String {
        if let hash = objc_getAssociatedObject(self, &srIdentifierKey) as? String {
            return hash
        } else {
            let hash = computeHash()
            objc_setAssociatedObject(self, &srIdentifierKey, hash, .OBJC_ASSOCIATION_RETAIN)
            return hash
        }
    }

    private func computeHash() -> String {
        guard let imageData = type.pngData() else {
            return ""
        }
        if #available(iOS 13.0, *) {
            return Insecure.MD5.hash(data: imageData).map { String(format: "%02hhx", $0) }.joined()
        } else {
            return "\(type.hash)"
        }
    }
}

extension UIColor {
    var srIdentifier: String {
        if let hash = objc_getAssociatedObject(self, &srIdentifierKey) as? String {
            return hash
        } else {
            let hash = computeIdentifier()
            objc_setAssociatedObject(self, &srIdentifierKey, hash, .OBJC_ASSOCIATION_RETAIN)
            return hash
        }
    }

    private func computeIdentifier() -> String {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X%02X", Int(round(r * 255)), Int(round(g * 255)), Int(round(b * 255)), Int(round(a * 255)))
    }
}
#endif
