/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Abstraction protocol to get device information on the current platform
public protocol DeviceProtocol {
    var model: String { get }
    var systemName: String { get }
    var systemVersion: String { get }
    var identifierForVendor: UUID? { get }
}

#if canImport(UIKit)
import UIKit

#if canImport(WatchKit)
import WatchKit

extension WKInterfaceDevice: DeviceProtocol {}
#else
extension UIDevice: DeviceProtocol {}
#endif

public enum DeviceFactory {
    /// Get the current device
    public static var current: DeviceProtocol {
        #if canImport(WatchKit)
        WKInterfaceDevice.current()
        #else
        UIDevice.current
        #endif
    }
}
#endif
