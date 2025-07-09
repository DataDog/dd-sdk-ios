/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

#if os(iOS)
import XCTest
import SwiftUI
@_spi(Internal)
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import DatadogInternal

@available(iOS 13.0, tvOS 13.0, *)
class SwiftUIWireframesBuilderTests: XCTestCase {
    func testDisplayListWithUnknownContent_itReturnsAPlaceholder() throws {
        // Given
        // - DisplayList with unknown content
        let renderer = DisplayList.ViewUpdater(
            viewCache: DisplayList.ViewUpdater.ViewCache(map: [:]),
            lastList: DisplayList.Lazy(
                DisplayList(items: [
                    DisplayList.Item(
                        identity: DisplayList.Identity(value: .mockRandom()),
                        frame: .mockAny(),
                        value: .content(DisplayList.Content(
                            seed: DisplayList.Seed(value: .mockRandom()),
                            value: .unknown
                        ))
                    )
                ])
            )
        )

        let builder = SwiftUIWireframesBuilder(
            wireframeID: .mockRandom(),
            renderer: renderer,
            textObfuscator: TextObfuscatorMock(),
            fontScalingEnabled: true,
            imagePrivacyLevel: .maskNone,
            attributes: .mockRandom()
        )

        // When
        let wireframes = builder.buildWireframes(with: WireframesBuilder())

        // Then
        let wireframe = try XCTUnwrap(wireframes.last?.placeholderWireframe)
        XCTAssertEqual(wireframe.label, "Unsupported SwiftUI component")
    }

    // MARK: Drawing Content (iOS 26+ Toolbar Items)
    func testDisplayListWithToolbarItem_itCreatesTextWireframeOniOS26() throws {
        guard #available(iOS 26, tvOS 26, *) else {
            return
        }

        let testCases: [(String, String)] = [
            ("Cancel", "Cancel"),
            ("", ""),
            ("Save & Continue", "Save & Continue"),
            ("📱 Settings", "📱 Settings"),
            ("Multi\nLine", "Multi\nLine"),
            ("   Spaces   ", "   Spaces   "),
        ]

        for (inputText, expectedText) in testCases {
            // Given
            let renderer = DisplayList.ViewUpdater(
                viewCache: DisplayList.ViewUpdater.ViewCache(map: [:]),
                lastList: DisplayList.Lazy(
                    DisplayList(items: [
                        DisplayList.Item(
                            identity: DisplayList.Identity(value: .mockRandom()),
                            frame: CGRect(x: 0, y: 0, width: 100, height: 44),
                            value: .content(DisplayList.Content(
                                seed: DisplayList.Seed(value: .mockRandom()),
                                value: .drawingWithText(inputText)
                            ))
                        )
                    ])
                )
            )

            // When
            let builder = SwiftUIWireframesBuilder(
                wireframeID: .mockRandom(),
                renderer: renderer,
                textObfuscator: TextObfuscatorMock(),
                fontScalingEnabled: true,
                imagePrivacyLevel: .maskNone,
                attributes: .mockRandom()
            )

            // Then
            let wireframes = builder.buildWireframes(with: WireframesBuilder())
            XCTAssertEqual(wireframes.count, 2, "Should create 2 wireframes for text: '\(inputText)'")
            let textWireframe = try XCTUnwrap(wireframes.last?.textWireframe, "Should create text wireframe for: '\(inputText)'")
            XCTAssertEqual(textWireframe.text, expectedText, "Text wireframe should match expected text for: '\(inputText)'")
        }
    }

    func testDisplayListWithDrawingContent_whenDrawingIsNil_itCreatesPlaceholderWireframe() throws {
        guard #available(iOS 26, tvOS 26, *) else {
            return
        }

        // Given
        let renderer = DisplayList.ViewUpdater(
            viewCache: DisplayList.ViewUpdater.ViewCache(map: [:]),
            lastList: DisplayList.Lazy(
                DisplayList(items: [
                    DisplayList.Item(
                        identity: DisplayList.Identity(value: .mockRandom()),
                        frame: CGRect(x: 0, y: 0, width: 100, height: 44),
                        value: .content(DisplayList.Content(
                            seed: DisplayList.Seed(value: .mockRandom()),
                            value: .unknown
                        ))
                    )
                ])
            )
        )

        // When
        let builder = SwiftUIWireframesBuilder(
            wireframeID: .mockRandom(),
            renderer: renderer,
            textObfuscator: TextObfuscatorMock(),
            fontScalingEnabled: true,
            imagePrivacyLevel: .maskNone,
            attributes: .mockRandom()
        )

        // Then
        let wireframes = builder.buildWireframes(with: WireframesBuilder())
        XCTAssertEqual(wireframes.count, 2, "Should create 2 wireframes for nil drawing content")
        let placeholderWireframe = try XCTUnwrap(wireframes.last?.placeholderWireframe, "Should create placeholder wireframe for nil drawing")
        XCTAssertEqual(placeholderWireframe.label, "Unsupported SwiftUI component", "Should show appropriate placeholder message for nil drawing")
    }
}
#endif
