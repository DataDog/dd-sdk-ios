/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

#if os(iOS)
import XCTest
import SwiftUI
import DatadogInternal
import TestUtilities

@_spi(Internal)
@testable import DatadogSessionReplay

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
}

#endif
