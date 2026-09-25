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

/// Protocol defining interface for type description functionality
@objc
internal protocol TypeDescribing {
    /// Returns a string describing the type of the object
    var typeDescription: String { get }
}

/// Default implementation for UIKit views
extension DDView: TypeDescribing {
    /// Returns a string describing the type of the view
    @objc var typeDescription: String {
        return String(describing: type(of: self))
    }
}

#endif
