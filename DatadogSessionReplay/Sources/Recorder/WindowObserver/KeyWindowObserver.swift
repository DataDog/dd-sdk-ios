/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import UIKit

/// Finds the key window in current application.
/// Ref.: https://developer.apple.com/documentation/uikit/uiwindow/1621612-iskeywindow
///
/// It is meant to hide the complexity of windows and scenes management among different versions of iOS.
internal class KeyWindowObserver: AppWindowObserver {
    /// Returns the key window of the app.
    var relevantWindow: UIWindow? {
        if #available(iOS 13.0, tvOS 13.0, *) {
            return findONiOS13AndLater()
        } else {
            return nil
        }
    }

    @available(iOS 13.0, tvOS 13.0, *)
    private func findONiOS13AndLater() -> UIWindow? {
        return UIApplication.managedShared?
            .connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

private extension UIApplication {
    /// `UIApplication.shared` does not compile in some environments (e.g. notification service app extension), resulting with:
    /// _"shared' is unavailable in application extensions for iOS: Use view controller based solutions where appropriate instead"_.
    ///
    /// As a workaround, this `managedShared` utility provides a key-path access to the `UIApplication.shared` to make the compiler pass.
    static var managedShared: UIApplication? {
        return UIApplication
            .value(forKeyPath: #keyPath(UIApplication.shared)) as? UIApplication // swiftlint:disable:this unsafe_uiapplication_shared
    }
}
#endif
