/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import UIKit

internal extension UIApplication {
    /// `UIApplication.shared` does not compile in some environments (e.g. notification service app extension), resulting with:
    /// _"shared' is unavailable in application extensions for iOS: Use view controller based solutions where appropriate instead"_.
    ///
    /// As a workaround, this `managedShared` utility provides a key-path access to the `UIApplication.shared` to make the compiler pass.
    static var managedShared: UIApplication? {
        return UIApplication
            .value(forKeyPath: #keyPath(UIApplication.shared)) as? UIApplication // swiftlint:disable:this unsafe_uiapplication_shared
    }
}

internal extension UIViewController {
    /// The canonical class name for this view controller.
    /// If this `UIViewController` class is defined in Swift module, it will be prefixed by the module name, e.g. `Foo.CheckoutViewController`. 
    var canonicalClassName: String {
        return NSStringFromClass(type(of: self))
    }
}

internal extension Bundle {
    var isUIKit: Bool {
        return bundleURL.lastPathComponent == "UIKitCore.framework" // on iOS 12+
            || bundleURL.lastPathComponent == "UIKit.framework" // on iOS 11
    }
}
