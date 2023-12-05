/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@_spi(Internal)
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
    }

    func testWhenViewIsVisibleAndHasSomeAppearance() throws {
        // When
        viewAttributes = .mock(fixture: .visible(.someAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is AmbiguousElement)
        XCTAssertTrue(semantics.nodes.first?.wireframesBuilder is UIViewWireframesBuilder)
    }

    func testWhenViewIsVisibleButHasNoAppearance() throws {
        // When
        viewAttributes = .mock(fixture: .visible(.noAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record)
    }

    func testWhenViewIsFromUIAlertController() throws {
        // When
        viewAttributes = .mockRandom()

        // Then
        var context = ViewTreeRecordingContext.mockRandom()
        context.viewControllerContext.isRootView = true
        context.viewControllerContext.parentType = .alert
        let semantics = try XCTUnwrap(recorder.semantics(of: view, with: viewAttributes, in: context))
        XCTAssertTrue(semantics is AmbiguousElement)
        XCTAssertEqual(semantics.subtreeStrategy, .record)
    }
}
