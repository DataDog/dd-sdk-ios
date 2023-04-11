/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import WebKit
@testable import DatadogSessionReplay

class UnsupportedViewwRecorderTests: XCTestCase {
    private let recorder = UnsupportedViewRecorder()
    /// The view under test.
    private let views = [UIProgressView(), UIActivityIndicatorView(), UIWebView(), WKWebView()]
    /// `ViewAttributes` simulating common attributes of the view.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenViewIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        try views.forEach { view in
            let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
            XCTAssertTrue(semantics is InvisibleElement)
        }
    }

    func testWhenViewIsVisibleAndHasSomeAppearance() throws {
        // When
        viewAttributes = .mock(fixture: .visible(.someAppearance))

        // Then
        try views.forEach { view in
            let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
            XCTAssertTrue(semantics is SpecificElement)
            XCTAssertTrue(semantics.nodes.first?.wireframesBuilder is UnsupportedViewWireframesBuilder)
        }
    }

    func testWhenViewIsVisibleButHasNoAppearance() throws {
        // When
        viewAttributes = .mock(fixture: .visible(.noAppearance))

        // Then
        try views.forEach { view in
            let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
            XCTAssertTrue(semantics is SpecificElement)
            XCTAssertEqual(semantics.subtreeStrategy, .ignore)
        }
    }
}
