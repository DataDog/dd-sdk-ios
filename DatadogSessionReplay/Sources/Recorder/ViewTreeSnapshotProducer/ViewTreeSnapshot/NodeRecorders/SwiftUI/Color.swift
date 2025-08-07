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

        var uiColor: UIColor {
            UIColor(
                red: CGFloat(linearRed),
                green: CGFloat(linearGreen),
                blue: CGFloat(linearBlue),
                alpha: CGFloat(opacity)
            )
        }
    }

    struct _ResolvedHDR {
        let base: _Resolved
        let _headroom: Float
    }
}

@available(iOS 13.0, tvOS 13.0, *)
internal struct ColorView {
    let color: SwiftUI.Color._ResolvedHDR
}

@available(iOS 13.0, tvOS 13.0, *)
internal struct ResolvedPaint {
    let paint: SwiftUI.Color._Resolved?
}

#endif
