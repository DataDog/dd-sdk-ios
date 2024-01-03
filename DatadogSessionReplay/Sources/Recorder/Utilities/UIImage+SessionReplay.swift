/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit
import CryptoKit

private var recordedKey: UInt8 = 22
extension UIImage {
    var srIdentifier: String {
        return customHash
    }

    var recorded: Bool {
        get {
            return objc_getAssociatedObject(self, &recordedKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &recordedKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

extension UIColor {
    var srIdentifier: String {
        return "\(hash)"
    }
}

private var customHashKey: UInt8 = 11
fileprivate extension UIImage {
    private static var associatedObjectQueue = DispatchQueue(label: "com.datadoghq.customHashQueue")

    var customHash: String {
        return UIImage.associatedObjectQueue.sync {
            if let hash = objc_getAssociatedObject(self, &customHashKey) as? String {
                return hash
            }

            let hash = computeHash()
            objc_setAssociatedObject(self, &customHashKey, hash, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return hash
        }
    }

    private func computeHash() -> String {
        guard let imageData = self.pngData() else {
            return ""
        }
        if #available(iOS 13.0, *) {
            return Insecure.MD5.hash(data: imageData).map { String(format: "%02hhx", $0) }.joined()
        } else {
            return "\(hash)"
        }
    }
}
#endif
