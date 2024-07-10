/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay
@testable import TestUtilities

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
        XCTAssertEqual(attributes.alpha, view.alpha)
        XCTAssertEqual(attributes.isHidden, view.isHidden)
        XCTAssertEqual(attributes.intrinsicContentSize, view.intrinsicContentSize)
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

    func testWhenViewIsTranslucent() {
        // Given
        let view: UIView = .mockRandom()

        // When
        oneOrMoreOf([
            { view.isHidden = true },
            { view.alpha = .mockRandom(min: 0, max: 0.99) },
            { view.frame = .zero },
            { view.backgroundColor = .mockRandomWith(alpha: .mockRandom(min: 0, max: 0.99)) }
        ])

        // Then
        let attributes = ViewAttributes(frameInRootView: view.frame, view: view)
        XCTAssertTrue(attributes.isTranslucent)
    }

    func testWhenViewIsNotTranslucent() {
        // Given
        let view: UIView = .mockRandom()

        // When
        view.alpha = 1
        view.isHidden = false
        view.frame = .mockRandom(minWidth: 10, minHeight: 10)
        view.backgroundColor = .mockRandomWith(alpha: 1)

        // Then
        let attributes = ViewAttributes(frameInRootView: view.frame, view: view)
        XCTAssertFalse(attributes.isTranslucent)
    }

    func testItSanitizesInvalidRuntimeAttributes() {
        // Given
        let view = UIView(frame: .zero)
        view.setValue("invalid color", forKeyPath: "layer.borderColor")

        // When
        let attributes = ViewAttributes(frameInRootView: view.frame, view: view)

        // Then
        XCTAssertNil(attributes.layerBorderColor)
    }

    func testWhenCopy() {
        let view: UIView = .mockRandom()
        let rect: CGRect = .mockRandom()
        let color: CGColor = .mockRandom()
        let float: CGFloat = .mockRandom()
        let boolean: Bool = .mockRandom()
        let attributes = ViewAttributes(frameInRootView: view.frame, view: view).copy {
            $0.frame = rect
            $0.backgroundColor = color
            $0.layerBorderColor = color
            $0.layerBorderWidth = float
            $0.layerCornerRadius = float
            $0.alpha = float
            $0.isHidden = boolean
            $0.intrinsicContentSize = rect.size
        }
        XCTAssertEqual(attributes.frame, rect)
        XCTAssertEqual(attributes.backgroundColor, color)
        XCTAssertEqual(attributes.layerBorderColor, color)
        XCTAssertEqual(attributes.layerBorderWidth, float)
        XCTAssertEqual(attributes.layerCornerRadius, float)
        XCTAssertEqual(attributes.alpha, float)
        XCTAssertEqual(attributes.isHidden, boolean)
        XCTAssertEqual(attributes.intrinsicContentSize, rect.size)
    }
}
// swiftlint:enable opening_brace

class NodeSemanticsTests: XCTestCase {
    func testImportance() {
        let unknownElement = UnknownElement.constant
        let invisibleElement = InvisibleElement.constant
        let ambiguousElement = AmbiguousElement(nodes: [])
        let specificElement = SpecificElement(subtreeStrategy: .mockAny(), nodes: [])

        XCTAssertGreaterThan(
            specificElement.importance,
            ambiguousElement.importance,
            "`SpecificElement` should override `AmbiguousElement` semantics"
        )
        XCTAssertGreaterThanOrEqual(
            invisibleElement.importance,
            ambiguousElement.importance,
            """
            `InvisibleElement` should override `AmbiguousElement` semantics - as invisibility
            can be noticed in specialised recorers by determining empty state for certain
            `UIView` subclass (e.g. no text in `UILabel` which has no other appearance but is visible)
            """
        )
        XCTAssertGreaterThan(invisibleElement.importance, unknownElement.importance, "All semantics should override `UnknownElement`")
        XCTAssertGreaterThan(ambiguousElement.importance, unknownElement.importance, "All semantics should override `UnknownElement`")
        XCTAssertGreaterThan(specificElement.importance, unknownElement.importance, "All semantics should override `UnknownElement`")
        XCTAssertEqual(specificElement.importance, .max)
    }

    func testSubtreeStrategy() {
        DDAssertReflectionEqual(
            UnknownElement.constant.subtreeStrategy,
            .record,
            "Subtree should be recorded for 'unknown' elements as a fallback"
        )
        DDAssertReflectionEqual(
            InvisibleElement.constant.subtreeStrategy,
            .ignore,
            "Subtree should not be recorded for 'invisible' elements as nothing in it will be visible anyway"
        )
    }
}
#endif
