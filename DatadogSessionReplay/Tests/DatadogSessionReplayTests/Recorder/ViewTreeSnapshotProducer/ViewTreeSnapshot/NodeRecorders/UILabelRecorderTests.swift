/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

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
        viewAttributes = .mock(fixture: .visibleWithNoAppearance)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertNil(semantics.wireframesBuilder)
    }

    func testWhenLabelHasTextOrAppearance() throws {
        // When
        oneOf([
            {
                self.label.text = .mockRandom()
                self.viewAttributes = .mock(fixture: .visibleWithSomeAppearance)
            },
            {
                self.label.text = nil
                self.viewAttributes = .mock(fixture: .visibleWithSomeAppearance)
            },
            {
                self.label.text = .mockRandom()
                self.viewAttributes = .mock(fixture: .visibleWithNoAppearance)
            },
        ])

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertFalse(semantics.recordSubtree, "Label's subtree should not be recorded")

        let builder = try XCTUnwrap(semantics.wireframesBuilder as? UILabelWireframesBuilder)
        XCTAssertEqual(builder.attributes, viewAttributes)
        XCTAssertEqual(builder.text, label.text ?? "")
        XCTAssertEqual(builder.textColor, label.textColor?.cgColor)
        XCTAssertEqual(builder.font, label.font)
    }

    func testWhenRecordingInDifferentPrivacyModes() throws {
        // Given
        label.text = .mockRandom()

        // When
        let semantics1 = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .maskAll))))
        let semantics2 = try XCTUnwrap(recorder.semantics(of: label, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .allowAll))))

        // Then
        let builder1 = try XCTUnwrap(semantics1.wireframesBuilder as? UILabelWireframesBuilder)
        let builder2 = try XCTUnwrap(semantics2.wireframesBuilder as? UILabelWireframesBuilder)
        XCTAssertTrue(builder1.textObfuscator is TextObfuscator, "With `.maskAll` privacy the text obfuscator should be used")
        XCTAssertTrue(builder2.textObfuscator is NOPTextObfuscator, "With `.allowAll` privacy the text obfuscator should not be used")
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UITextField()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
// swiftlint:enable opening_brace
