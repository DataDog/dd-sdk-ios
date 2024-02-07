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
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        if let hash = objc_getAssociatedObject(self, &srIdentifierKey) as? String {
            return hash
        } else {
            let hash = computeHash()
            objc_setAssociatedObject(self, &srIdentifierKey, hash, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
        return "\(hash)"
    }
}
#endif
