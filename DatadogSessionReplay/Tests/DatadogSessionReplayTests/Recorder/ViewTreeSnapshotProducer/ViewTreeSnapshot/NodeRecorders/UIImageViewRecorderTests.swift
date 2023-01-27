/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

// swiftlint:disable opening_brace
class UIImageViewRecorderTests: XCTestCase {
    private let recorder = UIImageViewRecorder()
    /// The view under test.
    private let imageView = UIImageView()
    /// `ViewAttributes` simulating common attributes of image view's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenImageViewHasNoImageAndNoAppearance() throws {
        // When
        imageView.image = nil
        viewAttributes = .mock(fixture: .visible(.noAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertFalse(semantics.recordSubtree, "Image view's subtree should not be recorded")
    }

    func testWhenImageViewHasNoImageAndSomeAppearance() throws {
        // When
        imageView.image = nil
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertTrue(semantics.recordSubtree, "Image view's subtree should be recorded")

        let builder = try XCTUnwrap(semantics.wireframesBuilder as? UIImageViewWireframesBuilder)
        XCTAssertEqual(builder.buildWireframes(with: WireframesBuilder()).count, 1)
    }

    func testWhenImageViewHasImageAndSomeAppearance() throws {
        // When
        imageView.image = UIImage()
        viewAttributes = .mock(fixture: .visible())

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertTrue(semantics.recordSubtree, "Image view's subtree should be recorded")

        let builder = try XCTUnwrap(semantics.wireframesBuilder as? UIImageViewWireframesBuilder)
        XCTAssertEqual(builder.buildWireframes(with: WireframesBuilder()).count, 2)
    }

    func testWhenImageViewHasImageOrAppearance() throws {
        // When
        oneOf([
            {
                self.imageView.image = UIImage()
                self.viewAttributes = .mock(fixture: .visible())
            },
            {
                self.imageView.image = nil
                self.viewAttributes = .mock(fixture: .visible())
            },
            {
                self.imageView.image = UIImage()
                self.viewAttributes = .mock(fixture: .visible(.noAppearance))
            },
        ])

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: imageView, with: viewAttributes, in: .mockAny()) as? SpecificElement)

        let builder = try XCTUnwrap(semantics.wireframesBuilder as? UIImageViewWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
        XCTAssertEqual(builder.wireframeRect, viewAttributes.frame)
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
// swiftlint:enable opening_brace
