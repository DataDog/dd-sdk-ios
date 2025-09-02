/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

extension UIColor {
    convenience init(hexString: String) {
        precondition(hexString.count == 9, "Invalid `hexString` - expected 9 characters, got '\(hexString)'")
        precondition(hexString.hasPrefix("#"), "Invalid `hexString` - expected # prefix, got '\(hexString)'")

        guard let hex8 = UInt64(hexString.dropFirst(), radix: 16) else {
            preconditionFailure("Invalid `hexString`` - expected hexadecimal value, got '\(hexString)'")
        }

        let mask: UInt64 = 0x00000000FF
        self.init(
            red: CGFloat((hex8 >> 24) & mask) / CGFloat(255),
            green: CGFloat((hex8 >> 16) & mask) / CGFloat(255),
            blue: CGFloat((hex8 >> 8) & mask) / CGFloat(255),
            alpha: CGFloat(hex8 & mask) / CGFloat(255)
        )
    }
}
