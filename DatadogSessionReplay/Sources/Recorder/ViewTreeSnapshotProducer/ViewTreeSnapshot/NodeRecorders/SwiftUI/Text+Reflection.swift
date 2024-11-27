/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation

extension StyledTextContentView: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        text = try mirror.descendant("text")
    }
}

extension ResolvedStyledText.StringDrawing: Reflection {
    init(_ mirror: ReflectionMirror) throws {
        storage = try mirror.descendant("storage")
    }
}

#endif
