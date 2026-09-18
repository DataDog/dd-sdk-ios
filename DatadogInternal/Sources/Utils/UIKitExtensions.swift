/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

#if !os(watchOS) && !os(macOS)
import Foundation
import UIKit

extension DatadogExtension where ExtendedType == UIApplication {
    /// `UIApplication.shared` does not compile in some environments (e.g. notification service app extension), resulting with:
    /// _"shared' is unavailable in application extensions for iOS: Use view controller based solutions where appropriate instead"_.
    ///
    /// As a workaround, this `managedShared` utility provides a key-path access to the `UIApplication.shared` to make the compiler pass.
    public static var managedShared: UIApplication? {
        return DDApplication
            .value(forKeyPath: #keyPath(UIApplication.shared)) as? UIApplication // swiftlint:disable:this unsafe_uiapplication_shared
    }
}

extension UIApplication: DatadogExtended { }
#elseif os(macOS)
import Foundation
import AppKit

extension DatadogExtension where ExtendedType == NSApplication {
    /// On macOS, simply return `NSApplication.shared`.
    ///
    /// AppKit does not have the same problem as UIKit in extensions, so this is not really needed. However, the API exists to maintain
    /// compatibility with SDK code that calls `managedShared`.
    public static var managedShared: NSApplication? {
        NSApplication.shared
    }
}

extension NSApplication: DatadogExtended { }
#endif
