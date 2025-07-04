/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import SwiftUI
import DatadogInternal
import TestUtilities
@testable import DatadogSessionReplay

@available(iOS 13.0, tvOS 13.0, *)
class DisplayListReflectionTests: XCTestCase {
    // MARK: Text
    func testDisplayList_withTextContent() throws {
        let textCases: [String] = [
            // Random text
            .mockRandom(),
            // Empty text
            "",
            // Multiline text
            .mockRandom() + "\n" + .mockRandom()
        ]

        for text in textCases {
            let textSize: CGSize = .mockAny()
            let styledText = StyledTextContentView(text: ResolvedStyledText.StringDrawing(storage: NSAttributedString(string: text)))
            let content = DisplayList.Content(
                seed: .init(value: .mockRandom()),
                value: .text(styledText, textSize)
            )

            let displayList = DisplayList(items: [
                DisplayList.Item(
                    identity: .init(value: .mockRandom()),
                    frame: CGRect(x: 0, y: 0, width: textSize.width, height: textSize.height),
                    value: .content(content)
                )
            ])

            let reflector = Reflector(subject: displayList, telemetry: NOPTelemetry())
            let reflectedList = try DisplayList(from: reflector)

            XCTAssertEqual(reflectedList.items.count, 1)
            if case let .content(reflectedContent) = reflectedList.items[0].value,
               case let .text(reflectedText, size) = reflectedContent.value {
                XCTAssertEqual(reflectedText.text.storage.string, text)
                XCTAssertEqual(size, textSize)
            } else {
                XCTFail("Failed to reflect DisplayList with text content.")
            }
        }
    }

    // MARK: Shape
    func testDisplayList_withShapeContent() throws {
        let color = Color._Resolved.mockRandom()
        let path: SwiftUI.Path = [
            SwiftUI.Path { $0.move(to: CGPoint.zero); $0.addLine(to: CGPoint(x: 10, y: 10)) },
            SwiftUI.Path(),
            SwiftUI.Path { $0.addRect(CGRect(x: 0, y: 0, width: 50, height: 50)) }
        ].randomElement()!
        let fillStyle: SwiftUI.FillStyle = [
            SwiftUI.FillStyle(eoFill: false, antialiased: true),
            SwiftUI.FillStyle(eoFill: true, antialiased: false)
        ].randomElement()!

        let shapeContent = DisplayList.Content(
            seed: .init(value: .mockRandom()),
            value: .shape(
                path,
                ResolvedPaint(
                    paint: color
                ),
                fillStyle
            )
        )

        let displayList = DisplayList(items: [
            DisplayList.Item(
                identity: .init(value: .mockRandom()),
                frame: .mockRandom(),
                value: .content(shapeContent)
            )
        ])

        let reflector = Reflector(subject: displayList, telemetry: NOPTelemetry())
        let reflectedList = try DisplayList(from: reflector)

        XCTAssertEqual(reflectedList.items.count, 1)
        if case let .content(reflectedContent) = reflectedList.items[0].value,
           case let .shape(reflectedPath, reflectedPaint, reflectedFillStyle) = reflectedContent.value {
            XCTAssertEqual(reflectedPaint.paint?.linearRed, color.linearRed)
            XCTAssertEqual(reflectedPaint.paint?.linearGreen, color.linearGreen)
            XCTAssertEqual(reflectedPaint.paint?.linearBlue, color.linearBlue)
            XCTAssertEqual(reflectedPaint.paint?.opacity, color.opacity)
            XCTAssertEqual(reflectedFillStyle, fillStyle, "Reflected fill style does not match.")
            XCTAssertEqual(reflectedPath.description, path.description, "Reflected path does not match.")
        } else {
            XCTFail("DisplayList does not handle shape content correctly.")
        }
    }

    // MARK: Image
    func testDisplayList_withImageContent() throws {
        let cgImage: CGImage = MockCGImage.mockWith(width: 20)
        let graphicsImage = GraphicsImage(
            contents: .cgImage(cgImage),
            scale: [1, 2, 3].randomElement()!,
            orientation: .mockRandom()
        )
        let imageContent = DisplayList.Content(
            seed: .init(value: .mockRandom()),
            value: .image(graphicsImage)
        )

        let displayList = DisplayList(items: [
            DisplayList.Item(
                identity: .init(value: .mockRandom()),
                frame: .mockRandom(),
                value: .content(imageContent)
            )
        ])

        let reflector = Reflector(subject: displayList, telemetry: NOPTelemetry())
        let reflectedList = try DisplayList(from: reflector)

        XCTAssertEqual(reflectedList.items.count, 1)
        if case let .content(content) = reflectedList.items[0].value,
           case let .image(reflectedImage) = content.value {
            XCTAssertNotNil(reflectedImage.contents)
            XCTAssertEqual(reflectedImage.contents, graphicsImage.contents)
            XCTAssertEqual(reflectedImage.scale, graphicsImage.scale)
            XCTAssertEqual(reflectedImage.orientation, graphicsImage.orientation)
        } else {
            XCTFail("DisplayList does not handle image content correctly.")
        }
    }

    // MARK: Unknown Content
    func testDisplayList_withUnknownContent2() throws {
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

        let reflector = Reflector(subject: displayList, telemetry: NOPTelemetry())
        let reflectedList = try DisplayList(from: reflector)

        XCTAssertEqual(reflectedList.items.count, 1)
        if case let .content(content) = reflectedList.items[0].value,
           case .unknown = content.value {
            XCTAssertTrue(true)
        } else {
            XCTFail("DisplayList should contain a content value.")
        }
    }
}
#endif
