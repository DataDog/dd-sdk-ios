/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import Foundation

@_spi(Internal)
@testable import DatadogSessionReplay

class SRDataModelsTests: XCTestCase {
    func testShapeStyleInitWithNaNValues() throws {
        // Given
        let backgroundColor = "#FF0000FF"
        let nanCornerRadius = Double.nan
        let nanOpacity = Double.nan

        // When
        let shapeStyle = SRShapeStyle(
            backgroundColor: backgroundColor,
            cornerRadius: nanCornerRadius,
            opacity: nanOpacity
        )

        // Then
        XCTAssertEqual(shapeStyle.backgroundColor, backgroundColor)
        XCTAssertNil(shapeStyle.cornerRadius, "NaN cornerRadius should be converted to nil")
        XCTAssertNil(shapeStyle.opacity, "NaN opacity should be converted to nil")
    }

    func testShapeStyleInitWithValidValues() throws {
        // Given
        let backgroundColor = "#FF0000FF"
        let cornerRadius = 10.0
        let opacity = 0.8

        // When
        let shapeStyle = SRShapeStyle(
            backgroundColor: backgroundColor,
            cornerRadius: cornerRadius,
            opacity: opacity
        )

        // Then
        XCTAssertEqual(shapeStyle.backgroundColor, backgroundColor)
        XCTAssertEqual(shapeStyle.cornerRadius, cornerRadius)
        XCTAssertEqual(shapeStyle.opacity, opacity)
    }
}
#endif
