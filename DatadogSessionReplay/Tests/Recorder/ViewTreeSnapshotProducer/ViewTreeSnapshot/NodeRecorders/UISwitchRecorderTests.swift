/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
@testable import DatadogSessionReplay

class UISwitchRecorderTests: XCTestCase {
    private let recorder = UISwitchRecorder()
    /// The label under test.
    private let `switch` = UISwitch()
    /// `ViewAttributes` simulating common attributes of switch's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenSwitchIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: `switch`, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
    }

    func testWhenSwitchIsVisible() throws {
        // Given
        `switch`.isOn = .mockRandom()
        `switch`.thumbTintColor = .mockRandom()
        `switch`.onTintColor = .mockRandom()
        `switch`.tintColor = .mockRandom()

        // When
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: `switch`, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Switch's subtree should not be recorded")

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UISwitchWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
        XCTAssertEqual(builder.isOn, `switch`.isOn)
        XCTAssertEqual(builder.thumbTintColor, `switch`.thumbTintColor?.cgColor)
        XCTAssertEqual(builder.onTintColor, `switch`.onTintColor?.cgColor)
        XCTAssertEqual(builder.offTintColor, `switch`.tintColor?.cgColor)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
