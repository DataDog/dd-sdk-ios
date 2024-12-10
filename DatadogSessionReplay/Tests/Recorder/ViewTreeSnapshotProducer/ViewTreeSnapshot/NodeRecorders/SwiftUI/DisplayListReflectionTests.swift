/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import SwiftUI
@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
class DisplayListReflectionTests: XCTestCase {
    // MARK: Text
    func testDisplayList_withMockedTextContent() throws {
        let text: String = .mockRandom()
        let textSize: CGSize = .mockAny()

        let mockText = StyledTextContentView(text: ResolvedStyledText.StringDrawing(storage: NSAttributedString(attributedString: NSAttributedString(string: text))))
        let mockMirror = ReflectionMirror(reflecting: mockText)
        let styledTextContent = try StyledTextContentView(mockMirror)
        let textContent = DisplayList.Content(
            seed: .init(value: .mockRandom()),
            value: .text(styledTextContent, textSize)
        )
        let displayList = DisplayList(items: [
            DisplayList.Item(
                identity: .init(value: .mockRandom()),
                frame: CGRect(x: 0, y: 0, width: textSize.width, height: textSize.height),
                value: .content(textContent)
            )
        ])

        XCTAssertEqual(displayList.items.count, 1)
        if case let .content(content) = displayList.items[0].value,
           case let .text(styledText, size) = content.value {
            XCTAssertEqual(styledText.text.storage.string, text)
            XCTAssertEqual(size.width, textSize.width)
            XCTAssertEqual(size.height, textSize.height)
        } else {
            XCTFail("DisplayList does not contain the expected text content.")
        }
    }

    func testDisplayList_withEmptyTextContent() throws {
        let text = ""
        let textSize: CGSize = .mockAny()

        let mockText = StyledTextContentView(
            text: ResolvedStyledText.StringDrawing(
                storage: NSAttributedString(string: text)
            )
        )
        let mockMirror = ReflectionMirror(reflecting: mockText)
        let styledTextContent = try StyledTextContentView(mockMirror)
        let textContent = DisplayList.Content(
            seed: .init(value: .mockRandom()),
            value: .text(styledTextContent, CGSize(width: textSize.width, height: textSize.height))
        )
        let displayList = DisplayList(items: [
            DisplayList.Item(
                identity: .init(value: .mockRandom()),
                frame: CGRect(x: 0, y: 0, width: textSize.width, height: textSize.height),
                value: .content(textContent)
            )
        ])

        XCTAssertEqual(displayList.items.count, 1)
        if case let .content(content) = displayList.items[0].value,
           case let .text(styledText, size) = content.value {
            XCTAssertEqual(styledText.text.storage.string, text)
            XCTAssertEqual(size.width, textSize.width)
            XCTAssertEqual(size.height, textSize.height)
        } else {
            XCTFail("DisplayList does not handle empty text correctly.")
        }
    }

    func testDisplayList_withMultilineTextContent() throws {
        let text: String = .mockRandom() + "\n" + .mockRandom()
        let textSize: CGSize = .mockAny()

        let mockText = StyledTextContentView(
            text: ResolvedStyledText.StringDrawing(
                storage: NSAttributedString(string: text)
            )
        )
        let mockMirror = ReflectionMirror(reflecting: mockText)

        let styledTextContent = try StyledTextContentView(mockMirror)

        let textContent = DisplayList.Content(
            seed: .init(value: .mockRandom()),
            value: .text(styledTextContent, CGSize(width: textSize.width, height: textSize.height))
        )

        let displayList = DisplayList(items: [
            DisplayList.Item(
                identity: .init(value: .mockRandom()),
                frame: CGRect(x: 0, y: 0, width: textSize.width, height: textSize.height),
                value: .content(textContent)
            )
        ])

        XCTAssertEqual(displayList.items.count, 1)
        if case let .content(content) = displayList.items[0].value,
           case let .text(styledText, size) = content.value {
            XCTAssertEqual(styledText.text.storage.string, text)
            XCTAssertEqual(size.width, textSize.width)
            XCTAssertEqual(size.height, textSize.height)
        } else {
            XCTFail("DisplayList does not handle multi-line text correctly.")
        }
    }

    // MARK: Shape
    func testDisplayList_withShapeContent() throws {
        let shapeColor = Color._Resolved(
            linearRed: .mockRandom(min: 0, max: 1),
            linearGreen: .mockRandom(min: 0, max: 1),
            linearBlue: .mockRandom(min: 0, max: 1),
            opacity: .mockRandom(min: 0, max: 1)
        )
        let shapeContent = DisplayList.Content(
            seed: .init(value: .mockRandom()),
            value: .shape(
                SwiftUI.Path(),
                ResolvedPaint(
                    paint: shapeColor
                ),
                SwiftUI.FillStyle()
            )
        )

        let displayList = DisplayList(items: [
            DisplayList.Item(
                identity: .init(value: .mockRandom()),
                frame: .mockRandom(),
                value: .content(shapeContent)
            )
        ])

        XCTAssertEqual(displayList.items.count, 1)
        if case let .content(content) = displayList.items[0].value,
           case let .shape(_, paint, _) = content.value {
            XCTAssertEqual(paint.paint?.linearRed, shapeColor.linearRed)
            XCTAssertEqual(paint.paint?.linearGreen, shapeColor.linearGreen)
            XCTAssertEqual(paint.paint?.linearBlue, shapeColor.linearBlue)
            XCTAssertEqual(paint.paint?.opacity, shapeColor.opacity)
        } else {
            XCTFail("DisplayList does not handle shape content correctly.")
        }
    }

    // MARK: Image
    func testDisplayList_withImageContent() throws {
        let cgImage: CGImage = MockCGImage.mockWith(width: 20)
        let imageContent = DisplayList.Content(
            seed: .init(value: .mockRandom()),
            value: .image(
                .init(
                    contents: .cgImage(cgImage),
                    scale: [1, 2, 3].randomElement()!,
                    orientation: .mockRandom()
                    )
                )
            )

        let displayList = DisplayList(items: [
            DisplayList.Item(
                identity: .init(value: .mockRandom()),
                frame: .mockRandom(),
                value: .content(imageContent)
            )
        ])

        XCTAssertEqual(displayList.items.count, 1)
        if case let .content(content) = displayList.items[0].value,
           case let .image(resolvedImage) = content.value {
            XCTAssertNotNil(resolvedImage.contents)
        } else {
            XCTFail("DisplayList does not handle image content correctly.")
        }
    }

    // MARK: Unknown Content
    func testDisplayList_withUnknownContent() throws {
        let unknownContent = DisplayList.Content(
            seed: .init(value: .mockRandom()),
            value: .unknown
        )
        let displayList = DisplayList(items: [
            DisplayList.Item(
                identity: .init(value: .mockRandom()),
                frame: .mockRandom(),
                value: .content(unknownContent)
            )
        ])

        XCTAssertEqual(displayList.items.count, 1)
        if case let .content(content) = displayList.items[0].value,
           case .unknown = content.value {
            XCTAssertTrue(true)
        } else {
            XCTFail("DisplayList should contain a content value.")
        }
    }
}
#endif
