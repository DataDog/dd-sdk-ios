/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
@_spi(Internal)
import TestUtilities
@_spi(Internal)
@testable import DatadogSessionReplay

class UIActivityIndicatorRecorderTests: XCTestCase {
    private let recorder = UIActivityIndicatorRecorder(identifier: UUID())
    private let activityIndicator = UIActivityIndicatorView()
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenActivityIndicatorIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: activityIndicator, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
    }

    func testWhenActivityIndicatorIsVisible() throws {
        // When
        viewAttributes = .mock(fixture: .visible())
        activityIndicator.startAnimating()

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: activityIndicator, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Activity Indicator's subtree should not be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIActivityIndicatorWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
    }

    func testWhenActivityIndicatorIsInvisible_WhenIsNotAnimatingAndHidesWhenStopped() throws {
        // Given
        activityIndicator.hidesWhenStopped = true
        activityIndicator.stopAnimating()

        // When
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: activityIndicator, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
    }

    func testWhenActivityIndicatorIsVisible_WhenIsNotAnimatingAndDoesntHideWhenStopped() throws {
        // Given
        activityIndicator.hidesWhenStopped = false
        activityIndicator.stopAnimating()

        // When
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: activityIndicator, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Activity Indicator's subtree should not be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIActivityIndicatorWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
#endif
