/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class UIPickerViewRecorderTests: XCTestCase {
    private let recorder = UIPickerViewRecorder()
    private let picker = UIPickerView()
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenPickerIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: picker, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertNil(semantics.wireframesBuilder)
    }

    func testWhenPickerIsVisibleButHasNoAppearance() throws {
        // When
        viewAttributes = .mock(fixture: .visible(.noAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: picker, with: viewAttributes, in: .mockAny()) as? InvisibleElement)
        XCTAssertNil(semantics.wireframesBuilder)
        guard case .replace(let nodes) = semantics.subtreeStrategy else {
            XCTFail("Expected `.replace()` subtreeStrategy, got \(semantics.subtreeStrategy)")
            return
        }
        XCTAssertFalse(nodes.isEmpty)
    }

    func testWhenPickerIsVisibleAndHasSomeAppearance() throws {
        // When
        viewAttributes = .mock(fixture: .visible(.someAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: picker, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertNotNil(semantics.wireframesBuilder)
        guard case .replace(let nodes) = semantics.subtreeStrategy else {
            XCTFail("Expected `.replace()` subtreeStrategy, got \(semantics.subtreeStrategy)")
            return
        }
        XCTAssertFalse(nodes.isEmpty)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
