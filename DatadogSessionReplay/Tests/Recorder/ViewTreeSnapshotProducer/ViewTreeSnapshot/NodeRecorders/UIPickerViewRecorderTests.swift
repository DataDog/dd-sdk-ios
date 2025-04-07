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

class UIPickerViewRecorderTests: XCTestCase {
    private let recorder = UIPickerViewRecorder(identifier: UUID())
    private let picker = UIPickerView()
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenPickerIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: picker, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
    }

    func testWhenPickerIsVisibleAndHasSomeAppearance() throws {
        // When
        viewAttributes = .mock(fixture: .visible(.someAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: picker, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)
        XCTAssertTrue(semantics.nodes.first?.wireframesBuilder is UIPickerViewWireframesBuilder)
    }

    func testWhenPickerIsVisibleAndHasNoAppearance() throws {
        // When
        viewAttributes = .mock(fixture: .visible(.noAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: picker, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)
        XCTAssertFalse(semantics.nodes.first?.wireframesBuilder is UIPickerViewWireframesBuilder)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
#endif
