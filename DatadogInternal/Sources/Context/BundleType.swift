/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public enum BundleType: String, CaseIterable {
    /// An iOS application.
    case iOSApp
    /// An iOS app extension.
    case iOSAppExtension

    public init(bundle: Bundle) {
        self = bundle.bundlePath.hasSuffix(".appex") ? .iOSAppExtension : .iOSApp
    }
}
