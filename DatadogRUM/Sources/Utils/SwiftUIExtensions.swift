/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

#if canImport(SwiftUI)
import SwiftUI

internal extension SwiftUI.View {
    /// The Type description of this view.
    var typeDescription: String {
        return String(describing: type(of: self))
    }
}
#endif
