/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

// swiftlint:disable opening_brace
class UILabelRecorderTests: XCTestCase {
    private let recorder = UILabelRecorder()
    /// The label under test.
    private let label = UILabel()
    /// `ViewAttributes` simulating common attributes of label's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenLabelHasNoTextAndNoAppearance() throws {
        // When
        oneOf([
            { self.label.text = nil },
            { self.label.text = "" },
        ])
        viewAttributes = .mock(fixture: .visible(.noAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)
    }

    func testWhenLabelHasTextOrAppearance() throws {
        // When
        oneOf([
            {
                self.label.text = .mockRandom()
                self.viewAttributes = .mock(fixture: .visible())
            },
            {
                self.label.text = nil
                self.viewAttributes = .mock(fixture: .visible())
            },
            {
                self.label.text = .mockRandom()
                self.viewAttributes = .mock(fixture: .visible(.noAppearance))
            },
        ])

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore, "Label's subtree should not be recorded")

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UILabelWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
        XCTAssertEqual(builder.text, label.text ?? "")
        XCTAssertEqual(builder.textColor, label.textColor?.cgColor)
        XCTAssertEqual(builder.font, label.font)
    }

    func testWhenRecordingInDifferentPrivacyModes() throws {
        // Given
        label.text = .mockRandom()

        // When
        let context: ViewTreeRecordingContext = .mockWith(
            recorder: .mockWith(privacy: .mockRandom()),
            textObfuscator: TextObfuscatorMock(),
            selectionTextObfuscator: mockRandomTextObfuscator(),
            sensitiveTextObfuscator: mockRandomTextObfuscator()
        )
        let semantics = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: context))

        // Then
        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UILabelWireframesBuilder)
        XCTAssertTrue(
            (builder.textObfuscator as? TextObfuscatorMock) === (context.textObfuscator as? TextObfuscatorMock),
            "Labels should use default text obfuscator specific to current privacy mode"
        )
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
// swiftlint:enable opening_brace
