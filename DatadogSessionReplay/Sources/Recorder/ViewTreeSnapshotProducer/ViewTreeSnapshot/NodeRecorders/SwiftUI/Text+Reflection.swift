/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation

extension StyledTextContentView: Reflection {
    init(from reflector: Reflector) throws {
        text = try reflector.descendant("text")
    }
}

extension ResolvedStyledText.StringDrawing: Reflection {
    init(from reflector: Reflector) throws {
        storage = try reflector.descendant("storage")
    }
}

#endif
