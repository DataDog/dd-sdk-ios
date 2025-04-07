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

class UIProgressViewRecorderTests: XCTestCase {
    private let recorder = UIProgressViewRecorder(identifier: UUID())
    private let progressView = UIProgressView()
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenProgressViewIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: progressView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
    }

    func testWhenProgressViewIsVisible() throws {
        // When
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: progressView, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Progress view's subtree should not be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIProgressViewWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
    }

    func testWhenProgressViewHasBackgroundColor() throws {
        // Given
        progressView.backgroundColor = .mockRandom()

        // When
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: progressView, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Progress view's subtree should not be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIProgressViewWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
        XCTAssertEqual(builder.backgroundColor, progressView.backgroundColor?.cgColor)
        XCTAssertEqual(builder.progressTintColor, progressView.tintColor?.cgColor)
    }

    func testWhenProgressViewHasTrackColors() throws {
        // Given
        progressView.trackTintColor = .mockRandom()
        progressView.progressTintColor = .mockRandom()

        // When
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: progressView, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Progress view's subtree should not be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIProgressViewWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
        XCTAssertEqual(builder.backgroundColor, progressView.trackTintColor?.cgColor)
        XCTAssertEqual(builder.progressTintColor, progressView.progressTintColor?.cgColor)
    }

    func testWhenProgressViewHasMultipleColors() throws {
        // Given
        progressView.trackTintColor = .mockRandom()
        progressView.progressTintColor = .mockRandom()
        progressView.backgroundColor = .mockRandom()
        progressView.tintColor = .mockRandom()

        // When
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: progressView, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Progress view's subtree should not be recorded")
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UIProgressViewWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
        XCTAssertEqual(builder.backgroundColor, progressView.trackTintColor?.cgColor)
        XCTAssertEqual(builder.progressTintColor, progressView.progressTintColor?.cgColor)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
#endif
