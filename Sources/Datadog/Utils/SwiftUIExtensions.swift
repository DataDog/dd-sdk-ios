/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

#if canImport(SwiftUI)
import SwiftUI
#endif

internal extension Bundle {
    /// Returns `true` when `self` represents the `SwiftUI` framework bundle.
    var isSwiftUI: Bool {
        return bundleURL.lastPathComponent == "SwiftUI.framework"
    }
}

#if canImport(SwiftUI)
@available(iOS 13, tvOS 13, *)
internal extension SwiftUI.View {
    /// The Type descriptionof this view.
    var typeDescription: String {
        return String(describing: type(of: self))
    }
}
#endif
