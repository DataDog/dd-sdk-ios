/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import SwiftUI

@available(iOS 13.0, tvOS 13.0, *)
extension SwiftUI.Color {
    struct _Resolved {
        let linearRed: Float
        let linearGreen: Float
        let linearBlue: Float
        let opacity: Float
    }
}

@available(iOS 13.0, tvOS 13.0, *)
internal struct ResolvedPaint {
    let paint: SwiftUI.Color._Resolved?
}

#endif
