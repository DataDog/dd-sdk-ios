/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

class UIStepperRecorderTests: XCTestCase {
    private let recorder = UIStepperRecorder()
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
}
#endif
