/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

#if os(macOS)
import AppKit
#else
import UIKit
#endif

internal extension DDView {
    /// Returns a string describing the type of the view.
    ///
    /// This must not be `@objc`: callers would then dispatch it through the Objective-C runtime and only reference
    /// its selector, so a static linker could drop this file from the `DatadogRUM` library (e.g. in non-WMO Debug builds
    /// without `-ObjC`), leaving `typeDescription` unregistered and crashing with "unrecognized selector".
    var typeDescription: String {
        return String(describing: type(of: self))
    }
}

#endif
