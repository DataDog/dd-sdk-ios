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
        let styledTextContent: StyledTextContentView = .mockRandom()

        let reflector = Reflector(subject: styledTextContent, telemetry: NOPTelemetry())
        let reflectedContent = try StyledTextContentView(from: reflector)

        XCTAssertEqual(reflectedContent.text.storage.string, styledTextContent.text.storage.string)
    }

    func testResolvedStyledTextStringDrawingReflection() throws {
        let stringDrawing: ResolvedStyledText.StringDrawing = .mockRandom()

        let reflector = Reflector(subject: stringDrawing, telemetry: NOPTelemetry())
        let reflectedStringDrawing = try ResolvedStyledText.StringDrawing(from: reflector)

        XCTAssertEqual(reflectedStringDrawing.storage.string, stringDrawing.storage.string)
    }

    func testStyledTextContentViewReflection_withEmptyText() throws {
        let emptyText = ""
        let styledTextContent = StyledTextContentView(
            text: ResolvedStyledText.StringDrawing(storage: NSAttributedString(string: emptyText))
        )

        let reflector = Reflector(subject: styledTextContent, telemetry: NOPTelemetry())
        let reflectedContent = try StyledTextContentView(from: reflector)

        XCTAssertEqual(reflectedContent.text.storage.string, emptyText)
    }
}
#endif
