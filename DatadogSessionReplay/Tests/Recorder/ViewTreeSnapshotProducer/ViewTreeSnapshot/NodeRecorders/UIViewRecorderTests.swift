/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

class UIViewRecorderTests: XCTestCase {
    private let recorder = UIViewRecorder()
    /// The view under test.
    private let view = UIView()
    /// `ViewAttributes` simulating common attributes of the view.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenViewIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertNil(semantics.wireframesBuilder)
    }

    func testWhenViewIsVisible() throws {
        // When
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is AmbiguousElement)

        let builder = try XCTUnwrap(semantics.wireframesBuilder as? UIViewWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
    }
}
