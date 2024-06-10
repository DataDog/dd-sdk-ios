/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if canImport(UIKit)
import UIKit
#endif

/// A type providing the vendor identifier of the device.
internal protocol VendorIdProvider {
    /// The vendor identifier of the device.
    var vendorId: String? { get }
}

extension UIDevice: VendorIdProvider {
    var vendorId: String? {
        let device = UIDevice.current
        return device.identifierForVendor?.uuidString
    }
}
