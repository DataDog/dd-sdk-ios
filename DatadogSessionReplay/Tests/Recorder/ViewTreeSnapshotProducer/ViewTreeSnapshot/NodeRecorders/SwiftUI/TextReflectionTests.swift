/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import DatadogInternal
import CoreGraphics
import SwiftUI
@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
class TextReflectionTests: XCTestCase {
    func testStyledTextContentViewReflection() throws {
        let text: String = .mockRandom()
        let textContentView = StyledTextContentView(
            text: ResolvedStyledText.StringDrawing(
                storage: NSAttributedString(string: text)
            )
        )

        XCTAssertEqual(textContentView.text.storage.string, text)
    }

    func testStyledTextContentViewReflection_withEmptyText() throws {
        let text = ""
        let textContentView = StyledTextContentView(
            text: ResolvedStyledText.StringDrawing(
                storage: NSAttributedString(string: text)
            )
        )

        XCTAssertEqual(textContentView.text.storage.string, text)
    }
}
#endif
