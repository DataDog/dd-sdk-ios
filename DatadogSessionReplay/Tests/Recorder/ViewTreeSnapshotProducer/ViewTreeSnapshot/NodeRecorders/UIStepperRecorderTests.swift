/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
@testable import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

class UIStepperRecorderTests: XCTestCase {
    private let recorder = UIStepperRecorder(identifier: UUID())
    private let stepper = UIStepper()
    /// `ViewAttributes` simulating common attributes of switch's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenStepperIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: stepper, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
    }

    func testWhenStepperIsVisible() throws {
        // Given
        stepper.tintColor = .mockRandom()

        // When
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: stepper, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Stepper's subtree should not be recorded")

        _ = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIStepperWireframesBuilder)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }

    func testWhenStepperHasTextAndInputPrivacyOverrideThatUnmasksInputs() throws {
        // Given
        stepper.minimumValue = 0
        stepper.maximumValue = 10
        stepper.value = 0 // at minimum: "minus" is disabled when not masked
        viewAttributes = .mock(fixture: .visible())
        viewAttributes.textAndInputPrivacy = .maskSensitiveInputs
        let context: ViewTreeRecordingContext = .mockWith(recorder: .mockWith(textAndInputPrivacy: .maskAllInputs))

        // When
        let semantics = try XCTUnwrap(recorder.semantics(of: stepper, with: viewAttributes, in: context))

        // Then
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIStepperWireframesBuilder)
        XCTAssertFalse(builder.isMinusEnabled, "Local override should take precedence over the global privacy level")
        XCTAssertTrue(builder.isPlusEnabled)
    }

    func testWhenStepperHasTextAndInputPrivacyOverrideThatMasksInputs() throws {
        // Given
        stepper.minimumValue = 0
        stepper.maximumValue = 10
        stepper.value = 0 // at minimum: "minus" is still shown as enabled when masked
        viewAttributes = .mock(fixture: .visible())
        viewAttributes.textAndInputPrivacy = .maskAll
        let context: ViewTreeRecordingContext = .mockWith(recorder: .mockWith(textAndInputPrivacy: .maskSensitiveInputs))

        // When
        let semantics = try XCTUnwrap(recorder.semantics(of: stepper, with: viewAttributes, in: context))

        // Then
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIStepperWireframesBuilder)
        XCTAssertTrue(builder.isMinusEnabled, "Local override should take precedence over the global privacy level")
        XCTAssertTrue(builder.isPlusEnabled)
    }
}
#endif
