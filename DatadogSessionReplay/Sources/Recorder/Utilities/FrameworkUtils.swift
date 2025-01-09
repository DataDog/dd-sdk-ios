/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI

internal enum FrameworkUtils {
    /// Checks if the given class belongs to the SwiftUI framework.
    static func isSwiftUI(`class`: AnyClass) -> Bool {
        /// Supports both native and custom subclasses
        if #available(iOS 13.0, tvOS 13.0, *) {
            return `class`.isSubclass(of: UIHostingController<AnyView>.self) || Bundle(for: `class`).isSwiftUI
        }
        return Bundle(for: `class`).isSwiftUI
    }

    /// Checks if the given class belongs to the UIKit framework.
    static func isUIKit(`class`: AnyClass) -> Bool {
        /// Supports both native and custom subclasses
        return `class` is UIViewController.Type || Bundle(for: `class`).isUIKit
    }
}
