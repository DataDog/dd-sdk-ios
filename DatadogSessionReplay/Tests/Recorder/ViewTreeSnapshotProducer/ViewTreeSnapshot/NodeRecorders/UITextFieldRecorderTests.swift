/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogSessionReplay

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
        viewAttributes = .mock(fixture: .visible(.someAppearance))

        // Then
        let semantics = try XCTUnwrap(recorder.semantics(of: textField, with: viewAttributes, in: .mockAny()))
        XCTAssertTrue(semantics is SpecificElement)
        XCTAssertEqual(semantics.subtreeStrategy, .ignore)

        let builder = try XCTUnwrap(semantics.nodes.first?.wireframesBuilder as? UITextFieldWireframesBuilder)
        XCTAssertEqual(builder.text, randomText)
        XCTAssertEqual(builder.textColor, textField.textColor?.cgColor)
        XCTAssertEqual(builder.font, textField.font)
    }

    func testWhenRecordingInDifferentPrivacyModes() throws {
        // Given
        let textField1 = UITextField(frame: .mockAny())
        let textField2 = UITextField(frame: .mockAny())
        let textField3 = UITextField(frame: .mockAny())
        textField1.text = .mockRandom()
        textField2.text = .mockRandom()
        textField3.text = .mockRandom()

        textField2.isSecureTextEntry = true
        textField3.textContentType = [.telephoneNumber, .emailAddress].randomElement()!

        // When
        viewAttributes = .mock(fixture: .visible())
        let semantics1 = try XCTUnwrap(recorder.semantics(of: textField1, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .maskAll))))
        let semantics2 = try XCTUnwrap(recorder.semantics(of: textField1, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .allowAll))))
        let semantics3 = try XCTUnwrap(recorder.semantics(of: textField2, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .mockRandom()))))
        let semantics4 = try XCTUnwrap(recorder.semantics(of: textField3, with: viewAttributes, in: .mockWith(recorder: .mockWith(privacy: .mockRandom()))))

        // Then
        let builder1 = try XCTUnwrap(semantics1.nodes.first?.wireframesBuilder as? UITextFieldWireframesBuilder)
        let builder2 = try XCTUnwrap(semantics2.nodes.first?.wireframesBuilder as? UITextFieldWireframesBuilder)
        let builder3 = try XCTUnwrap(semantics3.nodes.first?.wireframesBuilder as? UITextFieldWireframesBuilder)
        let builder4 = try XCTUnwrap(semantics4.nodes.first?.wireframesBuilder as? UITextFieldWireframesBuilder)
        XCTAssertTrue(builder1.textObfuscator is TextObfuscator, "With `.maskAll` privacy the text obfuscator should be used")
        XCTAssertTrue(builder2.textObfuscator is NOPTextObfuscator, "With `.allowAll` privacy the text obfuscator should not be used")
        XCTAssertTrue(builder3.textObfuscator is InputTextObfuscator, "When `TextField` accepts secure text entry, it should use `InputTextObfuscator`")
        XCTAssertTrue(builder4.textObfuscator is InputTextObfuscator, "When `TextField` accepts email or tlephone no. entry, it should use `InputTextObfuscator`")
    }

    func testWhenViewIsNotOfExpectedType() {
        // When
        let view = UILabel()

        // Then
        XCTAssertNil(recorder.semantics(of: view, with: viewAttributes, in: .mockAny()))
    }
}
// swiftlint:enable opening_brace
