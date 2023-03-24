/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class UISegmentRecorderTests: XCTestCase {
    private let recorder = UISegmentRecorder()
    private let segment = UISegmentedControl(items: ["first", "second", "third"])
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenSegmentIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: segment, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
    }

    func testWhenSegmentIsVisible() throws {
        // Given
        segment.selectedSegmentIndex = 2
        if #available(iOS 13.0, *) {
            segment.selectedSegmentTintColor = .mockRandom()
        }

        // When
        viewAttributes = .mock(fixture: .visible(.someAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: segment, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UISegmentWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
        XCTAssertEqual(builder.segmentTitles, ["first", "second", "third"])
        XCTAssertEqual(builder.selectedSegmentIndex, 2)
        if #available(iOS 13.0, *) {
            XCTAssertEqual(builder.selectedSegmentTintColor, segment.selectedSegmentTintColor)
        }
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
