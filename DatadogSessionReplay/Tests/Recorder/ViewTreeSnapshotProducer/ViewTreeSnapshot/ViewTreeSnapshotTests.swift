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
    // MARK: Appearance
    func testItCapturesViewAttributes() {
        // Given
        let view = UIView.mockRandom()

        // When
        let attributes = createViewAttributes(with: view)

        // Then
        XCTAssertEqual(attributes.frame, view.frame)
        XCTAssertEqual(attributes.clip, view.frame)
        XCTAssertEqual(attributes.backgroundColor, view.backgroundColor?.cgColor)
        XCTAssertEqual(attributes.layerBorderColor, view.layer.borderColor)
        XCTAssertEqual(attributes.layerBorderWidth, view.layer.borderWidth)
        XCTAssertEqual(attributes.layerCornerRadius, view.layer.cornerRadius)
        XCTAssertEqual(attributes.alpha, view.alpha)
        XCTAssertEqual(attributes.isHidden, view.isHidden)
        XCTAssertEqual(attributes.intrinsicContentSize, view.intrinsicContentSize)
        XCTAssertNil(attributes.textAndInputPrivacy)
        XCTAssertNil(attributes.imagePrivacy)
        XCTAssertNil(attributes.touchPrivacy)
        XCTAssertNil(attributes.hide)
    }

    func testWhenViewIsVisible() {
        // Given
        let view: UIView = .mockRandom()

        // When
        view.isHidden = false
        view.alpha = .mockRandom(min: 0.01, max: 1.0)
        view.frame = .mockRandom(minWidth: 0.01, minHeight: 0.01)
        let clip = view.frame.insetBy(dx: 1, dy: 1)
        let attributes = createViewAttributes(with: view, clip: clip)

        // Then
        XCTAssertTrue(attributes.isVisible)
    }

    func testWhenViewIsNotVisible() {
        // Given
        let view: UIView = .mockRandom()
        var clip = view.frame

        // When
        oneOrMoreOf([
            { view.isHidden = true },
            { view.alpha = 0 },
            { view.frame = .zero },
            { clip = clip.offsetBy(dx: clip.width, dy: clip.height) },
        ])

        // Then
        let attributes = createViewAttributes(with: view, clip: clip)
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
            { view.backgroundColor = .mockRandomWith(alpha: .mockRandom(min: 0.01, max: 1)) }
        ])

        // Then
        let attributes = createViewAttributes(with: view)
        XCTAssertTrue(attributes.hasAnyAppearance)
    }

    func testWhenViewHasNoAppearance() {
        // Given
        let view: UIView = .mockRandom()
        var clip = view.frame

        // When
        oneOf([
            { view.isHidden = true },
            { view.alpha = 0 },
            { view.frame = .zero },
            { clip = clip.offsetBy(dx: clip.width, dy: clip.height) },
            {
                view.layer.borderWidth = 0
                view.layer.borderColor = UIColor.mockRandomWith(alpha: 0).cgColor
                view.backgroundColor = .mockRandomWith(alpha: 0)
            }
        ])

        // Then
        let attributes = createViewAttributes(with: view, clip: clip)
        XCTAssertFalse(attributes.hasAnyAppearance)
    }

    func testWhenViewIsTranslucent() {
        // Given
        let view: UIView = .mockRandom()
        var clip = view.frame

        // When
        oneOrMoreOf([
            { view.isHidden = true },
            { view.alpha = .mockRandom(min: 0, max: 0.99) },
            { view.frame = .zero },
            { clip = clip.offsetBy(dx: clip.width, dy: clip.height) },
            { view.backgroundColor = .mockRandomWith(alpha: .mockRandom(min: 0, max: 0.99)) }
        ])

        // Then
        let attributes = createViewAttributes(with: view, clip: clip)
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
        let attributes = createViewAttributes(with: view)
        XCTAssertFalse(attributes.isTranslucent)
    }

    func testItSanitizesInvalidRuntimeAttributes() {
        // Given
        let view = UIView(frame: .zero)
        view.setValue("invalid color", forKeyPath: "layer.borderColor")

        // When
        let attributes = createViewAttributes(with: view)

        // Then
        XCTAssertNil(attributes.layerBorderColor)
    }

    // MARK: Privacy Overrides

    func testItDefaultsToNilWhenNoOverrideIsSet() {
        // Given
        let view: UIView = .mockAny()

        // When
        let attributes = createViewAttributes(with: view)

        // Then
        XCTAssertNil(attributes.textAndInputPrivacy)
        XCTAssertNil(attributes.imagePrivacy)
        XCTAssertNil(attributes.touchPrivacy)
        XCTAssertNil(attributes.hide)
    }

    func testChildViewInheritsParentHideOverride() {
        // Given
        let childView = UIView.mock(withFixture: .visible(.someAppearance))
        let parentView = UIView.mock(withFixture: .visible(.someAppearance))
        parentView.addSubview(childView)
        parentView.dd.sessionReplayPrivacyOverrides.hide = true

        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .defaults))

        // When
        let nodes = recorder.record(parentView, in: .mockWith(coordinateSpace: parentView))

        // Then
        XCTAssertEqual(nodes.count, 1)
    }

    func testChildViewHideOverrideSetToFalseDoesNotOverrideParentHideOverride() {
        // Given
        let parentView = UIView.mock(withFixture: .visible(.someAppearance))
        let childView = UIView.mock(withFixture: .visible(.someAppearance))
        parentView.addSubview(childView)

        parentView.dd.sessionReplayPrivacyOverrides.hide = true
        childView.dd.sessionReplayPrivacyOverrides.hide = false

        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .defaults))

        // When
        let nodes = recorder.record(parentView, in: .mockWith(coordinateSpace: parentView))

        // Then
        XCTAssertEqual(nodes.count, 1, "Child view overrides parent's hidden state, so it should be recorded.")
    }

    func testChildViewInheritsParentOverrides() {
        // Given
        let parentView = UIView.mock(withFixture: .visible(.someAppearance))
        let childView = UIView.mock(withFixture: .visible(.someAppearance))
        parentView.addSubview(childView)

        let parentOverrides: PrivacyOverrides = .mockRandom()
        parentView.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = parentOverrides.textAndInputPrivacy
        parentView.dd.sessionReplayPrivacyOverrides.imagePrivacy = parentOverrides.imagePrivacy
        parentView.dd.sessionReplayPrivacyOverrides.touchPrivacy = parentOverrides.touchPrivacy

        let recorder = ViewTreeRecorder(nodeRecorders: createDefaultNodeRecorders(featureFlags: .defaults))
        let nodes = recorder.record(parentView, in: .mockWith(coordinateSpace: parentView))

        // Then
        XCTAssertEqual(nodes.count, 2)
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

extension ViewAttributesTests {
    func createViewAttributes(with view: UIView, clip: CGRect? = nil) -> ViewAttributes {
        ViewAttributes(
            view: view,
            frame: view.frame,
            clip: clip ?? view.frame,
            overrides: .mockAny()
        )
    }
}
#endif
