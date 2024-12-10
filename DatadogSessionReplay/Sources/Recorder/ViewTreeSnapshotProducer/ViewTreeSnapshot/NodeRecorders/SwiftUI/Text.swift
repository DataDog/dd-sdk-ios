/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
import SwiftUI

internal struct StyledTextContentView {
    let text: ResolvedStyledText.StringDrawing
}

internal struct ResolvedStyledText {
    internal struct StringDrawing {
        let storage: NSAttributedString
    }
}

#endif
