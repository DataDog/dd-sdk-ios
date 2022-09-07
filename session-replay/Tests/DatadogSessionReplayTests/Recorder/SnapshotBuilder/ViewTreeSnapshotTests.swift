/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

// swiftlint:disable opening_brace
class ViewAttributesTests: XCTestCase {
    func testItCapturesViewAttributes() {
        // Given
        let view: UIView = .mockRandom()

        // When
        let attributes = ViewAttributes(frameInRootView: view.frame, view: view)

        // Then
        XCTAssertEqual(attributes.frame, view.frame)
        XCTAssertEqual(attributes.backgroundColor, view.backgroundColor?.cgColor)
        XCTAssertEqual(attributes.layerBorderColor, view.layer.borderColor)
        XCTAssertEqual(attributes.layerBorderWidth, view.layer.borderWidth)
        XCTAssertEqual(attributes.layerCornerRadius, view.layer.cornerRadius)
        XCTAssertEqual(attributes.intrinsicContentSize, view.intrinsicContentSize)
        XCTAssertEqual(attributes.alpha, view.alpha)
    }

    func testWhenViewIsVisible() {
        // Given
        let view: UIView = .mockRandom()

        // When
        view.isHidden = false
        view.alpha = .mockRandom(min: 0.01, max: 1.0)
        view.frame = .mockRandom(minWidth: 0.01, minHeight: 0.01)

        // Then
        let attributes = ViewAttributes(frameInRootView: view.frame, view: view)
        XCTAssertTrue(attributes.isVisible)
    }

    func testWhenViewIsNotVisible() {
        // Given
        let view: UIView = .mockRandom()

        // When
        oneOrMoreOf([
            { view.isHidden = true },
            { view.alpha = 0 },
            { view.frame = .zero },
        ])

        // Then
        let attributes = ViewAttributes(frameInRootView: view.frame, view: view)
        XCTAssertFalse(attributes.isVisible)
    }

    func testWhenViewHasSomeAppearance() {
        // Given
        let view: UIView = .mockRandom()

        // When
        view.isHidden = false
        view.alpha = .mockRandom(min: 0.01, max: 1.0)
        view.frame = .mockRandom(minWidth: 0.01, minHeight: 0.01)
        oneOf([
            {
                view.layer.borderWidth = .mockRandom(min: 0.01, max: 10)
                view.layer.borderColor = UIColor.mockRandomWith(alpha: .mockRandom(min: 0.01, max: 1)).cgColor
            },
            {
                view.backgroundColor = .mockRandomWith(alpha: .mockRandom(min: 0.01, max: 1))
            }
        ])

        // Then
        let attributes = ViewAttributes(frameInRootView: view.frame, view: view)
        XCTAssertTrue(attributes.hasAnyAppearance)
    }

    func testWhenViewHasNoAppearance() {
        // Given
        let view: UIView = .mockRandom()

        // When
        oneOf([
            {
                view.isHidden = false
                view.alpha = 0
                view.frame = .zero
            },
            {
                view.layer.borderWidth = 0
                view.layer.borderColor = UIColor.mockRandomWith(alpha: 0).cgColor
                view.backgroundColor = .mockRandomWith(alpha: 0)
            }
        ])

        // Then
        let attributes = ViewAttributes(frameInRootView: view.frame, view: view)
        XCTAssertFalse(attributes.hasAnyAppearance)
    }
}
// swiftlint:enable opening_brace

class NodeSemanticsTests: XCTestCase {
    func testSemanticsImportance() {
        let unknownElement = UnknownElement.constant
        let invisibleElement = InvisibleElement.constant
        let ambiguousElement = AmbiguousElement(wireframesBuilder: nil)
        let specificElement = SpecificElement(wireframesBuilder: nil)

        XCTAssertGreaterThan(specificElement.importance, ambiguousElement.importance)
        XCTAssertGreaterThan(ambiguousElement.importance, invisibleElement.importance)
        XCTAssertGreaterThan(invisibleElement.importance, unknownElement.importance)
        XCTAssertEqual(specificElement.importance, .max)
    }
}
