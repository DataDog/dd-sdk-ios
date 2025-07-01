/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

/// Note: while we only test one iOS version in CI,
/// make sure to test both iOS 18+ and iOS 17- locally
/// when making changes to the automatic SwiftUI action tracking logic
class SwiftUIComponentDetectorTests: XCTestCase {
    private let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
    private let defaultPredicate = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)

    // MARK: - Modern Detector Tests (iOS 18+)

    @available(iOS 18.0, tvOS 18.0, *)
    func testModernDetector_DetectsButtonInBeganPhase() {
        // Given
        let detector = ModernSwiftUIComponentDetector()
        let mockTouch = MockUITouch(
            phase: .began,
            view: SwiftUIViewMock(),
            description: "ButtonGesture" // Simulates a SwiftUI button
        )
        mockTouch.mockGestures = [
            MockGestureRecognizer(name: "Button<TestStyle>")
        ]

        // When - Begin phase
        var command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then - No command yet, just storing for later
        XCTAssertNil(command)

        // When - End phase
        mockTouch.mockPhase = .ended
        command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then - Command created
        XCTAssertNotNil(command)
        XCTAssertEqual(command?.name, "SwiftUI_Button")
        XCTAssertEqual(command?.actionType, .tap)
        XCTAssertEqual(command?.instrumentation, .swiftuiAutomatic)
        XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
    }

    @available(iOS 18.0, tvOS 18.0, *)
    func testModernDetector_DetectsNavigationLinkFromGestureName() {
        // Given
        let detector = ModernSwiftUIComponentDetector()
        let defaultPredicate = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)
        let mockTouch = MockUITouch(
            phase: .began,
            view: SwiftUIViewMock(),
            description: "ButtonGesture"
        )

        // When - Begin phase
        var command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then - No command yet, just storing for later
        XCTAssertNil(command)

        // When - End phase
        mockTouch.mockPhase = .ended
        command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then - Command created with correct component name
        XCTAssertNotNil(command)
        XCTAssertEqual(command?.name, "SwiftUI_NavigationLink")
        XCTAssertEqual(command?.actionType, .tap)
        XCTAssertEqual(command?.instrumentation, .swiftuiAutomatic)
        XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
    }

    @available(iOS 18.0, tvOS 18.0, *)
    func testModernDetector_IgnoresTouchesWithoutButtonGesture() {
        // Given
        let detector = ModernSwiftUIComponentDetector()
        let mockTouch = MockUITouch(
            phase: .began,
            view: SwiftUIViewMock(),
            description: "RegularGesture"
        )

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(command)
    }

    @available(iOS 18.0, tvOS 18.0, *)
    func testModernDetector_IgnoresNonSwiftUIViews() {
        // Given
        let detector = ModernSwiftUIComponentDetector()
        let regularView = UIView() // Not a SwiftUI view
        let mockTouch = MockUITouch(phase: .began, view: regularView)

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(command)
    }

    @available(iOS 18.0, tvOS 18.0, *)
    func testModernDetector_HandlesNilView() {
        // Given
        let detector = ModernSwiftUIComponentDetector()
        let mockTouch = MockUITouch(phase: .ended, view: nil)

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(command)
    }

    @available(iOS 18.0, tvOS 18.0, *)
    func testModernDetector_CleanupStalePendingActions() {
        // Given
        let detector = ModernSwiftUIComponentDetector()
        let mockTouch = MockUITouch(
            phase: .began,
            view: SwiftUIViewMock(),
            description: "ButtonGesture"
        )

        // Store a pending action
        _ = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Create a different touch to avoid matching the pending one
        let differentTouch = MockUITouch(
            phase: .ended,
            view: SwiftUIViewMock(),
            description: "ButtonGesture"
        )

        // Simulate that 6 seconds have passed since the original touch
        let staleDateProvider = RelativeDateProvider(
            using: Date(
                timeIntervalSince1970:
                          dateProvider.now.timeIntervalSince1970 + 6.0
            )
        )

        // When
        let command = detector.createActionCommand(
            from: differentTouch,
            predicate: defaultPredicate,
            dateProvider: staleDateProvider
        )

        // Then - Stale actions should be cleaned up, no command created
        XCTAssertNil(command)
    }

    @available(iOS 18.0, tvOS 18.0, *)
    func testModernDetector_IgnoresEndPhaseWithoutPriorBeginPhase() {
        // Given
        let detector = ModernSwiftUIComponentDetector()
        let mockTouch = MockUITouch(
            phase: .ended,
            view: SwiftUIViewMock(),
            description: "ButtonGesture"
        )
        mockTouch.mockGestures = [
            MockGestureRecognizer(name: "Button<TestStyle>")
        ]

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then - No command since there was no prior begin phase
        XCTAssertNil(command)
    }

    @available(iOS 18.0, tvOS 18.0, *)
    func testModernDetector_UsesCustomPredicate() {
        // Given
        let detector = ModernSwiftUIComponentDetector()
        let customPredicate = MockSwiftUIRUMActionsPredicate(
            returnAction: RUMAction(
                name: "custom_action",
                attributes: ["key": "value"]
            )
        )
        let mockTouch = MockUITouch(
            phase: .began,
            view: SwiftUIViewMock(),
            description: "ButtonGesture"
        )
        mockTouch.mockGestures = [
            MockGestureRecognizer(name: "Button<TestStyle>")
        ]

        // When - Begin phase
        var command = detector.createActionCommand(
            from: mockTouch,
            predicate: customPredicate,
            dateProvider: dateProvider
        )

        // Then - No command yet
        XCTAssertNil(command)

        // When - End phase
        mockTouch.mockPhase = .ended
        command = detector.createActionCommand(
            from: mockTouch,
            predicate: customPredicate,
            dateProvider: dateProvider
        )

        // Then - Command with default component name
        XCTAssertNotNil(command)
        XCTAssertEqual(command?.name, "custom_action")
        XCTAssertEqual(command?.attributes as? [String: String], ["key": "value"])
        XCTAssertEqual(command?.actionType, .tap)
        XCTAssertEqual(command?.instrumentation, .swiftuiAutomatic)
        XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
    }

    @available(iOS 18.0, tvOS 18.0, *)
    func testModernDetector_HandlesNilPredicate() {
        // Given
        let detector = ModernSwiftUIComponentDetector()
        let mockTouch = MockUITouch(
            phase: .began,
            view: SwiftUIViewMock(),
            description: "ButtonGesture"
        )

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: nil,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(command)
    }

    // MARK: - Legacy Detector Tests (iOS 17 and below)

    func testLegacyDetector_DetectsSwiftUIViewTaps() {
        // Given
        let detector = LegacySwiftUIComponentDetector()
        let mockTouch = MockUITouch(
            phase: .ended,
            view: SwiftUIViewMock()
        )

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNotNil(command)
        XCTAssertEqual(command?.name, "SwiftUI_Unidentified_Element")
        XCTAssertEqual(command?.actionType, .tap)
        XCTAssertEqual(command?.instrumentation, .swiftuiAutomatic)
        XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
    }

    func testLegacyDetector_IgnoresContainerViews() {
        // Given
        let detector = LegacySwiftUIComponentDetector()
        let containerView = SwiftUIViewMock()
        let mockTouch = MockUITouch(phase: .ended, view: containerView)
        let testCases = [
            "HostingView",
            "HostingScrollView",
            "PlatformGroupContainer"
        ]

        // When
        for containerType in testCases {
            containerView.mockTypeDescription = containerType
            let command = detector.createActionCommand(
                from: mockTouch,
                predicate: defaultPredicate,
                dateProvider: dateProvider
            )

            // Then
            XCTAssertNil(
                command,
                "Should ignore container views: \(containerType)"
            )
        }
    }

    func testLegacyDetector_IgnoresNonSwiftUIViews() {
        // Given
        let detector = LegacySwiftUIComponentDetector()
        let regularView = UIView()
        let mockTouch = MockUITouch(phase: .ended, view: regularView)

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(command)
    }

    func testLegacyDetector_IgnoresTouchesInNonEndedPhase() {
        // Given
        let detector = LegacySwiftUIComponentDetector()
        let mockTouch = MockUITouch(
            phase: .began,
            view: SwiftUIViewMock()
        )

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(command)
    }

    func testLegacyDetector_HandlesNilView() {
        // Given
        let detector = LegacySwiftUIComponentDetector()
        let mockTouch = MockUITouch(phase: .ended, view: nil)

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: defaultPredicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(command)
    }

    func testLegacyDetector_UsesCustomPredicate() {
        // Given
        let detector = LegacySwiftUIComponentDetector()
        let mockTouch = MockUITouch(
            phase: .ended,
            view: SwiftUIViewMock()
        )
        let customPredicate = MockSwiftUIRUMActionsPredicate(
            returnAction: RUMAction(
                name: "custom_action",
                attributes: ["key": "value"]
            )
        )

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: customPredicate,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNotNil(command)
        XCTAssertEqual(command?.name, "custom_action")
        XCTAssertEqual(command?.attributes as? [String: String], ["key": "value"])
        XCTAssertEqual(command?.actionType, .tap)
        XCTAssertEqual(command?.instrumentation, .swiftuiAutomatic)
        XCTAssertEqual(command?.time, .mockDecember15th2019At10AMUTC())
    }

    func testLegacyDetector_HandlesNilPredicate() {
        // Given
        let detector = LegacySwiftUIComponentDetector()
        let mockTouch = MockUITouch(
            phase: .ended,
            view: SwiftUIViewMock()
        )

        // When
        let command = detector.createActionCommand(
            from: mockTouch,
            predicate: nil,
            dateProvider: dateProvider
        )

        // Then
        XCTAssertNil(command)
    }

    // MARK: - Default Predicate and iOS Flag

    func testSwiftUIDetection_WithDefaultPredicateAndLegacyDetectorFlagEnabled() {
        // Given
        let detector = SwiftUIComponentFactory.createDetector()
        let predicateWithLegacyDetectorEnabled = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)
        let mockTouch = MockUITouch(
            phase: .began,
            view: SwiftUIViewMock()
        )
        if #available(iOS 18.0, *) {
            mockTouch.mockDescription = "ButtonGesture"
            mockTouch.mockGestures = [
                MockGestureRecognizer(name: "Button<TestStyle>")
            ]
        }

        // When - Begin phase
        var command = detector.createActionCommand(
            from: mockTouch,
            predicate: predicateWithLegacyDetectorEnabled,
            dateProvider: dateProvider
        )

        XCTAssertNil(command)

        mockTouch.mockPhase = .ended

        command = detector.createActionCommand(
            from: mockTouch,
            predicate: predicateWithLegacyDetectorEnabled,
            dateProvider: dateProvider
        )

        // Then
        if #available(iOS 18.0, *) {
            // On iOS 18+, should use modern detection
            XCTAssertNotNil(command)
            XCTAssertEqual(command?.name, "SwiftUI_Button")
        } else {
            // On iOS 17-, should use legacy detection
            XCTAssertNotNil(command)
            XCTAssertEqual(command?.name, "SwiftUI_Unidentified_Element")
        }
    }

    func testSwiftUIDetection_WithDefaultPredicateAndLegacyDetectorFlagDisabled() {
        // Given
        let detector = SwiftUIComponentFactory.createDetector()
        let predicateWithLegacyDetectorEnabled = DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: false)
        let mockTouch = MockUITouch(
            phase: .began,
            view: SwiftUIViewMock()
        )
        if #available(iOS 18.0, *) {
            mockTouch.mockDescription = "ButtonGesture"
            mockTouch.mockGestures = [
                MockGestureRecognizer(name: "Button<TestStyle>")
            ]
        }

        // When - Begin phase
        var command = detector.createActionCommand(
            from: mockTouch,
            predicate: predicateWithLegacyDetectorEnabled,
            dateProvider: dateProvider
        )

        XCTAssertNil(command)

        mockTouch.mockPhase = .ended

        command = detector.createActionCommand(
            from: mockTouch,
            predicate: predicateWithLegacyDetectorEnabled,
            dateProvider: dateProvider
        )

        // Then
        if #available(iOS 18.0, *) {
            // On iOS 18+, should still detect using modern detection
            XCTAssertNotNil(command)
            XCTAssertEqual(command?.name, "SwiftUI_Button")
        } else {
            // On iOS 17-, should not detect anything since toggle is off
            XCTAssertNil(command)
        }
    }

    // MARK: - Helpers

    func testSwiftUIComponentHelpers_ExtractComponentName() {
        // Given
        let mockTouch = MockUITouch(phase: .ended, view: UIView())

        // Test button extraction
        mockTouch.mockGestures = [MockGestureRecognizer(name: "Button<TestStyle>")]
        XCTAssertEqual(
            SwiftUIComponentHelpers.extractComponentName(touch: mockTouch, defaultName: "default"),
            "SwiftUI_Button"
        )

        // Test fallback to default
        mockTouch.mockGestures = [MockGestureRecognizer(name: "SomeOtherGesture")]
        XCTAssertEqual(
            SwiftUIComponentHelpers.extractComponentName(touch: mockTouch, defaultName: "default"),
            "default"
        )
    }

    func testSwiftUIComponentFactory_CreatesCorrectDetector() {
        // Test will always use the correct detector based on iOS version
        let detector = SwiftUIComponentFactory.createDetector()

        if #available(iOS 18.0, tvOS 18.0, visionOS 18.0, *) {
            XCTAssertTrue(detector is ModernSwiftUIComponentDetector)
        } else {
            XCTAssertTrue(detector is LegacySwiftUIComponentDetector)
        }
    }
}

// MARK: - Test Mocks
private class MockUITouch: UITouch {
    var mockPhase: UITouch.Phase
    var mockView: UIView?
    var mockGestures: [UIGestureRecognizer]?
    var mockDescription: String

    init(phase: UITouch.Phase, view: UIView?, description: String = "") {
        self.mockPhase = phase
        self.mockView = view
        self.mockDescription = description
        super.init()
    }

    override var phase: UITouch.Phase {
        return mockPhase
    }

    override var view: UIView? {
        return mockView
    }

    override var gestureRecognizers: [UIGestureRecognizer]? {
        return mockGestures
    }

    override var description: String {
        return mockDescription
    }
}

private class MockGestureRecognizer: UIGestureRecognizer {
    private var mockName: String?

    init(name: String? = nil) {
        self.mockName = name
        super.init(target: nil, action: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var name: String? {
        get { return mockName }
        set { mockName = newValue }
    }
}

private class SwiftUIViewMock: UIView {
    var mockTypeDescription: String?
    var overrideIsSwiftUIView: Bool?

    // Implement TypeDescribing protocol
    override var typeDescription: String {
        return mockTypeDescription ?? "_TtCV7SwiftUI9EmptyView"
    }

    @objc override var isSwiftUIView: Bool {
        return overrideIsSwiftUIView ?? true
    }
}
