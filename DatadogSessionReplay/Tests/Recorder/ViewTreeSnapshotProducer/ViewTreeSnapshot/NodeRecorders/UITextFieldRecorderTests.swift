/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay
@testable import TestUtilities

// swiftlint:disable opening_brace
class UITextFieldRecorderTests: XCTestCase {
    private let recorder = UITextFieldRecorder()
    /// The label under test.
    private let textField = UITextField(frame: .mockAny())
    /// `ViewAttributes` simulating common attributes of text field's `UIView`.
    private var viewAttributes: ViewAttributes = .mockAny()

    func testWhenTextFieldIsNotVisible() throws {
        // When
        viewAttributes = .mock(fixture: .invisible)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textField, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is InvisibleElement)
        XCTAssertNil(semantics.wireframesBuilder)
    }

    func testWhenTextFieldHasText() throws {
        // Given
        let randomText: String = .mockRandom()
        textField.textColor = .mockRandom()
        textField.font = .systemFont(ofSize: .mockRandom())

        // When
        oneOf([
            {
                self.textField.text = randomText
                self.textField.placeholder = nil
            },
            {
                self.textField.text = nil
                self.textField.placeholder = randomText
            },
            {
                self.textField.text = randomText
                self.textField.placeholder = .mockRandom()
            },
        ])
        viewAttributes = .mock(fixture: .visible())
        textField.layoutSubviews() // force layout (so TF creates its sub-tree)

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textField, with: viewAttributes, in: .mockAny()) as? SpecificElement)
        XCTAssertFalse(semantics.recordSubtree, "TextField's subtree should not be recorded")

        let builder = try XCTUnwrap(semantics.wireframesBuilder as? UITextFieldWireframesBuilder)
        XCTAssertEqual(builder.text, randomText)
        XCTAssertEqual(builder.textColor, textField.textColor?.cgColor)
        XCTAssertEqual(builder.font, textField.font)
        XCTAssertNotNil(builder.editor)
    }

    func testWhenRecordingInDifferentPrivacyModes() throws {
        // Given
        textField.text = .mockRandom()

        // When
        viewAttributes = .mock(fixture: .visible())
        let semantics1 = try XCTUnwrap(recorder.semantics(of: textField, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .maskAll))))
        let semantics2 = try XCTUnwrap(recorder.semantics(of: textField, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .allowAll))))

        // Then
        let builder1 = try XCTUnwrap(semantics1.wireframesBuilder as? UITextFieldWireframesBuilder)
        let builder2 = try XCTUnwrap(semantics2.wireframesBuilder as? UITextFieldWireframesBuilder)
        XCTAssertTrue(builder1.textObfuscator is TextObfuscator, "With `.maskAll` privacy the text obfuscator should be used")
        XCTAssertTrue(builder2.textObfuscator is NOPTextObfuscator, "With `.allowAll` privacy the text obfuscator should not be used")
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UILabel()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
// swiftlint:enable opening_brace
