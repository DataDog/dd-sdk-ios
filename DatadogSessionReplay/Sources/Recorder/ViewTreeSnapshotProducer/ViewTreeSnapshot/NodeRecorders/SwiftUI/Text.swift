/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

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

extension StyledTextContentView: STDReflection {
    init(_ mirror: Mirror) throws {
        text = try mirror.descendant(path: "text")
    }
}

extension ResolvedStyledText.StringDrawing: STDReflection {
    init(_ mirror: Mirror) throws {
        storage = try mirror.descendant(path: "storage")
    }
}

//=================================================================================

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
